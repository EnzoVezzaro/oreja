import Foundation
import OrejaCore

@MainActor
func runCoordinatorSuite(_ t: Harness) async {
    print("\nPlayback coordinator")

    await t.runAsync("secondary app mute follows the owned interruption and quiet interval") {
        let f = CoordinatorFixture()
        await f.startMonitoring()
        t.expect(!f.coordinator.shouldMuteTargetAudio)

        f.coordinator.audioActivityStarted(levelDB: -20)
        t.expect(f.coordinator.shouldMuteTargetAudio, "selected targets mute when primary speech starts")
        f.completeLast(nextState: .paused)
        f.coordinator.audioActivityEnded()
        t.expect(f.coordinator.shouldMuteTargetAudio, "targets stay muted during the resume delay")

        f.scheduler.advance(by: 0.81)
        t.expect(!f.coordinator.shouldMuteTargetAudio, "targets unmute when the quiet interval ends")
        f.coordinator.setAutomationEnabled(false)
        t.expect(!f.coordinator.shouldMuteTargetAudio, "disabling automation always releases target mute")
    }

    await t.runAsync("secondary apps mute on detected user speech even if the AI monitor is unavailable") {
        let f = CoordinatorFixture()
        await f.startMonitoring()
        f.coordinator.sourceInvalidated(reason: "selected app closed")

        f.coordinator.setUserSpeechActive(true)
        t.expect(f.coordinator.shouldMuteTargetAudio, "microphone speech can mute targets without an AI source tap")
        f.coordinator.setUserSpeechActive(false)
        t.expect(!f.coordinator.shouldMuteTargetAudio, "target mute releases after user speech ends")
    }

    await t.runAsync("1. music playing + AI begins audio = pause") {
        let f = CoordinatorFixture()
        await f.startMonitoring()
        t.expectEqual(f.coordinator.state, .musicPlaying, "idle state with music playing")

        f.coordinator.audioActivityStarted(levelDB: -22)
        t.expectEqual(f.commands.count, 1, "one command issued")
        t.expectEqual(f.lastCommand?.kind, .pause)
        t.expectEqual(f.coordinator.state, .aiActive)
        t.expect(f.coordinator.ownership == nil, "no ownership before the command completes")

        f.completeLast(nextState: .paused)
        t.expectEqual(f.coordinator.state, .musicPausedByOreja)
        t.expect(f.coordinator.ownership != nil, "Oreja owns the pause")
        t.expectEqual(f.journal.saveCount, 1, "pause is journaled")
        t.expectEqual(f.coordinator.statistics.pausesIssued, 1)
    }

    await t.runAsync("2. AI quiet + threshold met = resume") {
        let f = CoordinatorFixture()
        await f.startMonitoring()
        f.coordinator.audioActivityStarted(levelDB: -20)
        f.completeLast(nextState: .paused)

        f.coordinator.audioActivityEnded()
        t.expectEqual(f.coordinator.state, .waitingForSilence)
        t.expectEqual(f.scheduler.pendingCount, 1)

        f.scheduler.advance(by: 0.79)
        t.expectEqual(f.commands.count, 1, "no resume before the quiet interval")

        f.scheduler.advance(by: 0.02)
        t.expectEqual(f.commands.count, 2)
        t.expectEqual(f.lastCommand?.kind, .resume)
        t.expectEqual(f.coordinator.state, .restoringPlayback)

        f.completeLast(nextState: .playing)
        t.expect(f.coordinator.ownership == nil, "ownership released")
        t.expectEqual(f.coordinator.state, .musicPlaying)
        t.expectEqual(f.journal.clearCount, 1, "journal cleared after resume")
    }

    await t.runAsync("2b. stale playing snapshot after a successful pause still resumes") {
        let f = CoordinatorFixture()
        await f.startMonitoring()
        f.coordinator.audioActivityStarted(levelDB: -20)

        // The pause script succeeded, but the provider's first state read still said "playing".
        f.completeWithCurrentSnapshot(f.commands.last!)
        t.expect(f.coordinator.ownership != nil, "Oreja still owns the pause")
        t.expectEqual(f.coordinator.state, .musicPausedByOreja)

        f.coordinator.audioActivityEnded()
        f.scheduler.advance(by: 0.8)
        t.expectEqual(f.lastCommand?.kind, .resume, "resume is issued instead of stranding the pause")

        f.completeLast(nextState: .playing)
        t.expect(f.coordinator.ownership == nil, "ownership released after the resume")
    }

    await t.runAsync("2c. conversation hold keeps music paused while the assistant works") {
        var policy = PlaybackPolicy.default
        policy.conversationHold = 12
        let f = CoordinatorFixture(policy: policy)
        await f.startMonitoring()
        f.coordinator.audioActivityStarted(levelDB: -20)
        f.completeLast(nextState: .paused)

        // The reply ends; the assistant is now silently working on the next one.
        f.coordinator.audioActivityEnded()
        f.scheduler.advance(by: 5)
        t.expectEqual(f.commands.count, 1, "no resume in the middle of the conversation")
        t.expectEqual(f.coordinator.state, .waitingForSilence)

        // The user answers, which restarts the hold rather than shortening it.
        f.coordinator.audioActivityStarted(levelDB: -22)
        f.coordinator.audioActivityEnded()
        f.scheduler.advance(by: 11.5)
        t.expectEqual(f.commands.count, 1, "the hold restarts after every turn")
        f.scheduler.advance(by: 0.6)
        t.expectEqual(f.lastCommand?.kind, .resume, "music returns once the conversation is over")

        f.completeLast(nextState: .playing)
        t.expectEqual(f.coordinator.state, .musicPlaying)
    }

    await t.runAsync("2d. per-reply mode resumes as soon as one reply ends") {
        let f = CoordinatorFixture()
        await f.startMonitoring()
        f.coordinator.audioActivityStarted(levelDB: -20)
        f.completeLast(nextState: .paused)

        f.coordinator.audioActivityEnded()
        f.scheduler.advance(by: 0.8)
        t.expectEqual(f.lastCommand?.kind, .resume)
    }

    await t.runAsync("2e. duck mode keeps music playing and restores its volume") {
        var policy = PlaybackPolicy.default
        policy.interruptionMode = .duck
        policy.duckVolume = 0.05
        policy.restoreVolume = 0.67
        let f = CoordinatorFixture(policy: policy)
        f.media.snapshot.volume = 0.67
        await f.startMonitoring()

        f.coordinator.audioActivityStarted(levelDB: -20)
        t.expectEqual(f.lastCommand?.kind, .setVolume)
        t.expectClose(f.lastCommand?.targetVolume ?? -1, 0.05)
        f.completeLast()
        t.expectEqual(f.media.snapshot.state, .playing)
        t.expectClose(f.coordinator.volumeOwnership?.originalVolume ?? -1, 0.67)

        f.coordinator.audioActivityEnded()
        f.scheduler.advance(by: 0.8)
        t.expectEqual(f.lastCommand?.kind, .setVolume)
        t.expect(f.lastCommand?.restoresVolume == true)
        t.expectClose(f.lastCommand?.targetVolume ?? -1, 0.67)
        f.completeLast()
        t.expect(f.coordinator.volumeOwnership == nil, "volume ownership released after restore")
        t.expectEqual(f.media.snapshot.state, .playing)
    }

    await t.runAsync("2f. duck mode preserves original volume across conversation turns") {
        var policy = PlaybackPolicy.default
        policy.interruptionMode = .duck
        policy.duckVolume = 0.05
        policy.restoreVolume = 0.67
        policy.conversationHold = 12
        let f = CoordinatorFixture(policy: policy)
        f.media.snapshot.volume = 0.67
        await f.startMonitoring()

        f.coordinator.audioActivityStarted(levelDB: -20)
        t.expectEqual(f.lastCommand?.kind, .setVolume)
        f.completeLast()
        t.expectClose(f.coordinator.volumeOwnership?.originalVolume ?? -1, 0.67)

        f.coordinator.audioActivityEnded()
        f.scheduler.advance(by: 5)
        f.coordinator.audioActivityStarted(levelDB: -22)
        t.expectEqual(f.commands(of: .setVolume).count, 1, "a later turn does not re-duck or overwrite ownership")
        t.expectClose(f.coordinator.volumeOwnership?.originalVolume ?? -1, 0.67)

        f.coordinator.audioActivityEnded()
        f.scheduler.advance(by: 12.1)
        t.expect(f.lastCommand?.restoresVolume == true, "the whole conversation restores volume")
        t.expectClose(f.lastCommand?.targetVolume ?? -1, 0.67)
    }

    await t.runAsync("2g. live policy changes re-arm an active quiet timer") {
        var policy = PlaybackPolicy.default
        policy.interruptionMode = .duck
        policy.duckVolume = 0.05
        policy.restoreVolume = 0.67
        let f = CoordinatorFixture(policy: policy)
        f.media.snapshot.volume = 0.67
        await f.startMonitoring()

        f.coordinator.audioActivityStarted(levelDB: -20)
        f.completeLast()
        f.coordinator.audioActivityEnded()

        var updated = policy
        updated.quietInterval = 0
        f.coordinator.updatePolicy(updated)
        f.scheduler.advance(by: 0)

        t.expect(f.lastCommand?.restoresVolume == true, "changing quiet interval updates an active timer")
        t.expectClose(f.lastCommand?.targetVolume ?? -1, 0.67)
    }

    await t.runAsync("3. brief silence inside a response keeps music paused") {
        let f = CoordinatorFixture()
        await f.startMonitoring()
        f.coordinator.audioActivityStarted(levelDB: -18)
        f.completeLast(nextState: .paused)

        f.coordinator.audioActivityEnded()
        f.scheduler.advance(by: 0.3)
        f.coordinator.audioActivityStarted(levelDB: -18)
        t.expectEqual(f.scheduler.pendingCount, 0, "quiet timer cancelled by new activity")
        t.expectEqual(f.commands.count, 1, "still only the pause command")

        f.scheduler.advance(by: 2.0)
        t.expectEqual(f.commands.count, 1, "no resume while the AI is speaking")
        t.expectEqual(f.coordinator.state, .musicPausedByOreja)
    }

    await t.runAsync("4. music already paused before AI speaks = do not resume") {
        let f = CoordinatorFixture(mediaState: .paused)
        await f.startMonitoring()

        f.coordinator.audioActivityStarted(levelDB: -20)
        t.expectEqual(f.commands.count, 0, "Oreja does not pause already-paused music")
        t.expectEqual(f.coordinator.state, .aiActive)

        f.coordinator.audioActivityEnded()
        f.scheduler.advance(by: 5)
        t.expectEqual(f.commands.count, 0, "nothing to restore")
        t.expect(f.coordinator.ownership == nil)
    }

    await t.runAsync("5. user manually pauses after automation = no automatic resume") {
        let f = CoordinatorFixture()
        await f.startMonitoring()
        f.coordinator.audioActivityStarted(levelDB: -20)
        f.completeLast(nextState: .paused)
        f.coordinator.audioActivityEnded()
        f.scheduler.advance(by: 0.8)
        f.completeLast(nextState: .playing)

        // The user pauses music by hand between responses.
        f.media.snapshot.state = .paused
        f.coordinator.observe(media: f.media.snapshot)
        let commandCount = f.commands.count

        f.coordinator.audioActivityStarted(levelDB: -20)
        f.coordinator.audioActivityEnded()
        f.scheduler.advance(by: 5)

        t.expectEqual(f.commands.count, commandCount, "Oreja never resumes music the user paused")
        t.expect(f.coordinator.ownership == nil)
    }

    await t.runAsync("6. user manually resumes during speech = honor override") {
        let f = CoordinatorFixture()
        await f.startMonitoring()
        f.coordinator.audioActivityStarted(levelDB: -20)
        f.completeLast(nextState: .paused)

        f.media.snapshot.state = .playing
        f.coordinator.observe(media: f.media.snapshot)

        t.expect(f.coordinator.ownership == nil, "ownership released after external resume")
        t.expectEqual(f.coordinator.state, .aiActive)
        let commandCount = f.commands.count

        f.coordinator.audioActivityStarted(levelDB: -20)
        t.expectEqual(f.commands.count, commandCount, "Oreja does not re-pause after a manual resume")

        f.coordinator.audioActivityEnded()
        f.scheduler.advance(by: 5)
        t.expectEqual(f.commands.count, commandCount, "no resume command was needed")
    }

    await t.runAsync("7. ChatGPT process exits = safe recovery") {
        let f = CoordinatorFixture()
        await f.startMonitoring()
        f.coordinator.audioActivityStarted(levelDB: -20)
        f.completeLast(nextState: .paused)

        f.coordinator.sourceInvalidated(reason: "ChatGPT quit")
        t.expectEqual(f.lastCommand?.kind, .resume, "owned pause restored when the source disappears")
        t.expectEqual(f.coordinator.state, .searchingForSource)
        t.expectFalseMonitoredSource(f.coordinator.sourceIsValid)

        f.completeLast(nextState: .playing)
        t.expect(f.coordinator.ownership == nil)
        t.expectEqual(f.coordinator.state, .searchingForSource)
    }

    await t.runAsync("8. Music exits = release ownership without retries") {
        let f = CoordinatorFixture()
        await f.startMonitoring()
        f.coordinator.audioActivityStarted(levelDB: -20)
        f.completeLast(nextState: .paused)
        let commandCount = f.commands.count

        f.coordinator.observe(media: .unavailable(.appleMusic, at: f.clock.now))
        t.expect(f.coordinator.ownership == nil, "ownership cannot survive a provider exit")
        t.expectEqual(f.commands.count, commandCount, "no blind resume commands")
        t.expect(f.coordinator.lastSnapshot?.state == .unavailable)
        t.expectEqual(f.coordinator.state, .aiActive, "AI is still speaking, so the status stays truthful")

        f.coordinator.audioActivityEnded()
        t.expectEqual(f.coordinator.state, .monitoring)
    }

    await t.runAsync("9. capture permission revoked = stop monitoring and report") {
        let f = CoordinatorFixture()
        await f.startMonitoring()
        f.coordinator.audioActivityStarted(levelDB: -20)
        f.completeLast(nextState: .paused)

        f.coordinator.monitoringFailed(
            AudioMonitoringFailure(.permissionDenied, "Audio capture permission was revoked.")
        )
        t.expectEqual(f.coordinator.state, .permissionRequired)
        t.expectFalseMonitoredSource(f.coordinator.sourceIsValid)
        t.expectEqual(f.lastCommand?.kind, .resume, "owned pause restored once")

        f.completeLast(nextState: .playing)
        t.expectEqual(f.coordinator.state, .permissionRequired, "state remains actionable")
        t.expect(f.diagnostics.events.contains { $0.level == .error && $0.category == .permissions })
    }

    await t.runAsync("10. audio device change = degrade safely, then recover") {
        let f = CoordinatorFixture()
        await f.startMonitoring()
        f.coordinator.audioActivityStarted(levelDB: -20)
        f.completeLast(nextState: .paused)

        f.coordinator.monitoringFailed(AudioMonitoringFailure(.streamFailed, "Tap stopped delivering audio."))
        t.expectEqual(f.coordinator.state, .error)
        t.expectEqual(f.lastCommand?.kind, .resume)
        f.completeLast(nextState: .playing)
        t.expectEqual(f.coordinator.state, .error)

        f.coordinator.retryAfterError()
        t.expectEqual(f.coordinator.state, .searchingForSource)

        f.coordinator.monitoringBecameAvailable(description: "ChatGPT (1 audio process)")
        t.expectEqual(f.coordinator.state, .musicPlaying, "resumed music is reconciled after recovery")
    }

    await t.runAsync("11. two rapid responses = no oscillation") {
        let f = CoordinatorFixture()
        await f.startMonitoring()
        f.coordinator.audioActivityStarted(levelDB: -20)
        f.completeLast(nextState: .paused)
        f.coordinator.audioActivityEnded()
        f.scheduler.advance(by: 0.2)
        f.coordinator.audioActivityStarted(levelDB: -20)
        f.coordinator.audioActivityEnded()
        f.scheduler.advance(by: 0.8)

        t.expectEqual(f.commands(of: .pause).count, 1)
        t.expectEqual(f.commands(of: .resume).count, 1)
        t.expectEqual(f.coordinator.statistics.pausesIssued, 1)
    }

    await t.runAsync("12. non-speech output is treated as AI activity (documented policy)") {
        let f = CoordinatorFixture()
        await f.startMonitoring()
        f.coordinator.audioActivityStarted(levelDB: -25)
        t.expectEqual(f.lastCommand?.kind, .pause, "any audible output from the tapped process pauses music")
        f.completeLast(nextState: .paused)
        t.expectEqual(f.coordinator.state, .musicPausedByOreja)
    }

    await t.runAsync("13. sleep and wake reconciles an owned pause") {
        let f = CoordinatorFixture()
        await f.startMonitoring()
        f.coordinator.audioActivityStarted(levelDB: -20)
        f.completeLast(nextState: .paused)

        f.coordinator.systemWillSleep()
        t.expectEqual(f.coordinator.state, .suspended)
        t.expect(f.coordinator.ownership != nil, "ownership survives sleep")

        f.coordinator.systemDidWake()
        t.expectEqual(f.coordinator.state, .restoringPlayback)
        t.expectEqual(f.lastCommand?.kind, .resume)
        f.completeLast(nextState: .playing)
        t.expectEqual(f.coordinator.state, .musicPlaying)
    }

    await t.runAsync("14. provider changes track while paused = no resume") {
        let f = CoordinatorFixture()
        await f.startMonitoring()
        f.coordinator.audioActivityStarted(levelDB: -20)
        f.completeLast(nextState: .paused)

        f.media.snapshot.track = MediaTrack(id: "track-2", title: "Deacon Blues", artist: "Steely Dan")
        f.coordinator.observe(media: f.media.snapshot)
        f.coordinator.audioActivityEnded()
        f.scheduler.advance(by: 5)

        t.expect(f.coordinator.ownership == nil)
        t.expectEqual(f.commands(of: .resume).count, 0)
        t.expectEqual(f.journal.clearCount, 1)
    }

    await t.runAsync("15. quitting while owning a pause = restore once") {
        let f = CoordinatorFixture()
        await f.startMonitoring()
        f.coordinator.audioActivityStarted(levelDB: -20)
        f.completeLast(nextState: .paused)

        let command = f.coordinator.commandForTermination()
        t.expectEqual(command?.kind, .resume)
        t.expect(f.journal.record != nil, "journal still present until the resume succeeds")

        f.coordinator.acknowledgeTermination()
        t.expect(f.coordinator.ownership == nil)
        t.expect(f.journal.record == nil, "journal cleared")

        let idle = CoordinatorFixture()
        await idle.startMonitoring()
        t.expect(idle.coordinator.commandForTermination() == nil, "nothing to restore when no pause is owned")
    }

    await t.runAsync("16. delayed pause + end of speech = one deterministic resume") {
        let f = CoordinatorFixture()
        await f.startMonitoring()

        f.coordinator.audioActivityStarted(levelDB: -20)
        t.expectEqual(f.commands.count, 1)
        f.coordinator.audioActivityEnded()
        f.scheduler.advance(by: 0.8)
        t.expectEqual(f.commands.count, 1, "resume waits for the slow pause")

        f.completeLast(nextState: .paused)
        t.expectEqual(f.commands.count, 2, "queued resume dispatched after pause lands")
        t.expectEqual(f.commands.map(\.kind), [.pause, .resume])

        f.completeLast(nextState: .playing)
        t.expect(f.coordinator.ownership == nil)
        t.expectEqual(f.coordinator.state, .musicPlaying)
    }

    await t.runAsync("16b. AI speaks again while a resume is in flight = pause again") {
        let f = CoordinatorFixture()
        await f.startMonitoring()
        f.coordinator.audioActivityStarted(levelDB: -20)
        f.completeLast(nextState: .paused)
        f.coordinator.audioActivityEnded()
        f.scheduler.advance(by: 0.8)
        t.expectEqual(f.lastCommand?.kind, .resume)

        f.coordinator.audioActivityStarted(levelDB: -20)
        f.completeLast(nextState: .playing)
        t.expectEqual(f.commands(of: .pause).count, 2, "music paused again before the new response")
        t.expectEqual(f.coordinator.state, .aiActive)
    }

    await t.runAsync("17. command failures stop automation at the failure limit") {
        let f = CoordinatorFixture()
        await f.startMonitoring()
        f.coordinator.audioActivityStarted(levelDB: -20)
        f.completeLast(succeeded: false)
        t.expect(f.coordinator.lastError != nil)
        t.expectEqual(f.coordinator.state, .aiActive, "AI is still speaking; no blind retry during the response")
        f.coordinator.audioActivityEnded()

        for _ in 0..<2 {
            f.coordinator.audioActivityStarted(levelDB: -20)
            f.completeLast(succeeded: false)
            f.coordinator.audioActivityEnded()
        }
        t.expectEqual(f.coordinator.state, .error)
        t.expect(f.coordinator.statistics.failedCommands >= 3)
        t.expect(f.diagnostics.events.contains { $0.category == .playback && $0.level == .error })
    }

    await t.runAsync("18. disabling automation restores an owned pause") {
        let f = CoordinatorFixture()
        await f.startMonitoring()
        f.coordinator.audioActivityStarted(levelDB: -20)
        f.completeLast(nextState: .paused)

        f.coordinator.setAutomationEnabled(false)
        t.expectEqual(f.coordinator.state, .disabled)
        t.expectEqual(f.lastCommand?.kind, .resume, "music should not be left paused")
        f.completeLast(nextState: .playing)
        t.expect(f.coordinator.ownership == nil)
    }

    await t.runAsync("18b. an app with no audio process yet is a waiting state, not an error") {
        let f = CoordinatorFixture()
        await f.startMonitoring()

        f.coordinator.monitoringFailed(AudioMonitoringFailure(
            .sourceUnavailable,
            "ChatGPT is not writing audio right now."
        ))
        t.expectEqual(f.coordinator.state, .searchingForSource)
        t.expectFalseMonitoredSource(f.coordinator.sourceIsValid)
        t.expect(
            !f.diagnostics.events.contains { $0.level == .error },
            "waiting for the app to speak must not look like a failure"
        )

        f.coordinator.monitoringBecameAvailable(description: "ChatGPT (2 audio processes)")
        t.expectEqual(f.coordinator.state, .musicPlaying)
    }

    await t.runAsync("19. commands are ignored without a valid source") {
        let f = CoordinatorFixture()
        f.coordinator.setAutomationEnabled(true)
        f.coordinator.audioActivityStarted(levelDB: -20)
        t.expectEqual(f.coordinator.state, .searchingForSource)
        t.expectEqual(f.commands.count, 0)
    }

    await t.runAsync("19b. user speech can start a pause when the person speaks first") {
        let f = CoordinatorFixture()
        await f.startMonitoring()

        var activity = ActivityAggregator()
        if activity.set(true, for: .user) {
            f.coordinator.audioActivityStarted(levelDB: -30)
        }

        t.expectEqual(f.lastCommand?.kind, .pause, "the user's first turn pauses playing music")
        f.completeLast(nextState: .paused)
        t.expectEqual(f.coordinator.state, .musicPausedByOreja)

        if activity.set(false, for: .user) {
            f.coordinator.audioActivityEnded()
        }
        f.scheduler.advance(by: 0.81)
        t.expectEqual(f.lastCommand?.kind, .resume, "music resumes after the user goes quiet")
    }

    await t.runAsync("20. music stays paused through a spoken exchange") {
        let f = CoordinatorFixture()
        await f.startMonitoring()

        // ChatGPT answers, goes quiet for a moment, then the user starts answering.
        f.coordinator.audioActivityStarted(levelDB: -20)
        f.completeLast(nextState: .paused)
        f.coordinator.audioActivityEnded()

        var activity = ActivityAggregator()
        if activity.set(true, for: .user) {
            f.coordinator.audioActivityStarted(levelDB: -30)
        }
        t.expectEqual(f.coordinator.state, .musicPausedByOreja, "the user taking over keeps it paused")
        t.expectEqual(f.commands.count, 1, "no second pause command for the user's turn")

        if activity.set(false, for: .user) {
            f.coordinator.audioActivityEnded()
        }
        t.expectEqual(f.coordinator.state, .waitingForSilence)
        t.expectEqual(f.commands.count, 1, "nothing is resumed while the quiet interval runs")

        f.scheduler.advance(by: 0.81)
        t.expectEqual(f.lastCommand?.kind, .resume, "music returns once both sides are quiet")
    }

    await t.runAsync("21. microphone-only speech pauses and restores with no valid AI source") {
        let f = CoordinatorFixture()
        await f.startMonitoring()
        f.coordinator.monitoringFailed(AudioMonitoringFailure(.sourceUnavailable, "No AI source is speaking."))
        t.expectFalseMonitoredSource(f.coordinator.sourceIsValid)

        t.expect(f.coordinator.setActivity(true, source: .user, levelDB: -30), "mic onset is accepted without a tap")
        t.expectEqual(f.lastCommand?.kind, .pause, "the user's voice pauses music on its own")
        f.completeLast(nextState: .paused)
        t.expect(f.coordinator.ownership != nil)

        t.expect(f.coordinator.setActivity(false, source: .user))
        f.scheduler.advance(by: 0.81)
        t.expectEqual(f.lastCommand?.kind, .resume, "the owned pause restores without a valid source")
        f.completeLast(nextState: .playing)
        t.expect(f.coordinator.ownership == nil)
    }

    await t.runAsync("27. built-in speakers: your voice alone never pauses music") {
        let f = CoordinatorFixture()
        await f.startMonitoring()
        f.coordinator.monitoringFailed(AudioMonitoringFailure(.sourceUnavailable, "No AI source is speaking."))
        f.coordinator.setUserSpeechMayStartAlone(false)

        t.expect(!f.coordinator.setActivity(true, source: .user, levelDB: -30),
                 "a mic onset with no AI interruption is rejected on speakers")
        t.expect(f.lastCommand == nil, "no pause command is issued from speaker feedback")
        t.expect(f.coordinator.ownership == nil)
    }

    await t.runAsync("28. built-in speakers: your voice keeps an AI-started interruption alive") {
        let f = CoordinatorFixture()
        await f.startMonitoring()
        f.coordinator.setUserSpeechMayStartAlone(false)

        f.coordinator.audioActivityStarted(levelDB: -20)
        t.expectEqual(f.lastCommand?.kind, .pause, "the assistant starts the pause")
        f.completeLast(nextState: .paused)

        // The combined state was already active, so the call reports no change, but the voice is
        // accepted and no second pause is issued.
        f.coordinator.setActivity(true, source: .user, levelDB: -30)
        t.expect(f.coordinator.userSpeechIsActive, "your voice is accepted while that interruption is in progress")
        f.coordinator.setActivity(false, source: .user)
        t.expect(!f.coordinator.userSpeechIsActive, "releasing the voice clears only the microphone half")
    }

    await t.runAsync("22. microphone-only duck lowers and restores volume with no valid AI source") {
        var policy = PlaybackPolicy.default
        policy.interruptionMode = .duck
        policy.duckVolume = 0.05
        policy.restoreVolume = 0.67
        let f = CoordinatorFixture(policy: policy)
        f.media.snapshot.volume = 0.67
        await f.startMonitoring()
        f.coordinator.sourceInvalidated(reason: "no AI source")

        t.expect(f.coordinator.setActivity(true, source: .user, levelDB: -30))
        t.expectEqual(f.lastCommand?.kind, .setVolume, "the configured duck action still applies")
        t.expectClose(f.lastCommand?.targetVolume ?? -1, 0.05)
        f.completeLast()
        t.expectClose(f.coordinator.volumeOwnership?.originalVolume ?? -1, 0.67)

        t.expect(f.coordinator.setActivity(false, source: .user))
        f.scheduler.advance(by: 0.81)
        t.expect(f.lastCommand?.restoresVolume == true)
        t.expectClose(f.lastCommand?.targetVolume ?? -1, 0.67)
        f.completeLast()
        t.expect(f.coordinator.volumeOwnership == nil)
    }

    await t.runAsync("23. monitoring failure clears AI activity so a retry's next onset pauses") {
        let f = CoordinatorFixture()
        await f.startMonitoring()
        t.expect(f.coordinator.setActivity(true, source: .ai, levelDB: -20))
        f.completeLast(nextState: .paused)

        f.coordinator.monitoringFailed(AudioMonitoringFailure(.streamFailed, "Tap stopped delivering audio."))
        f.completeLast(nextState: .playing)
        t.expectEqual(f.coordinator.state, .error)

        f.coordinator.retryAfterError()
        f.coordinator.monitoringBecameAvailable(description: "ChatGPT (1 audio process)")
        t.expect(f.coordinator.setActivity(true, source: .ai, levelDB: -20), "stale AI activity was cleared")
        t.expectEqual(f.lastCommand?.kind, .pause, "the next real onset pauses again")
    }

    await t.runAsync("24. AI failure while the microphone is active keeps the owned pause") {
        let f = CoordinatorFixture()
        await f.startMonitoring()
        t.expect(f.coordinator.setActivity(true, source: .ai, levelDB: -20))
        f.completeLast(nextState: .paused)
        t.expect(!f.coordinator.setActivity(true, source: .user, levelDB: -30), "overlap does not issue a second pause")
        t.expectEqual(f.commands(of: .pause).count, 1)

        f.coordinator.monitoringFailed(AudioMonitoringFailure(.streamFailed, "Tap stopped delivering audio."))
        t.expect(f.coordinator.ownership != nil, "the pause is kept while the user still speaks")
        t.expect(f.coordinator.aiIsActive, "the combined active state is kept")
        t.expectEqual(f.commands(of: .resume).count, 0, "no premature restore")

        t.expect(f.coordinator.setActivity(false, source: .user))
        f.scheduler.advance(by: 0.81)
        t.expectEqual(f.lastCommand?.kind, .resume, "restore happens only when speech ends")
    }

    await t.runAsync("25. microphone failure while AI is active keeps music paused") {
        let f = CoordinatorFixture()
        await f.startMonitoring()
        t.expect(f.coordinator.setActivity(true, source: .ai, levelDB: -20))
        f.completeLast(nextState: .paused)
        f.coordinator.setActivity(true, source: .user, levelDB: -30)

        f.coordinator.setUserSpeechActive(false)
        t.expect(f.coordinator.aiIsActive, "AI still drives the combined state")
        t.expectEqual(f.commands(of: .resume).count, 0, "a mic failure alone never resumes music")

        t.expect(f.coordinator.setActivity(false, source: .ai))
        f.scheduler.advance(by: 0.81)
        t.expectEqual(f.lastCommand?.kind, .resume)
    }

    await t.runAsync("26. automation toggle and teardown never strand an owned pause") {
        let f = CoordinatorFixture()
        f.coordinator.setAutomationEnabled(true)
        f.coordinator.setAutomationEnabled(false)
        f.coordinator.setAutomationEnabled(true)
        f.coordinator.monitoringBecameAvailable(description: "ChatGPT (1 audio process)")
        f.coordinator.observe(media: f.media.snapshot)

        t.expect(f.coordinator.setActivity(true, source: .user, levelDB: -30), "mic still works after the toggle")
        f.completeLast(nextState: .paused)
        f.coordinator.resetActivity()
        f.scheduler.advance(by: 0.81)
        t.expectEqual(f.lastCommand?.kind, .resume, "teardown finishes the interruption")

        f.completeLast(nextState: .playing)
        t.expect(f.coordinator.ownership == nil)
    }
}

private extension Harness {
    func expectFalseMonitoredSource(_ value: Bool, file: StaticString = #fileID, line: UInt = #line) {
        expect(!value, "monitored source should be invalid", file: file, line: line)
    }
}
