import CoreAudio
import Foundation
import OrejaCore

/// Main-actor owner for target-app interruption state. The Core Audio tap itself is nonisolated so
/// its IOProc callback never inherits the main actor or hops onto the UI thread.
///
/// - `gain == 0` silences the selected apps (used for the "pause" interruption mode: apps such as
///   browsers have no pause control Oreja can reach, so silence stands in for it).
/// - `gain > 0` lowers them: the process output is muted at the source and the tapped audio is
///   played to the current output device at that gain, then ramped back to full on release.
/// What the controller is doing to the selected apps right now. The UI and the log report this,
/// so "lowered" is only claimed when the audio is really being replayed at the duck level.
public enum TargetInterruption: Equatable, Sendable {
    case none
    case lowered
    case silenced
}

@available(macOS 14.2, *)
@MainActor
public final class ProcessAudioTargetMuteController {
    private var applications: [AISourceSelection] = []
    private var shouldMute = false
    private var gain: Float = 0
    private var tap: TargetProcessMuteTap?
    private var refreshTask: Task<Void, Never>?
    private var releaseTask: Task<Void, Never>?
    private var tappedProcessIDs: [AudioObjectID] = []
    private var tappedOutputUID: String?

    /// How long a lowered app is ramped back up before its tap is removed.
    private static let releaseRampNanos: UInt64 = 300_000_000

    public init() {}

    /// `.lowered` only while the tapped audio is replayed to an output device. Lower mode falls back
    /// to `.silenced` when the output device cannot be read.
    public var activeInterruption: TargetInterruption {
        guard let tap, shouldMute else { return .none }
        return tap.rendersAudio ? .lowered : .silenced
    }

    public func update(applications: [AISourceSelection], shouldMute: Bool, gain: Float = 0) throws {
        self.applications = AISourceCatalog.normalizedTargets(applications)
        let clampedGain = min(max(gain, 0), 1)
        let modeChanged = (clampedGain > 0) != (self.gain > 0)
        self.gain = clampedGain
        self.shouldMute = shouldMute

        if shouldMute {
            releaseTask?.cancel()
            releaseTask = nil
            if modeChanged { teardown() }
            tap?.setTargetGain(clampedGain)
            startRefreshLoop()
            try refreshTargets()
        } else {
            refreshTask?.cancel()
            refreshTask = nil
            release()
        }
    }

    private func startRefreshLoop() {
        guard refreshTask == nil else { return }
        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard let self, self.shouldMute else { return }
                do { try self.refreshTargets() }
                catch { NSLog("Oreja: could not refresh interrupted app processes: %@", error.localizedDescription) }
            }
        }
    }

    private func refreshTargets() throws {
        let bundleIDRoots = Array(Set(applications
            .compactMap(AISourceCatalog.targetMuteBundleIDRoots(for:))
            .flatMap { $0 })).sorted()
        let processIDs: [AudioObjectID]
        do {
            processIDs = try AudioProcessCatalog.processes(matchingBundleIDRoots: bundleIDRoots)
                .map(\.objectID)
                .sorted()
        } catch {
            teardown()
            throw error
        }
        let outputUID = gain > 0 ? DefaultOutputDevice.uid() : nil
        guard processIDs != tappedProcessIDs || outputUID != tappedOutputUID || tap == nil else { return }
        teardown()
        guard !processIDs.isEmpty else { return }

        let newTap = TargetProcessMuteTap(gain: gain)
        try newTap.start(processIDs: processIDs, outputDeviceUID: outputUID)
        tap = newTap
        tappedProcessIDs = processIDs
        tappedOutputUID = outputUID
    }

    /// Lowered apps ramp back to full volume before the tap goes away, so the music does not jump.
    /// Silenced apps are released at once: there is no rendered signal to ramp.
    private func release() {
        guard let tap, tap.rendersAudio else {
            teardown()
            return
        }
        // A release already in progress keeps its schedule: restarting it on every state update
        // could postpone the teardown forever.
        guard releaseTask == nil else { return }
        tap.setTargetGain(1)
        releaseTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: Self.releaseRampNanos)
            guard let self, !Task.isCancelled else { return }
            self.releaseTask = nil
            guard !self.shouldMute else { return }
            self.teardown()
        }
    }

    private func teardown() {
        tap?.stop()
        tap = nil
        tappedProcessIDs = []
        tappedOutputUID = nil
    }
}

/// Owns Core Audio objects without actor isolation. In particular, the IOProc callback below runs
/// on Core Audio's real-time thread and must not inherit MainActor from a UI-facing caller.
@available(macOS 14.2, *)
private final class TargetProcessMuteTap: @unchecked Sendable {
    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateDeviceID = AudioObjectID(kAudioObjectUnknown)
    private var ioProcID: AudioDeviceIOProcID?
    private let gainState: TargetAudioGainState
    private(set) var rendersAudio = false

    init(gain: Float) {
        gainState = TargetAudioGainState(target: gain, current: 1)
    }

    func setTargetGain(_ gain: Float) {
        gainState.target.pointee = gain
    }

    /// `outputDeviceUID` non-nil means "lower": the tapped audio is played to that device at the
    /// target gain. Nil means "silence": the tap only applies its mute.
    func start(processIDs: [AudioObjectID], outputDeviceUID: String?) throws {
        let renders = outputDeviceUID != nil && gainState.target.pointee > 0
        let description = renders
            ? CATapDescription(stereoMixdownOfProcesses: processIDs)
            : CATapDescription(monoMixdownOfProcesses: processIDs)
        description.name = "Oreja — interrupted app audio"
        description.uuid = UUID()
        description.isPrivate = true
        description.muteBehavior = .muted

        var tap = AudioObjectID(kAudioObjectUnknown)
        let tapStatus = AudioHardwareCreateProcessTap(description, &tap)
        guard tapStatus == noErr, tap != AudioObjectID(kAudioObjectUnknown) else {
            throw AudioMonitoringFailure(.tapCreationFailed, "Could not interrupt the selected app audio (OSStatus \(tapStatus)).")
        }
        tapID = tap

        var aggregateDescription: [String: Any] = [
            kAudioAggregateDeviceNameKey: "Oreja Interrupted Audio",
            kAudioAggregateDeviceUIDKey: "com.oreja.target.\(UUID().uuidString)",
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: false,
            kAudioAggregateDeviceTapListKey: [[
                kAudioSubTapUIDKey: description.uuid.uuidString,
                kAudioSubTapDriftCompensationKey: true,
            ]],
        ]
        if renders, let outputDeviceUID {
            aggregateDescription[kAudioAggregateDeviceMainSubDeviceKey] = outputDeviceUID
            aggregateDescription[kAudioAggregateDeviceSubDeviceListKey] = [[kAudioSubDeviceUIDKey: outputDeviceUID]]
        }

        var aggregate = AudioObjectID(kAudioObjectUnknown)
        let aggregateStatus = AudioHardwareCreateAggregateDevice(aggregateDescription as CFDictionary, &aggregate)
        guard aggregateStatus == noErr, aggregate != AudioObjectID(kAudioObjectUnknown) else {
            stop()
            throw AudioMonitoringFailure(.deviceSetupFailed, "Could not set up app audio control (OSStatus \(aggregateStatus)).")
        }
        aggregateDeviceID = aggregate

        // The IOProc captures raw pointers and a constant, never this object or the state object,
        // so a callback does no reference counting. `gainState` outlives the IOProc: `stop()`
        // destroys the IOProc before this object (and its state) can go away.
        let target = gainState.target
        let current = gainState.current
        let step = TargetAudioRenderer.maxStep(sampleRate: Self.nominalSampleRate(of: aggregate))
        var procID: AudioDeviceIOProcID?
        let procStatus: OSStatus
        if renders {
            procStatus = AudioDeviceCreateIOProcIDWithBlock(&procID, aggregate, nil) { _, input, _, output, _ in
                // Real-time: read the target, render, store the ramped gain. Nothing else.
                current.pointee = TargetAudioRenderer.render(
                    input: input,
                    output: output,
                    targetGain: target.pointee,
                    startGain: current.pointee,
                    maxStepPerFrame: step
                )
            }
        } else {
            procStatus = AudioDeviceCreateIOProcIDWithBlock(&procID, aggregate, nil) { _, _, _, _, _ in
                // Discard immediately. The tap exists only to apply its mute behavior.
            }
        }
        guard procStatus == noErr, let procID else {
            stop()
            throw AudioMonitoringFailure(.deviceSetupFailed, "Could not start app audio control (OSStatus \(procStatus)).")
        }
        ioProcID = procID
        let startStatus = AudioDeviceStart(aggregate, procID)
        guard startStatus == noErr else {
            stop()
            throw AudioMonitoringFailure(.deviceSetupFailed, "Could not start app audio control (OSStatus \(startStatus)).")
        }
        rendersAudio = renders
    }

    private static func nominalSampleRate(of device: AudioObjectID) -> Double {
        var rate: Float64 = 0
        var size = UInt32(MemoryLayout<Float64>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyNominalSampleRate,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &rate) == noErr else { return 48_000 }
        return rate
    }

    func stop() {
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
        rendersAudio = false
    }

    deinit {
        stop()
    }
}
