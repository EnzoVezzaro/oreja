import Foundation

/// The single owner of the decision to pause or resume music.
///
/// The coordinator is deliberately synchronous and event-driven: adapters report audio activity
/// and media observations, and playback commands are handed out through `onCommand` and later
/// completed with `complete(_:outcome:)`. That keeps every race (slow AppleScript, manual
/// playback changes, source loss) representable and testable without sleeping.
@MainActor
public final class PlaybackCoordinator {
    public enum CommandKind: String, Sendable, Equatable {
        case pause
        case resume
    }

    public struct Command: Identifiable, Sendable, Equatable {
        public var id: UUID
        public var kind: CommandKind
        public var expectedTrack: MediaTrack?
        public var issuedAt: TimeInterval

        public init(id: UUID = UUID(), kind: CommandKind, expectedTrack: MediaTrack?, issuedAt: TimeInterval) {
            self.id = id
            self.kind = kind
            self.expectedTrack = expectedTrack
            self.issuedAt = issuedAt
        }
    }

    // MARK: Configuration

    public private(set) var policy: PlaybackPolicy
    private let scheduler: any SilenceScheduling
    private let diagnostics: (any DiagnosticsSink)?
    private let journal: (any PauseJournal)?
    private let now: @MainActor () -> TimeInterval
    private let dateProvider: () -> Date

    // MARK: Observable state

    public private(set) var state: CoordinatorState = .disabled
    public private(set) var automationEnabled = false
    public private(set) var aiIsActive = false
    public private(set) var ownership: PauseOwnership?
    public private(set) var lastSnapshot: MediaPlaybackSnapshot?
    public private(set) var pendingCommand: Command?
    public private(set) var sourceIsValid = false
    public private(set) var sourceDescription = ""
    public private(set) var lastError: String?
    public private(set) var statistics = CoordinatorStatistics()
    public private(set) var isRestoringOnFailure = false

    /// Called whenever a playback command must be executed by the adapter layer.
    public var onCommand: ((Command) -> Void)?
    /// Called after any state change so the UI can redraw.
    public var onStateChanged: (() -> Void)?

    // MARK: Internal bookkeeping

    private var silenceTask: (any ScheduledAction)?
    private var silenceToken: UUID?
    private var queuedIntent: CommandKind?
    private var activityOnsetTime: TimeInterval?
    private var quietElapsedTime: TimeInterval?
    private var consecutiveFailures = 0
    private var userOverrodeDuringActivity = false

    public init(
        policy: PlaybackPolicy = .default,
        scheduler: (any SilenceScheduling)? = nil,
        diagnostics: (any DiagnosticsSink)? = nil,
        journal: (any PauseJournal)? = nil,
        now: @escaping @MainActor () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
        dateProvider: @escaping () -> Date = Date.init
    ) {
        self.policy = policy
        self.scheduler = scheduler ?? TaskScheduler()
        self.diagnostics = diagnostics
        self.journal = journal
        self.now = now
        self.dateProvider = dateProvider
    }

    // MARK: Public API — user intent

    public func setAutomationEnabled(_ enabled: Bool) {
        guard enabled != automationEnabled else { return }

        if enabled {
            automationEnabled = true
            consecutiveFailures = 0
            lastError = nil
            log(.info, .lifecycle, "Automation enabled.")
            transition(desiredIdleState())
            return
        }

        automationEnabled = false
        cancelSilence()
        aiIsActive = false
        userOverrodeDuringActivity = false
        // Disabling automation releases responsibility for any pause Oreja owns, restoring
        // the user's playback so Oreja never leaves music stuck.
        restoreOwnedPause(reason: "automation disabled")
        transition(.disabled)
        log(.info, .lifecycle, "Automation disabled.")
    }

    public func updatePolicy(_ policy: PlaybackPolicy) {
        self.policy = policy
    }

    /// Re-arm automation after an error without changing settings.
    /// - Note: clears `.error` and `.permissionRequired` so a successful retry can resume normal states.
    public func retryAfterError() {
        lastError = nil
        consecutiveFailures = 0
        isRestoringOnFailure = false
        guard automationEnabled else {
            transition(.disabled)
            return
        }
        if sourceIsValid {
            state = .monitoring
            transition(desiredIdleState())
        } else {
            transition(.searchingForSource)
        }
        log(.info, .recovery, "Retrying after error.")
    }

    // MARK: Public API — monitoring events

    public func monitoringBecameAvailable(description: String) {
        sourceIsValid = true
        sourceDescription = description
        isRestoringOnFailure = false
        lastError = nil
        if state == .error || state == .permissionRequired {
            state = .monitoring
        }
        log(.success, .monitoring, "Monitoring \(description).")
        transition(desiredIdleState())
    }

    public func monitoringFailed(_ failure: AudioMonitoringFailure) {
        sourceIsValid = false
        cancelSilence()
        aiIsActive = false
        activityOnsetTime = nil
        lastError = failure.message

        if failure.kind == .permissionDenied {
            log(.error, .permissions, "Audio capture permission unavailable: \(failure.message)")
        } else {
            log(.error, .monitoring, "Monitoring failed: \(failure.message)")
        }

        if policy.restoreOwnedPauseOnFailure, ownership != nil {
            isRestoringOnFailure = true
            restoreOwnedPause(reason: "monitoring failed")
        }

        transition(failure.kind == .permissionDenied ? .permissionRequired : .error)
    }

    public func sourceInvalidated(reason: String) {
        sourceIsValid = false
        cancelSilence()
        aiIsActive = false
        activityOnsetTime = nil
        isRestoringOnFailure = false
        log(.warning, .monitoring, "Monitored source became invalid: \(reason)")
        restoreOwnedPause(reason: "monitored source vanished")
        transition(automationEnabled ? .searchingForSource : .disabled)
    }

    public func audioActivityStarted(levelDB: Double) {
        guard automationEnabled, sourceIsValid else { return }
        statistics.lastActivityLevelDB = levelDB
        activityOnsetTime = now()

        if aiIsActive {
            // Continued activity inside one response.
            return
        }

        aiIsActive = true
        userOverrodeDuringActivity = false
        cancelSilence()

        guard ownership == nil else {
            transition(.musicPausedByOreja)
            return
        }

        if let snapshot = lastSnapshot, snapshot.isPlaying, !userOverrodeDuringActivity {
            request(.pause, expectedTrack: snapshot.track)
        }
        transition(.aiActive)
    }

    public func audioActivityEnded() {
        guard aiIsActive else { return }
        aiIsActive = false
        activityOnsetTime = nil

        guard automationEnabled, sourceIsValid else {
            transition(desiredIdleState())
            return
        }

        guard ownership != nil || pendingCommand?.kind == .pause else {
            transition(desiredIdleState())
            return
        }

        scheduleQuietInterval()
    }

    /// Media observation, usually every second while automation is enabled.
    public func observe(media snapshot: MediaPlaybackSnapshot) {
        let previous = lastSnapshot
        lastSnapshot = snapshot

        // A command is in flight: the provider may still be reporting the pre-command state,
        // so postpone ownership decisions until the command completes.
        if pendingCommand != nil {
            noteProviderProblem(snapshot)
            return
        }

        if let own = ownership {
            switch snapshot.state {
            case .playing:
                releaseOwnership(reason: "music resumed externally")
                statistics.manualOverrides += 1
                if aiIsActive { userOverrodeDuringActivity = true }
                cancelSilence()
                log(.info, .playback, "Playback changed externally; Oreja released its pause and will not re-pause during this response.")
                transition(aiIsActive ? .aiActive : desiredIdleState())
                return
            case .paused:
                if !snapshot.refersTo(own.track) {
                    releaseOwnership(reason: "track changed while paused")
                    cancelSilence()
                    log(.warning, .playback, "The paused track changed; Oreja will not resume it.")
                }
                if state == .monitoring || state == .musicPlaying || state == .error {
                    transition(.musicPausedByOreja)
                }
                return
            case .stopped, .unavailable, .permissionRequired:
                releaseOwnership(reason: "provider became unavailable")
                cancelSilence()
                transition(providerProblemState(snapshot) ?? desiredIdleState())
                return
            }
        }

        if aiIsActive, snapshot.isPlaying, !userOverrodeDuringActivity, previous?.isPlaying != true {
            // Music started after Oreja's pause was released (or never issued). Treat it as a
            // manual decision and stay out of the way for the rest of this response.
            userOverrodeDuringActivity = true
            statistics.manualOverrides += 1
            log(.info, .playback, "Music started during AI output; honoring the manual playback choice.")
        }

        if let problem = providerProblemState(snapshot) {
            transition(problem)
            return
        }

        transition(desiredIdleState())
    }

    // MARK: Public API — command completion

    public func complete(_ commandID: UUID, outcome: MediaCommandOutcome) {
        guard let command = pendingCommand, command.id == commandID else {
            log(.warning, .playback, "Ignored a completion for a command that is no longer pending.")
            return
        }
        pendingCommand = nil

        switch outcome {
        case .succeeded(let snapshot):
            consecutiveFailures = 0
            lastError = nil
            if let snapshot {
                lastSnapshot = snapshot
            }

            switch command.kind {
            case .pause:
                let track = lastSnapshot?.track ?? command.expectedTrack
                let acquired = PauseOwnership(
                    track: track,
                    provider: lastSnapshot?.provider ?? .appleMusic,
                    acquiredAt: now()
                )
                ownership = acquired
                if let activityOnsetTime {
                    statistics.lastPauseLatency = now() - activityOnsetTime
                }
                statistics.pausesIssued += 1
                journal?.save(
                    PauseJournalRecord(
                        provider: acquired.provider,
                        track: acquired.track,
                        acquiredAt: dateProvider(),
                        reason: "AI output activity"
                    )
                )
                log(.success, .playback, "Paused \(acquired.provider.displayName)\(track.map { " (\($0.displayName))" } ?? "").")
                transition(aiIsActive ? .musicPausedByOreja : .monitoring)

            case .resume:
                ownership = nil
                journal?.clear()
                if let quietElapsedTime {
                    statistics.lastResumeLatency = now() - quietElapsedTime
                }
                statistics.resumesIssued += 1
                log(.success, .playback, "Resumed \(command.expectedTrack?.displayName ?? "music").")
                if aiIsActive {
                    // The AI started again while AppleScript was resuming: pause right away so
                    // a new response never competes with music.
                    request(.pause, expectedTrack: lastSnapshot?.track ?? command.expectedTrack)
                    transition(.aiActive)
                } else {
                    transition(desiredIdleState())
                }
            }

        case .noOp(let snapshot):
            if let snapshot {
                lastSnapshot = snapshot
            }
            if command.kind == .pause {
                log(.info, .playback, "Music was no longer playing, so no pause was needed.")
            } else {
                log(.info, .playback, "Playback changed before the resume command, so Oreja left it alone.")
            }
            ownership = nil
            journal?.clear()
            transition(desiredIdleState())

        case .failed(let error):
            consecutiveFailures += 1
            statistics.failedCommands += 1
            lastError = error.localizedDescription
            log(.error, .playback, "\(command.kind.rawValue.capitalized) command failed: \(error.localizedDescription)")

            if command.kind == .resume {
                ownership = nil
                journal?.clear()
            }

            if consecutiveFailures >= policy.failureLimit {
                lastError = "Playback control keeps failing. \(error.localizedDescription)"
                cancelSilence()
                log(.error, .playback, "Stopping automation after \(consecutiveFailures) failed commands.")
                transition(.error)
            } else {
                transition(desiredIdleState())
            }
        }

        drainQueuedIntent()
    }

    // MARK: Public API — lifecycle

    public func systemWillSleep() {
        cancelSilence()
        aiIsActive = false
        activityOnsetTime = nil
        transition(.suspended)
        log(.info, .lifecycle, "System is going to sleep; automation suspended.")
    }

    public func systemDidWake() {
        guard automationEnabled else {
            transition(.disabled)
            return
        }
        if ownership != nil, !aiIsActive {
            isRestoringOnFailure = false
            request(.resume, expectedTrack: ownership?.track)
            transition(.restoringPlayback)
        } else {
            transition(sourceIsValid ? desiredIdleState() : .searchingForSource)
        }
        log(.info, .lifecycle, "System woke; reconciling playback.")
    }

    /// Called when Oreja is about to quit. Returns a command the app must execute (and await)
    /// so a graceful quit never leaves the user's music paused by Oreja.
    public func commandForTermination() -> Command? {
        guard ownership != nil else { return nil }
        let kind: CommandKind = .resume
        let command = Command(kind: kind, expectedTrack: ownership?.track, issuedAt: now())
        pendingCommand = command
        queuedIntent = nil
        cancelSilence()
        log(.info, .lifecycle, "Restoring playback before quitting.")
        transition(.restoringPlayback)
        return command
    }

    /// Marks the ownership journal as cleared (used after a termination resume succeeds).
    public func acknowledgeTermination() {
        ownership = nil
        pendingCommand = nil
        journal?.clear()
        notify()
    }

    public func reset() {
        cancelSilence()
        pendingCommand = nil
        queuedIntent = nil
        silenceToken = nil
        ownership = nil
        aiIsActive = false
        userOverrodeDuringActivity = false
        lastSnapshot = nil
        lastError = nil
        consecutiveFailures = 0
        statistics = CoordinatorStatistics()
        sourceIsValid = false
        sourceDescription = ""
        automationEnabled = false
        transition(.disabled)
    }

    // MARK: - Command routing

    private func request(_ kind: CommandKind, expectedTrack: MediaTrack?) {
        guard state != .permissionRequired else { return }

        if pendingCommand != nil {
            queuedIntent = kind
            log(.info, .playback, "Queued \(kind.rawValue); another command is in flight.")
            return
        }

        let command = Command(kind: kind, expectedTrack: expectedTrack, issuedAt: now())
        pendingCommand = command
        log(.info, .playback, "Issuing \(kind.rawValue) for \(expectedTrack?.displayName ?? "current music").")
        onCommand?(command)
        notify()
    }

    private func drainQueuedIntent() {
        guard let intent = queuedIntent else { return }
        queuedIntent = nil

        switch intent {
        case .pause:
            guard automationEnabled, aiIsActive, sourceIsValid,
                  ownership == nil,
                  let snapshot = lastSnapshot, snapshot.isPlaying else { return }
            request(.pause, expectedTrack: snapshot.track)
        case .resume:
            guard automationEnabled, !aiIsActive, sourceIsValid,
                  let own = ownership,
                  pendingCommand == nil else { return }
            guard let snapshot = lastSnapshot, snapshot.isPaused, snapshot.refersTo(own.track) else {
                releaseOwnership(reason: "queued resume no longer applicable")
                journal?.clear()
                return
            }
            quietElapsedTime = now()
            request(.resume, expectedTrack: own.track)
            transition(.restoringPlayback)
        }
    }

    private func scheduleQuietInterval() {
        cancelSilence()
        let token = UUID()
        silenceToken = token
        transition(.waitingForSilence)
        log(.info, .detection, "AI is quiet; waiting \(Int(policy.quietInterval * 1000)) ms before resuming music.")
        let delay = policy.quietInterval
        silenceTask = scheduler.schedule(after: delay) { [weak self] in
            self?.quietIntervalElapsed(token)
        }
    }

    private func quietIntervalElapsed(_ token: UUID) {
        guard silenceToken == token else { return }
        silenceToken = nil
        silenceTask = nil

        guard automationEnabled, !aiIsActive, sourceIsValid else { return }

        if pendingCommand?.kind == .pause {
            // The pause was slow; resume once it lands (ownership does not exist yet).
            queuedIntent = .resume
            return
        }
        guard let own = ownership else { return }
        guard pendingCommand == nil else {
            queuedIntent = .resume
            return
        }
        guard let snapshot = lastSnapshot else {
            releaseOwnership(reason: "no playback observation during the quiet interval")
            journal?.clear()
            transition(desiredIdleState())
            return
        }
        switch snapshot.state {
        case .paused:
            guard snapshot.refersTo(own.track) else {
                releaseOwnership(reason: "the paused track changed during the quiet interval")
                journal?.clear()
                transition(desiredIdleState())
                return
            }
        case .playing:
            // The adapter paused playback but reported the previous state. Resuming a playing
            // provider is harmless; leaving an owned pause behind is not.
            log(.warning, .playback, "Provider still reported playing after a successful pause; resuming to avoid a stuck pause.")
        case .stopped, .unavailable, .permissionRequired:
            releaseOwnership(reason: "playback state changed during the quiet interval")
            journal?.clear()
            transition(desiredIdleState())
            return
        }

        quietElapsedTime = now()
        request(.resume, expectedTrack: own.track)
        transition(.restoringPlayback)
    }

    private func cancelSilence() {
        silenceTask?.cancel()
        silenceTask = nil
        silenceToken = nil
    }

    private func restoreOwnedPause(reason: String) {
        guard ownership != nil else { return }
        guard policy.restoreOwnedPauseOnFailure else {
            log(.warning, .recovery, "Leaving music paused (\(reason)); automatic restore is disabled.")
            return
        }
        guard let snapshot = lastSnapshot else {
            releaseOwnership(reason: "no playback observation for the owned pause")
            journal?.clear()
            return
        }
        switch snapshot.state {
        case .paused:
            guard snapshot.refersTo(ownership?.track) else {
                releaseOwnership(reason: "playback no longer matches the owned pause")
                journal?.clear()
                return
            }
        case .playing:
            log(.warning, .playback, "Provider reported playing while Oreja held a pause; issuing a harmless resume.")
        case .stopped, .unavailable, .permissionRequired:
            releaseOwnership(reason: "playback provider became unavailable")
            journal?.clear()
            return
        }
        log(.info, .recovery, "Restoring playback because \(reason).")
        quietElapsedTime = now()
        request(.resume, expectedTrack: ownership?.track)
        transition(.restoringPlayback)
    }

    private func releaseOwnership(reason: String) {
        guard ownership != nil else { return }
        ownership = nil
        journal?.clear()
        log(.info, .playback, "Released pause ownership (\(reason)).")
    }

    // MARK: - Derived state

    private func desiredIdleState() -> CoordinatorState {
        guard automationEnabled else { return .disabled }
        guard state != .permissionRequired, state != .suspended, state != .error else { return state }
        guard sourceIsValid else { return .searchingForSource }
        if aiIsActive { return ownership != nil ? .musicPausedByOreja : .aiActive }
        if let snapshot = lastSnapshot {
            if snapshot.isPlaying { return .musicPlaying }
            if ownership != nil { return .musicPausedByOreja }
        }
        return .monitoring
    }

    private func providerProblemState(_ snapshot: MediaPlaybackSnapshot) -> CoordinatorState? {
        switch snapshot.state {
        case .permissionRequired: .permissionRequired
        case .unavailable, .stopped: nil
        default: nil
        }
    }

    private func noteProviderProblem(_ snapshot: MediaPlaybackSnapshot) {
        guard snapshot.state == .permissionRequired else { return }
        lastError = "Automation permission for \(snapshot.provider.displayName) is required."
    }

    private func transition(_ newState: CoordinatorState) {
        guard state != newState else {
            notify()
            return
        }
        state = newState
        notify()
    }

    private func notify() {
        onStateChanged?()
    }

    private func log(_ level: DiagnosticEvent.Level, _ category: DiagnosticEvent.Category, _ message: String) {
        diagnostics?.record(
            DiagnosticEvent(level: level, category: category, message: message)
        )
    }
}
