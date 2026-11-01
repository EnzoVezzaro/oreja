import Foundation
import OrejaCore
import OrejaMedia

@MainActor
final class MutableClock {
    var now: TimeInterval = 1_000

    func advance(_ seconds: TimeInterval) {
        now += seconds
    }
}

@MainActor
final class ManualScheduledAction: ScheduledAction {
    private(set) var remaining: TimeInterval
    private(set) var isCancelled = false
    private let action: @MainActor () -> Void

    init(delay: TimeInterval, action: @escaping @MainActor () -> Void) {
        self.remaining = delay
        self.action = action
    }

    func cancel() {
        isCancelled = true
    }

    func tick(_ seconds: TimeInterval) -> Bool {
        guard !isCancelled else { return false }
        remaining -= seconds
        guard remaining <= 0 else { return false }
        action()
        isCancelled = true
        return true
    }
}

@MainActor
final class ManualScheduler: SilenceScheduling {
    private(set) var actions: [ManualScheduledAction] = []

    func schedule(after delay: TimeInterval, action: @escaping @MainActor () -> Void) -> any ScheduledAction {
        let scheduled = ManualScheduledAction(delay: delay, action: action)
        actions.append(scheduled)
        return scheduled
    }

    /// Moves time forward and fires any scheduled actions whose delay has elapsed.
    func advance(by seconds: TimeInterval) {
        let pending = actions.filter { !$0.isCancelled }
        pending.forEach { _ = $0.tick(seconds) }
    }

    var pendingCount: Int {
        actions.filter { !$0.isCancelled }.count
    }
}

@MainActor
final class RecordingDiagnostics: DiagnosticsSink {
    private(set) var events: [DiagnosticEvent] = []

    func record(_ event: DiagnosticEvent) {
        events.append(event)
    }

    func messages(level: DiagnosticEvent.Level? = nil) -> [String] {
        events.filter { level == nil || $0.level == level }.map(\.message)
    }
}

@MainActor
final class RecordingJournal: PauseJournal {
    private(set) var record: PauseJournalRecord?
    private(set) var saveCount = 0
    private(set) var clearCount = 0

    func load() -> PauseJournalRecord? { record }

    func save(_ record: PauseJournalRecord) {
        self.record = record
        saveCount += 1
    }

    func clear() {
        record = nil
        clearCount += 1
    }
}

/// Test double for the media adapter that records commands without executing them, so the
/// coordinator's command/completion protocol can be driven step by step.
@MainActor
final class ScriptedMediaController: MediaPlaybackController {
    let provider: MediaProviderID = .appleMusic
    let capabilities = MediaCapabilities(
        canPause: true,
        canResume: true,
        canSetVolume: false,
        canReportTrackIdentity: true,
        requiresAutomationPermission: true
    )

    var snapshot: MediaPlaybackSnapshot
    private(set) var pauseCalls = 0
    private(set) var resumeCalls = 0

    init(state: MediaPlaybackSnapshot.PlaybackState, track: MediaTrack? = MediaTrack(id: "track-1", title: "Aja", artist: "Steely Dan")) {
        snapshot = MediaPlaybackSnapshot(
            state: state,
            track: track,
            provider: .appleMusic,
            capturedAt: 1_000
        )
    }

    func currentPlayback() async -> MediaPlaybackSnapshot { snapshot }

    func pause() async throws {
        pauseCalls += 1
    }

    func resume() async throws {
        resumeCalls += 1
    }
}

@MainActor
final class CoordinatorFixture {
    let clock = MutableClock()
    let scheduler = ManualScheduler()
    let media: ScriptedMediaController
    let journal = RecordingJournal()
    let diagnostics = RecordingDiagnostics()
    let coordinator: PlaybackCoordinator
    private(set) var commands: [PlaybackCoordinator.Command] = []

    init(mediaState: MediaPlaybackSnapshot.PlaybackState = .playing) {
        media = ScriptedMediaController(state: mediaState)
        let clock = clock
        let scheduler = scheduler
        let journal = journal
        let diagnostics = diagnostics
        coordinator = PlaybackCoordinator(
            policy: .default,
            scheduler: scheduler,
            diagnostics: diagnostics,
            journal: journal,
            now: { clock.now },
            dateProvider: { Date(timeIntervalSince1970: 1_700_000_000) }
        )
        coordinator.onCommand = { [weak self] command in
            self?.commands.append(command)
        }
    }

    func startMonitoring() async {
        coordinator.setAutomationEnabled(true)
        coordinator.monitoringBecameAvailable(description: "ChatGPT (1 audio process)")
        coordinator.observe(media: media.snapshot)
    }

    var lastCommand: PlaybackCoordinator.Command? { commands.last }

    func commands(of kind: PlaybackCoordinator.CommandKind) -> [PlaybackCoordinator.Command] {
        commands.filter { $0.kind == kind }
    }

    /// Simulates the adapter completing the most recent command and updates the fake provider.
    func completeLast(
        succeeded: Bool = true,
        nextState: MediaPlaybackSnapshot.PlaybackState? = nil,
        track: MediaTrack? = nil,
        restoreStateForFailure: Bool = true
    ) {
        guard let command = commands.last else {
            preconditionFailure("No command to complete")
        }
        if succeeded {
            if let nextState {
                media.snapshot.state = nextState
            }
            if let track {
                media.snapshot.track = track
            }
            media.snapshot.capturedAt = clock.now
            coordinator.complete(command.id, outcome: .succeeded(media.snapshot))
        } else {
            if restoreStateForFailure, command.kind == .pause {
                media.snapshot.state = .playing
            }
            coordinator.complete(
                command.id,
                outcome: .failed(command.kind == .pause ? .commandFailed("simulated pause failure") : .commandFailed("simulated resume failure"))
            )
        }
    }

    /// Completes a command without changing the provider snapshot (used for race tests).
    func completeWithCurrentSnapshot(_ command: PlaybackCoordinator.Command) {
        coordinator.complete(command.id, outcome: .succeeded(media.snapshot))
    }
}
