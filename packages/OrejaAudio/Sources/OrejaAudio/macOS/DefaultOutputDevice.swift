import CoreAudio
import Foundation

/// Reads the system default output device. Used to decide whether the microphone may start an
/// interruption on its own: built-in speakers play Music back into the microphone.
public enum DefaultOutputDevice {
    /// True when the default output uses a built-in transport (the MacBook speakers). Bluetooth,
    /// USB, HDMI and AirPlay outputs return false. Unknown devices are treated as not built-in.
    public static func isBuiltInSpeakers() -> Bool {
        var deviceID = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &deviceID
        ) == noErr, deviceID != AudioObjectID(kAudioObjectUnknown) else {
            return false
        }

        var transport: UInt32 = 0
        size = UInt32(MemoryLayout<UInt32>.size)
        address.mSelector = kAudioDevicePropertyTransportType
        guard AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &transport) == noErr else {
            return false
        }
        return transport == kAudioDeviceTransportTypeBuiltIn
    }

    /// The UID of the default output device, used to play a lowered app's audio to the same place
    /// it was going. Nil when the device cannot be read.
    public static func uid() -> String? {
        var deviceID = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &deviceID
        ) == noErr, deviceID != AudioObjectID(kAudioObjectUnknown) else {
            return nil
        }

        var uid: Unmanaged<CFString>?
        size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        address.mSelector = kAudioDevicePropertyDeviceUID
        guard AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &uid) == noErr,
              let value = uid?.takeRetainedValue() else {
            return nil
        }
        return value as String
    }
}
