import Foundation

/// Platform-neutral port for a music provider.
public protocol MediaPlaybackController: AnyObject {
    var provider: MediaProviderID { get }
    var capabilities: MediaCapabilities { get }

    /// Reads the current playback state. Implementations must not launch the provider.
    func currentPlayback() async -> MediaPlaybackSnapshot

    /// Pauses without resetting the current track or queue.
    func pause() async throws

    /// Resumes the paused track from its previous position.
    func resume() async throws

    /// Pauses and reports the state observed after the command. Providers that can return the new
    /// state in the same round trip override this to save a command/observation cycle, which is the
    /// difference between a ~300 ms and a ~100 ms pause on Apple Events.
    func pauseReporting() async throws -> MediaPlaybackSnapshot

    /// Resumes and reports the state observed after the command.
    func resumeReporting() async throws -> MediaPlaybackSnapshot
}

extension MediaPlaybackController {
    public func pauseReporting() async throws -> MediaPlaybackSnapshot {
        try await pause()
        return await currentPlayback()
    }

    public func resumeReporting() async throws -> MediaPlaybackSnapshot {
        try await resume()
        return await currentPlayback()
    }
}

/// Platform-neutral port for an audio-activity source (the AI side of the conversation).
public protocol AIAudioMonitoring: AnyObject, Sendable {
    var events: AsyncStream<AudioActivityEvent> { get }
    func start() async throws
    func stop() async
}

public protocol AIAudioMonitorFactory: AnyObject, Sendable {
    func makeMonitor(for descriptor: AIAudioSourceDescriptor) -> any AIAudioMonitoring
}

public enum AudioActivityEvent: Sendable, Equatable {
    case monitorStarted(processDescription: String)
    case monitorStopped(String)
    case monitorFailed(AudioMonitoringFailure)
    case activityStarted(levelDB: Double)
    case activityEnded(levelDB: Double)
}

public struct AudioMonitoringFailure: Error, Sendable, Equatable, LocalizedError {
    public enum Kind: String, Sendable, Equatable {
        case permissionDenied
        case sourceUnavailable
        case tapCreationFailed
        case deviceSetupFailed
        case streamFailed
        case unknown
    }

    public var kind: Kind
    public var message: String

    public init(_ kind: Kind, _ message: String) {
        self.kind = kind
        self.message = message
    }

    public var errorDescription: String? { message }
}

/// Result of a playback command routed through the adapter layer.
public enum MediaCommandOutcome: Sendable {
    case succeeded(MediaPlaybackSnapshot?)
    /// The command was unnecessary (for example the track already changed). No ownership is
    /// taken and no failure is counted, but playback state is refreshed.
    case noOp(MediaPlaybackSnapshot?)
    case failed(MediaControlError)
}

public struct PauseJournalRecord: Codable, Sendable, Equatable {
    public var provider: MediaProviderID
    public var track: MediaTrack?
    public var acquiredAt: Date
    public var reason: String

    public init(provider: MediaProviderID, track: MediaTrack?, acquiredAt: Date, reason: String) {
        self.provider = provider
        self.track = track
        self.acquiredAt = acquiredAt
        self.reason = reason
    }
}

/// Persists the fact that Oreja owns a pause, so a crash cannot leave music paused forever.
@MainActor
public protocol PauseJournal: AnyObject {
    func load() -> PauseJournalRecord?
    func save(_ record: PauseJournalRecord)
    func clear()
}

@MainActor
public protocol DiagnosticsSink: AnyObject {
    func record(_ event: DiagnosticEvent)
}

public struct DiagnosticEvent: Sendable, Equatable, Identifiable {
    public enum Level: String, Sendable, Codable {
        case info
        case success
        case warning
        case error
    }

    public enum Category: String, Sendable, Codable {
        case lifecycle
        case monitoring
        case detection
        case playback
        case permissions
        case recovery
        case settings
    }

    public var id: UUID
    public var date: Date
    public var level: Level
    public var category: Category
    public var message: String

    public init(
        id: UUID = UUID(),
        date: Date = Date(),
        level: Level,
        category: Category,
        message: String
    ) {
        self.id = id
        self.date = date
        self.level = level
        self.category = category
        self.message = message
    }
}

/// Builds the scripts / requests an Apple Music adapter issues. Kept separate so the
/// AppleScript text can be unit tested without touching the Music app.
public enum AppleMusicScript {
    public static let fieldSeparator = String(UnicodeScalar(30))

    public static var playbackState: String {
        """
        if application "Music" is running then
            tell application "Music"
                try
                    set playerStatus to player state as text
                on error
                    set playerStatus to "stopped"
                end try
                set stateText to "unavailable"
                if playerStatus is "playing" then
                    set stateText to "playing"
                else if playerStatus is "paused" then
                    set stateText to "paused"
                else
                    set stateText to "stopped"
                end if
                set trackID to ""
                set trackName to ""
                set trackArtist to ""
                set trackVolume to ""
                try
                    if stateText is not "stopped" then
                        set trackID to persistent ID of current track
                        set trackName to name of current track
                        set trackArtist to artist of current track
                    end if
                end try
                try
                    set trackVolume to sound volume as text
                end try
                set sep to (ASCII character 30)
                return stateText & sep & trackID & sep & trackName & sep & trackArtist & sep & trackVolume
            end tell
        else
            return "unavailable" & (ASCII character 30) & "" & (ASCII character 30) & "" & (ASCII character 30) & "" & (ASCII character 30) & ""
        end if
        """
    }

    public static var pause: String {
        command("pause")
    }

    public static var resume: String {
        command("play")
    }

    /// Pause and report the resulting state in a single Apple Event round trip.
    public static var pauseReporting: String {
        commandReporting("pause")
    }

    /// Resume and report the resulting state in a single Apple Event round trip.
    public static var resumeReporting: String {
        commandReporting("play")
    }

    public static func command(_ verb: String) -> String {
        """
        if application "Music" is running then
            tell application "Music" to \(verb)
            return "ok"
        else
            return "not-running"
        end if
        """
    }

    /// Runs the command, then waits (inside the same Apple Event) for Music to report the new
    /// state and returns the full snapshot in the `playbackState` field format. Music updates its
    /// player state a few milliseconds after the command returns, so a caller reading separately
    /// would pay a second round trip and could still observe the old value.
    public static func commandReporting(_ verb: String) -> String {
        let expected = verb == "pause" ? "paused" : "playing"
        return """
        if application "Music" is running then
            tell application "Music"
                \(verb)
                set stateText to "unavailable"
                repeat 20 times
                    try
                        set playerStatus to player state as text
                    on error
                        set playerStatus to "stopped"
                    end try
                    if playerStatus is "\(expected)" then
                        set stateText to "\(expected)"
                        exit repeat
                    end if
                    delay 0.01
                end repeat
                if stateText is "unavailable" then
                    try
                        set playerStatus to player state as text
                    on error
                        set playerStatus to "stopped"
                    end try
                    if playerStatus is "playing" then
                        set stateText to "playing"
                    else if playerStatus is "paused" then
                        set stateText to "paused"
                    else
                        set stateText to "stopped"
                    end if
                end if
                set trackID to ""
                set trackName to ""
                set trackArtist to ""
                set trackVolume to ""
                try
                    if stateText is not "stopped" then
                        set trackID to persistent ID of current track
                        set trackName to name of current track
                        set trackArtist to artist of current track
                    end if
                end try
                try
                    set trackVolume to sound volume as text
                end try
                set sep to (ASCII character 30)
                return stateText & sep & trackID & sep & trackName & sep & trackArtist & sep & trackVolume
            end tell
        else
            return "unavailable" & (ASCII character 30) & "" & (ASCII character 30) & "" & (ASCII character 30) & "" & (ASCII character 30) & ""
        end if
        """
    }

    public static func setVolume(_ volume: Int) -> String {
        let clamped = min(100, max(0, volume))
        return """
        if application "Music" is running then
            tell application "Music" to set sound volume to \(clamped)
            return "ok"
        else
            return "not-running"
        end if
        """
    }
}

/// Parses the tab/record separated output of `AppleMusicScript.playbackState`.
public enum AppleMusicStateParser {
    public static func parse(_ output: String, capturedAt: TimeInterval = 0) -> MediaPlaybackSnapshot {
        let fields = output.components(separatedBy: AppleMusicScript.fieldSeparator)
        guard let rawState = fields.first?.trimmingCharacters(in: .whitespacesAndNewlines) else {
            return .unavailable(.appleMusic, at: capturedAt)
        }

        func field(_ index: Int) -> String {
            index < fields.count ? fields[index].trimmingCharacters(in: .whitespacesAndNewlines) : ""
        }

        let volume = Double(field(4)).map { $0 / 100.0 }
        switch rawState {
        case "playing":
            return MediaPlaybackSnapshot(
                state: .playing,
                track: track(fields: fields),
                volume: volume,
                provider: .appleMusic,
                capturedAt: capturedAt
            )
        case "paused":
            return MediaPlaybackSnapshot(
                state: .paused,
                track: track(fields: fields),
                volume: volume,
                provider: .appleMusic,
                capturedAt: capturedAt
            )
        case "stopped":
            return MediaPlaybackSnapshot(state: .stopped, volume: volume, provider: .appleMusic, capturedAt: capturedAt)
        default:
            return .unavailable(.appleMusic, at: capturedAt)
        }
    }

    private static func track(fields: [String]) -> MediaTrack? {
        func field(_ index: Int) -> String {
            index < fields.count ? fields[index].trimmingCharacters(in: .whitespacesAndNewlines) : ""
        }
        let id = field(1)
        let title = field(2)
        let artist = field(3)
        guard !id.isEmpty || !title.isEmpty else { return nil }
        return MediaTrack(id: id, title: title, artist: artist)
    }
}
