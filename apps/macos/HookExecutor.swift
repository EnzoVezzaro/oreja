import AppKit
import Darwin
import Foundation
import OrejaCore

private final class HookTimeoutState: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false

    func markTimedOut() {
        lock.lock()
        value = true
        lock.unlock()
    }

    var didTimeOut: Bool {
        lock.lock()
        defer { lock.unlock() }
        return value
    }
}

/// Runs hooks with macOS primitives only: the Shortcuts app and the default URL handler.
///
/// No shell, no embedded scripting language, no network client. A shortcut or a URL can do all of
/// that, which keeps the automation surface outside a process that holds audio-capture permission.
/// The first `shortcuts run` invocation shows the usual macOS automation prompt.
struct MacHookExecutor: HookExecuting {
    func execute(_ hook: Hook, context: HookContext) async throws {
        switch hook.action {
        case .runShortcut(let rawName):
            let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else {
                throw HookExecutionError("This hook has no shortcut name yet.")
            }
            try await Self.runShortcut(named: name, input: context.summary)
        case .openURL(let rawURL):
            let trimmed = rawURL.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let url = URL(string: trimmed), url.scheme != nil else {
                throw HookExecutionError("“\(trimmed)” is not a URL with a scheme, so it cannot be opened.")
            }
            await MainActor.run {
                _ = NSWorkspace.shared.open(url)
            }
        }
    }

    /// Runs off the main actor: a shortcut can take seconds and settings must stay responsive.
    private static func runShortcut(named name: String, input: String) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            DispatchQueue.global(qos: .utility).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts")
                process.arguments = ["run", name]
                let stdin = Pipe()
                process.standardInput = stdin
                // Discard output instead of using undrained pipes: a shortcut that writes
                // enough output must not block the process before it exits.
                process.standardOutput = FileHandle.nullDevice
                process.standardError = FileHandle.nullDevice

                do {
                    try process.run()
                } catch {
                    continuation.resume(throwing: HookExecutionError(
                        "Could not start Shortcuts: \(error.localizedDescription)"
                    ))
                    return
                }

                let timeoutState = HookTimeoutState()
                let timeout = DispatchWorkItem {
                    guard process.isRunning else { return }
                    timeoutState.markTimedOut()
                    process.terminate()

                    // Some external actions may not respond to SIGTERM. Bound the cleanup too.
                    DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 2) {
                        if process.isRunning {
                            _ = kill(process.processIdentifier, SIGKILL)
                        }
                    }
                }
                DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 30, execute: timeout)

                // The event is the shortcut's input, so shortcuts can branch on what happened.
                stdin.fileHandleForWriting.write(Data(input.utf8))
                try? stdin.fileHandleForWriting.close()
                process.waitUntilExit()
                timeout.cancel()

                if timeoutState.didTimeOut {
                    continuation.resume(throwing: HookExecutionError(
                        "Shortcut “\(name)” exceeded Oreja’s 30-second limit and was stopped."
                    ))
                    return
                }

                guard process.terminationStatus == 0 else {
                    continuation.resume(throwing: HookExecutionError(
                        "Shortcuts exited with \(process.terminationStatus). Is “\(name)” in your shortcut library?"
                    ))
                    return
                }
                continuation.resume()
            }
        }
    }
}
