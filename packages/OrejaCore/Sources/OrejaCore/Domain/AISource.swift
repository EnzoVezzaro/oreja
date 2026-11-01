import Foundation

/// Which application Oreja listens to for AI output audio.
public struct AISourceSelection: Codable, Sendable, Equatable, Hashable {
    public enum Kind: String, Codable, Sendable, CaseIterable {
        case chatGPTDesktop
        case browser

        public var displayName: String {
            switch self {
            case .chatGPTDesktop: "ChatGPT desktop app"
            case .browser: "ChatGPT in a browser (experimental)"
            }
        }
    }

    public var kind: Kind
    public var bundleIdentifier: String
    public var displayName: String

    public init(kind: Kind, bundleIdentifier: String, displayName: String) {
        self.kind = kind
        self.bundleIdentifier = bundleIdentifier
        self.displayName = displayName
    }

    public static let chatGPTDesktop = AISourceSelection(
        kind: .chatGPTDesktop,
        bundleIdentifier: AISourceCatalog.chatGPTBundleIdentifiers[0],
        displayName: "ChatGPT"
    )

    public static let chrome = AISourceSelection(
        kind: .browser,
        bundleIdentifier: "com.google.Chrome",
        displayName: "Google Chrome"
    )

    public static let safari = AISourceSelection(
        kind: .browser,
        bundleIdentifier: "com.apple.Safari",
        displayName: "Safari"
    )

    public static let egoLite = AISourceSelection(
        kind: .browser,
        bundleIdentifier: "com.citrolabs.ego.lite",
        displayName: "ego lite"
    )

    /// Browsers that are known to be running, beyond the built-in choices, so the settings picker
    /// can offer whatever the user actually has open.
    public static func browser(bundleIdentifier: String, displayName: String) -> AISourceSelection {
        AISourceSelection(kind: .browser, bundleIdentifier: bundleIdentifier, displayName: displayName)
    }
}

/// Static knowledge about which applications can be monitored.
///
/// The ChatGPT desktop app has shipped under more than one bundle identifier
/// (`com.openai.chat` historically, `com.openai.codex` in the 2026 Codex-era build), so
/// matching is done on the `com.openai.` prefix plus the known identifiers. Browser entries are
/// offered as *experimental*: a browser tap captures every tab's audio, not just ChatGPT.
public enum AISourceCatalog {
    public static let chatGPTBundleIdentifiers: [String] = [
        "com.openai.chat",
        "com.openai.chatgpt",
        "com.openai.codex",
    ]

    public static let chatGPTPrefix = "com.openai."

    /// Bundle identifiers of browsers where ChatGPT voice is known to work on the web.
    /// These are experimental sources and are labelled as such in the UI.
    public static let browserBundleIdentifiers: [String] = [
        "com.google.Chrome",
        "com.apple.Safari",
        "com.microsoft.edgemac",
        "company.thebrowser.Browser",
        "com.brave.Browser",
        "org.mozilla.firefox",
        "com.citrolabs.ego.lite",
    ]

    /// Chromium keeps audio out of the main process: it renders in a helper with its own bundle
    /// identifier (`com.google.Chrome.helper`, `com.citrolabs.ego.helper`, …), which often does not
    /// share the app's full identifier. Each browser therefore declares the prefix its audio
    /// processes actually use.
    public static let browserAudioProcessPrefixes: [String: [String]] = [
        "com.google.Chrome": ["com.google.Chrome"],
        "com.apple.Safari": ["com.apple.Safari", "com.apple.WebKit"],
        "com.microsoft.edgemac": ["com.microsoft.edgemac"],
        "company.thebrowser.Browser": ["company.thebrowser.Browser"],
        "com.brave.Browser": ["com.brave.Browser"],
        "org.mozilla.firefox": ["org.mozilla.firefox"],
        // ego lite renders audio in `com.citrolabs.ego.helper`, not in `com.citrolabs.ego.lite`.
        "com.citrolabs.ego.lite": ["com.citrolabs.ego"],
    ]

    public static func isChatGPT(bundleIdentifier: String?) -> Bool {
        guard let bundleIdentifier, !bundleIdentifier.isEmpty else { return false }
        return bundleIdentifier.hasPrefix(chatGPTPrefix) || chatGPTBundleIdentifiers.contains(bundleIdentifier)
    }

    public static func isBrowser(bundleIdentifier: String?) -> Bool {
        guard let bundleIdentifier else { return false }
        return browserBundleIdentifiers.contains(bundleIdentifier)
    }

    /// Bundle identifiers that should be mixed into a process tap for the selection.
    /// Matching on the `com.openai.` prefix also captures audio produced by helper processes.
    public static func matchPrefixes(for selection: AISourceSelection) -> [String] {
        switch selection.kind {
        case .chatGPTDesktop:
            return [chatGPTPrefix] + chatGPTBundleIdentifiers
        case .browser:
            return browserAudioProcessPrefixes[selection.bundleIdentifier] ?? [selection.bundleIdentifier]
        }
    }
}

public struct AIAudioSourceDescriptor: Sendable, Equatable {
    public var displayName: String
    public var bundleIdentifierPrefixes: [String]
    public var isExperimental: Bool

    public init(displayName: String, bundleIdentifierPrefixes: [String], isExperimental: Bool) {
        self.displayName = displayName
        self.bundleIdentifierPrefixes = bundleIdentifierPrefixes
        self.isExperimental = isExperimental
    }

    public init(selection: AISourceSelection) {
        self.init(
            displayName: selection.displayName,
            bundleIdentifierPrefixes: AISourceCatalog.matchPrefixes(for: selection),
            isExperimental: selection.kind == .browser
        )
    }
}
