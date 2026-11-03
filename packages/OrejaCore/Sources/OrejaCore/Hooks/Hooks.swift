import Foundation

/// Everything Oreja can tell the outside world about itself. A hook subscribes to one of these
/// events and runs one action when it happens.
///
/// The vocabulary is deliberately about *Oreja's own decisions*, not about conversation content:
/// there is no "the AI said this" event, because nothing is transcribed. An event carries a short
/// human-readable detail ("ChatGPT started speaking", "Music paused by Oreja") and nothing else.
public enum OrejaEvent: String, Codable, CaseIterable, Sendable {
    case speechStarted
    case speechEnded
    case soundIgnored
    case musicPaused
    case musicResumed
    case volumeLowered
    case volumeRestored
    case monitoringStarted
    case monitoringFailed
    case permissionRequired
    case sleep
    case wake

    public var title: String {
        switch self {
        case .speechStarted: "The AI starts speaking"
        case .speechEnded: "The AI stops speaking"
        case .soundIgnored: "A notification sound is ignored"
        case .musicPaused: "Music is paused"
        case .musicResumed: "Music is resumed"
        case .volumeLowered: "Music volume is lowered"
        case .volumeRestored: "Music volume is restored"
        case .monitoringStarted: "Listening starts"
        case .monitoringFailed: "Listening fails"
        case .permissionRequired: "A permission is missing"
        case .sleep: "The Mac goes to sleep"
        case .wake: "The Mac wakes up"
        }
    }

    /// Grouping for the picker, so a dozen events stay scannable.
    public var group: String {
        switch self {
        case .speechStarted, .speechEnded, .soundIgnored: "Conversation"
        case .musicPaused, .musicResumed, .volumeLowered, .volumeRestored: "Music"
        case .monitoringStarted, .monitoringFailed, .permissionRequired: "Listening"
        case .sleep, .wake: "System"
        }
    }
}

/// What a hook does when it fires.
///
/// Shortcuts and URLs cover the whole local automation surface — a shortcut can send a
/// notification, run a script, control HomeKit, or write a file — so Oreja does not need to embed a
/// shell, a scripting language, or any network client of its own.
public enum HookAction: Codable, Sendable, Equatable {
    /// `shortcuts run "<name>"` with the event provided as input text.
    case runShortcut(name: String)
    /// Opens a URL with the default handler (`shortcuts://run-shortcut?name=…`, an app link, a page).
    case openURL(String)

    public var kindTitle: String {
        switch self {
        case .runShortcut: "Run a Shortcut"
        case .openURL: "Open a URL"
        }
    }

    public var value: String {
        switch self {
        case .runShortcut(let name): name
        case .openURL(let url): url
        }
    }
}

/// One user-authored rule: *when this happens, do that*.
public struct Hook: Codable, Identifiable, Sendable, Equatable {
    public var id: UUID
    public var name: String
    public var event: OrejaEvent
    public var action: HookAction
    public var isEnabled: Bool
    /// Minimum gap between two runs of this hook, so a rapid exchange cannot spawn a burst of
    /// shortcuts. Filtering happens here rather than in the UI, so it also protects programmatic
    /// settings edits.
    public var cooldown: TimeInterval

    public init(
        id: UUID = UUID(),
        name: String = "",
        event: OrejaEvent = .speechStarted,
        action: HookAction = .runShortcut(name: ""),
        isEnabled: Bool = true,
        cooldown: TimeInterval = 2
    ) {
        self.id = id
        self.name = name
        self.event = event
        self.action = action
        self.isEnabled = isEnabled
        self.cooldown = max(0, cooldown)
    }

    /// A hook with no action configured is a draft: it is kept, shown, and never fired, so a
    /// half-typed rule cannot run something unexpected.
    public var isRunnable: Bool {
        switch action {
        case .runShortcut(let name): !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .openURL(let url): URL(string: url)?.scheme != nil
        }
    }

    public var displayName: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? action.kindTitle : trimmed
    }
}

/// What a hook receives when it fires. No audio, no prompts, no replies: the event and a short
/// description of Oreja's own action.
public struct HookContext: Sendable, Equatable {
    public var event: OrejaEvent
    public var detail: String
    public var date: Date

    public init(event: OrejaEvent, detail: String, date: Date = Date()) {
        self.event = event
        self.detail = detail
        self.date = date
    }

    /// Single-line input for `shortcuts run`, so a shortcut can branch on what happened.
    public var summary: String {
        "\(event.rawValue): \(detail)"
    }
}

/// Platform port for running one action. Throwing is allowed and reported; nothing is retried
/// automatically, because a failing shortcut is usually a missing shortcut, not a transient error.
public protocol HookExecuting: Sendable {
    func execute(_ hook: Hook, context: HookContext) async throws
}

public struct HookExecutionError: Error, Sendable, Equatable, LocalizedError {
    public var message: String

    public init(_ message: String) {
        self.message = message
    }

    public var errorDescription: String? { message }
}

/// Filters the configured hooks for an event and runs them through the platform executor.
///
/// The dispatcher owns three safeguards so a hook cannot become a runaway loop: a per-hook
/// cooldown, a single in-flight run per hook, and a hard cap on how many hooks one event may fire.
@MainActor
public final class HookDispatcher {
    public static let maximumHooksPerEvent = 8

    private let hooks: () -> [Hook]
    private let executor: any HookExecuting
    private let diagnostics: DiagnosticsSink
    private let now: () -> TimeInterval
    private var lastRun: [UUID: TimeInterval] = [:]
    private var inFlight: Set<UUID> = []
    /// Exposed for tests and for the last-run time in the UI.
    public private(set) var runs = 0

    public init(
        hooks: @escaping () -> [Hook],
        executor: any HookExecuting,
        diagnostics: DiagnosticsSink,
        now: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }
    ) {
        self.hooks = hooks
        self.executor = executor
        self.diagnostics = diagnostics
        self.now = now
    }

    /// Fires every enabled hook bound to `context.event`.
    public func emit(_ context: HookContext) {
        let matching = hooks().filter { $0.isEnabled && $0.event == context.event }
        guard !matching.isEmpty else { return }
        for hook in matching.prefix(Self.maximumHooksPerEvent) {
            run(hook, context: context, isManual: false)
        }
    }

    /// Runs one hook regardless of its event or cooldown, so "Test" proves the action works.
    public func runManually(_ hook: Hook, detail: String? = nil) {
        run(
            hook,
            context: HookContext(event: hook.event, detail: detail ?? "Test run from Oreja settings"),
            isManual: true
        )
    }

    /// Runs one hook and waits for it. Used by the settings “Test” button, which should report what
    /// actually happened instead of claiming success.
    @discardableResult
    public func runAndWait(_ hook: Hook, detail: String? = nil) async -> Bool {
        let context = HookContext(event: hook.event, detail: detail ?? "Test run from Oreja settings")
        guard begin(hook, context: context, isManual: true) else { return false }
        return await perform(hook, context: context)
    }

    private func run(_ hook: Hook, context: HookContext, isManual: Bool) {
        guard begin(hook, context: context, isManual: isManual) else { return }
        Task { [weak self] in
            _ = await self?.perform(hook, context: context)
        }
    }

    /// Applies the guards and reserves the hook, so a burst of events cannot start it twice.
    private func begin(_ hook: Hook, context: HookContext, isManual: Bool) -> Bool {
        guard hook.isEnabled, hook.isRunnable else { return false }
        guard !inFlight.contains(hook.id) else {
            diagnostics.record(DiagnosticEvent(
                level: .debug,
                category: .hooks,
                message: "Skipped hook “\(hook.displayName)”: still running."
            ))
            return false
        }
        if !isManual, let last = lastRun[hook.id], now() - last < hook.cooldown {
            diagnostics.record(DiagnosticEvent(
                level: .debug,
                category: .hooks,
                message: "Skipped hook “\(hook.displayName)”: cooling down."
            ))
            return false
        }

        lastRun[hook.id] = now()
        inFlight.insert(hook.id)
        runs += 1
        return true
    }

    private func perform(_ hook: Hook, context: HookContext) async -> Bool {
        let name = hook.displayName
        let event = context.event
        var failure: String?
        do {
            try await executor.execute(hook, context: context)
        } catch {
            failure = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
        inFlight.remove(hook.id)
        if let failure {
            diagnostics.record(DiagnosticEvent(
                level: .warning,
                category: .hooks,
                message: "Hook “\(name)” failed on \(event.title): \(failure)"
            ))
            return false
        }
        diagnostics.record(DiagnosticEvent(
            level: .info,
            category: .hooks,
            message: "Hook “\(name)” ran on \(event.title)."
        ))
        return true
    }
}
