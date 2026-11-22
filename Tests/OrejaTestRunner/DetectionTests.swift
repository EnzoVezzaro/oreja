import Foundation
import OrejaAudio
import OrejaCore

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

    t.run("sensitivity maps onto real detector thresholds") {
        let high = AudioActivityDetector.Configuration.forAI(.high)
        let normal = AudioActivityDetector.Configuration.forAI(.normal)
        let low = AudioActivityDetector.Configuration.forAI(.low)
        t.expect(high.activationThresholdDB < normal.activationThresholdDB)
        t.expect(normal.activationThresholdDB < low.activationThresholdDB)
        t.expectEqual(normal.activationThresholdDB, -45, "the default stays where it was calibrated")
        t.expectClose(normal.deactivationThresholdDB, -55, tolerance: 0.001)

        // Hysteresis is a fixed 10 dB gap, so raising sensitivity cannot make a sentence end between words.
        for level in DetectionSensitivity.allCases {
            let configuration = AudioActivityDetector.Configuration.forAI(level)
            t.expectClose(configuration.activationThresholdDB - configuration.deactivationThresholdDB, 10, tolerance: 0.001)
        }

        // The microphone starts higher than an app's output, because it hears the room too.
        for level in DetectionSensitivity.allCases {
            t.expect(AudioActivityDetector.Configuration.forMicrophone(level).activationThresholdDB
                > AudioActivityDetector.Configuration.forAI(level).activationThresholdDB)
        }

        // Normal must sit between the measured room floor (about -42 dBFS 90th percentile) and
        // ordinary speech at the built-in mic (about -26 dBFS median).
        let normalMic = AudioActivityDetector.Configuration.forMicrophone(.normal).activationThresholdDB
        t.expect(normalMic > -42 && normalMic < -26, "normal mic threshold sits between room noise and speech")
    }

    // MARK: Speech-shape filter

    /// Feeds one frame every 30 ms and returns every output the gate produced.
    func drive(_ gate: inout SpeechShapeFilter, _ levels: [Double], step: TimeInterval = 0.03) -> [SpeechShapeFilter.Output] {
        var outputs: [SpeechShapeFilter.Output] = []
        var time: TimeInterval = 0
        for level in levels {
            let output = gate.ingest(levelDB: level, at: time)
            if output != .none { outputs.append(output) }
            time += step
        }
        return outputs
    }

    func startedLevels(_ outputs: [SpeechShapeFilter.Output]) -> [Double] {
        outputs.compactMap {
            if case .started(let level) = $0 { return level }
            return nil
        }
    }

    func suppressions(_ outputs: [SpeechShapeFilter.Output]) -> [AudioSuppressionReason] {
        outputs.compactMap {
            if case .suppressed(let reason, _) = $0 { return reason }
            return nil
        }
    }

    t.run("gate: a brief blip is suppressed instead of pausing music") {
        var gate = SpeechShapeFilter()
        let quiet = [Double](repeating: -100, count: 2)
        let blip = [Double](repeating: -20, count: 4)
        let silence = [Double](repeating: -100, count: 12)
        let outputs = drive(&gate, quiet + blip + silence)
        t.expectEqual(startedLevels(outputs).count, 0, "no activity announced")
        t.expectEqual(suppressions(outputs), [.brief])
        t.expectEqual(gate.suppressedBurstCount, 1)
        t.expect(!gate.isActive)
    }

    t.run("gate: a steady alert tone is suppressed after the confirmation window") {
        var gate = SpeechShapeFilter()
        let outputs = drive(&gate, [Double](repeating: -20, count: 25))
        t.expectEqual(startedLevels(outputs).count, 0, "a flat tone never counts as speech")
        t.expectEqual(suppressions(outputs), [.steady])
    }

    t.run("gate: a chime that only decays is suppressed") {
        var gate = SpeechShapeFilter()
        var chime: [Double] = [-20]
        var level = -20.0
        for _ in 0..<20 {
            level -= 1.5
            chime.append(level)
        }
        let outputs = drive(&gate, chime)
        t.expectEqual(startedLevels(outputs).count, 0, "a single attack and decay has no reversals")
        t.expectEqual(suppressions(outputs).count, 1)
    }

    t.run("gate: speech-shaped audio is announced within a few frames") {
        var gate = SpeechShapeFilter()
        let speech: [Double] = [-30, -20, -32, -22, -33, -21, -30, -19]
        let outputs = drive(&gate, speech)
        t.expectEqual(startedLevels(outputs).count, 1)
        t.expect(gate.isActive)
        t.expectEqual(gate.suppressedBurstCount, 0, "syllables are not mistaken for an alert")
    }

    t.run("gate: speech that follows an alert is still announced") {
        var gate = SpeechShapeFilter()
        let alert = [Double](repeating: -20, count: 20)
        let speech: [Double] = [-20, -34, -22, -34, -22, -30]
        let ending = [Double](repeating: -100, count: 12)
        let outputs = drive(&gate, alert + speech + ending)
        t.expectEqual(suppressions(outputs), [.steady])
        t.expectEqual(startedLevels(outputs).count, 1, "the reply after the chime still pauses music")
        t.expect(outputs.contains {
            if case .ended = $0 { return true }
            return false
        }, "the announced window ends normally")
    }

    t.run("gate: disabled, every burst is forwarded") {
        var gate = SpeechShapeFilter(configuration: .passthrough)
        let quiet = [Double](repeating: -100, count: 2)
        let blip = [Double](repeating: -20, count: 4)
        let silence = [Double](repeating: -100, count: 12)
        let outputs = drive(&gate, quiet + blip + silence)
        t.expectEqual(startedLevels(outputs).count, 1, "pass-through keeps the old behavior")
        t.expectEqual(suppressions(outputs).count, 0)
    }

    t.run("gate: reset forgets an open window") {
        var gate = SpeechShapeFilter()
        _ = drive(&gate, [Double](repeating: -20, count: 10))
        gate.reset()
        t.expect(!gate.isActive)
        t.expectEqual(gate.lastLevelDB, -100)
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
