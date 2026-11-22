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
        /// "Test interruption" in Settings: a short, user-requested run of the configured
        /// interruption, so a setup can be checked without waiting for an assistant to speak.
        case preview
    }

    public private(set) var aiIsActive = false
    public private(set) var userIsActive = false
    public private(set) var previewIsActive = false

    public var isActive: Bool { aiIsActive || userIsActive || previewIsActive }

    public init() {}

    /// Updates one source and reports whether the *combined* state changed, which is what the
    /// coordinator wants to hear about.
    public mutating func set(_ active: Bool, for source: Source) -> Bool {
        let previous = isActive
        switch source {
        case .ai: aiIsActive = active
        case .user: userIsActive = active
        case .preview: previewIsActive = active
        }
        return isActive != previous
    }

    public mutating func reset() {
        aiIsActive = false
        userIsActive = false
        previewIsActive = false
    }
}

extension ActivityAggregator {
    /// Who is speaking right now, in plain words, or nil when nobody is.
    ///
    /// `sourceNames` are the apps Oreja listens to. Their audio is measured together, so with more
    /// than one selected app Oreja cannot tell which of them spoke and says "a selected app".
    public func speakerTitle(sourceNames: [String]) -> String? {
        let source = sourceNames.count == 1 ? sourceNames[0] : "a selected app"
        switch (aiIsActive, userIsActive) {
        case (true, true):
            return "You and \(source) are speaking"
        case (true, false):
            return "\(source.prefix(1).uppercased())\(source.dropFirst()) is speaking"
        case (false, true):
            return "You are speaking"
        case (false, false):
            // A test run has no speaker; the status falls back to what Oreja is doing.
            return nil
        }
    }
}
