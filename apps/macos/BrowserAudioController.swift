import Foundation
import OrejaCore

/// Whole-browser playback control is a documented hard platform blocker, not a best-effort
/// adapter. macOS exposes no supported public per-process gain or pause/transport API for a
/// browser; per-tab JavaScript and an Automation permission popup are explicitly out of scope and
/// would fake control. This type only reports that status — it never runs AppleScript, never mutes
/// an app, and never touches system volume. Selected conversation audio stays audible.
@MainActor
final class BrowserAudioController {
    static var capability: PlaybackTargetCapability {
        PlaybackTargets.capability(for: .browser)
    }

    /// Known browser bundle IDs, used only to describe which apps are in scope. Presence here does
    /// not imply a control adapter exists.
    static var knownBrowserBundleIDs: Set<String> {
        Set(AISourceCatalog.knownApps.filter { $0.category == .browser }.map(\.bundleIdentifier))
    }

    private(set) var lastErrorMessage: String?

    /// Records the unsupported reason when a browser target is selected. Deliberately performs no
    /// control action.
    func update(
        applications: [AISourceSelection],
        active: Bool,
        mode: MusicInterruptionMode,
        duckPercent: Int
    ) {
        lastErrorMessage = applications.isEmpty ? nil : Self.capability.reason
    }
}
