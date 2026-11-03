import Foundation
import OrejaCore

/// Test double for hook actions. Runs on the caller's task, so the test can await the result and
/// then read what was executed.
final class RecordingHookExecutor: HookExecuting, @unchecked Sendable {
    private(set) var calls: [(hook: Hook, context: HookContext)] = []
    var failure: Error?

    func execute(_ hook: Hook, context: HookContext) async throws {
        calls.append((hook, context))
        if let failure { throw failure }
    }
}

@MainActor
func runHookSuite(_ t: Harness) async {
    print("\nHooks")

    func makeDispatcher(
        hooks: [Hook],
        executor: RecordingHookExecutor,
        diagnostics: RecordingDiagnostics,
        clock: MutableClock
    ) -> HookDispatcher {
        let clockValue = clock
        return HookDispatcher(
            hooks: { hooks },
            executor: executor,
            diagnostics: diagnostics,
            now: { clockValue.now }
        )
    }

    await t.runAsync("hook: only hooks bound to the event fire") {
        let executor = RecordingHookExecutor()
        let diagnostics = RecordingDiagnostics()
        let clock = MutableClock()
        let speech = Hook(name: "Speech", event: .speechStarted, action: .runShortcut(name: "Notify"), cooldown: 0)
        let music = Hook(name: "Music", event: .musicPaused, action: .runShortcut(name: "Duck"), cooldown: 0)
        let dispatcher = makeDispatcher(hooks: [speech, music], executor: executor, diagnostics: diagnostics, clock: clock)

        dispatcher.emit(HookContext(event: .speechStarted, detail: "The AI source started speaking"))
        // `emit` is fire-and-forget; give the dispatched run a moment to land.
        try? await Task.sleep(for: .milliseconds(100))

        t.expectEqual(executor.calls.count, 1, "only the hook bound to the event fired")
        t.expectEqual(executor.calls.first?.hook.name, "Speech")
        t.expectEqual(executor.calls.first?.context.event, .speechStarted)

        // “Test” runs a hook even though its event never happened.
        let ranManually = await dispatcher.runAndWait(music)
        t.expect(ranManually)
        t.expectEqual(executor.calls.count, 2)
        t.expectEqual(executor.calls.last?.hook.name, "Music")
    }

    await t.runAsync("hook: a disabled hook or a draft never runs") {
        let executor = RecordingHookExecutor()
        let diagnostics = RecordingDiagnostics()
        let clock = MutableClock()
        var disabled = Hook(name: "Off", event: .speechStarted, action: .runShortcut(name: "Notify"))
        disabled.isEnabled = false
        let draft = Hook(name: "Draft", event: .speechStarted, action: .runShortcut(name: "   "))
        let dispatcher = makeDispatcher(hooks: [disabled, draft], executor: executor, diagnostics: diagnostics, clock: clock)

        dispatcher.emit(HookContext(event: .speechStarted, detail: "speech"))
        let ranDraft = await dispatcher.runAndWait(draft)

        t.expectEqual(executor.calls.count, 0, "neither hook may run")
        t.expect(!ranDraft)
        t.expect(!draft.isRunnable, "an empty shortcut name is a draft")
    }

    await t.runAsync("hook: a cooldown stops a rapid exchange from flooding shortcuts") {
        let executor = RecordingHookExecutor()
        let diagnostics = RecordingDiagnostics()
        let clock = MutableClock()
        let hook = Hook(name: "Notify", event: .speechStarted, action: .runShortcut(name: "Notify"), cooldown: 2)
        let dispatcher = makeDispatcher(hooks: [hook], executor: executor, diagnostics: diagnostics, clock: clock)
        let context = HookContext(event: .speechStarted, detail: "speech")

        dispatcher.emit(context)
        try? await Task.sleep(for: .milliseconds(50))
        dispatcher.emit(context)
        try? await Task.sleep(for: .milliseconds(100))
        t.expectEqual(executor.calls.count, 1, "the second event is inside the cooldown")

        clock.advance(3)
        dispatcher.emit(context)
        try? await Task.sleep(for: .milliseconds(100))
        t.expectEqual(executor.calls.count, 2, "after the cooldown it runs again")
        t.expect(diagnostics.events.contains { $0.message.contains("cooling down") })
    }

    await t.runAsync("hook: a failing action is reported, not retried") {
        let executor = RecordingHookExecutor()
        executor.failure = HookExecutionError("Shortcut “Nope” does not exist")
        let diagnostics = RecordingDiagnostics()
        let clock = MutableClock()
        let hook = Hook(name: "Broken", event: .musicPaused, action: .runShortcut(name: "Nope"))
        let dispatcher = makeDispatcher(hooks: [hook], executor: executor, diagnostics: diagnostics, clock: clock)

        let succeeded = await dispatcher.runAndWait(hook)

        t.expect(!succeeded)
        t.expectEqual(executor.calls.count, 1, "a failure is not retried")
        t.expect(diagnostics.messages(level: .warning).contains { $0.contains("does not exist") })
    }

    await t.runAsync("hook: a URL action needs a scheme to be runnable") {
        t.expect(!Hook(event: .wake, action: .openURL("shortcuts")).isRunnable)
        t.expect(Hook(event: .wake, action: .openURL("shortcuts://run-shortcut?name=Morning")).isRunnable)
        t.expect(Hook(event: .wake, action: .openURL("https://example.com")).isRunnable)
    }

    await t.runAsync("hook: settings round-trip keeps hooks and tolerates their absence") {
        let hook = Hook(
            name: "Morning",
            event: .wake,
            action: .openURL("shortcuts://run-shortcut?name=Morning"),
            cooldown: 5
        )
        var settings = AppSettings()
        settings.hooks = [hook]
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        let data = try encoder.encode(settings)
        let decoded = try decoder.decode(AppSettings.self, from: data)
        t.expectEqual(decoded.hooks, [hook])

        // Settings written by a build without hooks must still load, with no hooks configured.
        var legacy = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        legacy.removeValue(forKey: "hooks")
        let legacyData = try JSONSerialization.data(withJSONObject: legacy)
        let legacySettings = try decoder.decode(AppSettings.self, from: legacyData)
        t.expect(legacySettings.hooks.isEmpty, "old settings load with no hooks")
    }

    await t.runAsync("hook: every event is addressable from the picker groups") {
        t.expectEqual(OrejaEvent.allCases.count, 12)
        let groups = Set(OrejaEvent.allCases.map(\.group))
        t.expectEqual(groups.count, 4, "Conversation, Music, Listening, System")
        t.expect(!OrejaEvent.allCases.contains { $0.title.isEmpty })
    }
}
