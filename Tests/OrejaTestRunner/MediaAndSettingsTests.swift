import Foundation
import OrejaCore
import OrejaMedia

@MainActor
func runMediaAndSettingsSuite(_ t: Harness) async {
    print("\nApple Music scripting, settings and recovery")

    t.run("browser tab scripting is removed and cannot be used as a fallback") {
        // The per-tab Apple Events/JavaScript path was deleted with the v0.4.0 repair. No runtime
        // adapter may fall back to it, and no capability may claim browser playback control.
        t.expect(!PlaybackTargets.capability(for: .browser).isSupported)
        t.expect(PlaybackTargets.capability(for: .browser).reason?.contains("per-tab JavaScript") == true)
    }

    t.run("the status names who is speaking: the assistant, you, or both") {
        var speakers = ActivityAggregator()
        t.expect(speakers.speakerTitle(sourceNames: ["ChatGPT"]) == nil, "nobody speaking falls back to the state title")
        _ = speakers.set(true, for: .user)
        t.expectEqual(speakers.speakerTitle(sourceNames: ["ChatGPT"]), "You are speaking")
        _ = speakers.set(true, for: .ai)
        t.expectEqual(speakers.speakerTitle(sourceNames: ["ChatGPT"]), "You and ChatGPT are speaking")
        _ = speakers.set(false, for: .user)
        t.expectEqual(speakers.speakerTitle(sourceNames: ["ChatGPT"]), "ChatGPT is speaking")
        t.expectEqual(speakers.speakerTitle(sourceNames: ["ChatGPT", "Orca"]), "A selected app is speaking", "merged sources are not guessed")
        _ = speakers.set(false, for: .ai)
        _ = speakers.set(true, for: .preview)
        t.expect(speakers.speakerTitle(sourceNames: ["ChatGPT"]) == nil, "a test run names no speaker")
    }

    await t.runAsync("the coordinator reports a microphone-only onset as your voice, not the assistant") {
        let f = CoordinatorFixture()
        await f.startMonitoring()
        f.coordinator.setActivity(true, source: .user, levelDB: -30)
        t.expect(f.coordinator.speakers.userIsActive)
        t.expect(!f.coordinator.speakers.aiIsActive, "your voice is never shown as the assistant speaking")
    }

    t.run("AppleScript state parser reads playing state and track") {
        let sep = AppleMusicScript.fieldSeparator
        let output = "playing\(sep)ABC-123\(sep)Aja\(sep)Steely Dan\(sep)72"
        let snapshot = AppleMusicStateParser.parse(output, capturedAt: 42)
        t.expectEqual(snapshot.state, .playing)
        t.expectEqual(snapshot.track?.id, "ABC-123")
        t.expectEqual(snapshot.track?.title, "Aja")
        t.expectEqual(snapshot.track?.artist, "Steely Dan")
        t.expectClose(snapshot.volume ?? 0, 0.72)
        t.expectEqual(snapshot.provider, .appleMusic)
        t.expectClose(snapshot.capturedAt, 42)
    }

    t.run("AppleScript state parser handles paused, stopped and unavailable") {
        let sep = AppleMusicScript.fieldSeparator
        let paused = AppleMusicStateParser.parse("paused\(sep)ID\(sep)Song\(sep)Artist\(sep)40")
        t.expectEqual(paused.state, .paused)
        t.expectEqual(paused.track?.id, "ID")

        let stopped = AppleMusicStateParser.parse("stopped\(sep)\(sep)\(sep)\(sep)50")
        t.expectEqual(stopped.state, .stopped)
        t.expect(stopped.track == nil)

        let unavailable = AppleMusicStateParser.parse("unavailable\(sep)\(sep)\(sep)\(sep)\(sep)")
        t.expectEqual(unavailable.state, .unavailable)

        t.expectEqual(AppleMusicStateParser.parse("").state, .unavailable)
        t.expectEqual(AppleMusicStateParser.parse("garbage").state, .unavailable)
    }

    t.run("Apple Music scripts never launch, stop, or clear the track") {
        let state = AppleMusicScript.playbackState
        let pause = AppleMusicScript.pause
        let resume = AppleMusicScript.resume

        for (name, script) in [("state", state), ("pause", pause), ("resume", resume)] {
            t.expect(script.contains("application \"Music\" is running"), "\(name) script guards against launching Music")
            t.expect(!script.contains("to stop"), "\(name) script must never call the stop command")
            t.expect(!script.contains("activate"), "\(name) script must not bring Music forward")
        }
        // The state query necessarily *reads* the stopped player state, but never stops playback.
        t.expect(state.contains("player state"), "state query reads player state")
        t.expect(pause.contains("tell application \"Music\" to pause"))
        t.expect(resume.contains("tell application \"Music\" to play"))
        t.expect(AppleMusicScript.setVolume(140).contains("sound volume to 100"))
        t.expect(AppleMusicScript.setVolume(-20).contains("sound volume to 0"))
    }

    t.run("reporting scripts pause/resume and read state in one Apple Event") {
        let pause = AppleMusicScript.pauseReporting
        let resume = AppleMusicScript.resumeReporting

        for (name, script, verb) in [("pause", pause, "pause"), ("resume", resume, "play")] {
            t.expect(script.contains("application \"Music\" is running"), "\(name) guards against launching Music")
            t.expect(script.contains("\n        \(verb)\n"), "\(name) issues \(verb)")
            t.expect(script.contains("persistent ID of current track"), "\(name) reports the track in the same round trip")
            t.expect(!script.contains("to stop"), "\(name) must never stop playback")
            t.expect(script.contains("repeat 20 times"), "\(name) waits for Music to confirm inside the event")
        }
        t.expect(pause.contains("if playerStatus is \"paused\" then"), "pause waits for the paused state")
        t.expect(resume.contains("if playerStatus is \"playing\" then"), "resume waits for the playing state")
    }

    t.run("user speech keeps the activity window open while the AI is quiet") {
        var aggregator = ActivityAggregator()
        t.expect(!aggregator.isActive)

        t.expect(aggregator.set(true, for: .ai), "AI speech starts the window")
        t.expect(aggregator.isActive)
        t.expect(!aggregator.set(true, for: .user), "the user speaking does not restart it")

        // ChatGPT goes quiet while the user answers: the window must stay open, which is the whole
        // point of merging both sources.
        t.expect(!aggregator.set(false, for: .ai), "AI silence alone must not end the window")
        t.expect(aggregator.isActive, "music stays paused while the user is talking")

        t.expect(aggregator.set(false, for: .user), "the user going quiet ends the window")
        t.expect(!aggregator.isActive)

        // The reverse order must behave the same way.
        t.expect(aggregator.set(true, for: .user))
        t.expect(!aggregator.set(true, for: .ai))
        t.expect(!aggregator.set(false, for: .user))
        t.expect(aggregator.isActive)
        t.expect(aggregator.set(false, for: .ai))

        aggregator.set(true, for: .ai)
        aggregator.reset()
        t.expect(!aggregator.isActive, "reset clears both sources")
    }

    t.run("pause-while-I-speak is off by default and survives a settings round trip") {
        t.expectEqual(AppSettings().pauseWhileISpeak, false)

        let suiteName = "com.oreja.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = UserDefaultsSettingsStore(defaults: defaults)
        var settings = AppSettings()
        settings.pauseWhileISpeak = true
        store.save(settings)
        t.expect(store.load().pauseWhileISpeak)

        // Older builds' JSON has no such key; it must decode as off rather than fail.
        let legacy = #"{"automationEnabled":true,"resumeDelay":0.8}"#
        let decoded = try? JSONDecoder().decode(AppSettings.self, from: Data(legacy.utf8))
        t.expectEqual(decoded?.pauseWhileISpeak, false)
    }

    await t.runAsync("providers without a reporting script fall back to pause plus a state read") {
        let fake = ScriptedMediaController(state: .playing)
        let paused = try await fake.pauseReporting()
        t.expectEqual(fake.pauseCalls, 1)
        t.expectEqual(paused.state, .playing, "the default implementation re-reads the provider")
    }

    t.run("track identity validation") {
        let track = MediaTrack(id: "A", title: "Song", artist: "Artist")
        let other = MediaTrack(id: "B", title: "Other", artist: "Artist")
        let snapshot = MediaPlaybackSnapshot(state: .paused, track: track)
        t.expect(snapshot.refersTo(track))
        t.expect(!snapshot.refersTo(other))
        t.expect(snapshot.refersTo(nil), "no expected track means only state matters")
        t.expect(!MediaPlaybackSnapshot(state: .paused, track: nil).refersTo(track))
    }

    t.run("settings round-trip and clamping") {
        var settings = AppSettings()
        t.expectClose(settings.resumeDelay, 0.8)
        settings.resumeDelay = 99
        t.expectClose(settings.resumeDelay, 3.0)
        settings.resumeDelay = 0.1
        t.expectClose(settings.resumeDelay, 0.1)
        settings.resumeDelay = 1.4
        settings.aiSources = [.safari, .chatGPTDesktop]
        settings.targetAudioApps = [.app(bundleIdentifier: "com.apple.Preview", displayName: "Preview")]
        settings.launchAtLogin = true
        settings.onboardingCompleted = true
        settings.verboseDiagnostics = true

        let data = try! JSONEncoder().encode(settings)
        let decoded = try! JSONDecoder().decode(AppSettings.self, from: data)
        t.expectEqual(decoded, settings)
        t.expectEqual(decoded.targetAudioApps, [.app(bundleIdentifier: "com.apple.Preview", displayName: "Preview")])
        t.expectClose(decoded.policy.quietInterval, 1.4)
        t.expectClose(decoded.policy.conversationHold, 0, "conversation hold is disabled by default for immediate volume restore")
        t.expectClose(decoded.policy.resumeWait, 1.4)
        t.expectEqual(decoded.interruptionMode, .duck)
        t.expectEqual(decoded.duckVolumePercent, 5)
        t.expectEqual(decoded.restoreVolumePercent, 100)
        settings.duckVolumePercent = 100
        t.expectEqual(settings.duckVolumePercent, 100, "keep music volume accepts the full range")
        settings.restoreVolumePercent = 67
        t.expectClose(settings.policy.restoreVolume, 0.67)
        t.expectEqual(decoded.aiSources.map(\.bundleIdentifier), ["com.apple.Safari", "com.openai.codex"])
    }

    t.run("primary apps are removed from secondary target selections") {
        let data = #"{"aiSources":[{"kind":"browser","bundleIdentifier":"com.google.Chrome","displayName":"Google Chrome"}],"targetAudioApps":[{"kind":"browser","bundleIdentifier":"com.google.Chrome","displayName":"Google Chrome"}]}"#
        let decoded = try! JSONDecoder().decode(AppSettings.self, from: Data(data.utf8))
        t.expectEqual(decoded.aiSources.map(\.bundleIdentifier), ["com.google.Chrome"])
        t.expect(decoded.targetAudioApps.isEmpty)
    }

    t.run("conversation hold is clamped and can be switched off") {
        var settings = AppSettings()
        t.expectEqual(settings.holdThroughConversation, true)
        settings.conversationHold = -1
        t.expectClose(settings.conversationHold, AppSettings.conversationHoldRange.lowerBound)
        settings.conversationHold = 999
        t.expectClose(settings.conversationHold, AppSettings.conversationHoldRange.upperBound)

        settings.conversationHold = 20
        t.expectClose(settings.policy.resumeWait, 20)

        settings.holdThroughConversation = false
        t.expectClose(settings.policy.conversationHold, 0)
        t.expectClose(settings.policy.resumeWait, settings.resumeDelay, "per-reply mode uses the quiet interval")
    }

    t.run("settings decode tolerates missing and unknown fields") {
        let json = #"{"resumeDelay": 2.0, "unknownKey": true}"#.data(using: .utf8)!
        let decoded = try! JSONDecoder().decode(AppSettings.self, from: json)
        t.expectClose(decoded.resumeDelay, 2.0)
        t.expectEqual(decoded.aiSources, [.chatGPTDesktop])
        t.expectEqual(decoded.musicProvider, .appleMusic)
        t.expectEqual(decoded.onboardingCompleted, false)
    }

    t.run("UserDefaults stores settings and pause journal separately") {
        let suiteName = "com.oreja.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = UserDefaultsSettingsStore(defaults: defaults)
        t.expectEqual(store.load(), AppSettings(), "fresh store returns defaults")
        var settings = AppSettings()
        settings.resumeDelay = 1.9
        settings.onboardingCompleted = true
        store.save(settings)
        t.expectEqual(store.load(), settings)

        let journal = UserDefaultsPauseJournal(defaults: defaults)
        t.expect(journal.load() == nil)
        let record = PauseJournalRecord(
            provider: .appleMusic,
            track: MediaTrack(id: "ID", title: "Song", artist: "Artist"),
            acquiredAt: Date(timeIntervalSince1970: 1_700_000_000),
            reason: "AI output activity"
        )
        journal.save(record)
        t.expectEqual(journal.load(), record)
        journal.clear()
        t.expect(journal.load() == nil)
    }

    t.run("stale pause recovery only restores the same paused track") {
        let track = MediaTrack(id: "ID", title: "Song", artist: "Artist")
        let record = PauseJournalRecord(
            provider: .appleMusic,
            track: track,
            acquiredAt: Date(timeIntervalSince1970: 1_700_000_000),
            reason: "AI output activity"
        )
        let now = Date(timeIntervalSince1970: 1_700_000_600)
        let paused = MediaPlaybackSnapshot(state: .paused, track: track, provider: .appleMusic)
        t.expectEqual(StalePauseRecovery.decide(record: record, snapshot: paused, now: now), .resume)

        let otherTrack = MediaPlaybackSnapshot(
            state: .paused,
            track: MediaTrack(id: "OTHER", title: "Other", artist: "Artist"),
            provider: .appleMusic
        )
        if case .discard = StalePauseRecovery.decide(record: record, snapshot: otherTrack, now: now) {
            t.expect(true)
        } else {
            t.expect(false, "a different track must never be resumed")
        }

        let playing = MediaPlaybackSnapshot(state: .playing, track: track, provider: .appleMusic)
        if case .discard = StalePauseRecovery.decide(record: record, snapshot: playing, now: now) {
            t.expect(true)
        } else {
            t.expect(false, "playing music is not restored")
        }

        let tooOld = now.addingTimeInterval(48 * 60 * 60)
        if case .discard = StalePauseRecovery.decide(record: record, snapshot: paused, now: tooOld) {
            t.expect(true)
        } else {
            t.expect(false, "old pause journals expire")
        }

        if case .discard = StalePauseRecovery.decide(record: nil, snapshot: paused, now: now) {
            t.expect(true)
        } else {
            t.expect(false, "no journal means nothing to restore")
        }
    }

    t.run("AI source catalog matches ChatGPT builds and browsers") {
        t.expect(AISourceCatalog.isChatGPT(bundleIdentifier: "com.openai.codex"))
        t.expect(AISourceCatalog.isChatGPT(bundleIdentifier: "com.openai.chat"))
        t.expect(AISourceCatalog.isChatGPT(bundleIdentifier: "com.openai.chat.helper"))
        t.expect(!AISourceCatalog.isChatGPT(bundleIdentifier: "com.example.other"))
        t.expect(!AISourceCatalog.isChatGPT(bundleIdentifier: nil))
        t.expect(AISourceCatalog.isBrowser(bundleIdentifier: "com.google.Chrome"))
        t.expect(AISourceCatalog.isBrowser(bundleIdentifier: "com.apple.Safari"))
        t.expect(!AISourceCatalog.isBrowser(bundleIdentifier: "com.apple.Music"))

        let descriptor = AIAudioSourceDescriptor(selection: .chatGPTDesktop)
        t.expect(descriptor.bundleIdentifierPrefixes.contains("com.openai."))
        t.expect(!descriptor.isExperimental)
        t.expect(AIAudioSourceDescriptor(selection: .safari).isExperimental)
    }

    t.run("browsers are tapped where their audio actually renders") {
        // Chromium renders audio in a helper process whose bundle identifier is a prefix of the
        // browser's own id — but not always of the full one, which is the ego lite case.
        t.expect(AISourceCatalog.isBrowser(bundleIdentifier: "com.citrolabs.ego.lite"))
        t.expectEqual(
            AIAudioSourceDescriptor(selection: .egoLite).bundleIdentifierPrefixes,
            ["com.citrolabs.ego"]
        )
        t.expectEqual(
            AIAudioSourceDescriptor(selection: .chrome).bundleIdentifierPrefixes,
            ["com.google.Chrome"]
        )
        // An unknown browser still taps its own bundle identifier.
        let custom = AISourceSelection.browser(bundleIdentifier: "com.example.browser", displayName: "Example")
        t.expectEqual(AIAudioSourceDescriptor(selection: custom).bundleIdentifierPrefixes, ["com.example.browser"])
    }

    t.run("PlaybackPolicy clamps the quiet interval") {
        let clampedLow = PlaybackPolicy(
            quietInterval: 0.1,
            minimumActivityDuration: 0.06,
            minimumSilenceDuration: 0.25,
            failureLimit: 3,
            restoreOwnedPauseOnFailure: true,
            staleOwnershipLifetime: 100
        )
        t.expectClose(clampedLow.quietInterval, 0.1)
        t.expectClose(PlaybackPolicy.default.quietInterval, 0.8)
        t.expectClose(PlaybackPolicy.default.conversationHold, 0, "the plain policy returns after each reply")

        let held = PlaybackPolicy(
            quietInterval: 0.8,
            minimumActivityDuration: 0.06,
            minimumSilenceDuration: 0.25,
            failureLimit: 3,
            restoreOwnedPauseOnFailure: true,
            staleOwnershipLifetime: 100,
            conversationHold: 500
        )
        t.expectClose(held.conversationHold, PlaybackPolicy.conversationHoldRange.upperBound)
        t.expectClose(held.resumeWait, PlaybackPolicy.conversationHoldRange.upperBound)
    }

    await t.runAsync("mock provider records commands for adapter-level tests") {
        let mock = MockMusicController()
        t.expect(mock.snapshot.isPlaying)
        try await mock.pause()
        try await mock.resume()
        t.expectEqual(mock.commands, ["pause", "resume"])
        t.expectEqual(mock.pauseCount, 1)
        t.expectEqual(mock.resumeCount, 1)
    }

    t.run("unsupported playback targets report an honest reason instead of faked control") {
        t.expectEqual(PlaybackTargetID.allCases.count, 3)
        t.expectEqual(PlaybackTargetID.appleMusic.displayName, "Apple Music")

        let music = PlaybackTargets.capability(for: .appleMusic)
        t.expect(music.isSupported, "Apple Music is the one supported target")
        t.expect(music.reason == nil)

        let spotify = PlaybackTargets.capability(for: .spotify)
        t.expect(!spotify.isSupported)
        t.expect(spotify.reason?.contains("not installed") == true)
        t.expect(spotify.reason?.contains("remote service") == true)

        let browser = PlaybackTargets.capability(for: .browser)
        t.expect(!browser.isSupported)
        t.expect(browser.reason?.contains("no public per-process gain") == true)
        t.expect(browser.reason?.contains("per-tab JavaScript") == true)
        t.expect(browser.reason?.contains("stays audible") == true)

        for target in PlaybackTargetID.allCases where target != .appleMusic {
            t.expect(PlaybackTargets.capability(for: target).reason?.isEmpty == false)
        }
    }

    t.run("tapped process diagnostics name the exact helper and its output state") {
        t.expectEqual(AudioProcessDiagnostics.describe([]), "no audio process matched")

        let helper = AudioProcessIdentity(bundleID: "com.openai.codex.helper", pid: 15739, isRunningOutput: true)
        let silent = AudioProcessIdentity(bundleID: "com.citrolabs.ego.helper", pid: 6263, isRunningOutput: false)
        let described = AudioProcessDiagnostics.describe([helper, silent])

        t.expect(described.contains("com.openai.codex.helper"))
        t.expect(described.contains("pid 15739"))
        t.expect(described.contains("output"))
        t.expect(described.contains("com.citrolabs.ego.helper"))
        t.expect(described.contains("pid 6263"))
        t.expect(described.contains("silent"))

        let unknown = AudioProcessDiagnostics.describe([AudioProcessIdentity(bundleID: nil, pid: 412, isRunningOutput: true)])
        t.expect(unknown.contains("unknown bundle"))
        t.expect(unknown.contains("pid 412"))
    }
}
