import Foundation

/// Combines the AI's output activity with optional user-speech activity into the single
/// "somebody is talking" signal the coordinator consumes.
///
/// In a spoken conversation the two alternate: ChatGPT finishes, the user answers, ChatGPT starts
/// again. Without this, music resumes the moment ChatGPT goes quiet, which is exactly when the user
/// starts talking. Merging both sources means music stays paused through a full exchange and only
/// returns once both sides have been quiet for the configured interval.
public struct ActivityAggregator: Sendable, Equatable {
    public enum Source: Sendable, Equatable {
        case ai
        case user
    }

    public private(set) var aiIsActive = false
    public private(set) var userIsActive = false

    public var isActive: Bool { aiIsActive || userIsActive }

    public init() {}

    /// Updates one source and reports whether the *combined* state changed, which is what the
    /// coordinator wants to hear about.
    public mutating func set(_ active: Bool, for source: Source) -> Bool {
        let previous = isActive
        switch source {
        case .ai: aiIsActive = active
        case .user: userIsActive = active
        }
        return isActive != previous
    }

    public mutating func reset() {
        aiIsActive = false
        userIsActive = false
    }
}
