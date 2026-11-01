import Foundation

public struct AppSettings: Codable, Sendable, Equatable {
    public var aiSource: AISourceSelection
    public var musicProvider: MediaProviderID
    public var automationEnabled: Bool
    public var resumeDelay: TimeInterval {
        didSet {
            let clamped = Self.clampResumeDelay(resumeDelay)
            if clamped != resumeDelay { resumeDelay = clamped }
        }
    }
    public var launchAtLogin: Bool
    public var onboardingCompleted: Bool
    public var verboseDiagnostics: Bool
    /// Pause the music while the user is speaking too, not only while the AI speaks. Needs the
    /// microphone; off by default because it is a second, separate permission.
    public var pauseWhileISpeak: Bool
    public var interruptionMode: MusicInterruptionMode
    public var duckVolumePercent: Int {
        didSet { duckVolumePercent = min(max(duckVolumePercent, 1), 100) }
    }
    public var restoreVolumePercent: Int {
        didSet { restoreVolumePercent = min(max(restoreVolumePercent, 1), 100) }
    }
    /// Keep the music paused for the whole conversation instead of returning it between replies.
    /// A spoken conversation is mostly silence: the assistant is thinking, then the user answers.
    public var holdThroughConversation: Bool
    /// How much quiet ends the conversation when `holdThroughConversation` is on.
    public var conversationHold: TimeInterval {
        didSet {
            let clamped = Self.clampConversationHold(conversationHold)
            if clamped != conversationHold { conversationHold = clamped }
        }
    }

    public static let resumeDelayRange: ClosedRange<TimeInterval> = 0...3.0
    public static let conversationHoldRange: ClosedRange<TimeInterval> = 0...60

    public init(
        aiSource: AISourceSelection = .chatGPTDesktop,
        musicProvider: MediaProviderID = .appleMusic,
        automationEnabled: Bool = true,
        resumeDelay: TimeInterval = 0.8,
        launchAtLogin: Bool = false,
        onboardingCompleted: Bool = false,
        verboseDiagnostics: Bool = false,
        pauseWhileISpeak: Bool = false,
        interruptionMode: MusicInterruptionMode = .duck,
        duckVolumePercent: Int = 5,
        restoreVolumePercent: Int = 100,
        holdThroughConversation: Bool = true,
        conversationHold: TimeInterval = 0
    ) {
        self.aiSource = aiSource
        self.musicProvider = musicProvider
        self.automationEnabled = automationEnabled
        self.resumeDelay = Self.clampResumeDelay(resumeDelay)
        self.launchAtLogin = launchAtLogin
        self.onboardingCompleted = onboardingCompleted
        self.verboseDiagnostics = verboseDiagnostics
        self.pauseWhileISpeak = pauseWhileISpeak
        self.interruptionMode = interruptionMode
        self.duckVolumePercent = min(max(duckVolumePercent, 1), 100)
        self.restoreVolumePercent = min(max(restoreVolumePercent, 1), 100)
        self.holdThroughConversation = holdThroughConversation
        self.conversationHold = Self.clampConversationHold(conversationHold)
    }

    public static func clampResumeDelay(_ value: TimeInterval) -> TimeInterval {
        min(max(value, resumeDelayRange.lowerBound), resumeDelayRange.upperBound)
    }

    public static func clampConversationHold(_ value: TimeInterval) -> TimeInterval {
        min(max(value, conversationHoldRange.lowerBound), conversationHoldRange.upperBound)
    }

    public var policy: PlaybackPolicy {
        var policy = PlaybackPolicy.default
        policy.quietInterval = Self.clampResumeDelay(resumeDelay)
        policy.conversationHold = holdThroughConversation ? Self.clampConversationHold(conversationHold) : 0
        policy.interruptionMode = interruptionMode
        policy.duckVolume = Double(duckVolumePercent) / 100.0
        policy.restoreVolume = Double(restoreVolumePercent) / 100.0
        return policy
    }

    private enum CodingKeys: String, CodingKey {
        case aiSource, musicProvider, automationEnabled, resumeDelay, launchAtLogin, onboardingCompleted, verboseDiagnostics, pauseWhileISpeak, interruptionMode, duckVolumePercent, restoreVolumePercent, holdThroughConversation, conversationHold
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.aiSource = try container.decodeIfPresent(AISourceSelection.self, forKey: .aiSource) ?? .chatGPTDesktop
        self.musicProvider = try container.decodeIfPresent(MediaProviderID.self, forKey: .musicProvider) ?? .appleMusic
        self.automationEnabled = try container.decodeIfPresent(Bool.self, forKey: .automationEnabled) ?? true
        self.resumeDelay = Self.clampResumeDelay(try container.decodeIfPresent(TimeInterval.self, forKey: .resumeDelay) ?? 0.8)
        self.launchAtLogin = try container.decodeIfPresent(Bool.self, forKey: .launchAtLogin) ?? false
        self.onboardingCompleted = try container.decodeIfPresent(Bool.self, forKey: .onboardingCompleted) ?? false
        self.verboseDiagnostics = try container.decodeIfPresent(Bool.self, forKey: .verboseDiagnostics) ?? false
        self.pauseWhileISpeak = try container.decodeIfPresent(Bool.self, forKey: .pauseWhileISpeak) ?? false
        self.interruptionMode = try container.decodeIfPresent(MusicInterruptionMode.self, forKey: .interruptionMode) ?? .duck
        self.duckVolumePercent = min(max(try container.decodeIfPresent(Int.self, forKey: .duckVolumePercent) ?? 5, 1), 100)
        self.restoreVolumePercent = min(max(try container.decodeIfPresent(Int.self, forKey: .restoreVolumePercent) ?? 100, 1), 100)
        self.holdThroughConversation = try container.decodeIfPresent(Bool.self, forKey: .holdThroughConversation) ?? true
        self.conversationHold = Self.clampConversationHold(
            try container.decodeIfPresent(TimeInterval.self, forKey: .conversationHold) ?? 0
        )
    }
}

public protocol SettingsStoring: AnyObject {
    func load() -> AppSettings
    func save(_ settings: AppSettings)
}

public final class UserDefaultsSettingsStore: SettingsStoring {
    private let defaults: UserDefaults
    private let key: String
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(defaults: UserDefaults = .standard, key: String = "com.oreja.settings.v1") {
        self.defaults = defaults
        self.key = key
    }

    public func load() -> AppSettings {
        guard let data = defaults.data(forKey: key),
              let settings = try? decoder.decode(AppSettings.self, from: data) else {
            return AppSettings()
        }
        return settings
    }

    public func save(_ settings: AppSettings) {
        guard let data = try? encoder.encode(settings) else { return }
        defaults.set(data, forKey: key)
    }
}

@MainActor
public final class UserDefaultsPauseJournal: PauseJournal {
    private let defaults: UserDefaults
    private let key: String
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(defaults: UserDefaults = .standard, key: String = "com.oreja.pause-journal.v1") {
        self.defaults = defaults
        self.key = key
    }

    public func load() -> PauseJournalRecord? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? decoder.decode(PauseJournalRecord.self, from: data)
    }

    public func save(_ record: PauseJournalRecord) {
        guard let data = try? encoder.encode(record) else { return }
        defaults.set(data, forKey: key)
    }

    public func clear() {
        defaults.removeObject(forKey: key)
    }
}

/// A bounded, in-memory diagnostic log. Conversation content is never recorded, so the log only
/// ever contains Oreja's own state transitions and permission/provider diagnostics.
@MainActor
public final class DiagnosticsLog: DiagnosticsSink {
    public private(set) var events: [DiagnosticEvent] = []
    public var onChange: (() -> Void)?
    public var isVerbose = false
    public let capacity: Int
    private let logURL: URL?

    /// A support log is written next to the other user logs so a report can include what Oreja
    /// actually did. It only ever contains Oreja's own state changes and permission results.
    public static var defaultLogURL: URL? {
        guard let library = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first else {
            return nil
        }
        return library.appendingPathComponent("Logs/Oreja/oreja.log")
    }

    public init(capacity: Int = 300, logURL: URL? = DiagnosticsLog.defaultLogURL) {
        self.capacity = capacity
        self.logURL = logURL
    }

    public func record(_ event: DiagnosticEvent) {
        events.append(event)
        if events.count > capacity {
            events.removeFirst(events.count - capacity)
        }
        write(event)
        onChange?()
    }

    public func clear() {
        events.removeAll()
        onChange?()
    }

    private func write(_ event: DiagnosticEvent) {
        guard let logURL else { return }
        let formatter = ISO8601DateFormatter()
        let line = "\(formatter.string(from: event.date)) \(event.level.rawValue) \(event.category.rawValue) \(event.message)\n"
        guard let data = line.data(using: .utf8) else { return }
        let directory = logURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if !FileManager.default.fileExists(atPath: logURL.path) {
            try? data.write(to: logURL)
            return
        }
        let size = (try? FileManager.default.attributesOfItem(atPath: logURL.path)[.size] as? Int) ?? 0
        if size > 1_000_000 {
            try? data.write(to: logURL)
            return
        }
        guard let handle = try? FileHandle(forWritingTo: logURL) else { return }
        defer { try? handle.close() }
        _ = try? handle.seekToEnd()
        try? handle.write(contentsOf: data)
    }

    public func recent(_ count: Int) -> [DiagnosticEvent] {
        Array(events.suffix(count))
    }
}
