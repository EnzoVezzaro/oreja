import AppKit
import Foundation
import OrejaCore

/// Controls the macOS Music app through Apple Events / AppleScript.
///
/// - Pause uses `pause`, never `stop`, so the track, queue and playback position are preserved.
/// - Resume uses `play` only after the coordinator verified the paused track is still loaded.
/// - The adapter never launches Music and never changes volume in the MVP.
@MainActor
public final class AppleMusicController: MediaPlaybackController {
    public let provider: MediaProviderID = .appleMusic
    public let capabilities = MediaCapabilities(
        canPause: true,
        canResume: true,
        canSetVolume: false,
        canReportTrackIdentity: true,
        requiresAutomationPermission: true
    )

    private let runner: AppleScriptRunner
    public let musicBundleIdentifier = "com.apple.Music"

    public init(runner: AppleScriptRunner? = nil) {
        self.runner = runner ?? AppleScriptRunner()
    }

    public var isMusicRunning: Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: musicBundleIdentifier).isEmpty
    }

    public func currentPlayback() async -> MediaPlaybackSnapshot {
        guard isMusicRunning else {
            return .unavailable(.appleMusic, at: ProcessInfo.processInfo.systemUptime)
        }

        switch runner.run(AppleMusicScript.playbackState) {
        case .success(let output):
            return AppleMusicStateParser.parse(output, capturedAt: ProcessInfo.processInfo.systemUptime)
        case .failure(let error):
            if case .permissionDenied = error {
                return MediaPlaybackSnapshot(
                    state: .permissionRequired,
                    provider: .appleMusic,
                    capturedAt: ProcessInfo.processInfo.systemUptime
                )
            }
            return .unavailable(.appleMusic, at: ProcessInfo.processInfo.systemUptime)
        }
    }

    public func pause() async throws {
        _ = try await pauseReporting()
    }

    public func resume() async throws {
        _ = try await resumeReporting()
    }

    /// Pauses and returns the state Music reported inside the same Apple Event, so the caller
    /// does not pay a second round trip to learn the outcome.
    public func pauseReporting() async throws -> MediaPlaybackSnapshot {
        try await perform(AppleMusicScript.pauseReporting, expecting: .paused)
    }

    public func resumeReporting() async throws -> MediaPlaybackSnapshot {
        try await perform(AppleMusicScript.resumeReporting, expecting: .playing)
    }

    private func perform(_ script: String, expecting expected: MediaPlaybackSnapshot.PlaybackState) async throws -> MediaPlaybackSnapshot {
        guard isMusicRunning else { throw MediaControlError.notRunning("Music") }
        switch runner.run(script) {
        case .success(let output):
            let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed != "not-running" else { throw MediaControlError.notRunning("Music") }
            let snapshot = AppleMusicStateParser.parse(output, capturedAt: ProcessInfo.processInfo.systemUptime)
            guard snapshot.state != .unavailable else {
                throw MediaControlError.commandFailed("Music stopped responding while the command ran.")
            }
            if snapshot.state == expected { return snapshot }
            // The script already waited inside Music; a command that still has not landed is left to
            // the coordinator, which reconciles ownership from the snapshot returned here.
            return await settle(expected: expected, lastKnown: snapshot)
        case .failure(let error):
            throw error
        }
    }

    /// Last resort when the in-script wait did not observe the new state: poll briefly so a slow
    /// Music instance still reports accurately instead of handing back a stale snapshot.
    private func settle(
        expected: MediaPlaybackSnapshot.PlaybackState,
        lastKnown: MediaPlaybackSnapshot
    ) async -> MediaPlaybackSnapshot {
        var latest = lastKnown
        for _ in 0..<4 {
            try? await Task.sleep(nanoseconds: 40_000_000)
            latest = await currentPlayback()
            if latest.state == expected { return latest }
        }
        return latest
    }

    /// Opens Music so the user can start playback. Used by onboarding only.
    public func launchMusic() {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: musicBundleIdentifier) else { return }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: configuration) { _, error in
            if let error {
                NSLog("Oreja: could not open Music: %@", error.localizedDescription)
            }
        }
    }

    /// True when the caller currently holds automation permission. Runs a harmless query, which
    /// triggers the system prompt on first use and returns `.permissionDenied` afterwards.
    public func requestAutomationPermission() async -> Result<MediaPlaybackSnapshot, MediaControlError> {
        guard isMusicRunning else { return .failure(.notRunning("Music")) }
        switch runner.run(AppleMusicScript.playbackState) {
        case .success(let output):
            return .success(AppleMusicStateParser.parse(output, capturedAt: ProcessInfo.processInfo.systemUptime))
        case .failure(let error):
            return .failure(error)
        }
    }
}
