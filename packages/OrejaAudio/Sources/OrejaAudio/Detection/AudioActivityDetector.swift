import Foundation
import OrejaCore

/// Lightweight activity analysis over dBFS levels.
///
/// This is deliberately *not* a speech recognizer: it reports "the monitored application is
/// producing audio" with hysteresis and debouncing. Notifications or sound effects produced by
/// the monitored application can therefore trigger activity, which is documented product behavior.
public enum AudioActivityTransition: Sendable, Equatable {
    case started
    case ended
}

public struct AudioActivityDetector: Sendable, Equatable {
    public struct Configuration: Sendable, Equatable {
        /// Level that starts an activity window.
        public var activationThresholdDB: Double
        /// Lower level that must be reached before silence can end the activity window.
        public var deactivationThresholdDB: Double
        /// Audio must stay above the activation threshold this long to count as activity.
        public var minimumActivityDuration: TimeInterval
        /// Audio must stay below the deactivation threshold this long to count as silence.
        public var minimumSilenceDuration: TimeInterval
        /// Floor applied to digital silence, to keep dBFS finite.
        public var silenceFloorDB: Double

        public init(
            activationThresholdDB: Double = -45,
            deactivationThresholdDB: Double = -55,
            minimumActivityDuration: TimeInterval = 0.06,
            minimumSilenceDuration: TimeInterval = 0.25,
            silenceFloorDB: Double = -100
        ) {
            self.activationThresholdDB = activationThresholdDB
            self.deactivationThresholdDB = min(deactivationThresholdDB, activationThresholdDB)
            self.minimumActivityDuration = max(0, minimumActivityDuration)
            self.minimumSilenceDuration = max(0, minimumSilenceDuration)
            self.silenceFloorDB = silenceFloorDB
        }
    }

    public private(set) var isActive = false
    public private(set) var lastLevelDB: Double = -100
    public var configuration: Configuration

    private var loudSince: TimeInterval?
    private var quietSince: TimeInterval?

    public init(configuration: Configuration = Configuration()) {
        self.configuration = configuration
    }

    /// Feeds one analysis frame. Returns a transition only when the debounced state changes.
    public mutating func ingest(levelDB: Double, at time: TimeInterval) -> AudioActivityTransition? {
        let level = levelDB.isFinite ? max(configuration.silenceFloorDB, min(0, levelDB)) : configuration.silenceFloorDB
        lastLevelDB = level

        if isActive {
            if level <= configuration.deactivationThresholdDB {
                if let quietSince {
                    if time - quietSince >= configuration.minimumSilenceDuration {
                        isActive = false
                        self.quietSince = nil
                        loudSince = nil
                        return .ended
                    }
                } else {
                    quietSince = time
                }
            } else {
                quietSince = nil
            }
            return nil
        }

        if level >= configuration.activationThresholdDB {
            if let loudSince {
                if time - loudSince >= configuration.minimumActivityDuration {
                    isActive = true
                    self.loudSince = nil
                    quietSince = nil
                    return .started
                }
            } else {
                loudSince = time
            }
        } else {
            loudSince = nil
        }
        return nil
    }

    public mutating func reset() {
        isActive = false
        loudSince = nil
        quietSince = nil
        lastLevelDB = configuration.silenceFloorDB
    }
}

extension AudioActivityDetector.Configuration {
    /// Maps the user-facing sensitivity onto thresholds for the selected app's output.
    ///
    /// Deactivation stays 10 dB below activation: that gap is the hysteresis that keeps a sentence
    /// from ending between words, so it must not scale with sensitivity.
    public static func forAI(_ sensitivity: DetectionSensitivity) -> AudioActivityDetector.Configuration {
        let activation: Double
        switch sensitivity {
        case .high: activation = -55
        case .normal: activation = -45
        case .low: activation = -35
        }
        return AudioActivityDetector.Configuration(
            activationThresholdDB: activation,
            deactivationThresholdDB: activation - 10,
            minimumActivityDuration: 0.06,
            minimumSilenceDuration: 0.25
        )
    }

    /// The microphone hears room noise, keyboard clicks and fans, so it starts higher than the
    /// output detector and needs a slightly longer onset to count.
    public static func forMicrophone(_ sensitivity: DetectionSensitivity) -> AudioActivityDetector.Configuration {
        let activation: Double
        switch sensitivity {
        // Measured on the built-in mic: room noise median about -46 dBFS (90th percentile -42),
        // ordinary speech median about -26 dBFS. Normal sits between them.
        case .high: activation = -42
        case .normal: activation = -35
        case .low: activation = -28
        }
        return AudioActivityDetector.Configuration(
            activationThresholdDB: activation,
            deactivationThresholdDB: activation - 10,
            minimumActivityDuration: 0.12,
            minimumSilenceDuration: 0.35
        )
    }
}

public enum AudioMath {
    /// Converts a mean-square amplitude (0...1) to dBFS.
    public static func decibels(fromMeanSquare meanSquare: Double, floor: Double = -100) -> Double {
        guard meanSquare.isFinite, meanSquare > 0 else { return floor }
        let db = 10 * log10(meanSquare)
        guard db.isFinite else { return floor }
        return max(floor, min(0, db))
    }
}
