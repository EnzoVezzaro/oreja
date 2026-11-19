import Foundation

/// Platform-neutral decisions for a monitor whose audio tap may stall.
///
/// A Core Audio process tap is attached to processes, not to the default output device, so a route
/// change usually does not affect it. Rebuilding on every device notification would add a detection
/// gap for no reason. These rules rebuild only when a change is followed by an actual loss of frames,
/// and keep a diagnostic hint separate from a real permission failure — macOS has no public API to
/// query the System Audio Recording grant, and a tap created without it can deliver pure silence.
public enum MonitorRecoveryPolicy {
    /// Debounce for device/sample-rate notifications, which often arrive in bursts while a new
    /// route settles.
    public static let deviceChangeSettle: TimeInterval = 0.35
    /// Minimum interval between two tap rebuilds. A stalled tap behind a missing grant would
    /// otherwise be rebuilt forever.
    public static let rebuildCooldown: TimeInterval = 5
    /// Frames arriving within this window mean the tap survived the route change.
    public static let stalledFrameGrace: TimeInterval = 0.25
    /// A live tap that has never delivered a frame after this long deserves an actionable hint.
    public static let noSignalWindow: TimeInterval = 30
    /// A missing grant can produce zero-filled buffers rather than no buffers at all. Only levels
    /// above the detector's silence floor count as "the app actually spoke".
    public static let audibleLevelDBFloor: Double = -90

    public struct DeviceDecision: Sendable, Equatable {
        public var shouldRebuild: Bool
        public var reason: String

        public static let none = DeviceDecision(shouldRebuild: false, reason: "")
    }

    /// - Parameters:
    ///   - pendingDeadline: earliest time at which a queued device change may be acted on, or nil.
    ///   - lastFrameTime: when the tap last delivered any samples.
    ///   - lastRebuildTime: when the tap was last (re)created.
    ///   - now: current monotonic time.
    public static func deviceChangeDecision(
        pendingDeadline: TimeInterval?,
        lastFrameTime: TimeInterval,
        lastRebuildTime: TimeInterval,
        now: TimeInterval
    ) -> DeviceDecision {
        guard let deadline = pendingDeadline, now >= deadline else { return .none }
        guard now - lastFrameTime > stalledFrameGrace else {
            return DeviceDecision(shouldRebuild: false, reason: "tap is still delivering frames")
        }
        guard now - lastRebuildTime >= rebuildCooldown else {
            return DeviceDecision(shouldRebuild: false, reason: "rebuild cooldown")
        }
        return DeviceDecision(shouldRebuild: true, reason: "audio route change stalled the tap")
    }

    /// A tap that has *never* delivered a frame may be silent because the System Audio Recording
    /// grant is missing. A tap that delivered frames and then went quiet is normal — the selected
    /// app is simply between turns — and must not be reported as a permission problem.
    public static func shouldReportNoSignal(
        tapLiveSince: TimeInterval?,
        hasDeliveredAudio: Bool,
        now: TimeInterval,
        window: TimeInterval = noSignalWindow
    ) -> Bool {
        guard let started = tapLiveSince, !hasDeliveredAudio else { return false }
        return now - started >= window
    }
}
