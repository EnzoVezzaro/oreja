import Foundation
import OrejaAudio
import OrejaCore

/// Developer diagnostic: tap one running application and print its output level.
///
/// This exists so audio capture can be verified without the menu bar UI and without guessing:
///
///     ./build/oreja-probe --bundle com.openai.codex
///     ./build/oreja-probe --bundle com.openai.codex --seconds 20
///
/// It never records or writes audio; it prints dBFS levels and activity transitions only.
@main
struct AudioProbe {
    static func main() async {
        var bundlePrefix = "com.openai."
        var seconds: Double = 15
        var threshold: Double = -45
        var listOnly = false
        var targetPID: pid_t?
        var speechGate = false

        var arguments = Array(CommandLine.arguments.dropFirst())
        while let argument = arguments.first {
            arguments.removeFirst()
            switch argument {
            case "--bundle":
                if let value = arguments.first {
                    bundlePrefix = value
                    arguments.removeFirst()
                }
            case "--seconds":
                if let value = arguments.first, let parsed = Double(value) {
                    seconds = parsed
                    arguments.removeFirst()
                }
            case "--threshold":
                if let value = arguments.first, let parsed = Double(value) {
                    threshold = parsed
                    arguments.removeFirst()
                }
            case "--pid":
                if let value = arguments.first, let parsed = pid_t(value) {
                    targetPID = parsed
                    arguments.removeFirst()
                }
            case "--list":
                listOnly = true
            case "--speech-gate":
                // Runs the app's speech-shape filter instead of the raw level path, so notification-shaped
                // sounds can be checked against real system audio.
                speechGate = true
            case "--help", "-h":
                print("usage: oreja-probe [--bundle <prefix> | --pid <pid>] [--seconds <n>] [--threshold <dBFS>] [--speech-gate] [--list]")
                return
            default:
                print("Unknown argument: \(argument)")
                print("usage: oreja-probe [--bundle <prefix> | --pid <pid>] [--seconds <n>] [--threshold <dBFS>] [--list]")
                return
            }
        }

        guard #available(macOS 14.2, *) else {
            print("Core Audio process taps require macOS 14.2 or newer.")
            exit(2)
        }

        print("Oreja audio probe")
        if listOnly {
            do {
                let all = try AudioProcessCatalog.allProcesses()
                print("Audio processes (\(all.count)):")
                for process in all.sorted(by: { ($0.bundleID ?? "") < ($1.bundleID ?? "") }) {
                    print("  pid \(process.pid)  output=\(process.isRunningOutput ? "yes" : "no ")  \(process.bundleID ?? "(no bundle id)")")
                }
            } catch {
                print("Process discovery failed: \(error.localizedDescription)")
                exit(4)
            }
            return
        }
        var configuration = AudioActivityDetector.Configuration()
        configuration.activationThresholdDB = threshold
        let speechFilter: SpeechShapeFilter.Configuration = speechGate ? SpeechShapeFilter.Configuration() : .passthrough
        let monitor: ProcessAudioMonitor

        if let targetPID {
            do {
                let all = try AudioProcessCatalog.allProcesses()
                guard let process = all.first(where: { $0.pid == targetPID }) else {
                    print("PID \(targetPID) is not an audio process. Run --list while it plays audio.")
                    exit(3)
                }
                print("Tapping pid \(process.pid) (\(process.bundleID ?? "no bundle id"), output=\(process.isRunningOutput)).")
                monitor = ProcessAudioMonitor(
                    targetObjectIDs: [process.objectID],
                    displayName: "pid \(process.pid)",
                    detectorConfiguration: configuration,
                    speechFilterConfiguration: speechFilter
                )
            } catch {
                print("Process discovery failed: \(error.localizedDescription)")
                exit(4)
            }
        } else {
            print("Looking for processes with bundle prefix '\(bundlePrefix)'…")
            do {
                let processes = try AudioProcessCatalog.processes(matchingPrefixes: [bundlePrefix])
                guard !processes.isEmpty else {
                    print("No matching audio processes. Start the app's voice session first.")
                    exit(3)
                }
                for process in processes {
                    print("  found pid \(process.pid) bundle \(process.bundleID ?? "?") output=\(process.isRunningOutput)")
                }
            } catch {
                print("Process discovery failed: \(error.localizedDescription)")
                exit(4)
            }

            let descriptor = AIAudioSourceDescriptor(
                displayName: bundlePrefix,
                bundleIdentifierPrefixes: [bundlePrefix],
                isExperimental: true
            )
            monitor = ProcessAudioMonitor(
                descriptor: descriptor,
                detectorConfiguration: configuration,
                speechFilterConfiguration: speechFilter
            )
        }

        do {
            try await monitor.start()
        } catch {
            print("Could not start the tap: \(error.localizedDescription)")
            exit(5)
        }

        print("Monitoring for \(Int(seconds))s. Speak in the target app. Ctrl-C to stop.")

        let deadline = Date().addingTimeInterval(seconds)
        let stopper = Task {
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            await monitor.stop()
        }

        for await event in monitor.events {
            // Absolute host time so a harness can compare detection with the moment the target
            // process actually started producing sound.
            print(String(format: "t=%.3f ", Self.hostSeconds()), terminator: "")
            switch event {
            case .monitorStarted(let description):
                print("• monitoring \(description)")
            case .targetsChanged(let description):
                print("• re-targeted: \(description)")
            case .activityStarted(let levelDB):
                print("▶ activity started at \(String(format: "%.1f", levelDB)) dBFS")
            case .activityEnded(let levelDB):
                print("■ activity ended at \(String(format: "%.1f", levelDB)) dBFS")
            case .activitySuppressed(let reason, let levelDB):
                print("· suppressed (\(reason.explanation)) at \(String(format: "%.1f", levelDB)) dBFS")
            case .noSignalDetected(let detail):
                print("! no signal: \(detail)")
            case .monitorFailed(let failure):
                print("✕ monitor failed: \(failure.message)")
            case .monitorStopped(let reason):
                print("• stopped: \(reason)")
            }
            if Date() >= deadline { break }
        }

        stopper.cancel()
        await monitor.stop()
        print("Done. No audio was stored.")
    }

    static func hostSeconds() -> Double {
        var timebase = mach_timebase_info_data_t()
        mach_timebase_info(&timebase)
        return Double(mach_absolute_time()) * Double(timebase.numer) / Double(timebase.denom) / 1_000_000_000
    }
}
