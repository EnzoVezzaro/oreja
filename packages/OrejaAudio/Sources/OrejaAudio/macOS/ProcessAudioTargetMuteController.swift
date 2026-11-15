import CoreAudio
import Foundation
import OrejaCore

/// Main-actor owner for target-app mute state. The Core Audio tap itself is nonisolated so its IOProc
/// callback never inherits the main actor or hops onto the UI thread.
@available(macOS 14.2, *)
@MainActor
public final class ProcessAudioTargetMuteController {
    private var applications: [AISourceSelection] = []
    private var shouldMute = false
    private var tap: TargetProcessMuteTap?
    private var refreshTask: Task<Void, Never>?
    private var tappedProcessIDs: [AudioObjectID] = []

    public init() {}

    public func update(applications: [AISourceSelection], shouldMute: Bool) throws {
        self.applications = AISourceCatalog.normalized(applications)
        self.shouldMute = shouldMute
        if shouldMute {
            startRefreshLoop()
            try refreshTargets()
        } else {
            refreshTask?.cancel()
            refreshTask = nil
            teardown()
        }
    }

    private func startRefreshLoop() {
        guard refreshTask == nil else { return }
        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard let self, self.shouldMute else { return }
                do { try self.refreshTargets() }
                catch { NSLog("Oreja: could not refresh muted app processes: %@", error.localizedDescription) }
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
        guard processIDs != tappedProcessIDs else { return }
        teardown()
        guard !processIDs.isEmpty else { return }

        let newTap = TargetProcessMuteTap()
        try newTap.start(processIDs: processIDs)
        tap = newTap
        tappedProcessIDs = processIDs
    }

    private func teardown() {
        tap?.stop()
        tap = nil
        tappedProcessIDs = []
    }
}

/// Owns Core Audio objects without actor isolation. In particular, the IOProc callback below runs
/// on Core Audio's real-time thread and must not inherit MainActor from a UI-facing caller.
@available(macOS 14.2, *)
private final class TargetProcessMuteTap: @unchecked Sendable {
    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateDeviceID = AudioObjectID(kAudioObjectUnknown)
    private var ioProcID: AudioDeviceIOProcID?

    func start(processIDs: [AudioObjectID]) throws {
        let description = CATapDescription(monoMixdownOfProcesses: processIDs)
        description.name = "Oreja — secondary audio"
        description.uuid = UUID()
        description.isPrivate = true
        description.muteBehavior = CATapMuteBehavior(rawValue: 1)!

        var tap = AudioObjectID(kAudioObjectUnknown)
        let tapStatus = AudioHardwareCreateProcessTap(description, &tap)
        guard tapStatus == noErr, tap != AudioObjectID(kAudioObjectUnknown) else {
            throw AudioMonitoringFailure(.tapCreationFailed, "Could not mute the selected app audio (OSStatus \(tapStatus)).")
        }
        tapID = tap

        let aggregateDescription: [String: Any] = [
            kAudioAggregateDeviceNameKey: "Oreja Secondary Audio",
            kAudioAggregateDeviceUIDKey: "com.oreja.target.\(UUID().uuidString)",
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: false,
            kAudioAggregateDeviceTapListKey: [[
                kAudioSubTapUIDKey: description.uuid.uuidString,
                kAudioSubTapDriftCompensationKey: true,
            ]],
        ]
        var aggregate = AudioObjectID(kAudioObjectUnknown)
        let aggregateStatus = AudioHardwareCreateAggregateDevice(aggregateDescription as CFDictionary, &aggregate)
        guard aggregateStatus == noErr, aggregate != AudioObjectID(kAudioObjectUnknown) else {
            stop()
            throw AudioMonitoringFailure(.deviceSetupFailed, "Could not activate target-app muting (OSStatus \(aggregateStatus)).")
        }
        aggregateDeviceID = aggregate

        var procID: AudioDeviceIOProcID?
        let procStatus = AudioDeviceCreateIOProcIDWithBlock(&procID, aggregate, nil) { _, _, _, _, _ in
            // Discard immediately. The secondary tap exists only to apply mute behavior.
        }
        guard procStatus == noErr, let procID else {
            stop()
            throw AudioMonitoringFailure(.deviceSetupFailed, "Could not start target-app muting (OSStatus \(procStatus)).")
        }
        ioProcID = procID
        let startStatus = AudioDeviceStart(aggregate, procID)
        guard startStatus == noErr else {
            stop()
            throw AudioMonitoringFailure(.deviceSetupFailed, "Could not start target-app muting (OSStatus \(startStatus)).")
        }
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
    }

    deinit {
        stop()
    }
}
