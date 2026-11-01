import Foundation

/// Coarse, human-readable state of the coordination engine. It is intentionally a single
/// enum so the menu bar and the onboarding test can present exactly one truth.
public enum CoordinatorState: String, Sendable, Equatable, CaseIterable {
    case disabled
    case searchingForSource
    case monitoring
    case musicPlaying
    case aiActive
    case musicPausedByOreja
    case waitingForSilence
    case restoringPlayback
    case suspended
    case permissionRequired
    case error
}

public enum MusicInterruptionMode: String, Codable, Sendable, Equatable, CaseIterable {
    case pause
    case duck
}

public struct PlaybackPolicy: Sendable, Equatable {
    public var interruptionMode: MusicInterruptionMode
    public var duckVolume: Double
    /// Volume to restore when the conversation becomes quiet.
    public var restoreVolume: Double
    /// How long the AI must be quiet before music resumes.
    public var quietInterval: TimeInterval
    /// How long music stays paused once a conversation is under way. In a spoken conversation the
    /// assistant is silent while it works on the answer and while the user talks, so returning music
    /// after `quietInterval` would drop it into the middle of the exchange. Zero means "return after
    /// each reply"; the coordinator waits for the longer of this and `quietInterval`.
    public var conversationHold: TimeInterval
    /// How long the AI must be audible before Oreja treats output as activity.
    public var minimumActivityDuration: TimeInterval
    /// Silence required before the activity stream reports `.activityEnded`.
    public var minimumSilenceDuration: TimeInterval
    /// After this many failed provider commands, automation stops and reports an error.
    public var failureLimit: Int
    /// If Oreja owns a pause when monitoring fails, restore the user's playback once.
    public var restoreOwnedPauseOnFailure: Bool
    /// Upper bound for a stale ownership journal to be restored on next launch.
    public var staleOwnershipLifetime: TimeInterval

    public static let `default` = PlaybackPolicy(
        interruptionMode: .pause,
        duckVolume: 0.05,
        restoreVolume: 1.0,
        quietInterval: 0.8,
        minimumActivityDuration: 0.06,
        minimumSilenceDuration: 0.25,
        failureLimit: 3,
        restoreOwnedPauseOnFailure: true,
        staleOwnershipLifetime: 12 * 60 * 60
    )

    public static let quietIntervalRange: ClosedRange<TimeInterval> = 0...3.0
    public static let conversationHoldRange: ClosedRange<TimeInterval> = 0...60

    /// Silence Oreja waits for before touching playback again.
    public var resumeWait: TimeInterval {
        max(quietInterval, conversationHold)
    }

    public init(
        interruptionMode: MusicInterruptionMode = .pause,
        duckVolume: Double = 0.05,
        restoreVolume: Double = 1.0,
        quietInterval: TimeInterval,
        minimumActivityDuration: TimeInterval,
        minimumSilenceDuration: TimeInterval,
        failureLimit: Int,
        restoreOwnedPauseOnFailure: Bool,
        staleOwnershipLifetime: TimeInterval,
        conversationHold: TimeInterval = 0
    ) {
        self.interruptionMode = interruptionMode
        self.duckVolume = min(max(duckVolume, 0), 1)
        self.restoreVolume = min(max(restoreVolume, 0), 1)
        self.quietInterval = min(max(quietInterval, Self.quietIntervalRange.lowerBound), Self.quietIntervalRange.upperBound)
        self.conversationHold = min(max(conversationHold, Self.conversationHoldRange.lowerBound), Self.conversationHoldRange.upperBound)
        self.minimumActivityDuration = minimumActivityDuration
        self.minimumSilenceDuration = minimumSilenceDuration
        self.failureLimit = failureLimit
        self.restoreOwnedPauseOnFailure = restoreOwnedPauseOnFailure
        self.staleOwnershipLifetime = staleOwnershipLifetime
    }
}

public struct PauseOwnership: Sendable, Equatable {
    public var track: MediaTrack?
    public var provider: MediaProviderID
    public var acquiredAt: TimeInterval

    public init(track: MediaTrack?, provider: MediaProviderID, acquiredAt: TimeInterval) {
        self.track = track
        self.provider = provider
        self.acquiredAt = acquiredAt
    }
}

public struct VolumeOwnership: Sendable, Equatable {
    public var track: MediaTrack?
    public var provider: MediaProviderID
    public var originalVolume: Double
    public var duckVolume: Double
    public var restoreVolume: Double
    public var acquiredAt: TimeInterval

    public init(track: MediaTrack?, provider: MediaProviderID, originalVolume: Double, duckVolume: Double, restoreVolume: Double? = nil, acquiredAt: TimeInterval) {
        self.track = track
        self.provider = provider
        self.originalVolume = originalVolume
        self.duckVolume = duckVolume
        self.restoreVolume = restoreVolume ?? originalVolume
        self.acquiredAt = acquiredAt
    }
}

public struct CoordinatorStatistics: Sendable, Equatable {
    public var pausesIssued = 0
    public var resumesIssued = 0
    public var manualOverrides = 0
    public var failedCommands = 0
    public var lastPauseLatency: TimeInterval?
    public var lastResumeLatency: TimeInterval?
    public var lastActivityLevelDB: Double?
}

/// Decides whether a pause left behind by a previous run of Oreja should be restored.
/// Restoring is only allowed for the same paused track, shortly after the pause, so Oreja can
/// never start unrelated music.
public enum StalePauseRecovery {
    public static let defaultLifetime: TimeInterval = 12 * 60 * 60

    public enum Decision: Sendable, Equatable {
        case resume
        case discard(reason: String)
    }

    public static func decide(
        record: PauseJournalRecord?,
        snapshot: MediaPlaybackSnapshot,
        now: Date = Date(),
        maxAge: TimeInterval = defaultLifetime
    ) -> Decision {
        guard let record else { return .discard(reason: "No pause was left behind.") }
        let age = now.timeIntervalSince(record.acquiredAt)
        guard age >= 0, age <= maxAge else {
            return .discard(reason: "The pause record is too old to restore safely.")
        }
        guard snapshot.provider == record.provider else {
            return .discard(reason: "A different music provider is active.")
        }
        guard snapshot.state == .paused else {
            return .discard(reason: "Music is not paused, so there is nothing to restore.")
        }
        guard snapshot.refersTo(record.track) else {
            return .discard(reason: "A different track is loaded, so Oreja left it alone.")
        }
        return .resume
    }
}
