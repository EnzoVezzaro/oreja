import CoreAudio
import Foundation
import OrejaCore

/// Monitors the audio *output* of selected processes with a Core Audio process tap
/// (macOS 14.2+). The tap is unmuted: ChatGPT keeps playing through the normal output device and
/// only a copy of its audio is analyzed. Nothing is recorded or written to disk.
@available(macOS 14.2, *)
public final class ProcessAudioMonitor: AIAudioMonitoring, @unchecked Sendable {
    public let descriptor: AIAudioSourceDescriptor
    public let events: AsyncStream<AudioActivityEvent>

    private let continuation: AsyncStream<AudioActivityEvent>.Continuation
    private let detectorConfiguration: AudioActivityDetector.Configuration
    private let explicitTargets: [AudioObjectID]?
    private let sampler = LevelSampler()

    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateDeviceID = AudioObjectID(kAudioObjectUnknown)
    private var ioProcID: AudioDeviceIOProcID?
    private var analysisTask: Task<Void, Never>?
    private var sampleFormat: SampleFormat = .float32
    private var isRunning = false
    private var matchedProcessCount = 0

    private enum SampleFormat {
        case float32
        case int16
    }

    private static let analysisInterval: TimeInterval = 0.05
    private static let analysisIntervalNanos: UInt64 = 50_000_000
    private static let dataWatchdog: TimeInterval = 1.5

    public init(
        descriptor: AIAudioSourceDescriptor,
        detectorConfiguration: AudioActivityDetector.Configuration = .init()
    ) {
        self.descriptor = descriptor
        self.detectorConfiguration = detectorConfiguration
        self.explicitTargets = nil
        var localContinuation: AsyncStream<AudioActivityEvent>.Continuation!
        self.events = AsyncStream(bufferingPolicy: .bufferingNewest(64)) { continuation in
            localContinuation = continuation
        }
        self.continuation = localContinuation
    }

    /// Taps known Core Audio process objects directly. Used by the audio probe to verify capture
    /// against a controlled process that has no bundle identifier (for example `say`).
    public init(
        targetObjectIDs: [AudioObjectID],
        displayName: String,
        detectorConfiguration: AudioActivityDetector.Configuration = .init()
    ) {
        self.descriptor = AIAudioSourceDescriptor(
            displayName: displayName,
            bundleIdentifierPrefixes: [],
            isExperimental: true
        )
        self.detectorConfiguration = detectorConfiguration
        self.explicitTargets = targetObjectIDs
        var localContinuation: AsyncStream<AudioActivityEvent>.Continuation!
        self.events = AsyncStream(bufferingPolicy: .bufferingNewest(64)) { continuation in
            localContinuation = continuation
        }
        self.continuation = localContinuation
    }

    // MARK: - Lifecycle

    public func start() async throws {
        guard !isRunning else { return }
        try setUp()
        isRunning = true
        startAnalysis()
        continuation.yield(.monitorStarted(processDescription: processSummary))
    }

    public func stop() async {
        guard isRunning else { return }
        isRunning = false
        analysisTask?.cancel()
        analysisTask = nil
        teardown()
        continuation.yield(.monitorStopped("Monitoring stopped."))
        continuation.finish()
    }

    deinit {
        analysisTask?.cancel()
        teardown()
        continuation.finish()
    }

    public var processSummary: String {
        "\(descriptor.displayName) (\(matchedProcessCount) audio process\(matchedProcessCount == 1 ? "" : "es"))"
    }

    // MARK: - Setup

    private func setUp() throws {
        let targetIDs: [AudioObjectID]
        if let explicitTargets {
            guard !explicitTargets.isEmpty else {
                throw AudioMonitoringFailure(.sourceUnavailable, "No audio process was supplied to monitor.")
            }
            matchedProcessCount = explicitTargets.count
            targetIDs = explicitTargets
        } else {
            let processes = try AudioProcessCatalog.processes(matchingPrefixes: descriptor.bundleIdentifierPrefixes)
            guard !processes.isEmpty else {
                throw AudioMonitoringFailure(
                    .sourceUnavailable,
                    "\(descriptor.displayName) is not writing audio right now. Open it, start a voice session, and try again."
                )
            }
            matchedProcessCount = processes.count
            let running = processes.filter(\.isRunningOutput).map(\.objectID)
            targetIDs = running.isEmpty ? processes.map(\.objectID) : running
        }

        let description = CATapDescription(monoMixdownOfProcesses: targetIDs)
        description.name = "Oreja — \(descriptor.displayName)"
        description.uuid = UUID()
        // Audio is captured and also sent to the audio hardware. Oreja never mutes or reroutes.
        description.muteBehavior = CATapMuteBehavior(rawValue: 0)!
        description.isPrivate = true

        var tap = AudioObjectID(kAudioObjectUnknown)
        let tapStatus = AudioHardwareCreateProcessTap(description, &tap)
        guard tapStatus == noErr, tap != AudioObjectID(kAudioObjectUnknown) else {
            throw tapFailure(tapStatus)
        }
        tapID = tap

        let aggregateUID = "com.oreja.tap." + UUID().uuidString
        let tapUID = description.uuid.uuidString
        let aggregateDescription: [String: Any] = [
            kAudioAggregateDeviceNameKey: "Oreja AI Audio",
            kAudioAggregateDeviceUIDKey: aggregateUID,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: false,
            kAudioAggregateDeviceTapListKey: [
                [
                    kAudioSubTapUIDKey: tapUID,
                    kAudioSubTapDriftCompensationKey: true,
                ]
            ],
        ]

        var aggregate = AudioObjectID(kAudioObjectUnknown)
        let aggregateStatus = AudioHardwareCreateAggregateDevice(aggregateDescription as CFDictionary, &aggregate)
        guard aggregateStatus == noErr, aggregate != AudioObjectID(kAudioObjectUnknown) else {
            teardown()
            throw AudioMonitoringFailure(
                .deviceSetupFailed,
                "Could not create the private tap device (OSStatus \(aggregateStatus))."
            )
        }
        aggregateDeviceID = aggregate

        sampleFormat = Self.detectSampleFormat(deviceID: aggregate)
        try createIOProc()
        try startDevice()
    }

    private func tapFailure(_ status: OSStatus) -> AudioMonitoringFailure {
        // -50 (illegal operation) and -4 (not running) are what macOS returns when the
        // audio-capture privacy permission is missing. The message stays actionable either way.
        if status == -50 || status == -4 {
            return AudioMonitoringFailure(
                .permissionDenied,
                "macOS did not allow audio capture (OSStatus \(status)). Grant Oreja access in System Settings › Privacy & Security › Screen & System Audio Recording."
            )
        }
        return AudioMonitoringFailure(
            .tapCreationFailed,
            "Could not create the process tap (OSStatus \(status))."
        )
    }

    private func createIOProc() throws {
        let deviceID = aggregateDeviceID
        var procID: AudioDeviceIOProcID?
        let status = AudioDeviceCreateIOProcIDWithBlock(&procID, deviceID, nil) { [sampler, sampleFormat] _, inputData, _, _, _ in
            // Real-time callback: no allocation, no locks that can block, no UI work.
            let buffers = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: inputData))
            switch sampleFormat {
            case .float32:
                for buffer in buffers {
                    guard let data = buffer.mData else { continue }
                    sampler.ingestFloat32(
                        data.assumingMemoryBound(to: Float.self),
                        count: Int(buffer.mDataByteSize) / MemoryLayout<Float>.size
                    )
                }
            case .int16:
                for buffer in buffers {
                    guard let data = buffer.mData else { continue }
                    sampler.ingestInt16(
                        data.assumingMemoryBound(to: Int16.self),
                        count: Int(buffer.mDataByteSize) / MemoryLayout<Int16>.size
                    )
                }
            }
        }
        guard status == noErr, let procID else {
            teardown()
            throw AudioMonitoringFailure(.streamFailed, "Could not create the audio IOProc (OSStatus \(status)).")
        }
        ioProcID = procID
    }

    private func startDevice() throws {
        guard let ioProcID else {
            throw AudioMonitoringFailure(.streamFailed, "No audio IOProc is installed.")
        }
        let status = AudioDeviceStart(aggregateDeviceID, ioProcID)
        guard status == noErr else {
            teardown()
            throw AudioMonitoringFailure(.streamFailed, "Could not start the audio tap (OSStatus \(status)).")
        }
    }

    // MARK: - Analysis

    private func startAnalysis() {
        analysisTask?.cancel()
        analysisTask = Task.detached(priority: .utility) { [weak self] in
            guard let self else { return }
            var detector = AudioActivityDetector(configuration: self.detectorConfiguration)
            var lastDataTime = ProcessInfo.processInfo.systemUptime

            while !Task.isCancelled {
                do {
                    try await Task.sleep(nanoseconds: Self.analysisIntervalNanos)
                } catch {
                    return
                }
                let now = ProcessInfo.processInfo.systemUptime
                if let summary = self.sampler.drain() {
                    lastDataTime = now
                    if let transition = detector.ingest(levelDB: summary.levelDB, at: now) {
                        switch transition {
                        case .started:
                            self.continuation.yield(.activityStarted(levelDB: summary.levelDB))
                        case .ended:
                            self.continuation.yield(.activityEnded(levelDB: summary.levelDB))
                        }
                    }
                } else if detector.isActive, now - lastDataTime > Self.dataWatchdog {
                    // The tap stopped delivering audio (device change / process exit). Treat it
                    // as silence so music is not left paused forever.
                    if let transition = detector.ingest(levelDB: -100, at: now), transition == .ended {
                        self.continuation.yield(.activityEnded(levelDB: -100))
                    }
                }
            }
        }
    }

    // MARK: - Teardown

    private func teardown() {
        if aggregateDeviceID != AudioObjectID(kAudioObjectUnknown), let ioProcID {
            AudioDeviceStop(aggregateDeviceID, ioProcID)
            AudioDeviceDestroyIOProcID(aggregateDeviceID, ioProcID)
        }
        ioProcID = nil
        if aggregateDeviceID != AudioObjectID(kAudioObjectUnknown) {
            AudioHardwareDestroyAggregateDevice(aggregateDeviceID)
            aggregateDeviceID = AudioObjectID(kAudioObjectUnknown)
        }
        if tapID != AudioObjectID(kAudioObjectUnknown) {
            AudioHardwareDestroyProcessTap(tapID)
            tapID = AudioObjectID(kAudioObjectUnknown)
        }
    }

    private static func detectSampleFormat(deviceID: AudioObjectID) -> SampleFormat {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamFormat,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
        var streamFormat = AudioStreamBasicDescription()
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        let status = withUnsafeMutablePointer(to: &streamFormat) { pointer in
            AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, pointer)
        }
        guard status == noErr else { return .float32 }
        if streamFormat.mFormatFlags & kAudioFormatFlagIsFloat != 0, streamFormat.mBitsPerChannel == 32 {
            return .float32
        }
        if streamFormat.mBitsPerChannel == 16 {
            return .int16
        }
        return .float32
    }
}

/// Creates monitors for the app. Kept separate so the app can substitute a fake in tests.
public final class ProcessAudioMonitorFactory: AIAudioMonitorFactory {
    public init() {}

    public func makeMonitor(for descriptor: AIAudioSourceDescriptor) -> any AIAudioMonitoring {
        if #available(macOS 14.2, *) {
            return ProcessAudioMonitor(descriptor: descriptor)
        } else {
            return FailingAudioMonitor(
                failure: AudioMonitoringFailure(.sourceUnavailable, "Oreja requires macOS 14.2 or newer.")
            )
        }
    }
}

/// Used when the OS cannot provide process taps at all.
public final class FailingAudioMonitor: AIAudioMonitoring, @unchecked Sendable {
    public let events: AsyncStream<AudioActivityEvent>
    private let continuation: AsyncStream<AudioActivityEvent>.Continuation
    private let failure: AudioMonitoringFailure

    public init(failure: AudioMonitoringFailure) {
        self.failure = failure
        var localContinuation: AsyncStream<AudioActivityEvent>.Continuation!
        self.events = AsyncStream(bufferingPolicy: .bufferingNewest(8)) { continuation in
            localContinuation = continuation
        }
        self.continuation = localContinuation
    }

    public func start() async throws {
        continuation.yield(.monitorFailed(failure))
        throw failure
    }

    public func stop() async {
        continuation.finish()
    }
}
