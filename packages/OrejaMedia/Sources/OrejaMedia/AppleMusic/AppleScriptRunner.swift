import AppKit
import Foundation
import OrejaCore

/// Executes AppleScript against the Music application.
///
/// `NSAppleScript` is not thread-safe, so every call is main-actor isolated. The scripts generated
/// by `AppleMusicScript` guard with `if application "Music" is running then`, which means Oreja
/// never launches Music on its own.
@MainActor
public final class AppleScriptRunner {
    /// `NSAppleScript` compiles its source on the first execution and keeps the compiled form.
    /// Building a fresh instance per call therefore pays compilation on every pause and resume,
    /// which is a large part of the command latency, so compiled scripts are cached by source.
    private var compiled: [String: NSAppleScript] = [:]

    public init() {}

    private func script(for source: String) -> NSAppleScript? {
        if let cached = compiled[source] { return cached }
        guard let created = NSAppleScript(source: source) else { return nil }
        compiled[source] = created
        return created
    }

    public func run(_ source: String) -> Result<String, MediaControlError> {
        guard let script = script(for: source) else {
            return .failure(.commandFailed("The AppleScript could not be compiled."))
        }

        var errorInfo: NSDictionary?
        let descriptor = script.executeAndReturnError(&errorInfo)

        if let errorInfo {
            let number = (errorInfo[NSAppleScript.errorNumber] as? NSNumber)?.intValue ?? 0
            let message = errorInfo[NSAppleScript.errorMessage] as? String ?? "Unknown automation error."
            switch number {
            case -1743:
                return .failure(.permissionDenied("Music"))
            case -600:
                return .failure(.notRunning("Music"))
            case -1728:
                return .failure(.commandFailed("Music could not find the requested item."))
            default:
                return .failure(.commandFailed("Music automation failed (\(number)): \(message)"))
            }
        }

        return .success(descriptor.stringValue ?? "")
    }
}
