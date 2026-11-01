import AppKit
import CoreAudio
import Foundation
import OrejaCore

public struct RunningAudioApplication: Sendable, Identifiable, Equatable {
    public var bundleIdentifier: String
    public var name: String
    public var isRunning: Bool
    public var isProducingOutput: Bool

    public var id: String { bundleIdentifier }
}

/// Discovers installed/running applications that Oreja can offer as an AI source.
public enum RunningApplicationCatalog {
    public static func runningApplications() -> [RunningAudioApplication] {
        let running = NSWorkspace.shared.runningApplications.filter { $0.activationPolicy != .prohibited }
        var seen = Set<String>()
        var result: [RunningAudioApplication] = []
        for app in running {
            guard let bundleID = app.bundleIdentifier, !seen.contains(bundleID) else { continue }
            guard AISourceCatalog.isChatGPT(bundleIdentifier: bundleID) || AISourceCatalog.isBrowser(bundleIdentifier: bundleID) else {
                continue
            }
            seen.insert(bundleID)
            result.append(
                RunningAudioApplication(
                    bundleIdentifier: bundleID,
                    name: AISourceCatalog.isChatGPT(bundleIdentifier: bundleID) ? "ChatGPT" : (app.localizedName ?? bundleID),
                    isRunning: true,
                    isProducingOutput: false
                )
            )
        }
        return result.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// Returns the ChatGPT application's bundle identifier if it is installed, preferring the
    /// newest known identifier that is actually present on disk.
    public static func installedChatGPTBundleIdentifier() -> String? {
        for bundleID in AISourceCatalog.chatGPTBundleIdentifiers {
            if NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) != nil {
                return bundleID
            }
        }
        return nil
    }

    public static func isInstalled(bundleIdentifier: String) -> Bool {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) != nil
    }

    public static func launch(bundleIdentifier: String) throws {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) else {
            throw MediaControlError.providerUnavailable(bundleIdentifier)
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: configuration) { _, error in
            if let error {
                NSLog("Oreja: failed to launch %@: %@", bundleIdentifier, error.localizedDescription)
            }
        }
    }
}
