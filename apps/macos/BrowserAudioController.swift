import AppKit
import Foundation
import OrejaCore
import OrejaMedia

/// Controls standard HTML audio/video elements in every tab of supported scriptable browsers.
/// The page-side lease restores media if Oreja exits while an interruption is active.
@MainActor
final class BrowserAudioController {
    static var supportedBrowserBundleIDs: Set<String> {
        BrowserMediaScripting.supportedBundleIdentifiers
    }
    private var applications: [AISourceSelection] = []
    private var active = false
    private var mode: MusicInterruptionMode = .duck
    private var duckPercent = 5
    private var refreshTask: Task<Void, Never>?
    private(set) var lastErrorMessage: String?

    private(set) var unsupportedBundleIdentifiers: [String] = []

    func update(
        applications: [AISourceSelection],
        active: Bool,
        mode: MusicInterruptionMode,
        duckPercent: Int
    ) {
        let nextApplications = applications.filter {
            BrowserMediaScripting.dialectsByBundleIdentifier[$0.bundleIdentifier] != nil
        }
        unsupportedBundleIdentifiers = applications
            .filter { BrowserMediaScripting.dialectsByBundleIdentifier[$0.bundleIdentifier] == nil }
            .map(\.bundleIdentifier)
        let previousApplications = self.applications
        let changed = self.applications != nextApplications
            || self.active != active
            || self.mode != mode
            || self.duckPercent != duckPercent
        if changed {
            if active {
                let removedTargets = previousApplications.filter { !nextApplications.contains($0) }
                if !removedTargets.isEmpty { restoreOpenTabs(in: removedTargets) }
            } else {
                refreshTask?.cancel()
                refreshTask = nil
                restoreOpenTabs(in: Array(Set(previousApplications + nextApplications)))
            }
        }
        self.applications = nextApplications
        self.active = active
        self.mode = mode
        self.duckPercent = min(max(duckPercent, 1), 100)

        guard changed else { return }
        if active, !nextApplications.isEmpty {
            applyToOpenTabs()
            startRefreshLoop()
        } else {
            refreshTask?.cancel()
            refreshTask = nil
            lastErrorMessage = nil
        }
    }

    private func startRefreshLoop() {
        guard refreshTask == nil else { return }
        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard let self, self.active else { return }
                self.applyToOpenTabs()
            }
        }
    }

    private func applyToOpenTabs() {
        let command = BrowserMediaScripting.mediaControlJavaScript(
            mode: mode,
            duckPercent: duckPercent
        )
        let errors = applications.compactMap { run(command, for: $0) }
        lastErrorMessage = errors.first
    }

    private func restoreOpenTabs(in applications: [AISourceSelection]? = nil) {
        let command = "(() => { const s = window.__orejaMediaControlV1; if (!s) return 'ok'; s.last = 0; return 'ok'; })()"
        let targets = applications ?? self.applications
        let errors = targets.compactMap { run(command, for: $0) }
        lastErrorMessage = errors.first
    }

    private func run(_ javascript: String, for app: AISourceSelection) -> String? {
        guard let source = BrowserMediaScripting.controlScript(
            bundleIdentifier: app.bundleIdentifier,
            javascript: javascript
        ) else { return "No browser media adapter is registered for \(app.displayName)." }
        guard let script = NSAppleScript(source: source) else { return "Could not prepare browser media control." }
        var error: NSDictionary?
        let result = script.executeAndReturnError(&error)
        if let error {
            return "Browser media control failed for \(app.displayName): \(error.description)"
        }
        if let failures = result.stringValue, failures != "0" {
            return "Browser media control could not reach \(failures) tab(s) in \(app.displayName). Check its JavaScript-from-Apple-Events setting."
        }
        return nil
    }
}
