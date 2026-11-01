import Foundation
import OrejaAudio

@MainActor
func runDetectionSuite(_ t: Harness) {
    print("\nAudio activity detection")

    t.run("dBFS conversion is finite and clamped") {
        t.expectClose(AudioMath.decibels(fromMeanSquare: 1.0), 0)
        t.expectClose(AudioMath.decibels(fromMeanSquare: 0.01), -20)
        t.expectEqual(AudioMath.decibels(fromMeanSquare: 0), -100)
        t.expectEqual(AudioMath.decibels(fromMeanSquare: -1), -100)
        t.expectEqual(AudioMath.decibels(fromMeanSquare: .nan), -100)
    }

    t.run("start requires the minimum activity duration") {
        var detector = AudioActivityDetector(configuration: .init(minimumActivityDuration: 0.06))
        t.expect(detector.ingest(levelDB: -20, at: 0) == nil)
        t.expect(detector.ingest(levelDB: -20, at: 0.03) == nil)
        t.expectEqual(detector.ingest(levelDB: -20, at: 0.07), .started)
        t.expect(detector.isActive)
    }

    t.run("sub-threshold blips never start activity") {
        var detector = AudioActivityDetector(configuration: .init(minimumActivityDuration: 0.06))
        t.expect(detector.ingest(levelDB: -70, at: 0) == nil)
        t.expect(detector.ingest(levelDB: -50, at: 0.05) == nil, "above deactivation but below activation")
        t.expect(detector.ingest(levelDB: -70, at: 0.2) == nil)
        t.expect(!detector.isActive)
    }

    t.run("end requires the full silence duration") {
        var detector = AudioActivityDetector(configuration: .init(minimumSilenceDuration: 0.25))
        _ = detector.ingest(levelDB: -10, at: 0)
        t.expectEqual(detector.ingest(levelDB: -10, at: 0.1), .started)
        t.expect(detector.ingest(levelDB: -80, at: 0.2) == nil)
        t.expect(detector.ingest(levelDB: -80, at: 0.3) == nil)
        t.expectEqual(detector.ingest(levelDB: -80, at: 0.46), .ended)
        t.expect(!detector.isActive)
    }

    t.run("hysteresis: moderate levels do not end activity") {
        var detector = AudioActivityDetector(configuration: .init())
        _ = detector.ingest(levelDB: -20, at: 0)
        _ = detector.ingest(levelDB: -20, at: 0.1)
        t.expect(detector.isActive)
        t.expect(detector.ingest(levelDB: -50, at: 0.5) == nil, "between thresholds keeps the current state")
        t.expect(detector.ingest(levelDB: -50, at: 1.0) == nil)
        t.expect(detector.isActive)
    }

    t.run("a quiet gap shorter than the silence window does not end activity") {
        var detector = AudioActivityDetector(configuration: .init(minimumSilenceDuration: 0.25))
        _ = detector.ingest(levelDB: -10, at: 0)
        _ = detector.ingest(levelDB: -10, at: 0.1)
        t.expect(detector.isActive)
        t.expect(detector.ingest(levelDB: -80, at: 0.2) == nil)
        t.expect(detector.ingest(levelDB: -20, at: 0.4) == nil, "speech restarted before silence elapsed")
        t.expect(detector.isActive)
        t.expect(detector.ingest(levelDB: -80, at: 0.5) == nil)
        t.expect(detector.ingest(levelDB: -80, at: 0.6) == nil)
        t.expectEqual(detector.ingest(levelDB: -80, at: 0.76), .ended)
    }

    t.run("reset clears pending state") {
        var detector = AudioActivityDetector()
        _ = detector.ingest(levelDB: -10, at: 0)
        _ = detector.ingest(levelDB: -10, at: 0.2)
        t.expect(detector.isActive)
        detector.reset()
        t.expect(!detector.isActive)
        t.expectEqual(detector.lastLevelDB, -100)
    }

    t.run("LevelSampler averages dequeued buffers") {
        let sampler = LevelSampler()
        let samples = [Float](repeating: 0.5, count: 512)
        samples.withUnsafeBufferPointer { buffer in
            sampler.ingestFloat32(buffer.baseAddress!, count: buffer.count)
        }
        let summary = sampler.drain()
        t.expect(summary != nil)
        t.expectClose(summary?.levelDB ?? 0, -6.0206, tolerance: 0.01)
        t.expect(sampler.drain() == nil, "drain empties the accumulator")
    }
}
