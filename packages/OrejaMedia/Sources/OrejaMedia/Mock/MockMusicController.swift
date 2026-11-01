import Foundation
import OrejaCore

/// Deterministic in-memory music provider for tests, previews and the onboarding dry run.
@MainActor
public final class MockMusicController: MediaPlaybackController {
    public let provider: MediaProviderID = .mock
    public let capabilities = MediaCapabilities(
        canPause: true,
        canResume: true,
        canSetVolume: true,
        canReportTrackIdentity: true,
        requiresAutomationPermission: false
    )

    public private(set) var snapshot: MediaPlaybackSnapshot
    public private(set) var pauseCount = 0
    public private(set) var resumeCount = 0
    public private(set) var commands: [String] = []
    public private(set) var volumeChanges: [Double] = []
    public var pauseError: MediaControlError?
    public var resumeError: MediaControlError?

    public init(
        state: MediaPlaybackSnapshot.PlaybackState = .playing,
        track: MediaTrack? = MediaTrack(id: "mock-1", title: "Test Track", artist: "Oreja")
    ) {
        self.snapshot = MediaPlaybackSnapshot(
            state: state,
            track: track,
            provider: .mock,
            capturedAt: ProcessInfo.processInfo.systemUptime
        )
    }

    public func currentPlayback() async -> MediaPlaybackSnapshot {
        snapshot
    }

    public func pause() async throws {
        commands.append("pause")
        if let pauseError { throw pauseError }
        pauseCount += 1
        snapshot.state = .paused
        snapshot.capturedAt = ProcessInfo.processInfo.systemUptime
    }

    public func resume() async throws {
        commands.append("resume")
        if let resumeError { throw resumeError }
        resumeCount += 1
        snapshot.state = .playing
        snapshot.capturedAt = ProcessInfo.processInfo.systemUptime
    }

    public func setVolume(_ volume: Double) async throws {
        let value = min(max(volume, 0), 1)
        volumeChanges.append(value)
        commands.append("volume:\(value)")
        snapshot.volume = value
    }

    /// Simulates a user action in the music app (manual pause/resume/track change).
    public func simulateUser(_ state: MediaPlaybackSnapshot.PlaybackState, track: MediaTrack? = nil) {
        snapshot.state = state
        if let track { snapshot.track = track }
        snapshot.capturedAt = ProcessInfo.processInfo.systemUptime
    }
}
