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
                music
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

    private var versionFooter: some View {
        Text("Version \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Development")")
            .font(OrejaTheme.Typography.micro)
            .foregroundStyle(OrejaTheme.Palette.inkSoft)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.top, 2)
    }

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
            title: "AI source",
            caption: "Browser sources capture every tab in that browser; use them only for dedicated ChatGPT windows."
        ) {
            HStack {
                Text("Listen to")
                    .font(.system(size: 13))
                    .foregroundStyle(OrejaTheme.Palette.ink)
                Spacer(minLength: 8)
                Picker("Listen to", selection: Binding(
                    get: { model.settings.aiSource },
                    set: { model.selectSource($0) }
                )) {
                    ForEach(sourceOptions, id: \.bundleIdentifier) { option in
                        Text(option.kind == .chatGPTDesktop ? "ChatGPT desktop app" : "\(option.displayName) (experimental)")
                            .tag(option)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(maxWidth: 240)
            }
        }
    }

    /// The built-in choices, plus whatever is currently selected if onboarding picked a browser
    /// that is not in the built-in list, so the picker never shows a blank selection.
    private var sourceOptions: [AISourceSelection] {
        var options: [AISourceSelection] = [.chatGPTDesktop, .chrome, .safari, .egoLite]
        let current = model.settings.aiSource
        if !options.contains(where: { $0.kind == current.kind && $0.bundleIdentifier == current.bundleIdentifier }) {
            options.append(current)
        }
        return options
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
        }
    }
}
