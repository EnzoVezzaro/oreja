import OrejaCore
import SwiftUI

/// One hook, edited in place. Every change commits immediately, like the rest of Settings: there is
/// no Save button here, and a half-typed hook stays a draft that cannot fire.
struct HookRow: View {
    var hook: Hook
    var onChange: (Hook) -> Void
    var onTest: () -> Void
    var onDelete: () -> Void

    @State private var isShowingDeleteConfirmation = false

    /// Typed selector for the action picker: comparing action titles would break the moment a title
    /// changes, and a hook's kind must switch without losing what the other kind had typed.
    private enum ActionKind: Hashable {
        case shortcut
        case url
    }

    private var actionKind: ActionKind {
        switch hook.action {
        case .runShortcut: .shortcut
        case .openURL: .url
        }
    }

    private var groupedEvents: [(String, [OrejaEvent])] {
        let groups = Dictionary(grouping: OrejaEvent.allCases, by: \.group)
        return groups.keys.sorted(by: Self.groupOrder).compactMap { key in
            groups[key].map { (key, $0) }
        }
    }

    private static func groupOrder(_ lhs: String, _ rhs: String) -> Bool {
        let order = ["Conversation", "Music", "Listening", "System"]
        return (order.firstIndex(of: lhs) ?? 99) < (order.firstIndex(of: rhs) ?? 99)
    }

    private func mutated(_ change: (inout Hook) -> Void) -> Hook {
        var copy = hook
        change(&copy)
        return copy
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Toggle("Enabled", isOn: Binding(
                    get: { hook.isEnabled },
                    set: { value in onChange(mutated { $0.isEnabled = value }) }
                ))
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.mini)
                .tint(OrejaTheme.Palette.accent)
                .accessibilityLabel("\(hook.displayName) enabled")

                TextField("Hook name", text: Binding(
                    get: { hook.name },
                    set: { value in onChange(mutated { $0.name = value }) }
                ))
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 12))

                Button {
                    isShowingDeleteConfirmation = true
                } label: {
                    Image(systemName: "minus.circle")
                }
                .buttonStyle(.plain)
                .foregroundStyle(OrejaTheme.Palette.inkSoft)
                .help("Remove this hook")
                .accessibilityLabel("Remove hook \(hook.displayName)")
                .confirmationDialog(
                    "Remove “\(hook.displayName)”?",
                    isPresented: $isShowingDeleteConfirmation
                ) {
                    Button("Remove hook", role: .destructive) { onDelete() }
                    Button("Keep it", role: .cancel) {}
                } message: {
                    Text("The shortcut or URL itself is not deleted.")
                }
            }

            HStack(spacing: 10) {
                Text("When")
                    .font(.system(size: 11))
                    .foregroundStyle(OrejaTheme.Palette.inkSoft)
                    .frame(width: 38, alignment: .leading)

                Picker("Event", selection: Binding(
                    get: { hook.event },
                    set: { value in onChange(mutated { $0.event = value }) }
                )) {
                    ForEach(groupedEvents, id: \.0) { group, events in
                        Section(group) {
                            ForEach(events, id: \.self) { event in
                                Text(event.title).tag(event)
                            }
                        }
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(maxWidth: 260, alignment: .leading)

                Spacer(minLength: 8)

                Picker("Action", selection: Binding(
                    get: { actionKind },
                    set: { kind in
                        guard kind != actionKind else { return }
                        onChange(mutated { hook in
                            switch kind {
                            case .shortcut: hook.action = .runShortcut(name: "")
                            case .url: hook.action = .openURL("")
                            }
                        })
                    }
                )) {
                    Text(HookAction.runShortcut(name: "").kindTitle).tag(ActionKind.shortcut)
                    Text(HookAction.openURL("").kindTitle).tag(ActionKind.url)
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(maxWidth: 180, alignment: .trailing)
            }

            HStack(spacing: 10) {
                TextField(
                    actionKind == .shortcut
                        ? "Shortcut name, exactly as it appears in Shortcuts"
                        : "https:// or shortcuts://…",
                    text: Binding(
                        get: { hook.action.value },
                        set: { value in
                            onChange(mutated {
                                switch $0.action {
                                case .runShortcut: $0.action = .runShortcut(name: value)
                                case .openURL: $0.action = .openURL(value)
                                }
                            })
                        }
                    )
                )
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 12))

                Button("Test") { onTest() }
                    .controlSize(.small)
                    .disabled(!hook.isRunnable || !hook.isEnabled)
                    .help(hook.isRunnable ? "Run this hook now" : "Add a shortcut name or a URL first")
            }
        }
        .padding(.vertical, 2)
    }
}
