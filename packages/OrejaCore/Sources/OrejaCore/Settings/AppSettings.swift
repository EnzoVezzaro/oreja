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

    public static let resumeDelayRange: ClosedRange<TimeInterval> = 0.3...3.0

    public init(
        aiSource: AISourceSelection = .chatGPTDesktop,
        musicProvider: MediaProviderID = .appleMusic,
        automationEnabled: Bool = true,
        resumeDelay: TimeInterval = 0.8,
        launchAtLogin: Bool = false,
        onboardingCompleted: Bool = false,
        verboseDiagnostics: Bool = false
    ) {
        self.aiSource = aiSource
        self.musicProvider = musicProvider
        self.automationEnabled = automationEnabled
        self.resumeDelay = Self.clampResumeDelay(resumeDelay)
        self.launchAtLogin = launchAtLogin
        self.onboardingCompleted = onboardingCompleted
        self.verboseDiagnostics = verboseDiagnostics
    }

    public static func clampResumeDelay(_ value: TimeInterval) -> TimeInterval {
        min(max(value, resumeDelayRange.lowerBound), resumeDelayRange.upperBound)
    }

    public var policy: PlaybackPolicy {
        var policy = PlaybackPolicy.default
        policy.quietInterval = Self.clampResumeDelay(resumeDelay)
        return policy
    }

    private enum CodingKeys: String, CodingKey {
        case aiSource, musicProvider, automationEnabled, resumeDelay, launchAtLogin, onboardingCompleted, verboseDiagnostics
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

    public init(capacity: Int = 300) {
        self.capacity = capacity
    }

    public func record(_ event: DiagnosticEvent) {
        events.append(event)
        if events.count > capacity {
            events.removeFirst(events.count - capacity)
        }
        onChange?()
    }

    public func clear() {
        events.removeAll()
        onChange?()
    }

    public func recent(_ count: Int) -> [DiagnosticEvent] {
        Array(events.suffix(count))
    }
}
