import CoreAudio
import Foundation

/// One audio input device as the microphone monitor sees it.
public struct InputDeviceCandidate: Sendable, Equatable {
    public let id: AudioDeviceID
    public let transport: UInt32
    public let hasInput: Bool

    public init(id: AudioDeviceID, transport: UInt32, hasInput: Bool) {
        self.id = id
        self.transport = transport
        self.hasInput = hasInput
    }
}

/// Chooses which microphone the voice monitor listens to.
///
/// Opening a Bluetooth headset microphone switches the headset into call mode, which lowers the
/// quality of the music playing through it. So:
/// - when another app already has a microphone open (a ChatGPT voice session, a call), the headset
///   is in call mode anyway and the person is speaking into it: listen to the default input;
/// - otherwise listen to the built-in microphone, so Oreja never degrades the music by itself.
/// The choice is a pure function so it can be tested without hardware; `AppModel` re-checks it
/// every few seconds and moves the monitor when it changes.
public enum InputDeviceSelection {
    /// The built-in microphone when the default input is wireless and nobody else is recording;
    /// `nil` keeps the system default input.
    public static func preferredInput(
        defaultInput: InputDeviceCandidate?,
        devices: [InputDeviceCandidate],
        anotherAppIsRecording: Bool
    ) -> AudioDeviceID? {
        guard let defaultInput, defaultInput.hasInput, isWireless(defaultInput.transport) else {
            return nil
        }
        guard !anotherAppIsRecording else { return nil }
        return devices.first { $0.hasInput && $0.transport == kAudioDeviceTransportTypeBuiltIn }?.id
    }

    /// Reads the live Core Audio state and applies `preferredInput`.
    @available(macOS 14.2, *)
    public static func preferredInputForMonitoring() -> AudioDeviceID? {
        let devices = allInputCandidates()
        let defaultID = systemDeviceID(kAudioHardwarePropertyDefaultInputDevice)
        let defaultInput = devices.first { $0.id == defaultID }
        return preferredInput(
            defaultInput: defaultInput,
            devices: devices,
            anotherAppIsRecording: AudioProcessCatalog.anotherProcessIsRecording()
        )
    }

    /// The device the monitor will actually capture from: the preferred one, or the default input.
    @available(macOS 14.2, *)
    public static func effectiveInputForMonitoring() -> AudioDeviceID {
        preferredInputForMonitoring() ?? systemDeviceID(kAudioHardwarePropertyDefaultInputDevice)
    }

    /// The device's name as macOS shows it, for the status line and the log.
    public static func name(of device: AudioDeviceID) -> String? {
        var name: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioObjectPropertyName,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &name) == noErr,
              let value = name?.takeRetainedValue() else { return nil }
        return value as String
    }

    private static func isWireless(_ transport: UInt32) -> Bool {
        transport == kAudioDeviceTransportTypeBluetooth
            || transport == kAudioDeviceTransportTypeBluetoothLE
    }

    private static func systemDeviceID(_ selector: AudioObjectPropertySelector) -> AudioDeviceID {
        var deviceID = AudioDeviceID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &deviceID
        ) == noErr else {
            return AudioDeviceID(kAudioObjectUnknown)
        }
        return deviceID
    }

    private static func allInputCandidates() -> [InputDeviceCandidate] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &dataSize
        ) == noErr else {
            return []
        }
        let count = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        var ids = [AudioDeviceID](repeating: AudioDeviceID(kAudioObjectUnknown), count: count)
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &dataSize, &ids
        ) == noErr else {
            return []
        }
        return ids.map { id in
            InputDeviceCandidate(id: id, transport: transportType(id), hasInput: hasInputStreams(id))
        }
    }

    private static func transportType(_ id: AudioDeviceID) -> UInt32 {
        var transport: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyTransportType,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &transport) == noErr else {
            return 0
        }
        return transport
    }

    private static func hasInputStreams(_ id: AudioDeviceID) -> Bool {
        var dataSize: UInt32 = 0
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreams,
            mScope: kAudioObjectPropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectGetPropertyDataSize(id, &address, 0, nil, &dataSize) == noErr else {
            return false
        }
        return dataSize > 0
    }
}
