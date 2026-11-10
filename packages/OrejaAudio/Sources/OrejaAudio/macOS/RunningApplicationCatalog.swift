import AppKit
import CoreAudio
import Foundation
import OrejaCore

/// One row in the audio-source picker.
public struct AudioAppChoice: Sendable, Identifiable, Equatable {
    public var selection: AISourceSelection
    public var category: AudioSourceCategory
    public var isInstalled: Bool
    public var isRunning: Bool
    /// The app currently has an audio process with output. Only meaningful while it is running.
    public var isProducingOutput: Bool

    public var id: String { selection.bundleIdentifier }
}

/// Builds the list of applications Oreja can listen to: known AI assistants, coding agents, browsers,
/// calls and media apps that are installed or running, plus every other regular app that is open.
public enum RunningApplicationCatalog {
    public static func choices(including selected: [AISourceSelection] = []) -> [AudioAppChoice] {
        let running = NSWorkspace.shared.runningApplications.filter { $0.activationPolicy != .prohibited }
        let runningIDs = running.compactMap(\.bundleIdentifier)
        let producing = producingBundleIdentifiers()

        func isRunning(_ bundleIdentifier: String) -> Bool {
            runningIDs.contains { $0 == bundleIdentifier || $0.hasPrefix(bundleIdentifier + ".") }
        }

        func isProducing(_ prefixes: [String]) -> Bool {
            producing.contains { bundle in prefixes.contains { bundle.hasPrefix($0) } }
        }

        var result: [AudioAppChoice] = []
        var listed = Set<String>()

        for app in AISourceCatalog.knownApps {
            let installed = isInstalled(bundleIdentifier: app.bundleIdentifier)
            let running = isRunning(app.bundleIdentifier)
            let isSelected = selected.contains { $0.bundleIdentifier == app.bundleIdentifier }
            guard installed || running || app.alwaysListed || isSelected else { continue }
            listed.insert(app.bundleIdentifier)
            result.append(
                AudioAppChoice(
                    selection: AISourceCatalog.selection(for: app),
                    category: app.category,
                    isInstalled: installed,
                    isRunning: running,
                    isProducingOutput: running && isProducing(app.prefixes)
                )
            )
        }

        for app in running where app.activationPolicy == .regular {
            guard let bundleID = app.bundleIdentifier,
                  AISourceCatalog.isSelectable(bundleIdentifier: bundleID),
                  AISourceCatalog.profile(for: bundleID) == nil,
                  listed.insert(bundleID).inserted else { continue }
            let name = app.localizedName ?? bundleID
            result.append(
                AudioAppChoice(
                    selection: .app(bundleIdentifier: bundleID, displayName: name),
                    category: .other,
                    isInstalled: true,
                    isRunning: true,
                    isProducingOutput: isProducing([bundleID])
                )
            )
        }

        // A selection whose app has since quit still appears, so it can be deselected.
        for selection in selected where listed.insert(selection.bundleIdentifier).inserted {
            result.append(
                AudioAppChoice(
                    selection: selection,
                    category: selection.category,
                    isInstalled: isInstalled(bundleIdentifier: selection.bundleIdentifier),
                    isRunning: false,
                    isProducingOutput: false
                )
            )
        }

        return result.sorted(by: order)
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

    /// Bundle identifiers of audio processes that are producing output right now. Helper processes
    /// report their own identifiers, so callers match these by prefix.
    private static func producingBundleIdentifiers() -> [String] {
        guard #available(macOS 14.2, *) else { return [] }
        let processes = (try? AudioProcessCatalog.allProcesses()) ?? []
        return processes.filter(\.isRunningOutput).compactMap(\.bundleID)
    }

    private static func order(_ lhs: AudioAppChoice, _ rhs: AudioAppChoice) -> Bool {
        let left = categoryRank(lhs.category)
        let right = categoryRank(rhs.category)
        if left != right { return left < right }
        if lhs.isProducingOutput != rhs.isProducingOutput { return lhs.isProducingOutput }
        if lhs.isRunning != rhs.isRunning { return lhs.isRunning }
        return lhs.selection.displayName.localizedCaseInsensitiveCompare(rhs.selection.displayName) == .orderedAscending
    }

    private static func categoryRank(_ category: AudioSourceCategory) -> Int {
        AudioSourceCategory.allCases.firstIndex(of: category) ?? AudioSourceCategory.allCases.count
    }
}
