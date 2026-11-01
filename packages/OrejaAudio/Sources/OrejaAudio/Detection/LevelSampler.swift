import Foundation
import os

/// Collects audio levels from the real-time IOProc.
///
/// The IOProc must never block: `ingest` uses `os_unfair_lock_trylock` and drops the frame if the
/// analysis task happens to hold the lock. Allocation, level conversion and event publishing all
/// happen outside the audio callback.
public final class LevelSampler: @unchecked Sendable {
    public struct Summary: Sendable, Equatable {
        public var levelDB: Double
        public var frames: Int
    }

    private var lock = os_unfair_lock_s()
    private var sumOfSquares: Double = 0
    private var sampleCount: Int = 0
    private var peakMagnitude: Float = 0

    public init() {}

    /// Called from the audio IOProc with Float32 samples.
    public func ingestFloat32(_ samples: UnsafePointer<Float>, count: Int) {
        guard count > 0 else { return }
        var localSum: Double = 0
        var localPeak: Float = 0
        for i in 0..<count {
            let value = samples[i]
            localSum += Double(value) * Double(value)
            let magnitude = abs(value)
            if magnitude > localPeak { localPeak = magnitude }
        }

        withUnsafeMutablePointer(to: &lock) { lockPointer in
            guard os_unfair_lock_trylock(lockPointer) else {
                return
            }
            sumOfSquares += localSum
            sampleCount += count
            if localPeak > peakMagnitude { peakMagnitude = localPeak }
            os_unfair_lock_unlock(lockPointer)
        }
    }

    /// Called from the audio IOProc for 16-bit integer sample buffers.
    public func ingestInt16(_ samples: UnsafePointer<Int16>, count: Int) {
        guard count > 0 else { return }
        var localSum: Double = 0
        var localPeak: Float = 0
        for i in 0..<count {
            let value = Float(samples[i]) / 32768.0
            localSum += Double(value) * Double(value)
            let magnitude = abs(value)
            if magnitude > localPeak { localPeak = magnitude }
        }

        withUnsafeMutablePointer(to: &lock) { lockPointer in
            guard os_unfair_lock_trylock(lockPointer) else {
                return
            }
            sumOfSquares += localSum
            sampleCount += count
            if localPeak > peakMagnitude { peakMagnitude = localPeak }
            os_unfair_lock_unlock(lockPointer)
        }
    }

    /// Drains the accumulated levels. Returns `nil` when no audio has arrived since the last drain.
    public func drain() -> Summary? {
        withUnsafeMutablePointer(to: &lock) { lockPointer in
            os_unfair_lock_lock(lockPointer)
            defer { os_unfair_lock_unlock(lockPointer) }
            guard sampleCount > 0 else { return nil }
            let meanSquare = sumOfSquares / Double(sampleCount)
            let summary = Summary(
                levelDB: AudioMath.decibels(fromMeanSquare: meanSquare),
                frames: sampleCount
            )
            sumOfSquares = 0
            sampleCount = 0
            peakMagnitude = 0
            return summary
        }
    }
}
