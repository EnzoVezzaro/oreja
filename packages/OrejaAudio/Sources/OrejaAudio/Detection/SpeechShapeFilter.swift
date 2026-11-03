import Foundation
import OrejaCore

/// Decides whether a burst of audio from the monitored application is worth interrupting music for.
///
/// macOS has no public way to ask "was that sound a notification?". What it does provide is the
/// audio itself, and a spoken reply differs from an alert in *shape*, not level: speech is
/// modulated at syllable rate, so its envelope rises and falls several times a second, while an
/// alert is either over in a fraction of a second, a single attack followed by a decay (a chime, a
/// bell, a "sent" whoosh), or a continuous tone with no modulation at all.
///
/// The gate therefore watches the dBFS envelope rather than its absolute value. It forwards an
/// activity window only once the envelope has reversed direction at least
/// `minimumReversals` times by at least `stepDB` inside `confirmationWindow`. Anything else is
/// reported as suppressed and never reaches the coordinator: no pause, no resume, no ownership.
///
/// This is a filter for a known failure mode, not a speech recognizer: a long, loudly modulated
/// non-speech sound (an alarm tone with a beat, a ringtone melody) still passes. Silence it with
/// `isEnabled = false` if a source is unusual.
public struct SpeechShapeFilter: Sendable, Equatable {
    public enum Output: Sendable, Equatable {
        case none
        case started(levelDB: Double)
        case ended(levelDB: Double)
        /// A burst was real audio but not speech-shaped, so it was never announced as activity.
        case suppressed(reason: AudioSuppressionReason, levelDB: Double)
    }

    public struct Configuration: Sendable, Equatable {
        /// When false the gate forwards every burst, which is the pre-gate behavior.
        public var isEnabled: Bool
        /// How long the gate may listen before deciding that a continuous burst is not speech.
        public var confirmationWindow: TimeInterval
        /// Envelope change that counts as a direction change.
        public var stepDB: Double
        /// Direction changes required before a burst counts as speech.
        public var minimumReversals: Int
        /// Peak-to-peak envelope swing required before a burst counts as speech.
        public var minimumSwingDB: Double
        /// How much envelope history the analysis keeps.
        public var historyWindow: TimeInterval
        /// Levels at or below this belong to the silence between sounds and are not analyzed.
        public var quietFloorDB: Double
        /// Floor applied to digital silence, to keep dBFS finite.
        public var silenceFloorDB: Double

        public init(
            isEnabled: Bool = true,
            confirmationWindow: TimeInterval = 0.45,
            stepDB: Double = 1.5,
            minimumReversals: Int = 2,
            minimumSwingDB: Double = 3.0,
            historyWindow: TimeInterval = 0.6,
            quietFloorDB: Double = -55,
            silenceFloorDB: Double = -100
        ) {
            self.isEnabled = isEnabled
            self.confirmationWindow = max(0.05, confirmationWindow)
            self.stepDB = max(0.1, stepDB)
            self.minimumReversals = max(1, minimumReversals)
            self.minimumSwingDB = max(0, minimumSwingDB)
            self.historyWindow = max(self.confirmationWindow, historyWindow)
            self.quietFloorDB = quietFloorDB
            self.silenceFloorDB = silenceFloorDB
        }

        /// Pass-through configuration, used by the developer probe to see raw levels.
        public static var passthrough: Configuration { Configuration(isEnabled: false) }
    }

    private enum Phase: Equatable {
        /// No activity window is open.
        case idle
        /// Activity detected, nothing announced yet: the gate is looking for speech shape.
        case evaluating(since: TimeInterval)
        /// A window was announced to the coordinator and will be ended normally.
        case forwarded
        /// The window was judged non-speech. It stays open until it ends, in case real speech
        /// follows the alert inside the same window (a chime, then the reply).
        case suppressed
    }

    private struct Sample: Equatable {
        var time: TimeInterval
        var levelDB: Double
    }

    private var detector: AudioActivityDetector
    private var phase: Phase = .idle
    private var history: [Sample] = []

    public var configuration: Configuration
    /// Exposed for diagnostics: true while an announced activity window is open.
    public private(set) var isActive = false
    public private(set) var lastLevelDB: Double = -100
    /// Number of bursts the gate has suppressed since creation.
    public private(set) var suppressedBurstCount = 0

    public init(
        configuration: Configuration = Configuration(),
        detectorConfiguration: AudioActivityDetector.Configuration = .init()
    ) {
        self.configuration = configuration
        self.detector = AudioActivityDetector(configuration: detectorConfiguration)
        self.lastLevelDB = detectorConfiguration.silenceFloorDB
    }

    /// Feeds one analysis frame. Returns an output only when something happened.
    public mutating func ingest(levelDB: Double, at time: TimeInterval) -> Output {
        let level = levelDB.isFinite
            ? max(configuration.silenceFloorDB, min(0, levelDB))
            : configuration.silenceFloorDB
        lastLevelDB = level
        record(Sample(time: time, levelDB: level), at: time)

        let transition = detector.ingest(levelDB: level, at: time)

        switch phase {
        case .idle:
            guard transition == .started else { return .none }
            guard configuration.isEnabled else {
                phase = .forwarded
                isActive = true
                return .started(levelDB: level)
            }
            phase = .evaluating(since: time)
            // Speech often opens with a modulated first syllable, so the common case is decided
            // immediately instead of after the confirmation window.
            if isSpeechLike(at: time) {
                phase = .forwarded
                isActive = true
                return .started(levelDB: level)
            }
            return .none

        case .evaluating(let since):
            if transition == .ended {
                return finishSuppressed(.brief, levelDB: level)
            }
            if isSpeechLike(at: time) {
                phase = .forwarded
                isActive = true
                return .started(levelDB: level)
            }
            if time - since >= configuration.confirmationWindow {
                // Continuous but unmodulated: an alert tone, a chime tail, a notification loop.
                phase = .suppressed
                suppressedBurstCount += 1
                return .suppressed(reason: .steady, levelDB: level)
            }
            return .none

        case .forwarded:
            guard transition == .ended else { return .none }
            phase = .idle
            isActive = false
            return .ended(levelDB: level)

        case .suppressed:
            if transition == .ended {
                phase = .idle
                isActive = false
                return .none
            }
            // Speech started inside a window that was already declared non-speech (an alert
            // followed immediately by the reply): announce it now rather than miss the turn.
            if isSpeechLike(at: time) {
                phase = .forwarded
                isActive = true
                return .started(levelDB: level)
            }
            return .none
        }
    }

    /// Called when monitoring stops or the source changes.
    public mutating func reset() {
        detector.reset()
        phase = .idle
        history.removeAll(keepingCapacity: true)
        isActive = false
        lastLevelDB = configuration.silenceFloorDB
    }

    // MARK: - Analysis

    private mutating func finishSuppressed(_ reason: AudioSuppressionReason, levelDB: Double) -> Output {
        phase = .idle
        isActive = false
        suppressedBurstCount += 1
        return .suppressed(reason: reason, levelDB: levelDB)
    }

    private mutating func record(_ sample: Sample, at time: TimeInterval) {
        history.append(sample)
        let cutoff = time - configuration.historyWindow
        if let firstKept = history.firstIndex(where: { $0.time >= cutoff }), firstKept > 0 {
            history.removeFirst(firstKept)
        }
    }

    /// True when the recent envelope looks like a voice: several direction changes and a wide
    /// enough swing. Silence frames are excluded so the onset ramp alone does not count as a
    /// reversal, and so a burst's own decay cannot manufacture one.
    private func isSpeechLike(at time: TimeInterval) -> Bool {
        let cutoff = time - configuration.historyWindow
        let levels = history
            .filter { $0.time >= cutoff && $0.levelDB > configuration.quietFloorDB }
            .map(\.levelDB)
        guard levels.count >= 3 else { return false }
        guard let low = levels.min(), let high = levels.max(), high - low >= configuration.minimumSwingDB else {
            return false
        }

        var reversals = 0
        var direction = 0
        var previous = levels[0]
        for level in levels.dropFirst() {
            let delta = level - previous
            previous = level
            guard abs(delta) >= configuration.stepDB else { continue }
            let step = delta > 0 ? 1 : -1
            if direction != 0, step != direction { reversals += 1 }
            direction = step
        }
        return reversals >= configuration.minimumReversals
    }
}
