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

/// A media service a user might expect Oreja to control. This is deliberately broader than
/// `MediaProviderID`: an unavailable target must still be nameable in Settings without pretending
/// an adapter exists.
public enum PlaybackTargetID: String, Sendable, Equatable, CaseIterable {
    case appleMusic
    case spotify
    case browser

    public var displayName: String {
        switch self {
        case .appleMusic: "Apple Music"
        case .spotify: "Spotify"
        case .browser: "Browser"
        }
    }
}

/// What Oreja can actually do for a target. Unsupported targets are surfaced verbatim instead of
/// running a best-effort script that would look like working control.
public enum PlaybackTargetCapability: Sendable, Equatable {
    case supported
    case unavailable(reason: String)

    public var isSupported: Bool {
        if case .supported = self { return true }
        return false
    }

    public var reason: String? {
        if case .unavailable(let reason) = self { return reason }
        return nil
    }
}

public enum PlaybackTargets {
    /// Capability findings from the v0.4.0 dependency audits. These describe supported platform
    /// APIs and local installation state, not an intention to fake control.
    public static func capability(for target: PlaybackTargetID) -> PlaybackTargetCapability {
        switch target {
        case .appleMusic:
            return .supported
        case .spotify:
            return .unavailable(reason: "Not implemented. Spotify is not installed here and no official desktop scripting dictionary was available to verify; its Web API needs a Premium account and a remote service, which Oreja does not use.")
        case .browser:
            return .unavailable(reason: "No supported whole-browser control: macOS exposes no public per-process gain or pause/transport API for a browser. Oreja does not use per-tab JavaScript, app mute, or system volume as a substitute, and selected conversation audio stays audible.")
        }
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
