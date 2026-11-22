import CoreAudio
import Foundation

/// Gain shared between the main actor (writer) and the real-time IOProc (reader).
///
/// A single aligned `Float` store/load is atomic on Apple silicon and Intel, so the IOProc reads the
/// target without a lock. `current` is touched only by the IOProc, which ramps it toward `target`.
/// The IOProc captures the two raw pointers, not this object, so a callback does no reference
/// counting. The owner keeps this object alive until the IOProc is destroyed.
final class TargetAudioGainState: @unchecked Sendable {
    let target: UnsafeMutablePointer<Float>
    let current: UnsafeMutablePointer<Float>

    init(target: Float, current: Float = 1) {
        self.target = .allocate(capacity: 1)
        self.current = .allocate(capacity: 1)
        self.target.initialize(to: target)
        self.current.initialize(to: current)
    }

    deinit {
        target.deallocate()
        current.deallocate()
    }
}

/// Copies tapped process audio to an output device at a gain, for "lower the volume" on apps that
/// expose no volume control of their own (browsers, other players).
///
/// Real-time safe: raw pointer arithmetic only. No allocation, no locks, no Swift collections or
/// generics, no reference counting. Both sides are Float32, the format Core Audio hands an IOProc.
/// Each output channel takes the input channel with the same index, wrapping when the output has
/// more channels than the tap (a stereo tap feeds outputs 1-2, 3-4, …; a mono tap feeds all).
public enum TargetAudioRenderer {
    /// Seconds for a full 0→1 gain change. Time-based, so the ramp sounds the same whatever the
    /// device buffer size is.
    public static let rampSeconds: Double = 0.2

    /// Per-frame step for `rampSeconds` at `sampleRate`. Computed off the real-time thread.
    public static func maxStep(sampleRate: Double) -> Float {
        let rate = sampleRate > 0 ? sampleRate : 48_000
        return Float(1 / (rampSeconds * rate))
    }

    /// Byte offset of `mBuffers` inside `AudioBufferList`: the `UInt32` count, padded to the
    /// alignment of `AudioBuffer`. Compile-time constants, no key path or runtime lookup.
    @inline(__always)
    private static var buffersOffset: Int {
        let alignment = MemoryLayout<AudioBuffer>.alignment
        return (MemoryLayout<UInt32>.size + alignment - 1) & ~(alignment - 1)
    }

    @inline(__always)
    private static func buffers(_ list: UnsafeRawPointer) -> UnsafePointer<AudioBuffer> {
        list.advanced(by: buffersOffset).assumingMemoryBound(to: AudioBuffer.self)
    }

    /// Gain after `frames` frames of ramping from `start` toward `target`.
    @inline(__always)
    private static func ramped(_ start: Float, _ target: Float, step: Float, frames: Int) -> Float {
        let limit = step * Float(frames)
        let delta = target - start
        return start + (delta > limit ? limit : (delta < -limit ? -limit : delta))
    }

    /// Renders one callback. Returns the gain reached at the end of the buffer, which the caller
    /// stores as the next starting gain.
    @discardableResult
    public static func render(
        input: UnsafePointer<AudioBufferList>,
        output: UnsafeMutablePointer<AudioBufferList>,
        targetGain: Float,
        startGain: Float,
        maxStepPerFrame: Float
    ) -> Float {
        let inCount = Int(input.pointee.mNumberBuffers)
        let outCount = Int(output.pointee.mNumberBuffers)
        let inBuffers = buffers(UnsafeRawPointer(input))
        let outBuffers = UnsafeMutablePointer(mutating: buffers(UnsafeRawPointer(output)))

        var totalInputChannels = 0
        var inputFrames = 0
        var index = 0
        while index < inCount {
            let buffer = inBuffers[index]
            let channels = max(1, Int(buffer.mNumberChannels))
            totalInputChannels += channels
            if index == 0 { inputFrames = Int(buffer.mDataByteSize) / (MemoryLayout<Float>.size * channels) }
            index += 1
        }

        var outputChannelBase = 0
        var outIndex = 0
        while outIndex < outCount {
            let outBuffer = outBuffers[outIndex]
            let outChannels = max(1, Int(outBuffer.mNumberChannels))
            outIndex += 1
            defer { outputChannelBase += outChannels }
            guard let outRaw = outBuffer.mData else { continue }
            memset(outRaw, 0, Int(outBuffer.mDataByteSize))
            guard totalInputChannels > 0 else { continue }
            let outData = outRaw.assumingMemoryBound(to: Float.self)
            let outFrames = Int(outBuffer.mDataByteSize) / (MemoryLayout<Float>.size * outChannels)

            var channel = 0
            while channel < outChannels {
                let inputChannel = (outputChannelBase + channel) % totalInputChannels
                // Find the input buffer that holds `inputChannel`.
                var accumulated = 0
                var inIndex = 0
                var offset = 0
                while inIndex < inCount {
                    let count = max(1, Int(inBuffers[inIndex].mNumberChannels))
                    if inputChannel < accumulated + count {
                        offset = inputChannel - accumulated
                        break
                    }
                    accumulated += count
                    inIndex += 1
                }
                if inIndex < inCount, let inRaw = inBuffers[inIndex].mData {
                    let inData = inRaw.assumingMemoryBound(to: Float.self)
                    let inStride = max(1, Int(inBuffers[inIndex].mNumberChannels))
                    let inFrames = Int(inBuffers[inIndex].mDataByteSize) / (MemoryLayout<Float>.size * inStride)
                    let frames = min(outFrames, inFrames)
                    var frame = 0
                    while frame < frames {
                        let gain = ramped(startGain, targetGain, step: maxStepPerFrame, frames: frame + 1)
                        outData[frame * outChannels + channel] = inData[frame * inStride + offset] * gain
                        frame += 1
                    }
                }
                channel += 1
            }
        }
        return ramped(startGain, targetGain, step: maxStepPerFrame, frames: inputFrames)
    }
}
