import CoreAudio
import Foundation
import OrejaAudio
import OrejaCore

/// Owns synthetic Float32 buffers for one AudioBufferList so renderer tests need no hardware.
private final class TestBufferList {
    let list: UnsafeMutableAudioBufferListPointer
    private var storage: [UnsafeMutablePointer<Float>] = []

    /// `layout` gives the channel count of each buffer; every buffer holds `frames` frames.
    init(layout: [Int], frames: Int, fill: (Int, Int, Int) -> Float = { _, _, _ in 0 }) {
        list = AudioBufferList.allocate(maximumBuffers: layout.count)
        for (index, channels) in layout.enumerated() {
            let count = frames * channels
            let data = UnsafeMutablePointer<Float>.allocate(capacity: count)
            for frame in 0..<frames {
                for channel in 0..<channels {
                    data[frame * channels + channel] = fill(index, frame, channel)
                }
            }
            storage.append(data)
            list[index] = AudioBuffer(
                mNumberChannels: UInt32(channels),
                mDataByteSize: UInt32(count * MemoryLayout<Float>.size),
                mData: UnsafeMutableRawPointer(data)
            )
        }
    }

    func sample(buffer: Int, frame: Int, channel: Int) -> Float {
        let channels = Int(list[buffer].mNumberChannels)
        return storage[buffer][frame * channels + channel]
    }

    deinit {
        storage.forEach { $0.deallocate() }
        free(list.unsafeMutablePointer)
    }
}

@MainActor
func runTargetAudioSuite(_ t: Harness) {
    print("\nOther-app audio (browsers and players)")

    t.run("renderer copies stereo audio unchanged at full gain") {
        let input = TestBufferList(layout: [2], frames: 4) { _, frame, channel in Float(frame + 1) * (channel == 0 ? 0.1 : -0.1) }
        let output = TestBufferList(layout: [2], frames: 4)
        let end = TargetAudioRenderer.render(input: input.list.unsafePointer, output: output.list.unsafeMutablePointer, targetGain: 1, startGain: 1, maxStepPerFrame: 1)
        t.expectClose(Double(end), 1)
        for frame in 0..<4 {
            t.expectClose(Double(output.sample(buffer: 0, frame: frame, channel: 0)), Double(frame + 1) * 0.1, tolerance: 1e-6)
            t.expectClose(Double(output.sample(buffer: 0, frame: frame, channel: 1)), Double(frame + 1) * -0.1, tolerance: 1e-6)
        }
    }

    t.run("renderer ramps toward the duck level over time, not per callback") {
        let step = TargetAudioRenderer.maxStep(sampleRate: 48_000)
        t.expectClose(Double(step) * 48_000 * TargetAudioRenderer.rampSeconds, 1, tolerance: 1e-4, "a full change takes rampSeconds")

        let input = TestBufferList(layout: [2], frames: 480) { _, _, _ in 1 }
        let output = TestBufferList(layout: [2], frames: 480)
        let end = TargetAudioRenderer.render(input: input.list.unsafePointer, output: output.list.unsafeMutablePointer, targetGain: 0.1, startGain: 1, maxStepPerFrame: step)
        t.expectClose(Double(end), 1 - Double(step) * 480, tolerance: 1e-5, "10 ms at 48 kHz moves 5% of the way")
        t.expect(output.sample(buffer: 0, frame: 0, channel: 0) < 1, "the ramp starts on the first frame")
        t.expectClose(Double(output.sample(buffer: 0, frame: 479, channel: 1)), Double(end), tolerance: 1e-5, "every channel ends on the same gain")

        // The same time span reaches the target whatever the buffer size.
        var small: Float = 1
        for _ in 0..<20 {
            small = TargetAudioRenderer.render(input: input.list.unsafePointer, output: output.list.unsafeMutablePointer, targetGain: 0.1, startGain: small, maxStepPerFrame: step)
        }
        let big = TestBufferList(layout: [2], frames: 9_600) { _, _, _ in 1 }
        let bigOut = TestBufferList(layout: [2], frames: 9_600)
        let large = TargetAudioRenderer.render(input: big.list.unsafePointer, output: bigOut.list.unsafeMutablePointer, targetGain: 0.1, startGain: 1, maxStepPerFrame: step)
        t.expectClose(Double(small), Double(large), tolerance: 1e-4, "20 small buffers and one 200 ms buffer end at the same gain")
        t.expectClose(Double(large), 0.1, tolerance: 1e-4)
    }

    t.run("renderer feeds a mono tap to both output channels") {
        let input = TestBufferList(layout: [1], frames: 3) { _, frame, _ in Float(frame) * 0.25 }
        let output = TestBufferList(layout: [2], frames: 3)
        TargetAudioRenderer.render(input: input.list.unsafePointer, output: output.list.unsafeMutablePointer, targetGain: 1, startGain: 1, maxStepPerFrame: 1)
        for frame in 0..<3 {
            t.expectClose(Double(output.sample(buffer: 0, frame: frame, channel: 0)), Double(frame) * 0.25, tolerance: 1e-6)
            t.expectClose(Double(output.sample(buffer: 0, frame: frame, channel: 1)), Double(frame) * 0.25, tolerance: 1e-6)
        }
    }

    t.run("renderer writes non-interleaved output buffers channel by channel") {
        let input = TestBufferList(layout: [2], frames: 2) { _, _, channel in channel == 0 ? 0.5 : -0.5 }
        let output = TestBufferList(layout: [1, 1], frames: 2)
        TargetAudioRenderer.render(input: input.list.unsafePointer, output: output.list.unsafeMutablePointer, targetGain: 1, startGain: 1, maxStepPerFrame: 1)
        t.expectClose(Double(output.sample(buffer: 0, frame: 1, channel: 0)), 0.5, tolerance: 1e-6, "left goes to the first buffer")
        t.expectClose(Double(output.sample(buffer: 1, frame: 1, channel: 0)), -0.5, tolerance: 1e-6, "right goes to the second buffer")
    }

    t.run("renderer outputs silence when the tap delivers nothing") {
        let input = TestBufferList(layout: [2], frames: 0)
        let output = TestBufferList(layout: [2], frames: 4) { _, _, _ in 0.9 }
        TargetAudioRenderer.render(input: input.list.unsafePointer, output: output.list.unsafeMutablePointer, targetGain: 0.1, startGain: 1, maxStepPerFrame: 1)
        for frame in 0..<4 {
            t.expectClose(Double(output.sample(buffer: 0, frame: frame, channel: 0)), 0, tolerance: 0, "stale output is cleared")
        }
    }

    t.run("browsers can be lowered as other apps; Safari is excluded") {
        var settings = AppSettings()
        settings.aiSources = [.chatGPTDesktop]
        settings.targetAudioApps = [
            .chrome,
            .browser(bundleIdentifier: "com.citrolabs.ego.lite", displayName: "ego lite"),
            .safari,
        ]
        t.expectEqual(settings.targetAudioApps.map(\.bundleIdentifier), ["com.google.Chrome", "com.citrolabs.ego.lite"])

        let data = try! JSONEncoder().encode(settings)
        let decoded = try! JSONDecoder().decode(AppSettings.self, from: data)
        t.expectEqual(decoded.targetAudioApps.map(\.bundleIdentifier), ["com.google.Chrome", "com.citrolabs.ego.lite"], "browser targets survive a round trip")
    }

    t.run("an app is never both the conversation source and a lowered target") {
        var settings = AppSettings()
        settings.aiSources = [.chatGPTDesktop, .chrome]
        settings.targetAudioApps = [.chrome]
        t.expect(settings.targetAudioApps.isEmpty, "the browser carrying the conversation is never lowered")
    }

    t.run("other-app gain follows the interruption mode") {
        var settings = AppSettings()
        settings.interruptionMode = .duck
        settings.duckVolumePercent = 11
        t.expectClose(Double(settings.targetAudioGain), 0.11, tolerance: 1e-6, "lower mode uses the duck level")
        settings.interruptionMode = .pause
        t.expectClose(Double(settings.targetAudioGain), 0, tolerance: 0, "pause mode silences apps with no pause control")
    }
}
