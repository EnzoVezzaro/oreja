import Foundation

/// A hardware-neutral description of one audio-producing process. The platform layer maps its Core
/// Audio process object onto this value so diagnostics can name the exact helper that was tapped.
public struct AudioProcessIdentity: Sendable, Equatable {
    public var bundleID: String?
    public var pid: Int32
    public var isRunningOutput: Bool

    public init(bundleID: String?, pid: Int32, isRunningOutput: Bool) {
        self.bundleID = bundleID
        self.pid = pid
        self.isRunningOutput = isRunningOutput
    }
}

/// Formats the tapped process set for logs and Settings. This is deliberately in the neutral core
/// so the attribution format is covered by deterministic tests, not by a live hardware run.
public enum AudioProcessDiagnostics {
    public static func describe(_ processes: [AudioProcessIdentity]) -> String {
        guard !processes.isEmpty else { return "no audio process matched" }
        return processes.map { process in
            let name = process.bundleID ?? "unknown bundle"
            let state = process.isRunningOutput ? "output" : "silent"
            return "\(name) (pid \(process.pid), \(state))"
        }.joined(separator: ", ")
    }
}
