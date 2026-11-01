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
    private var tappedTargetIDs: [AudioObjectID] = []
    /// Guards tap creation and teardown: the analysis task re-targets the tap when the monitored
    /// app spawns new audio processes, which can race with `stop()`. Never taken on the audio
    /// thread — the IOProc only touches the sampler.
    private let lifecycleLock = NSLock()
    private var processListListener: AudioObjectPropertyListenerBlock?

    private enum SampleFormat {
        case float32
        case int16
    }

    private static let analysisInterval: TimeInterval = 0.03
    private static let analysisIntervalNanos: UInt64 = 30_000_000
    /// Target IO buffer for the tap device, in frames (~23 ms at 44.1 kHz).
    private static let preferredBufferFrames = 1024
    private static let dataWatchdog: TimeInterval = 1.5
    /// How often the monitor looks for newly appeared audio processes of the monitored app.
    private static let retargetInterval: TimeInterval = 1.0

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
        isRunning = true
        do {
            try setUp()
        } catch {
            isRunning = false
            throw error
        }
        startAnalysis()
        continuation.yield(.monitorStarted(processDescription: processSummary))
    }

    public func stop() async {
        guard isRunning else { return }
        isRunning = false
        analysisTask?.cancel()
        analysisTask = nil
        lifecycleLock.withLock { teardown() }
        continuation.yield(.monitorStopped("Monitoring stopped."))
        continuation.finish()
    }

    deinit {
        analysisTask?.cancel()
        lifecycleLock.withLock { teardown() }
        continuation.finish()
    }

    public var processSummary: String {
        guard matchedProcessCount > 0 else {
            return "\(descriptor.displayName) (waiting for its audio process)"
        }
        return "\(descriptor.displayName) (\(matchedProcessCount) audio process\(matchedProcessCount == 1 ? "" : "es"))"
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
            guard let resolved = try resolveTargets() else {
                // The app is running but has not created an audio process yet — Chrome only spawns
                // its audio service on the first sound, and ChatGPT creates a renderer when a voice
                // session starts. Failing here would leave the first sentence unheard: the app
                // would give up, retry three seconds later, and miss it. Instead the monitor stays
                // alive with no tap and picks the process up the moment it appears, through the
                // Core Audio process-list listener (with the one-second poll as a fallback).
                matchedProcessCount = 0
                tappedTargetIDs = []
                addProcessListListener()
                return
            }
            matchedProcessCount = resolved.count
            targetIDs = resolved
        }

        try createTap(targetIDs: targetIDs)
    }

    /// The set of Core Audio objects to tap right now.
    ///
    /// An app that starts a voice session can spawn audio processes that did not exist when
    /// monitoring began (ChatGPT's renderer and WebRTC helpers, a browser's audio service). Those
    /// processes are only tapped after a re-target, which is why this is re-evaluated while running.
    ///
    /// Every matching process is tapped, including the ones that are quiet right now, and that is
    /// deliberate: an app toggles `isRunningOutput` on and off with each spoken turn, so preferring
    /// only the running ones would rebuild the tap at the moment a sentence starts and lose its
    /// first syllables. Tapping a silent process costs nothing.
    private func resolveTargets() throws -> [AudioObjectID]? {
        let processes = try AudioProcessCatalog.processes(matchingPrefixes: descriptor.bundleIdentifierPrefixes)
        guard !processes.isEmpty else { return nil }
        return processes.map(\.objectID).sorted()
    }

    private enum RetargetOutcome {
        case unchanged
        case changed
    }

    /// Re-evaluates the target processes and rebuilds the tap when the set changed.
    private func retargetIfNeeded() throws -> RetargetOutcome {
        guard explicitTargets == nil else { return .unchanged }

        lifecycleLock.lock()
        defer { lifecycleLock.unlock() }
        guard isRunning else { return .unchanged }

        guard let resolved = try resolveTargets() else {
            // The app dropped every audio process: it quit, or its voice session ended. Keep the
            // monitor alive and wait for the next one instead of ending monitoring, so a new
            // session is picked up immediately rather than after a retry delay.
            guard tapID != AudioObjectID(kAudioObjectUnknown) else { return .unchanged }
            teardown(removeListener: false)
            tappedTargetIDs = []
            matchedProcessCount = 0
            return .changed
        }
        guard Set(resolved) != Set(tappedTargetIDs) else { return .unchanged }

        teardown(removeListener: false)
        try createTap(targetIDs: resolved)
        return .changed
    }

    /// Core Audio tells us the moment the process list changes, so a voice session that spawns a
    /// renderer is picked up immediately instead of on the next poll. The one-second poll above
    /// stays as a fallback for systems where the listener does not fire.
    private func addProcessListListener() {
        guard explicitTargets == nil, processListListener == nil else { return }
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyProcessObjectList,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            self?.handleProcessListChange()
        }
        let status = AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            DispatchQueue.global(qos: .userInitiated),
            block
        )
        if status == noErr { processListListener = block }
    }

    private func removeProcessListListener() {
        guard let processListListener else { return }
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyProcessObjectList,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectRemovePropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            DispatchQueue.global(qos: .userInitiated),
            processListListener
        )
        self.processListListener = nil
    }

    private func handleProcessListChange() {
        lifecycleLock.lock()
        let running = isRunning
        lifecycleLock.unlock()
        guard running else { return }
        do {
            if try retargetIfNeeded() == .changed {
                continuation.yield(.targetsChanged(processDescription: processSummary))
            }
        } catch {
            // The poll below retries; a listener callback must not throw into Core Audio.
        }
    }

    private func createTap(targetIDs: [AudioObjectID]) throws {
        matchedProcessCount = targetIDs.count
        tappedTargetIDs = targetIDs
        addProcessListListener()

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

        try createAggregateDevice(description: description)
    }

    private func createAggregateDevice(description: CATapDescription) throws {
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
        Self.requestShortBuffer(deviceID: aggregate)

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
            var nextRetarget = ProcessInfo.processInfo.systemUptime + Self.retargetInterval

            while !Task.isCancelled {
                do {
                    try await Task.sleep(nanoseconds: Self.analysisIntervalNanos)
                } catch {
                    return
                }
                let now = ProcessInfo.processInfo.systemUptime

                if now >= nextRetarget {
                    nextRetarget = now + Self.retargetInterval
                    do {
                        if try self.retargetIfNeeded() == .changed {
                            self.continuation.yield(.targetsChanged(processDescription: self.processSummary))
                        }
                    } catch let failure as AudioMonitoringFailure {
                        self.continuation.yield(.monitorFailed(failure))
                    } catch {
                        // A transient Core Audio error while re-targeting: try again next interval.
                        nextRetarget = now + Self.retargetInterval * 2
                    }
                }

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

    private func teardown(removeListener: Bool = true) {
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
        if removeListener {
            removeProcessListListener()
        }
    }

    /// A tap device starts with a large IO buffer, so audio would reach the analysis task several
    /// hundred milliseconds after it was spoken. A short buffer keeps detection close to real time.
    private static func requestShortBuffer(deviceID: AudioObjectID) {
        var rangeAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyBufferFrameSizeRange,
            mScope: kAudioObjectPropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
        var range = AudioValueRange()
        var rangeSize = UInt32(MemoryLayout<AudioValueRange>.size)
        let rangeStatus = withUnsafeMutablePointer(to: &range) { pointer in
            AudioObjectGetPropertyData(deviceID, &rangeAddress, 0, nil, &rangeSize, pointer)
        }
        var frames = UInt32(preferredBufferFrames)
        if rangeStatus == noErr, range.mMaximum >= range.mMinimum {
            frames = min(max(frames, UInt32(range.mMinimum)), UInt32(range.mMaximum))
        }
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyBufferFrameSize,
            mScope: kAudioObjectPropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
        var value = frames
        let size = UInt32(MemoryLayout<UInt32>.size)
        // A refused buffer size is not fatal: the tap still works, just with more latency.
        _ = withUnsafeMutablePointer(to: &value) { pointer in
            AudioObjectSetPropertyData(deviceID, &address, 0, nil, size, pointer)
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
