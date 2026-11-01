import Foundation

/// A music service Oreja can coordinate with. Every adapter declares what it can actually do,
/// so the coordinator never assumes capabilities that a provider lacks.
public enum MediaProviderID: String, Codable, Sendable, CaseIterable {
    case appleMusic
    case mock

    public var displayName: String {
        switch self {
        case .appleMusic: "Apple Music"
        case .mock: "Mock Player"
        }
    }
}

/// Identity of the currently loaded media. `id` is a provider-specific stable identifier
/// (for Apple Music: the track's persistent ID).
public struct MediaTrack: Codable, Sendable, Equatable, Hashable {
    public var id: String
    public var title: String
    public var artist: String

    public init(id: String, title: String, artist: String) {
        self.id = id
        self.title = title
        self.artist = artist
    }

    public var displayName: String {
        artist.isEmpty ? title : "\(title) — \(artist)"
    }
}

public struct MediaPlaybackSnapshot: Codable, Sendable, Equatable {
    public enum PlaybackState: String, Codable, Sendable, Equatable {
        case playing
        case paused
        case stopped
        case unavailable
        case permissionRequired
    }

    public var state: PlaybackState
    public var track: MediaTrack?
    public var volume: Double?
    public var provider: MediaProviderID
    /// Monotonic timestamp (seconds since boot) at which this observation was made.
    public var capturedAt: TimeInterval

    public init(
        state: PlaybackState,
        track: MediaTrack? = nil,
        volume: Double? = nil,
        provider: MediaProviderID = .appleMusic,
        capturedAt: TimeInterval = 0
    ) {
        self.state = state
        self.track = track
        self.volume = volume
        self.provider = provider
        self.capturedAt = capturedAt
    }

    public static func unavailable(_ provider: MediaProviderID = .appleMusic, at time: TimeInterval = 0) -> Self {
        .init(state: .unavailable, provider: provider, capturedAt: time)
    }

    public var isPlaying: Bool { state == .playing }
    public var isPaused: Bool { state == .paused }

    /// Whether this snapshot still refers to `track`. An adapter that cannot report a track
    /// identity reports `nil`; in that case only the paused state can be validated.
    public func refersTo(_ track: MediaTrack?) -> Bool {
        guard let expected = track else { return true }
        guard let current = self.track else { return false }
        return current.id == expected.id
    }
}

public struct MediaCapabilities: Sendable, Equatable {
    public var canPause: Bool
    public var canResume: Bool
    public var canSetVolume: Bool
    public var canReportTrackIdentity: Bool
    public var requiresAutomationPermission: Bool

    public init(
        canPause: Bool,
        canResume: Bool,
        canSetVolume: Bool,
        canReportTrackIdentity: Bool,
        requiresAutomationPermission: Bool
    ) {
        self.canPause = canPause
        self.canResume = canResume
        self.canSetVolume = canSetVolume
        self.canReportTrackIdentity = canReportTrackIdentity
        self.requiresAutomationPermission = requiresAutomationPermission
    }
}

public enum MediaControlError: Error, Sendable, Equatable, LocalizedError {
    case providerUnavailable(String)
    case notRunning(String)
    case permissionDenied(String)
    case trackChanged
    case unsupported(String)
    case commandFailed(String)

    public var errorDescription: String? {
        switch self {
        case .providerUnavailable(let name): "\(name) is not available."
        case .notRunning(let name): "\(name) is not running."
        case .permissionDenied(let name): "Automation permission for \(name) was denied."
        case .trackChanged: "The playing track changed, so Oreja did not touch playback."
        case .unsupported(let message): message
        case .commandFailed(let message): message
        }
    }
}
