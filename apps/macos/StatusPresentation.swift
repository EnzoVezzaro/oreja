import SwiftUI
import OrejaCore

/// Presentation of the coordinator's single source of truth.
///
/// Every surface (menu bar label, menu bar panel, onboarding check) reads these properties so the
/// app never shows two different stories about what Oreja is doing.
extension CoordinatorState {
    var title: String {
        switch self {
        case .disabled: "Automation off"
        case .searchingForSource: "Looking for the AI source"
        case .monitoring: "Monitoring ChatGPT"
        case .musicPlaying: "Music playing"
        case .aiActive: "ChatGPT is speaking"
        case .musicPausedByOreja: "Music paused by Oreja"
        case .waitingForSilence: "Waiting for silence"
        case .restoringPlayback: "Resuming music"
        case .suspended: "Suspended"
        case .permissionRequired: "Permission required"
        case .error: "Needs attention"
        }
    }

    var detail: String {
        switch self {
        case .disabled: "Turn automation on to coordinate music with ChatGPT."
        case .searchingForSource: "Open ChatGPT and start a voice session."
        case .monitoring: "Listening for AI output. Music is left alone until ChatGPT speaks."
        case .musicPlaying: "ChatGPT is quiet; your music is playing."
        case .aiActive: "Oreja is holding playback so the response stays clear."
        case .musicPausedByOreja: "Paused because ChatGPT is speaking. It will resume after the quiet interval."
        case .waitingForSilence: "Counting the quiet interval before music resumes."
        case .restoringPlayback: "Handing playback back to your music."
        case .suspended: "The Mac went to sleep; Oreja will reconcile playback on wake."
        case .permissionRequired: "Oreja needs a macOS permission to keep working."
        case .error: "Automation paused itself. Open diagnostics for the reason."
        }
    }

    /// Menu bar glyph. Small, state-only changes; no animation, no distraction.
    var menuBarSymbol: String {
        switch self {
        case .disabled: "ear.slash"
        case .searchingForSource: "ear.badge.questionmark"
        case .monitoring: "ear"
        case .musicPlaying: "music.note"
        case .aiActive: "waveform"
        case .musicPausedByOreja: "pause.circle"
        case .waitingForSilence: "hourglass"
        case .restoringPlayback: "play.circle"
        case .suspended: "moon.zzz"
        case .permissionRequired: "lock.trianglebadge.exclamationmark"
        case .error: "exclamationmark.triangle"
        }
    }

    var tint: Color {
        switch self {
        case .aiActive, .musicPausedByOreja: OrejaTheme.Palette.accent
        case .waitingForSilence, .restoringPlayback: OrejaTheme.Palette.wheat
        case .permissionRequired, .error: OrejaTheme.Palette.warning
        case .disabled, .suspended, .searchingForSource: OrejaTheme.Palette.inkSoft
        case .monitoring, .musicPlaying: OrejaTheme.Palette.positive
        }
    }

    /// Whether the dot should carry a quiet ring: speaking, holding a pause, or handing back.
    var isActive: Bool {
        switch self {
        case .aiActive, .musicPausedByOreja, .waitingForSilence, .restoringPlayback: true
        default: false
        }
    }

    /// Only these states mean "a pause is currently held by Oreja".
    var holdsPause: Bool {
        self == .musicPausedByOreja || self == .waitingForSilence
    }
}

/// One line of the onboarding / troubleshooting check.
struct CheckStep: Identifiable, Equatable {
    enum Status: Equatable {
        case pending
        case running
        case passed(String)
        case failed(String)
        case skipped(String)
    }

    var id: String { title }
    var title: String
    var status: Status

    var symbol: String {
        switch status {
        case .pending: "circle.dotted"
        case .running: "circle.dotted"
        case .passed: "checkmark.circle.fill"
        case .failed: "xmark.circle.fill"
        case .skipped: "minus.circle"
        }
    }

    var message: String {
        switch status {
        case .pending: "Not checked yet."
        case .running: "Checking…"
        case .passed(let text), .failed(let text), .skipped(let text): text
        }
    }

    var isFailure: Bool {
        if case .failed = status { return true }
        return false
    }
}

struct ConnectionCheckReport: Equatable {
    var steps: [CheckStep]
    var startedAt: Date

    var allPassed: Bool { !steps.isEmpty && steps.allSatisfy { !$0.isFailure } }
    var hasFailure: Bool { steps.contains { $0.isFailure } }
}
