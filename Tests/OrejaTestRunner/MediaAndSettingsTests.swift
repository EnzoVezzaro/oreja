import Foundation
import OrejaCore
import OrejaMedia

@MainActor
func runMediaAndSettingsSuite(_ t: Harness) async {
    print("\nApple Music scripting, settings and recovery")

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
        t.expectClose(settings.resumeDelay, 0.3)
        settings.resumeDelay = 1.4
        settings.aiSource = .safari
        settings.launchAtLogin = true
        settings.onboardingCompleted = true
        settings.verboseDiagnostics = true

        let data = try! JSONEncoder().encode(settings)
        let decoded = try! JSONDecoder().decode(AppSettings.self, from: data)
        t.expectEqual(decoded, settings)
        t.expectClose(decoded.policy.quietInterval, 1.4)
        t.expectEqual(decoded.aiSource.bundleIdentifier, "com.apple.Safari")
    }

    t.run("settings decode tolerates missing and unknown fields") {
        let json = #"{"resumeDelay": 2.0, "unknownKey": true}"#.data(using: .utf8)!
        let decoded = try! JSONDecoder().decode(AppSettings.self, from: json)
        t.expectClose(decoded.resumeDelay, 2.0)
        t.expectEqual(decoded.aiSource, .chatGPTDesktop)
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

    t.run("PlaybackPolicy clamps the quiet interval") {
        let clampedLow = PlaybackPolicy(
            quietInterval: 0.1,
            minimumActivityDuration: 0.06,
            minimumSilenceDuration: 0.25,
            failureLimit: 3,
            restoreOwnedPauseOnFailure: true,
            staleOwnershipLifetime: 100
        )
        t.expectClose(clampedLow.quietInterval, 0.3)
        t.expectClose(PlaybackPolicy.default.quietInterval, 0.8)
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
}
