import SwiftUI
import OrejaCore

/// Settings, grouped the same way as the setup flow. Native controls, brand spacing, no form
/// chrome: the window should read as five short answers, not a control panel.
struct SettingsView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                header
                behavior
                source
                detection
                music
                hooks
                startup
                privacy
                permissions
                versionFooter
            }
            .frame(maxWidth: 500, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.horizontal, 28)
            .padding(.top, 24)
            .padding(.bottom, 28)
        }
        .background(OrejaTheme.Palette.paper)
        .tint(OrejaTheme.Palette.accent)
        .frame(minWidth: 560, minHeight: 560)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 20) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 14) {
                    BrandMark(size: 36)
                    BrandWordmark(size: 23)
                }
                Text("Settings")
                    .font(OrejaTheme.Typography.pageTitle)
                    .foregroundStyle(OrejaTheme.Palette.ink)
                Text("Oreja only touches playback while the selected AI source is speaking.")
                    .font(OrejaTheme.Typography.caption)
                    .foregroundStyle(OrejaTheme.Palette.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            VincentCompanion(size: 80, isListening: model.state.isActive, isMusicPlaying: model.music?.isPlaying == true)
        }
    }

    /// Where someone looks once the settings are set: what this build is, what changed, and the
    /// source. Both links are the same repository, so they stay correct when the app moves.
    private var versionFooter: some View {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        return VStack(alignment: .leading, spacing: 14) {
            Hairline()
            HStack(spacing: 8) {
                Text("Version \(version ?? "Development")")
                    .foregroundStyle(OrejaTheme.Palette.inkSoft)
                Spacer(minLength: 12)
                footerLink(
                    "GitHub",
                    symbol: "chevron.left.forwardslash.chevron.right",
                    url: Self.repositoryURL,
                    help: "github.com/EnzoVezzaro/oreja",
                    label: "Oreja de Van Gogh on GitHub"
                )
                Text("·")
                    .foregroundStyle(OrejaTheme.Palette.inkSoft)
                footerLink(
                    "Changelog",
                    symbol: "list.bullet.rectangle",
                    url: Self.changelogURL,
                    help: "What changed in each version",
                    label: "Changelog"
                )
            }
            .font(OrejaTheme.Typography.micro)
        }
        .padding(.top, 6)
    }

    /// Footer links are small by design, so they get a 24 pt target and an explicit label: at
    /// 11 pt the accent stays legible (5.5:1 on paper) but the word alone is a poor VoiceOver stop.
    private func footerLink(
        _ title: String,
        symbol: String,
        url: URL,
        help: String,
        label: String
    ) -> some View {
        Link(destination: url) {
            HStack(spacing: 4) {
                Image(systemName: symbol)
                    .imageScale(.small)
                Text(title)
            }
            .foregroundStyle(OrejaTheme.Palette.accent)
            .frame(minHeight: 24)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(label)
        .accessibilityHint("Opens in your browser")
    }

    private static let repositoryURL = URL(string: "https://github.com/EnzoVezzaro/oreja")!
    private static let changelogURL = URL(string: "https://github.com/EnzoVezzaro/oreja/blob/main/CHANGELOG.md")!

    // MARK: Sections

    private var behavior: some View {
        ThemeSection(title: "Behavior") {
            VStack(alignment: .leading, spacing: 14) {
                behaviorPreview

                Toggle("Automation enabled", isOn: Binding(
                    get: { model.settings.automationEnabled },
                    set: { model.setAutomationEnabled($0) }
                ))
                .toggleStyle(.switch)
                .tint(OrejaTheme.Palette.accent)
                .font(.system(size: 13))

                Text("When off, Oreja never touches playback.")
                    .font(OrejaTheme.Typography.micro)
                    .foregroundStyle(OrejaTheme.Palette.inkSoft)

                HStack {
                    Text("While ChatGPT speaks")
                        .font(.system(size: 13))
                        .foregroundStyle(OrejaTheme.Palette.ink)
                    Spacer(minLength: 8)
                    Picker("Playback behavior", selection: Binding(
                        get: { model.settings.interruptionMode },
                        set: { model.settings.interruptionMode = $0 }
                    )) {
                        Text("Pause music").tag(MusicInterruptionMode.pause)
                        Text("Lower volume").tag(MusicInterruptionMode.duck)
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                }

                if model.settings.interruptionMode == .duck {
                    HStack {
                        Text("Keep Music at")
                            .font(.system(size: 13))
                            .foregroundStyle(OrejaTheme.Palette.ink)
                        Spacer(minLength: 8)
                        Text("\(model.settings.duckVolumePercent)%")
                            .font(.system(size: 11, design: .monospaced))
                            .monospacedDigit()
                            .foregroundStyle(OrejaTheme.Palette.inkSoft)
                    }
                    Slider(
                        value: Binding(
                            get: { Double(model.settings.duckVolumePercent) },
                            set: { model.settings.duckVolumePercent = Int($0.rounded()) }
                        ),
                        in: 1...100,
                        step: 1
                    )
                    .tint(OrejaTheme.Palette.accent)
                    Text("Music lowers to this level while you speak and returns to the volume below when the conversation is quiet.")
                        .font(OrejaTheme.Typography.micro)
                        .foregroundStyle(OrejaTheme.Palette.inkSoft)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack {
                        Text("Return Music to")
                            .font(.system(size: 13))
                            .foregroundStyle(OrejaTheme.Palette.ink)
                        Spacer(minLength: 8)
                        Text("\(model.settings.restoreVolumePercent)%")
                            .font(.system(size: 11, design: .monospaced))
                            .monospacedDigit()
                            .foregroundStyle(OrejaTheme.Palette.inkSoft)
                    }
                    Slider(
                        value: Binding(
                            get: { Double(model.settings.restoreVolumePercent) },
                            set: { model.settings.restoreVolumePercent = Int($0.rounded()) }
                        ),
                        in: 1...100,
                        step: 1
                    )
                    .tint(OrejaTheme.Palette.accent)
                    Text("After the conversation is quiet, music automatically returns to this volume.")
                        .font(OrejaTheme.Typography.micro)
                        .foregroundStyle(OrejaTheme.Palette.inkSoft)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Hairline()
                    .padding(.vertical, 2)

                HStack {
                    Text("Quiet interval before music resumes")
                        .font(.system(size: 13))
                        .foregroundStyle(OrejaTheme.Palette.ink)
                    Spacer(minLength: 8)
                    Text("\(Int(model.settings.resumeDelay * 1000)) ms")
                        .font(.system(size: 11, design: .monospaced))
                        .monospacedDigit()
                        .foregroundStyle(OrejaTheme.Palette.inkSoft)
                }

                Slider(
                    value: Binding(
                        get: { model.settings.resumeDelay },
                        set: { model.settings.resumeDelay = $0 }
                    ),
                    in: AppSettings.resumeDelayRange,
                    step: 0.05
                )
                .tint(OrejaTheme.Palette.accent)

                Text("Longer values tolerate natural pauses between sentences; shorter values resume music faster. When the conversation hold above is on, that hold decides instead.")
                    .font(OrejaTheme.Typography.micro)
                    .foregroundStyle(OrejaTheme.Palette.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)

                Hairline()
                    .padding(.vertical, 2)

                Toggle("Keep music paused through a whole conversation", isOn: Binding(
                    get: { model.settings.holdThroughConversation },
                    set: { model.settings.holdThroughConversation = $0 }
                ))
                .toggleStyle(.switch)
                .tint(OrejaTheme.Palette.accent)
                .font(.system(size: 13))

                Text("In a spoken conversation most of the time nobody is talking: the assistant is working on the answer, you are answering it. With this on, music stays paused for the whole exchange and comes back only once the conversation has gone quiet.")
                    .font(OrejaTheme.Typography.micro)
                    .foregroundStyle(OrejaTheme.Palette.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)

                if model.settings.holdThroughConversation {
                    HStack {
                        Text("Music returns after")
                            .font(.system(size: 13))
                            .foregroundStyle(OrejaTheme.Palette.ink)
                        Spacer(minLength: 8)
                        Text(model.settings.conversationHold < 60
                            ? "\(Int(model.settings.conversationHold)) s"
                            : "\(Int(model.settings.conversationHold / 60)) min")
                            .font(.system(size: 11, design: .monospaced))
                            .monospacedDigit()
                            .foregroundStyle(OrejaTheme.Palette.inkSoft)
                    }

                    Slider(
                        value: Binding(
                            get: { model.settings.conversationHold },
                            set: { model.settings.conversationHold = $0 }
                        ),
                        in: AppSettings.conversationHoldRange,
                        step: 1
                    )
                    .tint(OrejaTheme.Palette.accent)

                    Text("Seconds of complete quiet that end the conversation. Raise it if music comes back while the assistant is still working on a long answer; lower it if you want music back sooner after a short question.")
                        .font(OrejaTheme.Typography.micro)
                        .foregroundStyle(OrejaTheme.Palette.inkSoft)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Hairline()
                    .padding(.vertical, 2)

                Toggle("Pause while I speak", isOn: Binding(
                    get: { model.settings.pauseWhileISpeak },
                    set: { model.settings.pauseWhileISpeak = $0 }
                ))
                .toggleStyle(.switch)
                .tint(OrejaTheme.Palette.accent)
                .font(.system(size: 13))

                Text("For spoken conversations: music also stays paused while you answer, not only while the assistant talks. Uses the microphone, which is a separate permission. The microphone can only keep a pause alive; the assistant's answer is what starts it, so a speaker playing music can never keep Oreja looping.")
                    .font(OrejaTheme.Typography.micro)
                    .foregroundStyle(OrejaTheme.Palette.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)

                if let error = model.userSpeechError {
                    InlineNotice(text: error, symbol: "mic.slash")
                }
            }
        }
    }

    private var behaviorPreview: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 14) {
                BrandMark(size: 32)
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 7) {
                        StatusDot(color: model.settings.automationEnabled ? OrejaTheme.Palette.wheat : OrejaTheme.Palette.inkSoft, isActive: model.settings.automationEnabled)
                        Text(model.settings.interruptionMode == .duck ? "Oreja makes room" : "Oreja pauses Music")
                            .font(OrejaTheme.Typography.sectionTitle)
                            .foregroundStyle(OrejaTheme.Palette.ink)
                    }
                    if model.settings.interruptionMode == .duck {
                        Text("Music \(model.settings.duckVolumePercent)% while AI speaks · \(model.settings.restoreVolumePercent)% when quiet")
                    } else {
                        Text("Music resumes after the conversation is quiet")
                    }
                }
                .font(OrejaTheme.Typography.caption)
                .foregroundStyle(OrejaTheme.Palette.inkSoft)
                Spacer(minLength: 0)
            }
        }
    }

    private var source: some View {
        ThemeSection(
            title: "Audio sources",
            caption: "Oreja listens to every app you select and pauses music when any of them speaks. It reads levels only. Browsers capture every tab, and notifications from a selected app can count as speech."
        ) {
            AudioSourcePicker(selected: model.settings.aiSources) { selection in
                model.toggleSource(selection)
            }
        }
    }

    /// The real detection controls: how loud the AI has to be, how loud you have to be, and whether
    /// notification-shaped bursts count at all. Everything here changes what the detectors hear, not
    /// just what the panel says.
    private var detection: some View {
        ThemeSection(
            title: "Detection",
            caption: "Oreja reads the audio itself, so there is no account and no network. These are the thresholds that decide when a sound counts as someone talking."
        ) {
            VStack(alignment: .leading, spacing: 14) {
                sensitivityRow(
                    title: "The AI's voice",
                    selection: Binding(
                        get: { model.settings.aiSensitivity },
                        set: { model.settings.aiSensitivity = $0 }
                    )
                )

                Hairline()

                Toggle("Ignore notification sounds", isOn: Binding(
                    get: { model.settings.ignoreNotificationSounds },
                    set: { model.settings.ignoreNotificationSounds = $0 }
                ))
                .toggleStyle(.switch)
                .tint(OrejaTheme.Palette.accent)
                .font(.system(size: 13))

                HStack(spacing: 8) {
                    StatusDot(
                        color: model.settings.ignoreNotificationSounds
                            ? OrejaTheme.Palette.accent
                            : OrejaTheme.Palette.inkSoft
                    )
                    Text(
                        model.settings.ignoreNotificationSounds
                            ? "A chime, a sent-sound or an alert tone is ignored; a reply, which rises and falls with every syllable, is not."
                            : "Any sound from the AI source counts, including notifications."
                    )
                    .font(OrejaTheme.Typography.micro)
                    .foregroundStyle(OrejaTheme.Palette.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
                }

                if model.settings.pauseWhileISpeak {
                    Hairline()

                    sensitivityRow(
                        title: "Your voice",
                        selection: Binding(
                            get: { model.settings.microphoneSensitivity },
                            set: { model.settings.microphoneSensitivity = $0 }
                        )
                    )

                    Text("Used by “Pause while I speak”. Raise it if the microphone hears room noise, lower it if your own answers are missed.")
                        .font(OrejaTheme.Typography.micro)
                        .foregroundStyle(OrejaTheme.Palette.inkSoft)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func sensitivityRow(
        title: String,
        selection: Binding<DetectionSensitivity>
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                    .font(.system(size: 13))
                    .foregroundStyle(OrejaTheme.Palette.ink)
                Spacer(minLength: 8)
                Picker(title, selection: selection) {
                    ForEach(DetectionSensitivity.allCases, id: \.self) { level in
                        Text(level.title).tag(level)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(maxWidth: 190)
            }

            Text(selection.wrappedValue.detail)
                .font(OrejaTheme.Typography.micro)
                .foregroundStyle(OrejaTheme.Palette.inkSoft)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var music: some View {
        ThemeSection(title: "Music") {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("Provider")
                        .font(.system(size: 13))
                        .foregroundStyle(OrejaTheme.Palette.ink)
                    Spacer(minLength: 8)
                    Picker("Provider", selection: Binding(
                        get: { model.settings.musicProvider },
                        set: { model.settings.musicProvider = $0 }
                    )) {
                        Text("Apple Music").tag(MediaProviderID.appleMusic)
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(maxWidth: 200)
                }

                Hairline()

                HStack(spacing: 14) {
                    Button("Open Music") { model.launchMusic() }
                        .controlSize(.regular)
                    Button("Check permissions") { model.runConnectionCheck() }
                        .controlSize(.regular)
                        .disabled(model.isRunningCheck)
                }

                if !model.hasAudioPermission {
                    InlineNotice(
                        text: "Audio recording permission is missing.",
                        symbol: "exclamationmark.triangle.fill"
                    )
                }
            }
        }
    }

    /// One rule per line: when Oreja does something, run one of the user's own actions. Kept out of
    /// Behavior on purpose — this is the extensibility surface, not a playback preference.
    private var hooks: some View {
        ThemeSection(
            title: "Hooks",
            caption: "Hooks run your own automation when Oreja does something. A Shortcut or a URL is all Oreja runs: no shell, no network client, no account."
        ) {
            VStack(alignment: .leading, spacing: 14) {
                if model.settings.hooks.isEmpty {
                    Text("Nothing hooked yet. A hook is one line — when this happens, do that. A useful first one: a shortcut that notifies you when a reply starts, so you know the music paused for a reason.")
                        .font(OrejaTheme.Typography.micro)
                        .foregroundStyle(OrejaTheme.Palette.inkSoft)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    ForEach(model.settings.hooks) { hook in
                        HookRow(
                            hook: hook,
                            onChange: { model.updateHook($0) },
                            onTest: { model.testHook(hook) },
                            onDelete: { model.removeHook(id: hook.id) }
                        )
                        if hook.id != model.settings.hooks.last?.id {
                            Hairline()
                        }
                    }
                }

                Button("Add hook") { model.addHook() }
                    .controlSize(.regular)
            }
        }
    }

    private var startup: some View {
        ThemeSection(title: "Startup") {
            VStack(alignment: .leading, spacing: 8) {
                Toggle("Start Oreja at login", isOn: Binding(
                    get: { model.settings.launchAtLogin },
                    set: { model.settings.launchAtLogin = $0 }
                ))
                .toggleStyle(.switch)
                .tint(OrejaTheme.Palette.accent)
                .font(.system(size: 13))

                if let error = model.launchAtLoginError {
                    InlineNotice(text: error, symbol: "exclamationmark.triangle.fill")
                }
            }
        }
    }

    private var privacy: some View {
        ThemeSection(
            title: "Privacy",
            caption: "Diagnostics never contain audio, prompts or replies. Only Oreja's own state changes and permission results are kept, in memory."
        ) {
            Toggle("Verbose diagnostics", isOn: Binding(
                get: { model.settings.verboseDiagnostics },
                set: { model.settings.verboseDiagnostics = $0 }
            ))
            .toggleStyle(.switch)
            .tint(OrejaTheme.Palette.accent)
            .font(.system(size: 13))
        }
    }

    private var permissions: some View {
        ThemeSection(title: "Permissions") {
            HStack(spacing: 14) {
                Button("Audio recording…") { model.openSystemAudioSettings() }
                    .controlSize(.regular)
                Button("Automation…") { model.openAutomationSettings() }
                    .controlSize(.regular)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
/// One hook, edited in place. Every change commits immediately, like the rest of Settings: there is
/// no Save button here, and a half-typed hook stays a draft that cannot fire.
private struct HookRow: View {
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
