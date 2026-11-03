import Foundation

/// How loud a source has to be before Oreja treats it as speech.
///
/// This is the one detection control that maps to something a person can actually hear. The
/// numbers behind each case live in `OrejaAudio`, because they are platform detector thresholds;
/// settings only store the intent, so the mapping can be tuned without migrating anyone's data.
public enum DetectionSensitivity: String, Codable, Sendable, CaseIterable {
    /// Picks up quiet speech and soft laptop speakers. Can be triggered by a noisy room.
    case high
    /// The default: calibrated against ordinary spoken replies.
    case normal
    /// Only clearly loud speech counts. Use when a hissing or humming source keeps waking Oreja.
    case low

    public var title: String {
        switch self {
        case .high: "High"
        case .normal: "Normal"
        case .low: "Low"
        }
    }

    public var detail: String {
        switch self {
        case .high: "Catches quiet speech and small laptop speakers. A noisy room can trigger it."
        case .normal: "Works for ordinary spoken replies at a comfortable volume."
        case .low: "Only clearly loud speech counts. Use it when a hissing source keeps reacting."
        }
    }
}

/// What the platform monitor should do for this source. Passed to the factory instead of a list of
/// booleans, so adding a detection option later does not change the port again.
public struct AudioMonitorOptions: Sendable, Equatable {
    public var sensitivity: DetectionSensitivity
    /// Ask the speech-shape filter to drop brief, steady or single-decay bursts.
    public var ignoresNotificationSounds: Bool

    public init(
        sensitivity: DetectionSensitivity = .normal,
        ignoresNotificationSounds: Bool = true
    ) {
        self.sensitivity = sensitivity
        self.ignoresNotificationSounds = ignoresNotificationSounds
    }
}
