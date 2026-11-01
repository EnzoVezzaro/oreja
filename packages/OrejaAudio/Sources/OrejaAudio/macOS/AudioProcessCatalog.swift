import CoreAudio
import Foundation
import OrejaCore

/// Reads the Core Audio process objects, which are what a process tap targets.
@available(macOS 14.2, *)
public enum AudioProcessCatalog {
    public struct AudioProcess: Sendable, Identifiable, Equatable {
        public var objectID: AudioObjectID
        public var pid: pid_t
        public var bundleID: String?
        public var isRunningOutput: Bool

        public var id: AudioObjectID { objectID }
    }

    public static func allProcesses() throws -> [AudioProcess] {
        let objectIDs = try processObjectIDs()
        return objectIDs.compactMap { objectID in
            guard let pid = try? readPID(objectID) else { return nil }
            let bundleID = try? readBundleID(objectID)
            let isRunning = (try? readRunningOutput(objectID)) ?? false
            return AudioProcess(objectID: objectID, pid: pid, bundleID: bundleID, isRunningOutput: isRunning)
        }
    }

    /// Processes whose bundle identifier starts with any of the given prefixes. Helper processes
    /// of the same application (which may be the ones actually rendering audio) are included.
    public static func processes(matchingPrefixes prefixes: [String]) throws -> [AudioProcess] {
        let cleaned = prefixes.filter { !$0.isEmpty }
        guard !cleaned.isEmpty else { return [] }
        return try allProcesses().filter { process in
            guard let bundleID = process.bundleID else { return false }
            return cleaned.contains { bundleID.hasPrefix($0) || bundleID == $0 }
        }
    }

    private static func processObjectIDs() throws -> [AudioObjectID] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyProcessObjectList,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        var status = AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size)
        guard status == noErr else {
            throw AudioMonitoringFailure(.unknown, "Could not list audio processes (OSStatus \(status)).")
        }
        let count = Int(size) / MemoryLayout<AudioObjectID>.size
        guard count > 0 else { return [] }
        var objectIDs = [AudioObjectID](repeating: 0, count: count)
        status = objectIDs.withUnsafeMutableBufferPointer { buffer in
            guard let baseAddress = buffer.baseAddress else { return OSStatus(kAudioHardwareBadObjectError) }
            return AudioObjectGetPropertyData(
                AudioObjectID(kAudioObjectSystemObject),
                &address,
                0,
                nil,
                &size,
                baseAddress
            )
        }
        guard status == noErr else {
            throw AudioMonitoringFailure(.unknown, "Could not read audio processes (OSStatus \(status)).")
        }
        return Array(objectIDs.prefix(Int(size) / MemoryLayout<AudioObjectID>.size))
    }

    private static func readPID(_ objectID: AudioObjectID) throws -> pid_t {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioProcessPropertyPID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var pid: pid_t = 0
        var size = UInt32(MemoryLayout<pid_t>.size)
        let status = withUnsafeMutablePointer(to: &pid) { pointer in
            AudioObjectGetPropertyData(objectID, &address, 0, nil, &size, pointer)
        }
        guard status == noErr else {
            throw AudioMonitoringFailure(.unknown, "Could not read process pid (OSStatus \(status)).")
        }
        return pid
    }

    private static func readBundleID(_ objectID: AudioObjectID) throws -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioProcessPropertyBundleID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var bundleID: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let status = withUnsafeMutablePointer(to: &bundleID) { pointer in
            AudioObjectGetPropertyData(objectID, &address, 0, nil, &size, pointer)
        }
        guard status == noErr, let bundleID else { return nil }
        return bundleID.takeRetainedValue() as String
    }

    private static func readRunningOutput(_ objectID: AudioObjectID) throws -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioProcessPropertyIsRunningOutput,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        let status = withUnsafeMutablePointer(to: &value) { pointer in
            AudioObjectGetPropertyData(objectID, &address, 0, nil, &size, pointer)
        }
        guard status == noErr else {
            throw AudioMonitoringFailure(.unknown, "Could not read process output state (OSStatus \(status)).")
        }
        return value != 0
    }
}
