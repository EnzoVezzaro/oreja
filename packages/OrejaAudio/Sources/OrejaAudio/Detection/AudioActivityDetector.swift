import Foundation

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

public enum AudioMath {
    /// Converts a mean-square amplitude (0...1) to dBFS.
    public static func decibels(fromMeanSquare meanSquare: Double, floor: Double = -100) -> Double {
        guard meanSquare.isFinite, meanSquare > 0 else { return floor }
        let db = 10 * log10(meanSquare)
        guard db.isFinite else { return floor }
        return max(floor, min(0, db))
    }
}
