import AppKit
import Foundation
import OrejaAudio
import OrejaCore
import OrejaMedia

/// End-to-end integration harness: a real Core Audio process tap, the real playback coordinator and
/// the real Apple Music adapter, driven by a controlled audio fixture.
///
/// It exists to measure what unit tests cannot: capture latency, pause/resume command latency and
/// whether Music really pauses and resumes the same track. It plays a WAV through `afplay`, taps
/// only that process (never Music), and prints observed timings. Nothing is recorded.
///
///     ./scripts/build.sh --harness
///     ./build/bin/oreja-integration --file /tmp/oreja-test.wav --lead 3 --tone 2.5
@main
struct IntegrationHarness {
    @MainActor
    static func main() async {
        let options = Options(arguments: Array(CommandLine.arguments.dropFirst()))
        guard let file = options.file else {
            print("usage: oreja-integration --file <wav> [--lead 3] [--tone 2.5] [--seconds 15]")
            exit(2)
        }
        guard FileManager.default.fileExists(atPath: file) else {
            print("Fixture not found: \(file)")
            exit(2)
        }

        print("Oreja integration harness")
        print("fixture: \(file) (lead \(options.lead)s, tone \(options.tone)s)")
        print("No audio is recorded; only levels and command timings are printed.\n")

        let media = AppleMusicController()
        let before = await media.currentPlayback()
        guard before.state == .playing, let originalTrack = before.track else {
            print("Music must be playing a track before this test. State: \(before.state.rawValue)")
            exit(3)
        }
        let startPosition = scriptDouble(AppleMusicScripts.position) ?? -1
        print("music before: playing \"\(originalTrack.displayName)\" at \(String(format: "%.2f", startPosition))s")

        // Launch the controlled audio source. The file begins with silence so the tap can attach
        // before the tone starts.
        let player = Process()
        player.executableURL = URL(fileURLWithPath: "/usr/bin/afplay")
        player.arguments = [file]
        player.standardOutput = FileHandle.nullDevice
        player.standardError = FileHandle.nullDevice
        let launchedAt = ProcessInfo.processInfo.systemUptime
        do {
            try player.run()
        } catch {
            print("Could not launch afplay: \(error.localizedDescription)")
            exit(4)
        }

        guard #available(macOS 14.2, *) else {
            print("Core Audio process taps require macOS 14.2+.")
            exit(5)
        }

        var target: AudioProcessCatalog.AudioProcess?
        for _ in 0..<150 {
            if let process = try? AudioProcessCatalog.allProcesses().first(where: { $0.pid == player.processIdentifier }) {
                target = process
                break
            }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        guard let target else {
            print("afplay did not register as an audio process.")
            player.terminate()
            exit(6)
        }
        print("tap: pid \(target.pid), output=\(target.isRunningOutput), 1 process (Music excluded)")

        let coordinator = PlaybackCoordinator(policy: {
            var policy = PlaybackPolicy.default
            policy.quietInterval = 0.8
            return policy
        }())

        var pauseIssuedAt: TimeInterval?
        var pauseDoneAt: TimeInterval?
        var resumeIssuedAt: TimeInterval?
        var resumeDoneAt: TimeInterval?
        var pauseSnapshot: MediaPlaybackSnapshot?
        var resumeSnapshot: MediaPlaybackSnapshot?
        var pauseCount = 0
        var resumeCount = 0
        var commandError: String?

        coordinator.onCommand = { command in
            let issued = ProcessInfo.processInfo.systemUptime
            Task { @MainActor in
                do {
                    let snapshot: MediaPlaybackSnapshot
                    switch command.kind {
                    case .pause:
                        pauseCount += 1
                        pauseIssuedAt = issued
                        snapshot = try await media.pauseReporting()
                    case .resume:
                        resumeCount += 1
                        resumeIssuedAt = issued
                        snapshot = try await media.resumeReporting()
                    case .setVolume:
                        // The harness verifies pause/resume timing; ducking is still executed so
                        // the coordinator completes its command rather than stalling.
                        try await media.setVolume(command.targetVolume ?? 0)
                        snapshot = await media.currentPlayback()
                    }
                    let done = ProcessInfo.processInfo.systemUptime
                    switch command.kind {
                    case .pause:
                        pauseDoneAt = done
                        pauseSnapshot = snapshot
                    case .resume:
                        resumeDoneAt = done
                        resumeSnapshot = snapshot
                    case .setVolume:
                        break
                    }
                    coordinator.complete(command.id, outcome: .succeeded(snapshot))
                } catch {
                    commandError = error.localizedDescription
                    coordinator.complete(command.id, outcome: .failed(.commandFailed(error.localizedDescription)))
                }
            }
        }

        // The fixture is a steady sine tone, which the app's speech-shape filter classifies as an alert
        // rather than speech. Measuring the tap-to-command path therefore needs the raw gate, or
        // this harness would report zero activity. The gate's own cost is the confirmation window
        // (see docs/test-evidence.md).
        let monitor = ProcessAudioMonitor(
            targetObjectIDs: [target.objectID],
            displayName: "afplay fixture",
            speechFilterConfiguration: .passthrough
        )

        coordinator.setAutomationEnabled(true)
        coordinator.observe(media: before)

        do {
            try await monitor.start()
        } catch {
            print("Could not start tap: \(error.localizedDescription)")
            player.terminate()
            exit(7)
        }
        coordinator.monitoringBecameAvailable(description: "afplay pid \(target.pid)")

        var activityStartedAt: TimeInterval?
        var activityEndedAt: TimeInterval?
        var monitorError: String?

        let deadline = launchedAt + options.seconds
        let stopper = Task { @MainActor in
            while ProcessInfo.processInfo.systemUptime < deadline {
                if resumeDoneAt != nil { break }
                try? await Task.sleep(nanoseconds: 50_000_000)
            }
            await monitor.stop()
        }

        for await event in monitor.events {
            let now = ProcessInfo.processInfo.systemUptime
            switch event {
            case .monitorStarted(let description):
                print("monitor: \(description)")
            case .targetsChanged(let description):
                print("monitor: re-targeted at \(description)")
            case .activityStarted(let levelDB):
                activityStartedAt = now
                print(String(format: "event: activity started at %.1f dBFS (t+%.3fs)", levelDB, now - launchedAt))
                coordinator.audioActivityStarted(levelDB: levelDB)
            case .activityEnded(let levelDB):
                activityEndedAt = now
                print(String(format: "event: activity ended at %.1f dBFS (t+%.3fs)", levelDB, now - launchedAt))
                coordinator.audioActivityEnded()
            case .activitySuppressed(let reason, let levelDB):
                print(String(format: "event: suppressed (%@) at %.1f dBFS", reason.explanation, levelDB))
            case .noSignalDetected(let detail):
                print("no signal: \(detail)")
            case .microphoneLevels:
                break
            case .monitorFailed(let failure):
                monitorError = failure.message
                print("monitor failed: \(failure.message)")
            case .monitorStopped(let reason):
                print("monitor stopped: \(reason)")
            }
            if resumeDoneAt != nil || now >= deadline { break }
        }

        stopper.cancel()
        await monitor.stop()

        // Give a late second pause/resume a moment to surface, so oscillation is detectable.
        try? await Task.sleep(nanoseconds: 700_000_000)
        let after = await media.currentPlayback()
        let endPosition = scriptDouble(AppleMusicScripts.position) ?? -1

        print("\n== Observed ==")
        print("activity start event: t+\(format(activityStartedAt.map { $0 - launchedAt }))")
        print("pause issued:        t+\(format(pauseIssuedAt.map { $0 - launchedAt }))")
        print("pause completed:     t+\(format(pauseDoneAt.map { $0 - launchedAt }))")
        print("activity end event:  t+\(format(activityEndedAt.map { $0 - launchedAt }))")
        print("resume issued:       t+\(format(resumeIssuedAt.map { $0 - launchedAt }))")
        print("resume completed:    t+\(format(resumeDoneAt.map { $0 - launchedAt }))")

        let expectedOnset = launchedAt + options.lead
        let expectedSilence = launchedAt + options.lead + options.tone
        if let activityStartedAt {
            print(String(format: "capture+detect onset after expected tone: %.0f ms", (activityStartedAt - expectedOnset) * 1000))
        }
        if let pauseIssuedAt, let activityStartedAt {
            print(String(format: "coordinator pause decision: %.0f ms", (pauseIssuedAt - activityStartedAt) * 1000))
        }
        if let pauseDoneAt, let pauseIssuedAt {
            print(String(format: "Apple Music pause command: %.0f ms", (pauseDoneAt - pauseIssuedAt) * 1000))
        }
        if let pauseDoneAt {
            print(String(format: "observed pause path (expected tone start to Music paused): %.0f ms", (pauseDoneAt - expectedOnset) * 1000))
        }
        if let activityEndedAt {
            print(String(format: "detector silence recognition after expected tone end: %.0f ms", (activityEndedAt - expectedSilence) * 1000))
        }
        if let resumeIssuedAt, let activityEndedAt {
            print(String(format: "quiet interval wait: %.0f ms", (resumeIssuedAt - activityEndedAt) * 1000))
        }
        if let resumeDoneAt, let resumeIssuedAt {
            print(String(format: "Apple Music resume command: %.0f ms", (resumeDoneAt - resumeIssuedAt) * 1000))
        }
        if let resumeDoneAt {
            print(String(format: "observed resume path (expected tone end to Music playing): %.0f ms", (resumeDoneAt - expectedSilence) * 1000))
        }

        print("\n== Result ==")
        print("pause commands: \(pauseCount), resume commands: \(resumeCount)")
        print("paused state observed: \(pauseSnapshot?.state.rawValue ?? "nil")")
        print("resumed state observed: \(resumeSnapshot?.state.rawValue ?? "nil")")
        print("track after: \"\(after.track?.displayName ?? "nil")\"")
        print("position before: \(String(format: "%.2f", startPosition))s, after: \(String(format: "%.2f", endPosition))s")
        if let commandError { print("command error: \(commandError)") }
        if let monitorError { print("monitor error: \(monitorError)") }

        var failures: [String] = []
        if activityStartedAt == nil { failures.append("no activity event") }
        if pauseSnapshot?.state != .paused { failures.append("Music never observed paused") }
        if resumeSnapshot?.state != .playing { failures.append("Music never observed playing again") }
        if pauseCount != 1 { failures.append("expected 1 pause command, got \(pauseCount)") }
        if resumeCount != 1 { failures.append("expected 1 resume command, got \(resumeCount)") }
        if after.track?.id != originalTrack.id { failures.append("track changed") }
        if endPosition >= 0, startPosition >= 0, endPosition + 0.5 < startPosition {
            failures.append("playback position moved backwards")
        }
        if let commandError { failures.append("command error: \(commandError)") }
        if let monitorError { failures.append("monitor error: \(monitorError)") }

        if failures.isEmpty {
            print("PASS: real capture → pause → quiet interval → resume, same track")
        } else {
            print("FAIL: " + failures.joined(separator: "; "))
        }

        if player.isRunning { player.terminate() }
        exit(failures.isEmpty ? 0 : 1)
    }

    static func format(_ value: TimeInterval?) -> String {
        guard let value else { return "—" }
        return String(format: "%.3fs", value)
    }

    static func scriptDouble(_ source: String) -> Double? {
        guard let script = NSAppleScript(source: source) else { return nil }
        var error: NSDictionary?
        let descriptor = script.executeAndReturnError(&error)
        guard error == nil else { return nil }
        return Double(descriptor.stringValue ?? "")
    }

    struct Options {
        var file: String?
        var lead: Double = 3
        var tone: Double = 2.5
        var seconds: Double = 15

        init(arguments: [String]) {
            var remaining = arguments
            while let argument = remaining.first {
                remaining.removeFirst()
                switch argument {
                case "--file":
                    if let value = remaining.first { file = value; remaining.removeFirst() }
                case "--lead":
                    if let value = remaining.first, let parsed = Double(value) { lead = parsed; remaining.removeFirst() }
                case "--tone":
                    if let value = remaining.first, let parsed = Double(value) { tone = parsed; remaining.removeFirst() }
                case "--seconds":
                    if let value = remaining.first, let parsed = Double(value) { seconds = parsed; remaining.removeFirst() }
                default:
                    break
                }
            }
        }
    }
}

/// Minimal read-only scripts used for position checks only. Playback control goes through
/// AppleMusicController, the same adapter the app uses.
enum AppleMusicScripts {
    static let position = """
    if application "Music" is running then
        tell application "Music" to return (player position as text)
    else
        return "-1"
    end if
    """
}
