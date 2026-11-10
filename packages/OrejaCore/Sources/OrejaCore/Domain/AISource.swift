import Foundation

/// An application Oreja listens to for voice output. Several can be selected at once; their audio is
/// merged into one activity signal, so a reply from any of them pauses the music.
public struct AISourceSelection: Codable, Sendable, Equatable, Hashable {
    public enum Kind: String, Codable, Sendable, CaseIterable {
        case chatGPTDesktop
        case browser
        case app

        public var displayName: String {
            switch self {
            case .chatGPTDesktop: "ChatGPT desktop app"
            case .browser: "Browser (experimental)"
            case .app: "Audio app"
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

    /// The ChatGPT desktop app as built in 2026 (`com.openai.codex`). Older builds are canonicalised
    /// to this value by `AISourceCatalog.normalized`, so there is one ChatGPT selection.
    public static let chatGPTDesktop = AISourceSelection(
        kind: .chatGPTDesktop,
        bundleIdentifier: "com.openai.codex",
        displayName: "ChatGPT"
    )

    public static let chrome = AISourceSelection(kind: .browser, bundleIdentifier: "com.google.Chrome", displayName: "Google Chrome")
    public static let safari = AISourceSelection(kind: .browser, bundleIdentifier: "com.apple.Safari", displayName: "Safari")
    public static let egoLite = AISourceSelection(kind: .browser, bundleIdentifier: "com.citrolabs.ego.lite", displayName: "ego lite")

    /// A browser that is not in the built-in catalog.
    public static func browser(bundleIdentifier: String, displayName: String) -> AISourceSelection {
        AISourceSelection(kind: .browser, bundleIdentifier: bundleIdentifier, displayName: displayName)
    }

    /// Any application that produces audio, selected by its bundle identifier.
    public static func app(bundleIdentifier: String, displayName: String) -> AISourceSelection {
        AISourceSelection(kind: .app, bundleIdentifier: bundleIdentifier, displayName: displayName)
    }

    public var category: AudioSourceCategory {
        AISourceCatalog.profile(for: bundleIdentifier)?.category ?? .other
    }

    public var isExperimental: Bool {
        kind == .browser || (AISourceCatalog.profile(for: bundleIdentifier)?.experimental ?? false)
    }
}

/// Groups used by the source picker, in display order.
public enum AudioSourceCategory: String, Codable, Sendable, CaseIterable {
    case aiAssistant
    case codingAgent
    case browser
    case calling
    case media
    case other

    public var title: String {
        switch self {
        case .aiAssistant: "AI assistants and voices"
        case .codingAgent: "Coding agents and terminals"
        case .browser: "Browsers (experimental)"
        case .calling: "Calls and messages"
        case .media: "Video and podcasts"
        case .other: "Other running apps"
        }
    }
}

/// An application Oreja knows how to match. The bundle identifiers are the ones observed on the
/// development Mac or documented by the vendor; an app that is installed under a different identifier
/// still appears in "Other running apps" and can be selected from there.
public struct KnownAudioApp: Sendable, Equatable {
    public var bundleIdentifier: String
    public var displayName: String
    public var category: AudioSourceCategory
    /// Prefixes of the Core Audio process identifiers that carry this app's audio.
    public var prefixes: [String]
    public var experimental: Bool
    /// Listed even when no matching app is installed or running (for example a system assistant).
    public var alwaysListed: Bool

    public init(
        bundleIdentifier: String,
        displayName: String,
        category: AudioSourceCategory,
        prefixes: [String]? = nil,
        experimental: Bool = false,
        alwaysListed: Bool = false
    ) {
        self.bundleIdentifier = bundleIdentifier
        self.displayName = displayName
        self.category = category
        self.prefixes = prefixes ?? [bundleIdentifier]
        self.experimental = experimental
        self.alwaysListed = alwaysListed
    }
}

/// Static knowledge about which applications can be monitored.
///
/// ChatGPT has shipped under several bundle identifiers (`com.openai.chat`, `com.openai.codex` in the
/// 2026 Codex-era build), so it matches on the `com.openai.` prefix. Browsers and system assistants
/// are experimental: a browser tap captures every tab, and a system service may not expose audio.
public enum AISourceCatalog {
    public static let chatGPTBundleIdentifiers: [String] = [
        "com.openai.chat",
        "com.openai.chatgpt",
        "com.openai.codex",
    ]

    public static let chatGPTPrefix = "com.openai."

    /// Players whose audio is what Oreja pauses. They are never valid AI sources: selecting one would
    /// make the music trigger its own pause.
    public static let musicPlayerBundleIdentifiers: [String] = [
        "com.apple.Music",
        "com.spotify.client",
        "org.videolan.vlc",
    ]

    /// Oreja never listens to itself.
    public static let ownBundlePrefix = "app.oreja."

    public static let knownApps: [KnownAudioApp] = [
        KnownAudioApp(bundleIdentifier: "com.openai.codex", displayName: "ChatGPT", category: .aiAssistant, prefixes: [chatGPTPrefix] + chatGPTBundleIdentifiers, alwaysListed: false),
        KnownAudioApp(bundleIdentifier: "com.anthropic.claudefordesktop", displayName: "Claude", category: .aiAssistant),
        KnownAudioApp(bundleIdentifier: "ai.perplexity.mac", displayName: "Perplexity", category: .aiAssistant),
        KnownAudioApp(bundleIdentifier: "com.microsoft.copilot-mac", displayName: "Microsoft Copilot", category: .aiAssistant),
        KnownAudioApp(
            bundleIdentifier: "com.apple.SiriNCService",
            displayName: "Siri",
            category: .aiAssistant,
            prefixes: ["com.apple.SiriNCService", "com.apple.assistant"],
            experimental: true,
            alwaysListed: true
        ),

        KnownAudioApp(bundleIdentifier: "com.google.antigravity-ide", displayName: "Antigravity", category: .codingAgent),
        KnownAudioApp(bundleIdentifier: "com.stablyai.orca", displayName: "Orca", category: .codingAgent),
        KnownAudioApp(bundleIdentifier: "com.microsoft.VSCode", displayName: "Visual Studio Code", category: .codingAgent),
        KnownAudioApp(bundleIdentifier: "com.todesktop.230313mzl4w4u92", displayName: "Cursor", category: .codingAgent),
        KnownAudioApp(bundleIdentifier: "com.exafunction.windsurf", displayName: "Windsurf", category: .codingAgent),
        KnownAudioApp(bundleIdentifier: "dev.zed.Zed", displayName: "Zed", category: .codingAgent),
        KnownAudioApp(bundleIdentifier: "dev.warp.Warp-Stable", displayName: "Warp", category: .codingAgent),
        KnownAudioApp(bundleIdentifier: "com.mitchellh.ghostty", displayName: "Ghostty", category: .codingAgent),
        KnownAudioApp(bundleIdentifier: "com.googlecode.iterm2", displayName: "iTerm2", category: .codingAgent),
        KnownAudioApp(bundleIdentifier: "com.apple.Terminal", displayName: "Terminal", category: .codingAgent),

        KnownAudioApp(bundleIdentifier: "com.google.Chrome", displayName: "Google Chrome", category: .browser, experimental: true),
        KnownAudioApp(bundleIdentifier: "com.apple.Safari", displayName: "Safari", category: .browser, prefixes: ["com.apple.Safari", "com.apple.WebKit"], experimental: true),
        KnownAudioApp(bundleIdentifier: "com.microsoft.edgemac", displayName: "Microsoft Edge", category: .browser, experimental: true),
        KnownAudioApp(bundleIdentifier: "company.thebrowser.Browser", displayName: "Arc", category: .browser, experimental: true),
        KnownAudioApp(bundleIdentifier: "com.brave.Browser", displayName: "Brave", category: .browser, experimental: true),
        KnownAudioApp(bundleIdentifier: "org.mozilla.firefox", displayName: "Firefox", category: .browser, experimental: true),
        KnownAudioApp(bundleIdentifier: "com.citrolabs.ego.lite", displayName: "ego lite", category: .browser, prefixes: ["com.citrolabs.ego"], experimental: true),

        KnownAudioApp(bundleIdentifier: "com.apple.FaceTime", displayName: "FaceTime", category: .calling),
        KnownAudioApp(bundleIdentifier: "net.whatsapp.WhatsApp", displayName: "WhatsApp", category: .calling),
        KnownAudioApp(bundleIdentifier: "ru.keepcoder.Telegram", displayName: "Telegram", category: .calling),
        KnownAudioApp(bundleIdentifier: "com.tinyspeck.slackmacgap", displayName: "Slack", category: .calling),
        KnownAudioApp(bundleIdentifier: "us.zoom.xos", displayName: "Zoom", category: .calling),
        KnownAudioApp(bundleIdentifier: "com.hnc.Discord", displayName: "Discord", category: .calling),
        KnownAudioApp(bundleIdentifier: "com.microsoft.teams2", displayName: "Microsoft Teams", category: .calling),

        KnownAudioApp(bundleIdentifier: "com.apple.podcasts", displayName: "Podcasts", category: .media),
        KnownAudioApp(bundleIdentifier: "com.apple.TV", displayName: "TV", category: .media),
    ]

    public static func profile(for bundleIdentifier: String?) -> KnownAudioApp? {
        guard let bundleIdentifier, !bundleIdentifier.isEmpty else { return nil }
        if isChatGPT(bundleIdentifier: bundleIdentifier) {
            return knownApps.first { $0.bundleIdentifier == "com.openai.codex" }
        }
        return knownApps.first { $0.bundleIdentifier == bundleIdentifier }
    }

    public static func isChatGPT(bundleIdentifier: String?) -> Bool {
        guard let bundleIdentifier, !bundleIdentifier.isEmpty else { return false }
        return bundleIdentifier.hasPrefix(chatGPTPrefix) || chatGPTBundleIdentifiers.contains(bundleIdentifier)
    }

    public static func isBrowser(bundleIdentifier: String?) -> Bool {
        profile(for: bundleIdentifier)?.category == .browser
    }

    public static var browserBundleIdentifiers: [String] {
        knownApps.filter { $0.category == .browser }.map(\.bundleIdentifier)
    }

    public static func isMusicPlayer(bundleIdentifier: String?) -> Bool {
        guard let bundleIdentifier, !bundleIdentifier.isEmpty else { return false }
        return musicPlayerBundleIdentifiers.contains { bundleIdentifier == $0 || bundleIdentifier.hasPrefix($0 + ".") }
    }

    /// Whether an application may be selected as an AI source at all.
    public static func isSelectable(bundleIdentifier: String?) -> Bool {
        guard let bundleIdentifier, !bundleIdentifier.isEmpty else { return false }
        return !isMusicPlayer(bundleIdentifier: bundleIdentifier) && !bundleIdentifier.hasPrefix(ownBundlePrefix)
    }

    /// Canonicalises ChatGPT builds, removes non-selectable entries and duplicates, and keeps the
    /// first occurrence of each app.
    public static func normalized(_ selections: [AISourceSelection]) -> [AISourceSelection] {
        var seen = Set<String>()
        let canonical = selections.map { selection in
            isChatGPT(bundleIdentifier: selection.bundleIdentifier) ? AISourceSelection.chatGPTDesktop : selection
        }
        return canonical.filter { selection in
            guard isSelectable(bundleIdentifier: selection.bundleIdentifier) else { return false }
            return seen.insert(selection.bundleIdentifier).inserted
        }
    }

    /// Bundle identifiers that should be mixed into a process tap for the selection.
    public static func matchPrefixes(for selection: AISourceSelection) -> [String] {
        if selection.kind == .chatGPTDesktop || isChatGPT(bundleIdentifier: selection.bundleIdentifier) {
            return [chatGPTPrefix] + chatGPTBundleIdentifiers
        }
        return profile(for: selection.bundleIdentifier)?.prefixes ?? [selection.bundleIdentifier]
    }

    /// The selection the picker stores for a known app.
    public static func selection(for app: KnownAudioApp) -> AISourceSelection {
        if isChatGPT(bundleIdentifier: app.bundleIdentifier) {
            return .chatGPTDesktop
        }
        switch app.category {
        case .browser: return .browser(bundleIdentifier: app.bundleIdentifier, displayName: app.displayName)
        default: return .app(bundleIdentifier: app.bundleIdentifier, displayName: app.displayName)
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
            isExperimental: selection.isExperimental
        )
    }

    /// One tap over every selected application. The names and prefixes are merged, so the monitor
    /// listens to all of them at once.
    public init(selections: [AISourceSelection]) {
        let normalized = AISourceCatalog.normalized(selections)
        var prefixes: [String] = []
        for selection in normalized {
            for prefix in AISourceCatalog.matchPrefixes(for: selection) where !prefixes.contains(prefix) {
                prefixes.append(prefix)
            }
        }
        self.init(
            displayName: normalized.isEmpty ? "no audio app" : normalized.map(\.displayName).joined(separator: ", "),
            bundleIdentifierPrefixes: prefixes,
            isExperimental: normalized.contains { $0.isExperimental }
        )
    }
}
