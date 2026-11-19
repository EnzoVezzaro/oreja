import AppKit
import Combine
import Foundation
import OrejaAudio
import OrejaCore
import OrejaMedia
import SwiftUI

/// The app's single coordinator. It owns the state machine, the audio monitor, the music adapter
/// and the persistence, so views stay declarative and the decision to pause never leaks into UI code.
@MainActor
final class AppModel: ObservableObject {
    static let shared = AppModel()

    // MARK: Published state

    @Published private(set) var state: CoordinatorState = .disabled
    @Published private(set) var music: MediaPlaybackSnapshot?
    @Published private(set) var sourceDescription = ""
    @Published private(set) var lastError: String?
    @Published private(set) var isMonitoring = false
    @Published private(set) var hasAudioPermission = true
    @Published private(set) var report: ConnectionCheckReport?
    @Published private(set) var isRunningCheck = false
    @Published private(set) var launchAtLoginError: String?
    @Published private(set) var userSpeechError: String?
    @Published private(set) var isListeningForUser = false

    @Published var settings: AppSettings {
        didSet {
            guard settings != oldValue else { return }
            settingsStore.save(settings)
            applySettingsChange(from: oldValue)
        }
    }

    // MARK: Collaborators

    let coordinator: PlaybackCoordinator
    let diagnostics: DiagnosticsLog
    let media: any MediaPlaybackController & MediaAdministration
    private let monitorFactory: any AIAudioMonitorFactory
    private var targetAudioMuteController: ProcessAudioTargetMuteController?
    private let browserAudioController = BrowserAudioController()
    private let settingsStore: any SettingsStoring
    private let pauseJournal: any PauseJournal
    private let hookExecutor: any HookExecuting = MacHookExecutor()
    /// Fires the user's hooks. Set at the end of `init`, once `settings` is readable.
    private var hookDispatcher: HookDispatcher?

    // MARK: Private state

    private var monitor: (any AIAudioMonitoring)?
    private var eventTask: Task<Void, Never>?
    private var speechMonitor: MicrophoneActivityMonitor?
    private var speechEventTask: Task<Void, Never>?
    private var activity = ActivityAggregator()
    private var observationTask: Task<Void, Never>?
    private var retryTask: Task<Void, Never>?
    private var hasRunStalePauseRecovery = false
    private var windows = WindowRegistry()
    /// Last ownership seen, so hooks fire on the transition and not on every state refresh.
    private var lastOwnership: PauseOwnership?
    private var lastVolumeOwnership: VolumeOwnership?
    private var lastTargetMuteIntent: Bool?
    private var lastUnsupportedBrowserTargetIDs = Set<String>()
    private var lastBrowserControlError: String?
    private var browserInterruptionTargets: [AISourceSelection]?
    private var browserInterruptionMode: MusicInterruptionMode?
    private var browserInterruptionDuckPercent: Int?

    init(
        settingsStore: (any SettingsStoring)? = nil,
        pauseJournal: (any PauseJournal)? = nil,
        monitorFactory: (any AIAudioMonitorFactory)? = nil,
        media: (any MediaPlaybackController & MediaAdministration)? = nil
    ) {
        let resolvedStore = settingsStore ?? UserDefaultsSettingsStore()
        let resolvedJournal = pauseJournal ?? UserDefaultsPauseJournal()
        let loaded = resolvedStore.load()
        self.settingsStore = resolvedStore
        self.pauseJournal = resolvedJournal
        self.monitorFactory = monitorFactory ?? ProcessAudioMonitorFactory()
        if #available(macOS 14.2, *) {
            self.targetAudioMuteController = ProcessAudioTargetMuteController()
        }
        let resolvedMedia: any MediaPlaybackController & MediaAdministration = media ?? AppleMusicController()
        self.media = resolvedMedia
        self.settings = loaded

        let diagnostics = DiagnosticsLog()
        self.diagnostics = diagnostics
        self.coordinator = PlaybackCoordinator(
            policy: loaded.policy,
            diagnostics: diagnostics,
            journal: resolvedJournal,
            canSetVolume: resolvedMedia.capabilities.canSetVolume
        )

        coordinator.onCommand = { [weak self] command in
            self?.perform(command)
        }
        coordinator.onStateChanged = { [weak self] in
            self?.publishCoordinatorState()
        }

        diagnostics.isVerbose = loaded.verboseDiagnostics
        diagnostics.onChange = { [weak self] in
            self?.objectWillChange.send()
        }

        hookDispatcher = HookDispatcher(
            hooks: { [weak self] in self?.settings.hooks ?? [] },
            executor: hookExecutor,
            diagnostics: diagnostics
        )

        observeSystemEvents()
    }

    // MARK: Hooks

    /// Publishes one of Oreja's own events to the user's hooks. Nothing about the conversation is
    /// included: the detail is a description of what Oreja itself just did.
    private func fire(_ event: OrejaEvent, detail: String) {
        hookDispatcher?.emit(HookContext(event: event, detail: detail))
    }

    func addHook() {
        settings.hooks.append(Hook(name: "New hook"))
    }

    func updateHook(_ hook: Hook) {
        guard let index = settings.hooks.firstIndex(where: { $0.id == hook.id }) else { return }
        guard settings.hooks[index] != hook else { return }
        settings.hooks[index] = hook
    }

    func removeHook(id: UUID) {
        settings.hooks.removeAll { $0.id == id }
    }

    /// Proves a hook works now, including one whose event has not happened yet.
    func testHook(_ hook: Hook) {
        hookDispatcher?.runManually(hook)
    }

    // MARK: Lifecycle

    /// Called once, when the app finishes launching.
    func bootstrap() {
        coordinator.updatePolicy(settings.policy)
        if settings.automationEnabled {
            coordinator.setAutomationEnabled(true)
            startObservation()
            // Do not create an audio tap before onboarding has explained why. The first tap
            // triggers the system permission prompt, so it belongs to onboarding step 4.
            if settings.onboardingCompleted {
                startMonitoringIfNeeded()
                startUserSpeechMonitoring()
            }
        }
        publishCoordinatorState()
        refreshMusic()
        if !settings.onboardingCompleted {
            showOnboarding()
        }
    }

    func setAutomationEnabled(_ enabled: Bool) {
        guard settings.automationEnabled != enabled else {
            if enabled { startMonitoringIfNeeded() }
            return
        }
        settings.automationEnabled = enabled
    }

    func toggleAutomation() {
        setAutomationEnabled(!settings.automationEnabled)
    }

    /// Adds the app to the listened-to set, or removes it when it is already selected.
    func toggleSource(_ selection: AISourceSelection) {
        if settings.aiSources.contains(where: { $0.bundleIdentifier == selection.bundleIdentifier }) {
            settings.aiSources.removeAll { $0.bundleIdentifier == selection.bundleIdentifier }
        } else {
            settings.targetAudioApps.removeAll { $0.bundleIdentifier == selection.bundleIdentifier }
            settings.aiSources.append(selection)
        }
    }

    func toggleTargetAudioApp(_ selection: AISourceSelection) {
        if settings.targetAudioApps.contains(where: { $0.bundleIdentifier == selection.bundleIdentifier }) {
            settings.targetAudioApps.removeAll { $0.bundleIdentifier == selection.bundleIdentifier }
        } else {
            settings.aiSources.removeAll { $0.bundleIdentifier == selection.bundleIdentifier }
            settings.targetAudioApps.append(selection)
        }
    }

    func refreshMusic() {
        Task { [weak self] in
            guard let self else { return }
            let snapshot = await self.media.currentPlayback()
            self.music = snapshot
            self.coordinator.observe(media: snapshot)
            self.considerStalePauseRecovery(snapshot)
        }
    }

    func launchMusic() {
        media.launchProvider()
    }

    func openSystemAudioSettings() {
        openPrivacyPane(anchor: "Privacy_ScreenCapture")
    }

    func openAutomationSettings() {
        openPrivacyPane(anchor: "Privacy_Automation")
    }

    // MARK: Settings side effects

    private func applySettingsChange(from previous: AppSettings) {
        diagnostics.isVerbose = settings.verboseDiagnostics
        coordinator.updatePolicy(settings.policy)

        if settings.launchAtLogin != previous.launchAtLogin {
            LaunchAtLogin.apply(settings.launchAtLogin) { [weak self] error in
                guard let self else { return }
                self.launchAtLoginError = error
                if let error {
                    self.record(.warning, .settings, "Could not change launch at login: \(error)")
                }
            }
        }

        if settings.aiSources != previous.aiSources {
            stopMonitoring(reason: "audio sources changed")
            if settings.automationEnabled { startMonitoringIfNeeded() }
        }

        if settings.automationEnabled != previous.automationEnabled {
            if settings.automationEnabled {
                coordinator.setAutomationEnabled(true)
                startObservation()
                startMonitoringIfNeeded()
            } else {
                coordinator.setAutomationEnabled(false)
                stopMonitoring(reason: "automation disabled")
                stopObservation()
            }
        }

        if settings.audioMonitorOptions != previous.audioMonitorOptions {
            stopMonitoring(reason: "detection setting changed")
            if settings.automationEnabled { startMonitoringIfNeeded() }
        }

        if settings.microphoneSensitivity != previous.microphoneSensitivity {
            stopUserSpeechMonitoring(reason: "microphone sensitivity changed")
            startUserSpeechMonitoring()
        }

        if settings.pauseWhileISpeak != previous.pauseWhileISpeak {
            if settings.pauseWhileISpeak, settings.automationEnabled {
                startUserSpeechMonitoring()
            } else {
                stopUserSpeechMonitoring(reason: "option turned off")
            }
        }

        // Playback mode and target duck level are applied by the target adapters directly, so
        // refresh them even when changing those preferences does not emit a coordinator event.
        syncTargetAudioMute()
        record(.info, .settings, "Settings updated.")
    }

    // MARK: Monitoring

    func startMonitoringIfNeeded() {
        guard settings.automationEnabled, monitor == nil else { return }
        retryTask?.cancel()
        retryTask = nil

        guard !settings.aiSources.isEmpty else {
            coordinator.monitoringFailed(AudioMonitoringFailure(.sourceUnavailable, "Choose at least one audio app to listen to."))
            return
        }

        let descriptor = AIAudioSourceDescriptor(selections: settings.aiSources)
        let newMonitor = monitorFactory.makeMonitor(
            for: descriptor,
            options: settings.audioMonitorOptions
        )
        monitor = newMonitor
        record(
            .info,
            .monitoring,
            settings.ignoreNotificationSounds
                ? "Starting audio monitor for \(descriptor.displayName); ignoring notification sounds."
                : "Starting audio monitor for \(descriptor.displayName)."
        )

        let monitorID = ObjectIdentifier(newMonitor as AnyObject)
        eventTask = Task { [weak self] in
            for await event in newMonitor.events {
                guard let self else { return }
                self.handle(event)
            }
            guard let self else { return }
            // An intentional stop also ends the stream; only a monitor that is still the current
            // one has ended unexpectedly.
            self.monitorEndedUnexpectedly(monitorID: monitorID)
        }

        Task { [weak self] in
            do {
                try await newMonitor.start()
                guard let self else { return }
                self.isMonitoring = true
                self.hasAudioPermission = true
            } catch {
                guard let self else { return }
                self.handleStartFailure(error)
            }
        }

        startUserSpeechMonitoring()
    }

    func stopMonitoring(reason: String) {
        stopUserSpeechMonitoring(reason: reason)
        activity.reset()
        // The aggregator forgets activity here, so the coordinator must hear that it ended too.
        // Otherwise a stale `aiIsActive` makes every later voice onset return without pausing.
        coordinator.audioActivityEnded()
        retryTask?.cancel()
        retryTask = nil
        isMonitoring = false

        if let monitor {
            self.monitor = nil
            eventTask?.cancel()
            eventTask = nil
            Task { await monitor.stop() }
        }
        record(.info, .monitoring, "Stopped monitoring: \(reason).")
    }

    private func handle(_ event: AudioActivityEvent) {
        switch event {
        case .monitorStarted(let description):
            isMonitoring = true
            hasAudioPermission = true
            sourceDescription = description
            coordinator.monitoringBecameAvailable(description: description)
            fire(.monitoringStarted, detail: "Listening to \(description)")
        case .targetsChanged(let description):
            // The app opened a new audio process (for example the renderer that appears when a
            // voice conversation starts). The tap was rebuilt; music must not resume because of it.
            sourceDescription = description
            record(.info, .monitoring, "Now listening to \(description).")
        case .monitorStopped(let reason):
            isMonitoring = false
            sourceDescription = ""
            record(.info, .monitoring, reason)
        case .noSignalDetected(let detail):
            // Diagnostic only. There is no public API to query the System Audio Recording grant,
            // so a silent tap cannot be treated as a confirmed permission failure — doing so would
            // stop automation and restore playback on a false positive. Call the user's attention
            // to the check without changing the coordinator's state.
            record(.warning, .permissions, detail)
        case .monitorFailed(let failure):
            isMonitoring = false
            if failure.kind == .permissionDenied { hasAudioPermission = false }
            coordinator.monitoringFailed(failure)
            fire(.monitoringFailed, detail: failure.message)
            if failure.kind == .permissionDenied {
                fire(.permissionRequired, detail: failure.message)
            }
            // The monitored app quit or dropped all of its audio processes. Without this the tap
            // would stay dead until the user toggled automation by hand.
            if failure.kind != .permissionDenied {
                scheduleMonitoringRetry()
            }
        case .activityStarted(let levelDB):
            if activity.set(true, for: .ai) {
                coordinator.audioActivityStarted(levelDB: levelDB)
                fire(.speechStarted, detail: "The AI source started speaking")
            }
        case .activityEnded:
            if activity.set(false, for: .ai) {
                coordinator.audioActivityEnded()
                fire(.speechEnded, detail: "The AI source went quiet")
            }
        case .activitySuppressed(let reason, let levelDB):
            fire(.soundIgnored, detail: "Ignored a sound that was \(reason.explanation)")
            // Not activity: nothing to pause for. The log line is what makes the option
            // verifiable, so a user can see a chime being ignored instead of guessed at.
            record(
                .info,
                .monitoring,
                String(format: "Ignored a sound from the AI source: %@ (%.0f dBFS).", reason.explanation, levelDB)
            )
        }
        publishCoordinatorState()
    }

    // MARK: User speech

    /// Starts the optional microphone monitor. Only ever called while automation is enabled and the
    /// user turned the option on; it never runs by default.
    func startUserSpeechMonitoring() {
        guard settings.pauseWhileISpeak, settings.automationEnabled else { return }
        guard #available(macOS 14.2, *) else { return }
        guard speechMonitor == nil else { return }

        let monitor = MicrophoneActivityMonitor(sensitivity: settings.microphoneSensitivity)
        speechMonitor = monitor
        record(.info, .monitoring, "Listening for your voice as well.")

        speechEventTask = Task { [weak self] in
            for await event in monitor.events {
                guard let self else { return }
                self.handleSpeech(event)
            }
        }

        Task { [weak self] in
            do {
                try await monitor.start()
                guard let self else { return }
                self.isListeningForUser = true
                self.userSpeechError = nil
            } catch {
                guard let self else { return }
                let message = (error as? AudioMonitoringFailure)?.message ?? error.localizedDescription
                self.userSpeechError = message
                self.isListeningForUser = false
                self.record(.error, .permissions, "Microphone unavailable: \(message)")
                self.stopUserSpeechMonitoring(reason: "microphone unavailable")
            }
        }
    }

    private func stopUserSpeechMonitoring(reason: String) {
        guard let monitor = speechMonitor else { return }
        speechMonitor = nil
        speechEventTask?.cancel()
        speechEventTask = nil
        isListeningForUser = false
        if activity.set(false, for: .user) {
            coordinator.audioActivityEnded()
        }
        coordinator.setUserSpeechActive(false)
        Task { await monitor.stop() }
        record(.info, .monitoring, "Stopped listening for your voice: \(reason).")
        publishCoordinatorState()
    }

    private func handleSpeech(_ event: AudioActivityEvent) {
        switch event {
        case .monitorStarted:
            isListeningForUser = true
            userSpeechError = nil
        case .targetsChanged:
            break
        case .monitorStopped:
            isListeningForUser = false
        case .monitorFailed(let failure):
            isListeningForUser = false
            userSpeechError = failure.message
            if activity.set(false, for: .user) {
                coordinator.audioActivityEnded()
            }
            coordinator.setUserSpeechActive(false)
        case .activityStarted(let levelDB):
            // User speech must be able to start a pause when the person speaks first. Headphones
            // are recommended because speakers can feed Music back into this microphone. The
            // coordinator still owns the pause and the activity aggregator prevents duplicate
            // pause requests when AI and user activity overlap.
            coordinator.setUserSpeechActive(true)
            if activity.set(true, for: .user) {
                record(.info, .monitoring, "Your voice is active; pausing music.")
                coordinator.audioActivityStarted(levelDB: levelDB)
            }
        case .activityEnded:
            if activity.set(false, for: .user) {
                coordinator.audioActivityEnded()
            }
            coordinator.setUserSpeechActive(false)
        case .activitySuppressed:
            // The microphone path is not gated: it exists to hear the person in the room, and a
            // hesitation in their own sentence should not be second-guessed.
            break
        case .noSignalDetected:
            // Only the process tap emits this hint; the microphone monitor does not.
            break
        }
        publishCoordinatorState()
    }

    private func handleStartFailure(_ error: Error) {
        isMonitoring = false
        let failure = (error as? AudioMonitoringFailure)
            ?? AudioMonitoringFailure(.unknown, error.localizedDescription)
        if failure.kind == .permissionDenied {
            hasAudioPermission = false
        }
        coordinator.monitoringFailed(failure)
        publishCoordinatorState()
        // A missing permission cannot fix itself. Retrying would only re-prompt or spin; the user
        // grants access and then uses Retry.
        if failure.kind != .permissionDenied {
            scheduleMonitoringRetry()
        }
    }

    private func monitorEndedUnexpectedly(monitorID: ObjectIdentifier) {
        guard settings.automationEnabled else { return }
        guard let monitor, ObjectIdentifier(monitor as AnyObject) == monitorID else { return }
        isMonitoring = false
        coordinator.sourceInvalidated(reason: "the audio monitor stopped")
        scheduleMonitoringRetry()
    }

    /// Retries are intentionally slow and bounded by the coordinator's own state, never a tight loop.
    private func scheduleMonitoringRetry() {
        guard settings.automationEnabled, retryTask == nil else { return }
        stopMonitoringKeepRetry()
        retryTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard let self, !Task.isCancelled else { return }
            self.retryTask = nil
            self.startMonitoringIfNeeded()
        }
    }

    private func stopMonitoringKeepRetry() {
        if let monitor {
            self.monitor = nil
            eventTask?.cancel()
            eventTask = nil
            Task { await monitor.stop() }
        }
    }

    /// Selected applications that are running now, by display name.
    private func runningSourceNames() -> [String] {
        let running = NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier)
        return settings.aiSources.filter { selection in
            let prefixes = AISourceCatalog.matchPrefixes(for: selection)
            return running.contains { id in prefixes.contains { id.hasPrefix($0) } }
        }.map(\.displayName)
    }

    // MARK: Music observation

    private func startObservation() {
        observationTask?.cancel()
        observationTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let snapshot = await self.media.currentPlayback()
                self.music = snapshot
                self.coordinator.observe(media: snapshot)
                self.considerStalePauseRecovery(snapshot)
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }
    }

    private func stopObservation() {
        observationTask?.cancel()
        observationTask = nil
    }

    /// If a previous run of Oreja left music paused, restore exactly that pause once and only when
    /// the same track is still loaded. This is the crash-safety half of pause ownership.
    private func considerStalePauseRecovery(_ snapshot: MediaPlaybackSnapshot) {
        guard !hasRunStalePauseRecovery, settings.automationEnabled else { return }
        guard coordinator.ownership == nil else {
            hasRunStalePauseRecovery = true
            return
        }
        hasRunStalePauseRecovery = true
        let journalRecord = pauseJournal.load()
        let decision = StalePauseRecovery.decide(
            record: journalRecord,
            snapshot: snapshot,
            maxAge: PlaybackPolicy.default.staleOwnershipLifetime
        )
        switch decision {
        case .resume:
            record(.warning, .recovery, "A previous pause was left behind for the same track; restoring it.")
            Task { [weak self] in
                guard let self else { return }
                do {
                    try await self.media.resume()
                    self.pauseJournal.clear()
                    let refreshed = await self.media.currentPlayback()
                    self.music = refreshed
                    self.coordinator.observe(media: refreshed)
                    self.record(.success, .recovery, "Restored playback after an earlier exit.")
                } catch {
                    self.pauseJournal.clear()
                    self.record(.error, .recovery, "Could not restore the earlier pause: \(error.localizedDescription)")
                }
            }
        case .discard(let reason):
            if journalRecord != nil {
                record(.info, .recovery, "Left the earlier pause alone: \(reason)")
            }
            pauseJournal.clear()
        }
    }

    // MARK: Commands

    private func perform(_ command: PlaybackCoordinator.Command) {
        Task { [weak self] in
            guard let self else { return }
            do {
                let snapshot: MediaPlaybackSnapshot
                switch command.kind {
                case .pause:
                    snapshot = try await self.media.pauseReporting()
                case .resume:
                    snapshot = try await self.media.resumeReporting()
                case .setVolume:
                    guard let target = command.targetVolume else {
                        throw MediaControlError.commandFailed("No target volume was provided.")
                    }
                    try await self.media.setVolume(target)
                    snapshot = await self.media.currentPlayback()
                }
                self.music = snapshot
                self.coordinator.complete(command.id, outcome: .succeeded(snapshot))
            } catch let error as MediaControlError {
                self.coordinator.complete(command.id, outcome: .failed(error))
            } catch {
                self.coordinator.complete(
                    command.id,
                    outcome: .failed(.commandFailed(error.localizedDescription))
                )
            }
            self.publishCoordinatorState()
        }
    }

    // MARK: Coordinator mirror

    private func publishCoordinatorState() {
        state = coordinator.state
        lastError = coordinator.lastError
        syncTargetAudioMute()

        // Hooks fire on ownership transitions: the moment Oreja takes responsibility for playback
        // and the moment it gives it back. Comparing ownership rather than state keeps this
        // correct in both pause and lower-volume modes.
        let ownership = coordinator.ownership
        let volumeOwnership = coordinator.volumeOwnership
        if (lastOwnership == nil) != (ownership == nil) {
            fire(
                ownership == nil ? .musicResumed : .musicPaused,
                detail: ownership == nil ? "Music resumed" : "Music paused by Oreja"
            )
        }
        if (lastVolumeOwnership == nil) != (volumeOwnership == nil) {
            fire(
                volumeOwnership == nil ? .volumeRestored : .volumeLowered,
                detail: volumeOwnership == nil ? "Music volume restored" : "Music volume lowered by Oreja"
            )
        }
        lastOwnership = ownership
        lastVolumeOwnership = volumeOwnership

        objectWillChange.send()
    }

    private func syncTargetAudioMute() {
        guard #available(macOS 14.2, *), let targetAudioMuteController else { return }
        let primaryIDs = Set(settings.aiSources.map(\.bundleIdentifier))
        let targets = settings.targetAudioApps.filter { !primaryIDs.contains($0.bundleIdentifier) }
        let shouldInterrupt = coordinator.shouldMuteTargetAudio
        if shouldInterrupt {
            if browserInterruptionTargets == nil {
                browserInterruptionTargets = browserPlaybackTargets()
                browserInterruptionMode = settings.interruptionMode
                browserInterruptionDuckPercent = settings.duckVolumePercent
            }
        } else {
            browserInterruptionTargets = nil
            browserInterruptionMode = nil
            browserInterruptionDuckPercent = nil
        }
        browserAudioController.update(
            applications: settings.browserPlaybackEnabled ? (browserInterruptionTargets ?? []) : [],
            active: shouldInterrupt,
            mode: browserInterruptionMode ?? settings.interruptionMode,
            duckPercent: browserInterruptionDuckPercent ?? settings.duckVolumePercent
        )
        let unsupported = Set(browserAudioController.unsupportedBundleIdentifiers)
        if unsupported != lastUnsupportedBrowserTargetIDs {
            if !unsupported.isEmpty {
                record(.warning, .monitoring, "No browser media adapter is available for: \(unsupported.sorted().joined(separator: ", ")).")
            }
            lastUnsupportedBrowserTargetIDs = unsupported
        }
        if let error = browserAudioController.lastErrorMessage, error != lastBrowserControlError {
            record(.warning, .monitoring, error)
            lastBrowserControlError = error
        } else if browserAudioController.lastErrorMessage == nil {
            lastBrowserControlError = nil
        }

        // Browser playback is controlled through the selected media sessions. Other selected app
        // targets retain the existing process-level mute behavior.
        let processMuteTargets = targets.filter { !AISourceCatalog.isBrowser(bundleIdentifier: $0.bundleIdentifier) }
        let shouldMute = shouldInterrupt && !processMuteTargets.isEmpty
        do {
            try targetAudioMuteController.update(
                applications: processMuteTargets,
                shouldMute: shouldMute
            )
            if !processMuteTargets.isEmpty, lastTargetMuteIntent != shouldMute {
                record(.info, .monitoring, shouldMute
                    ? "Muting selected secondary app audio during speech."
                    : "Released selected secondary app mute.")
            }
            lastTargetMuteIntent = shouldMute
        } catch {
            lastTargetMuteIntent = nil
            record(.warning, .monitoring, "Could not control selected app audio: \(error.localizedDescription)")
        }
    }

    private func browserPlaybackTargets() -> [AISourceSelection] {
        let supported = AISourceCatalog.knownApps.filter {
            $0.category == .browser && BrowserAudioController.supportedBrowserBundleIDs.contains($0.bundleIdentifier)
        }
        let candidates = supported.map {
            AISourceSelection.browser(bundleIdentifier: $0.bundleIdentifier, displayName: $0.displayName)
        }
        guard settings.browserTargetScope == .activeBrowserOnly else { return candidates }
        guard let frontmostID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier else { return [] }
        return candidates.filter { $0.bundleIdentifier == frontmostID }
    }

    // MARK: System events

    private func observeSystemEvents() {
        let workspace = NSWorkspace.shared.notificationCenter
        workspace.addObserver(
            forName: NSWorkspace.willSleepNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.coordinator.systemWillSleep()
                self?.fire(.sleep, detail: "The Mac is going to sleep")
                // Core Audio taps and AVAudioEngine can stop delivering audio while the Mac sleeps.
                // Both monitors are cleared so wake-up creates fresh taps. Leaving the app monitor
                // in place made wake-up a no-op, because startMonitoringIfNeeded returns early when
                // a monitor exists, so the stale tap never came back.
                self?.stopMonitoring(reason: "system sleep")
                self?.stopObservation()
            }
        }
        workspace.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.fire(.wake, detail: "The Mac woke up")
                self.coordinator.updatePolicy(self.settings.policy)
                self.coordinator.systemDidWake()
                if self.settings.automationEnabled {
                    self.startMonitoringIfNeeded()
                    self.startUserSpeechMonitoring()
                    self.startObservation()
                }
                self.refreshMusic()
            }
        }
    }

    // MARK: Termination

    /// Restores an owned pause before the process exits. Returns `.terminateLater` when a resume
    /// command must run first, so quitting never leaves the user's music stuck.
    func handleTermination() -> NSApplication.TerminateReply {
        if #available(macOS 14.2, *) {
            try? targetAudioMuteController?.update(applications: [], shouldMute: false)
        }
        guard coordinator.commandForTermination() != nil else {
            stopObservation()
            stopMonitoring(reason: "quitting")
            return .terminateNow
        }
        record(.info, .lifecycle, "Restoring playback before quitting.")
        Task { [weak self] in
            guard let self else {
                NSApp.reply(toApplicationShouldTerminate: true)
                return
            }
            do {
                try await self.media.resume()
                self.pauseJournal.clear()
            } catch {
                self.record(.error, .recovery, "Could not restore playback while quitting: \(error.localizedDescription)")
            }
            self.coordinator.acknowledgeTermination()
            self.stopObservation()
            self.stopMonitoring(reason: "quitting")
            NSApp.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    // MARK: Windows

    func showOnboarding() {
        windows.show(id: "onboarding", title: "Welcome to Oreja de Van Gogh", size: NSSize(width: 620, height: 660)) { [weak self] in
            guard let self else { return AnyView(EmptyView()) }
            return AnyView(OnboardingView(model: self))
        }
    }

    func showSettings() {
        windows.show(id: "settings", title: "Oreja Settings", size: NSSize(width: 820, height: 640)) { [weak self] in
            guard let self else { return AnyView(EmptyView()) }
            return AnyView(SettingsView(model: self))
        }
    }

    func showDiagnostics() {
        windows.show(id: "diagnostics", title: "Oreja Diagnostics", size: NSSize(width: 620, height: 560)) { [weak self] in
            guard let self else { return AnyView(EmptyView()) }
            return AnyView(DiagnosticsView(model: self))
        }
    }

    func finishOnboarding() {
        settings.onboardingCompleted = true
        windows.close(id: "onboarding")
        if settings.automationEnabled {
            startObservation()
            startMonitoringIfNeeded()
        }
    }

    // MARK: Connection check

    /// Runs the same checks the onboarding test describes, and reports *only* what was verified.
    func runConnectionCheck() {
        guard !isRunningCheck else { return }
        isRunningCheck = true
        report = nil
        record(.info, .lifecycle, "Running connection check.")

        let steps = [
            CheckStep(title: "Apple Music is running", status: .pending),
            CheckStep(title: "Oreja may control Music", status: .pending),
            CheckStep(title: "A selected audio app is running", status: .pending),
            CheckStep(title: "Oreja may capture the selected audio apps", status: .pending),
        ]
        report = ConnectionCheckReport(steps: steps, startedAt: Date())

        Task { [weak self] in
            guard let self else { return }
            await self.checkMusicRunning()
            await self.checkAutomation()
            await self.checkAISource()
            await self.checkAudioCapture()
            self.isRunningCheck = false
            self.record(
                self.report?.hasFailure == true ? .warning : .success,
                .lifecycle,
                "Connection check finished."
            )
        }
    }

    private func updateStep(_ index: Int, _ status: CheckStep.Status) {
        guard var report, report.steps.indices.contains(index) else { return }
        report.steps[index].status = status
        self.report = report
    }

    private func checkMusicRunning() async {
        if media.isProviderRunning {
            updateStep(0, .passed("Music is open."))
        } else {
            updateStep(0, .failed("Music is not running. Open it, then run the check again."))
        }
    }

    private func checkAutomation() async {
        switch await media.requestAutomationPermission() {
        case .success(let snapshot):
            let detail = snapshot.track.map { "Music responded to automation (\($0.displayName))." } ?? "Music responded to automation."
            updateStep(1, .passed(detail))
        case .failure(.permissionDenied):
            updateStep(1, .failed("Automation permission was denied. Allow Oreja in System Settings › Privacy & Security › Automation."))
        case .failure(.notRunning):
            updateStep(1, .failed("Music is not running."))
        case .failure(let error):
            updateStep(1, .failed(error.localizedDescription))
        }
    }

    private func checkAISource() async {
        guard !settings.aiSources.isEmpty else {
            updateStep(2, .failed("No audio app is selected. Choose one in Settings."))
            return
        }
        let running = runningSourceNames()
        if running.isEmpty {
            updateStep(2, .failed("None of the selected apps is running: \(settings.aiSources.map(\.displayName).joined(separator: ", "))."))
        } else {
            updateStep(2, .passed("Running: \(running.joined(separator: ", "))."))
        }
    }

    private func checkAudioCapture() async {
        guard monitor != nil else {
            // No live monitor: prove the tap can be created, then tear it down again.
            let descriptor = AIAudioSourceDescriptor(selections: settings.aiSources)
            let probe = monitorFactory.makeMonitor(
                for: descriptor,
                options: settings.audioMonitorOptions
            )
            do {
                try await probe.start()
            } catch let failure as AudioMonitoringFailure {
                if failure.kind == .permissionDenied { hasAudioPermission = false }
                updateStep(3, .failed(failure.message))
                await probe.stop()
                return
            } catch {
                updateStep(3, .failed(error.localizedDescription))
                await probe.stop()
                return
            }
            updateStep(3, .passed("Audio capture started for \(descriptor.displayName). Play a reply in a selected app to see activity."))
            await probe.stop()
            return
        }

        if isMonitoring {
            updateStep(3, .passed("Audio capture is active for \(sourceDescription.isEmpty ? AIAudioSourceDescriptor(selections: settings.aiSources).displayName : sourceDescription)."))
        } else {
            updateStep(3, .failed("Audio capture is not active right now. Check the audio recording permission."))
        }
    }

    // MARK: Helpers

    private func openPrivacyPane(anchor: String) {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)") else { return }
        NSWorkspace.shared.open(url)
    }

    private func record(_ level: DiagnosticEvent.Level, _ category: DiagnosticEvent.Category, _ message: String) {
        diagnostics.record(DiagnosticEvent(level: level, category: category, message: message))
    }
}

/// Keeps at most one window per identifier, so repeated menu commands focus the existing window.
@MainActor
final class WindowRegistry {
    private var windows: [String: NSWindow] = [:]

    func show(id: String, title: String, size: NSSize, content: @escaping () -> AnyView) {
        NSApp.setActivationPolicy(.accessory)
        if let existing = windows[id] {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let hosting = NSHostingView(rootView: content())
        var styleMask: NSWindow.StyleMask = [.titled, .closable, .miniaturizable]
        if id == "settings" { styleMask.insert(.resizable) }
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: styleMask,
            backing: .buffered,
            defer: false
        )
        window.title = title
        window.contentView = hosting
        window.isReleasedWhenClosed = false
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        windows[id] = window
    }

    func close(id: String) {
        windows[id]?.close()
        windows[id] = nil
    }
}
