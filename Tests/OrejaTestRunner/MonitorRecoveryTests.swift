import Foundation
import OrejaAudio
import OrejaCore

@MainActor
func runMonitorRecoverySuite(_ t: Harness) {
    print("\nMonitor recovery")

    t.run("a route change with frames still arriving does not rebuild the tap") {
        let decision = MonitorRecoveryPolicy.deviceChangeDecision(
            pendingDeadline: 100,
            lastFrameTime: 100.48,
            lastRebuildTime: 0,
            now: 100.5
        )
        t.expect(!decision.shouldRebuild, "a healthy tap must not be torn down for a device switch")
        t.expect(decision.reason.contains("delivering"), decision.reason)
    }

    t.run("a stalled tap is rebuilt after the change settles") {
        let decision = MonitorRecoveryPolicy.deviceChangeDecision(
            pendingDeadline: 100,
            lastFrameTime: 99.0,
            lastRebuildTime: 0,
            now: 101.0
        )
        t.expect(decision.shouldRebuild, decision.reason)
    }

    t.run("a change before the settle deadline is ignored") {
        let decision = MonitorRecoveryPolicy.deviceChangeDecision(
            pendingDeadline: 101,
            lastFrameTime: 99.0,
            lastRebuildTime: 0,
            now: 100.5
        )
        t.expect(!decision.shouldRebuild, "let the new route settle before deciding")
    }

    t.run("a rebuild cooldown prevents a stalled tap from being rebuilt forever") {
        let decision = MonitorRecoveryPolicy.deviceChangeDecision(
            pendingDeadline: 100,
            lastFrameTime: 99.0,
            lastRebuildTime: 98.0,
            now: 100.5
        )
        t.expect(!decision.shouldRebuild)
        t.expect(decision.reason.contains("cooldown"), decision.reason)
    }

    t.run("a live tap with no frames ever is reported only after the full window") {
        let now = 1_000.0
        t.expect(!MonitorRecoveryPolicy.shouldReportNoSignal(
            tapLiveSince: now, hasDeliveredAudio: false, now: now + 29
        ))
        t.expect(MonitorRecoveryPolicy.shouldReportNoSignal(
            tapLiveSince: now, hasDeliveredAudio: false, now: now + 30
        ))
    }

    t.run("a quiet app that has spoken before is not reported as a permission problem") {
        let now = 1_000.0
        t.expect(!MonitorRecoveryPolicy.shouldReportNoSignal(
            tapLiveSince: now, hasDeliveredAudio: true, now: now + 600
        ), "normal silence between turns must stay silent in diagnostics")
    }

    t.run("zero-filled buffers do not masquerade as speech") {
        // A tap created without the capture grant can deliver silent buffers rather than fail.
        t.expect(MonitorRecoveryPolicy.audibleLevelDBFloor > -100)
        t.expect(!(-100.0 > MonitorRecoveryPolicy.audibleLevelDBFloor), "the silence floor is not audio")
        t.expect(-20.0 > MonitorRecoveryPolicy.audibleLevelDBFloor, "real speech is audio")
    }

    t.run("no tap means no no-signal report") {
        t.expect(!MonitorRecoveryPolicy.shouldReportNoSignal(
            tapLiveSince: nil, hasDeliveredAudio: false, now: 2_000
        ))
    }

    t.run("a no-signal hint is diagnostic only and carries no failure kind") {
        // The event exists to point at Settings; it must not be routable into monitoringFailed,
        // which would stop automation and restore the user's playback on a false positive.
        let event = AudioActivityEvent.noSignalDetected(detail: "check permission")
        guard case .noSignalDetected(let detail) = event else {
            t.expect(false, "event was not a no-signal hint")
            return
        }
        t.expectEqual(detail, "check permission")
        if case .monitorFailed = event {
            t.expect(false, "a no-signal hint must not be a monitor failure")
        }
    }
}
