import AVFoundation
import Foundation
import OrejaCore

/// Optional microphone activity monitor for "pause the music while I speak".
///
/// It is a level detector, not a recognizer: no audio leaves the process, nothing is written to
/// disk, and only a dBFS summary survives each analysis frame. It exists because in a spoken
/// conversation ChatGPT is silent while the user talks, so AI-only detection would resume the music
/// into the user's own sentence.
///
/// Microphone access is separate from the system audio recording permission and is only requested
/// when the user turns the option on. Wearing headphones is strongly recommended: with speakers the
/// microphone also hears the music.
@available(macOS 14.2, *)
public final class MicrophoneActivityMonitor: @unchecked Sendable {
    public let events: AsyncStream<AudioActivityEvent>

    private let continuation: AsyncStream<AudioActivityEvent>.Continuation
    private let sampler = LevelSampler()
    private var engine: AVAudioEngine?
    private var analysisTask: Task<Void, Never>?
    private var isRunning = false

    /// Slightly stricter than the output detector: room noise, keyboard clicks and fans should not
    /// hold the music paused, and the user's own voice is close to the microphone.
    private let configuration: AudioActivityDetector.Configuration

    private static let analysisIntervalNanos: UInt64 = 50_000_000

    public init(sensitivity: DetectionSensitivity = .normal) {
        // Bluetooth microphone noise can spike into the high -30s dBFS even in a quiet room, which
        // is why the normal threshold sits above that floor.
        self.configuration = .forMicrophone(sensitivity)
        var localContinuation: AsyncStream<AudioActivityEvent>.Continuation!
        self.events = AsyncStream(bufferingPolicy: .bufferingNewest(32)) { continuation in
            localContinuation = continuation
        }
        self.continuation = localContinuation
    }

    public func start() async throws {
        guard !isRunning else { return }
        try await ensurePermission()

        let engine = AVAudioEngine()
        let input = engine.inputNode
        let format = input.inputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            throw AudioMonitoringFailure(
                .sourceUnavailable,
                "No microphone input is available, so Oreja cannot listen for your voice."
            )
        }

        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [sampler] buffer, _ in
            // Real-time callback: summarize, never allocate or block.
            guard let channel = buffer.floatChannelData?[0] else { return }
            sampler.ingestFloat32(channel, count: Int(buffer.frameLength))
        }

        engine.prepare()
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            throw AudioMonitoringFailure(
                .streamFailed,
                "The microphone could not start: \(error.localizedDescription)"
            )
        }

        self.engine = engine
        isRunning = true
        startAnalysis()
        continuation.yield(.monitorStarted(processDescription: "Microphone"))
    }

    public func stop() async {
        guard isRunning else { return }
        isRunning = false
        analysisTask?.cancel()
        analysisTask = nil
        engine?.inputNode.removeTap(onBus: 0)
        engine?.stop()
        engine = nil
        continuation.yield(.monitorStopped("Microphone monitoring stopped."))
        continuation.finish()
    }

    deinit {
        analysisTask?.cancel()
        engine?.inputNode.removeTap(onBus: 0)
        engine?.stop()
        continuation.finish()
    }

    private func ensurePermission() async throws {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return
        case .notDetermined:
            let granted = await AVCaptureDevice.requestAccess(for: .audio)
            guard granted else { throw Self.permissionFailure }
        default:
            throw Self.permissionFailure
        }
    }

    private static var permissionFailure: AudioMonitoringFailure {
        AudioMonitoringFailure(
            .permissionDenied,
            "Microphone access is off. Turn it on for Oreja in System Settings › Privacy & Security › Microphone, or switch off “Pause while I speak”."
        )
    }

    private func startAnalysis() {
        analysisTask?.cancel()
        analysisTask = Task.detached(priority: .utility) { [weak self] in
            guard let self else { return }
            var detector = AudioActivityDetector(configuration: self.configuration)
            while !Task.isCancelled {
                do {
                    try await Task.sleep(nanoseconds: Self.analysisIntervalNanos)
                } catch {
                    return
                }
                let now = ProcessInfo.processInfo.systemUptime
                guard let summary = self.sampler.drain() else { continue }
                if let transition = detector.ingest(levelDB: summary.levelDB, at: now) {
                    switch transition {
                    case .started:
                        self.continuation.yield(.activityStarted(levelDB: summary.levelDB))
                    case .ended:
                        self.continuation.yield(.activityEnded(levelDB: summary.levelDB))
                    }
                }
            }
        }
    }
}
