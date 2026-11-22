import Foundation

/// Summarizes microphone analysis frames into one report per window, for diagnostics only.
///
/// It keeps dBFS numbers, never samples: the peak and the mean of the frame levels that the
/// analysis loop already produced. A report with `frameCount == 0` means the microphone delivered
/// no audio at all during the window, which is a different fault from "quiet audio".
public struct MicrophoneLevelWindow: Sendable, Equatable {
    public struct Report: Sendable, Equatable {
        /// Highest frame level in the window, or nil when no frames arrived.
        public var peakDB: Double?
        /// Mean of the frame levels in dBFS, or nil when no frames arrived.
        public var meanDB: Double?
        public var frameCount: Int
    }

    public let duration: TimeInterval
    private var windowStart: TimeInterval?
    private var frameCount = 0
    private var levelSum: Double = 0
    private var peakDB: Double?

    public init(duration: TimeInterval = 1.0) {
        self.duration = max(0.05, duration)
    }

    /// Feeds one analysis tick. `levelDB` is nil when no audio arrived since the previous tick.
    /// Returns a report once per `duration`, then starts the next window.
    public mutating func ingest(levelDB: Double?, at time: TimeInterval) -> Report? {
        let start = windowStart ?? time
        windowStart = start

        if let levelDB, levelDB.isFinite {
            frameCount += 1
            levelSum += levelDB
            peakDB = max(peakDB ?? levelDB, levelDB)
        }

        guard time - start >= duration else { return nil }

        let report = Report(
            peakDB: peakDB,
            meanDB: frameCount > 0 ? levelSum / Double(frameCount) : nil,
            frameCount: frameCount
        )
        windowStart = time
        frameCount = 0
        levelSum = 0
        peakDB = nil
        return report
    }
}
