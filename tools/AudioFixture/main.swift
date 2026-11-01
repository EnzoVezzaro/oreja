import AppKit
import AVFoundation
import Foundation

/// Test-only audio fixture. It mimics the shape of a voice app: a process that exists in the
/// Core Audio list before it makes any sound, then starts rendering audio seconds later.
///
///     OrejaFixture --delay 6 --duration 4          # silent, then a 4 s tone
///     OrejaFixture --duration 4                    # tone immediately
///     OrejaFixture --delay 600                     # stay silent (keep watching, never speak)
///
/// It is never bundled with the app.
@main
struct OrejaFixture {
    static func main() {
        let options = Options(arguments: Array(CommandLine.arguments.dropFirst()))
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)

        let player = TonePlayer()
        player.logFile = options.logFile
        // Create the audio graph immediately so the process registers with Core Audio before it
        // ever produces sound, which is what the monitor has to cope with.
        player.prepare()

        DispatchQueue.global().asyncAfter(deadline: .now() + options.delay) {
            print("fixture: tone starts (\(options.duration)s)")
            player.play(duration: options.duration)
            DispatchQueue.global().asyncAfter(deadline: .now() + options.duration) {
                print("fixture: tone ended")
                player.stop()
                if options.exitAfterPlay {
                    exit(0)
                }
            }
        }

        print("fixture: idle for \(options.delay)s")
        app.run()
    }

    struct Options {
        var delay: TimeInterval = 0
        var duration: TimeInterval = 4
        var exitAfterPlay = true
        /// Where to mirror the timing lines, so a harness can read them when the fixture is
        /// launched by LaunchServices instead of a shell.
        var logFile: String?

        init(arguments: [String]) {
            var remaining = arguments
            while let argument = remaining.first {
                remaining.removeFirst()
                switch argument {
                case "--delay":
                    if let value = remaining.first, let parsed = Double(value) { delay = parsed; remaining.removeFirst() }
                case "--duration":
                    if let value = remaining.first, let parsed = Double(value) { duration = parsed; remaining.removeFirst() }
                case "--stay":
                    exitAfterPlay = false
                case "--log":
                    if let value = remaining.first { logFile = value; remaining.removeFirst() }
                default:
                    break
                }
            }
        }
    }
}

/// Plays a sine tone through AVAudioEngine. The engine is started in `prepare()` so the process
/// has an audio client (and therefore a Core Audio process object) while it is still silent.
final class TonePlayer {
    private let engine = AVAudioEngine()
    private var source: AVAudioSourceNode?

    /// Set by `play()`/`stop()`, read from the real-time render thread.
    var logFile: String?

    private let stateLock = NSLock()
    private var wantsTone = false
    /// Mach time of the first non-silent render, so a test can compare "fixture started making
    /// sound" with "Oreja saw sound". Without it the fixture's own startup latency is invisible.
    private var firstAudibleRender: UInt64?

    func prepare() {
        let format = engine.outputNode.inputFormat(forBus: 0)
        let frequency = 2 * Double.pi * 440.0
        let increment = Float(frequency / format.sampleRate)
        var phase: Float = 0

        let node = AVAudioSourceNode { [weak self] _, _, frameCount, audioBufferList -> OSStatus in
            let buffers = UnsafeMutableAudioBufferListPointer(audioBufferList)
            let playing = self.map { player in
                player.stateLock.lock()
                let value = player.wantsTone
                player.stateLock.unlock()
                return value
            } ?? false
            if playing, let self {
                self.stateLock.lock()
                if self.firstAudibleRender == nil { self.firstAudibleRender = mach_absolute_time() }
                self.stateLock.unlock()
            }
            for frame in 0..<Int(frameCount) {
                let value: Float = playing ? 0.25 * sin(phase) : 0
                if playing {
                    phase += increment
                    if phase > Float.pi * 2 { phase -= Float.pi * 2 }
                }
                for buffer in buffers {
                    guard let data = buffer.mData else { continue }
                    data.assumingMemoryBound(to: Float.self)[frame] = value
                }
            }
            return noErr
        }
        source = node
        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: format)
        do {
            try engine.start()
            print("fixture: engine started at \(Int(format.sampleRate)) Hz, \(format.channelCount) ch")
        } catch {
            print("fixture: engine failed: \(error.localizedDescription)")
        }
    }

    func play(duration: TimeInterval) {
        stateLock.lock()
        wantsTone = true
        firstAudibleRender = nil
        stateLock.unlock()
        // Report when the fixture itself starts rendering, not when it asked to.
        DispatchQueue.global().async { [weak self] in
            while true {
                usleep(2_000)
                guard let self else { return }
                self.stateLock.lock()
                let stamp = self.firstAudibleRender
                self.stateLock.unlock()
                if let stamp {
                    var timebase = mach_timebase_info_data_t()
                    mach_timebase_info(&timebase)
                    let seconds = Double(stamp) * Double(timebase.numer) / Double(timebase.denom) / 1_000_000_000
                    let line = "fixture: audible at \(String(format: "%.3f", seconds))"
                    print(line)
                    self.mirror(line)
                    return
                }
            }
        }
        _ = duration
    }

    func stop() {
        stateLock.lock()
        wantsTone = false
        stateLock.unlock()
    }

    /// Appends one timing line when a log path was requested, so a harness can read the fixture's
    /// own clock even when LaunchServices started the process.
    private func mirror(_ line: String) {
        guard let logFile, let data = (line + "\n").data(using: .utf8) else { return }
        if let handle = FileHandle(forWritingAtPath: logFile) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        } else {
            try? data.write(to: URL(fileURLWithPath: logFile))
        }
    }

    private static func makeTone(format: AVAudioFormat, seconds: Double) -> AVAudioPCMBuffer? {
        let frames = AVAudioFrameCount(format.sampleRate * seconds)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames) else { return nil }
        buffer.frameLength = frames
        guard let channels = buffer.floatChannelData else { return nil }
        let frequency = 440.0
        let amplitude: Float = 0.25
        for frame in 0..<Int(frames) {
            let value = amplitude * Float(sin(2 * Double.pi * frequency * Double(frame) / format.sampleRate))
            for channel in 0..<Int(format.channelCount) {
                channels[channel][frame] = value
            }
        }
        return buffer
    }
}
