import AppKit
import AVFoundation
import OrejaAudio
import OrejaCore
import SwiftUI

/// Settings stay grouped by task with native controls and the existing warm brand palette.
///
/// - Audio: what Oreja listens to (apps, and optionally your voice) and how sensitive it is.
/// - Playback: what happens to playback while someone speaks (Apple Music and other apps).
/// - Automation: hooks and startup.
/// - Privacy: permissions, diagnostics and the build.
struct SettingsView: View {
    @ObservedObject var model: AppModel
    @State private var selectedPage: SettingsPage = .audio
    @FocusState private var focusedPage: SettingsPage?

    /// Header and content share this column, so titles and cards start on the same edge.
    static let columnWidth: CGFloat = 600
    static let pagePadding: CGFloat = 28

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Rectangle()
                .fill(OrejaTheme.Palette.hairline)
                .frame(width: 1)
            VStack(spacing: 0) {
                header
                    .frame(maxWidth: Self.columnWidth, alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, Self.pagePadding)
                    .padding(.top, 20)
                    .padding(.bottom, 14)
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        switch selectedPage {
                        case .audio: audioPage
                        case .playback: PlaybackSettingsPage(model: model)
                        case .automation: automationPage
                        case .privacy: privacyPage
                        }
                    }
                    .frame(maxWidth: Self.columnWidth, alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, Self.pagePadding)
                    .padding(.top, 2)
                    .padding(.bottom, 28)
                }
            }
        }
        .background(OrejaTheme.Palette.paper)
        .tint(OrejaTheme.Palette.accent)
        .frame(minWidth: 720, minHeight: 560)
    }

    // MARK: Shell

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 9) {
                BrandMark(size: 26)
                BrandWordmark(size: 17)
            }
            .padding(.horizontal, 6)
            .padding(.bottom, 14)

            ForEach(SettingsPage.allCases) { page in
                sidebarButton(page)
            }

            Spacer(minLength: 0)
            sidebarFooter
        }
        .padding(.horizontal, 12)
        .padding(.top, 20)
        .padding(.bottom, 16)
        .frame(width: 180)
        .background(OrejaTheme.Palette.paper.opacity(0.72))
    }

    /// The icon column has a fixed width, so every label starts on the same line, and keyboard focus
    /// outlines the whole row instead of hugging the text.
    private func sidebarButton(_ page: SettingsPage) -> some View {
        let isSelected = selectedPage == page
        return Button { selectedPage = page } label: {
            HStack(spacing: 9) {
                Image(systemName: page.symbol)
                    .font(.system(size: 13, weight: .medium))
                    .frame(width: 18, alignment: .center)
                    .accessibilityHidden(true)
                Text(page.title)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                Spacer(minLength: 0)
            }
            .foregroundStyle(isSelected ? OrejaTheme.Palette.ink : OrejaTheme.Palette.inkSoft)
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, minHeight: 32, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isSelected ? OrejaTheme.Palette.accent.opacity(0.14) : .clear)
            )
            .overlay(
                // Keyboard focus follows the selected page, so this ring never marks a second row.
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(OrejaTheme.Palette.accent.opacity(0.55), lineWidth: 1.5)
                    .opacity(focusedPage == page ? 1 : 0)
            )
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .focused($focusedPage, equals: page)
        .onChange(of: selectedPage) { _, newPage in
            if focusedPage != nil { focusedPage = newPage }
        }
        .accessibilityLabel(page.title)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    /// What Oreja is doing right now and which build this is, visible from every page.
    private var sidebarFooter: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                StatusDot(color: model.state.tint)
                Text(model.statusTitle)
                    .font(OrejaTheme.Typography.micro)
                    .foregroundStyle(OrejaTheme.Palette.ink)
                    .lineLimit(2)
            }
            Text(AppVersion.current.shortTitle)
                .font(OrejaTheme.Typography.micro)
                .foregroundStyle(OrejaTheme.Palette.inkSoft)
                .lineLimit(1)
                .help("\(AppVersion.current.title)\n\(AppVersion.current.detail)")
        }
        .padding(.horizontal, 6)
        .accessibilityElement(children: .combine)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 20) {
            VStack(alignment: .leading, spacing: 3) {
                Text(selectedPage.title)
                    .font(OrejaTheme.Typography.pageTitle)
                    .foregroundStyle(OrejaTheme.Palette.ink)
                    .accessibilityAddTraits(.isHeader)
                Text(selectedPage.subtitle)
                    .font(OrejaTheme.Typography.caption)
                    .foregroundStyle(OrejaTheme.Palette.inkSoft)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
            VincentCompanion(size: 42, isListening: model.state.isActive, isMusicPlaying: model.music?.isPlaying == true)
        }
    }

    // MARK: Audio

    private var audioPage: some View {
        VStack(alignment: .leading, spacing: 24) {
            ThemeSection(
                title: "Listen to",
                caption: "When one of these apps makes sound, Oreja starts the interruption. Pick the assistant you talk to. Music you want lowered goes under Playback › Lower these apps."
            ) {
                AppSelectionList(
                    mode: .sources,
                    selected: model.settings.aiSources,
                    otherList: model.settings.targetAudioApps,
                    onToggle: model.toggleSource,
                    onMoveToTargets: model.toggleTargetAudioApp
                )
            }
            yourVoice
            detection
        }
    }

    private var yourVoice: some View {
        ThemeSection(
            title: "Your voice",
            caption: "Optional. Oreja hears your microphone level only, never words, and nothing is recorded."
        ) {
            VStack(alignment: .leading, spacing: 14) {
                SettingToggle(
                    "Interrupt while I speak",
                    detail: "Your voice can start the interruption and keep it going while you talk. On the Mac's own speakers it only extends one already started, because the microphone also hears the music.",
                    isOn: Binding(
                        get: { model.settings.pauseWhileISpeak },
                        set: { model.settings.pauseWhileISpeak = $0 }
                    )
                )

                if model.settings.pauseWhileISpeak {
                    HStack(spacing: 6) {
                        StatusDot(color: model.isListeningForUser ? OrejaTheme.Palette.accent : OrejaTheme.Palette.inkSoft)
                        Text(model.isListeningForUser ? "Listening on \(model.listeningMicrophoneName ?? "the default microphone"). The headset mic is used while a call or voice session has it open; otherwise the Mac's own mic, so Oreja never lowers your headset's music quality." : "Not listening yet. Automation must be on and microphone access granted.")
                            .font(OrejaTheme.Typography.micro)
                            .foregroundStyle(OrejaTheme.Palette.inkSoft)
                    }

                    Hairline()

                    sensitivityRow(
                        title: "Voice sensitivity",
                        selection: Binding(
                            get: { model.settings.microphoneSensitivity },
                            set: { model.settings.microphoneSensitivity = $0 }
                        ),
                        note: "Raise it if your speech is missed; lower it if room noise triggers it."
                    )
                }

                if let error = model.userSpeechError {
                    InlineNotice(text: error, symbol: "mic.slash")
                    Button("Open Microphone settings…") { model.openMicrophoneSettings() }
                        .controlSize(.small)
                }
            }
        }
    }

    /// The real detection controls: how loud the AI has to be and whether notification-shaped
    /// bursts count at all. Everything here changes what the detectors hear.
    private var detection: some View {
        ThemeSection(
            title: "Detection",
            caption: "How loud the selected apps must be, and whether short notification sounds count. Audio is analyzed on this Mac and discarded."
        ) {
            VStack(alignment: .leading, spacing: 14) {
                sensitivityRow(
                    title: "Assistant sensitivity",
                    selection: Binding(
                        get: { model.settings.aiSensitivity },
                        set: { model.settings.aiSensitivity = $0 }
                    ),
                    note: nil
                )

                Hairline()

                SettingToggle(
                    "Ignore notification sounds",
                    detail: model.settings.ignoreNotificationSounds
                        ? "A chime, a sent-sound or an alert tone is ignored; a reply, which rises and falls with every syllable, is not."
                        : "Any sound from the selected apps counts, including notifications.",
                    isOn: Binding(
                        get: { model.settings.ignoreNotificationSounds },
                        set: { model.settings.ignoreNotificationSounds = $0 }
                    )
                )
            }
        }
    }

    private func sensitivityRow(
        title: String,
        selection: Binding<DetectionSensitivity>,
        note: String?
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            SettingRow(title) {
                Picker(title, selection: selection) {
                    ForEach(DetectionSensitivity.allCases, id: \.self) { level in
                        Text(level.title).tag(level)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 200)
            }
            SettingDetail(note.map { "\(selection.wrappedValue.detail) \($0)" } ?? selection.wrappedValue.detail)
        }
    }

    // MARK: Automation

    private var automationPage: some View {
        VStack(alignment: .leading, spacing: 24) {
            hooks
            ThemeSection(title: "Startup") {
                VStack(alignment: .leading, spacing: 8) {
                    SettingToggle(
                        "Start Oreja at login",
                        detail: "Oreja opens in the menu bar when you log in.",
                        isOn: Binding(
                            get: { model.settings.launchAtLogin },
                            set: { model.settings.launchAtLogin = $0 }
                        )
                    )
                    if let error = model.launchAtLoginError {
                        InlineNotice(text: error, symbol: "exclamationmark.triangle.fill")
                    }
                }
            }
        }
    }

    /// One rule per line: when Oreja does something, run one of the user's own actions.
    private var hooks: some View {
        ThemeSection(
            title: "Hooks",
            caption: "Hooks run your own automation when Oreja does something. A Shortcut or a URL is all Oreja runs: no shell, no network client, no account."
        ) {
            VStack(alignment: .leading, spacing: 14) {
                if model.settings.hooks.isEmpty {
                    SettingDetail("Nothing hooked yet. A hook is one line: when this happens, do that. A useful first one is a shortcut that notifies you when a reply starts, so you know playback changed for a reason.")
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

                Button {
                    model.addHook()
                } label: {
                    Label("Add hook", systemImage: "plus")
                }
                .controlSize(.regular)
            }
        }
    }

    // MARK: Privacy

    private var privacyPage: some View {
        VStack(alignment: .leading, spacing: 24) {
            permissions
            diagnostics
            versionFooter
        }
    }

    private var permissions: some View {
        ThemeSection(
            title: "Permissions",
            caption: "macOS asks for each of these once. Oreja works with the first; the others are needed only for the features named."
        ) {
            VStack(alignment: .leading, spacing: 14) {
                PermissionRow(
                    title: "Audio recording",
                    detail: "Lets Oreja measure how loud the selected apps are, and lower other apps.",
                    status: model.hasAudioPermission ? "Granted" : "Missing",
                    tone: model.hasAudioPermission ? .good : .attention,
                    actionTitle: "Open Settings",
                    action: model.openSystemAudioSettings
                )
                Hairline()
                PermissionRow(
                    title: "Microphone",
                    detail: "Only for “Interrupt while I speak”.",
                    status: microphoneStatus.text,
                    tone: microphoneStatus.tone,
                    actionTitle: "Open Settings",
                    action: model.openMicrophoneSettings
                )
                Hairline()
                PermissionRow(
                    title: "Automation for Music",
                    detail: "Lets Oreja pause, resume and set the volume of Apple Music.",
                    status: musicAutomationStatus.text,
                    tone: musicAutomationStatus.tone,
                    actionTitle: "Open Settings",
                    action: model.openAutomationSettings
                )
                HStack {
                    Button(model.isRunningCheck ? "Checking…" : "Check again") { model.runConnectionCheck() }
                        .controlSize(.small)
                        .disabled(model.isRunningCheck)
                    Spacer(minLength: 0)
                }
            }
        }
    }

    private var microphoneStatus: (text: String, tone: StatusTone) {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: ("Granted", .good)
        case .notDetermined: ("Not asked yet", .neutral)
        case .denied, .restricted: (model.settings.pauseWhileISpeak ? "Missing" : "Off", model.settings.pauseWhileISpeak ? .attention : .neutral)
        @unknown default: ("Unknown", .neutral)
        }
    }

    /// Automation can only be read by trying it, so this shows the last connection check.
    private var musicAutomationStatus: (text: String, tone: StatusTone) {
        guard let step = model.report?.steps.first(where: { $0.title == "Oreja may control Music" }) else {
            return ("Not checked", .neutral)
        }
        switch step.status {
        case .passed: return ("Granted", .good)
        case .failed: return ("Missing", .attention)
        case .pending, .running: return ("Checking…", .neutral)
        case .skipped: return ("Not checked", .neutral)
        }
    }

    private var diagnostics: some View {
        ThemeSection(
            title: "Diagnostics",
            caption: "Diagnostics never contain audio, prompts or replies. Only Oreja's own state changes and permission results are kept."
        ) {
            VStack(alignment: .leading, spacing: 14) {
                SettingToggle(
                    "Verbose diagnostics",
                    detail: "Also records the microphone level once a second, to see why speech is or is not detected.",
                    isOn: Binding(
                        get: { model.settings.verboseDiagnostics },
                        set: { model.settings.verboseDiagnostics = $0 }
                    )
                )
                HStack(spacing: 10) {
                    Button("Open diagnostics") { model.showDiagnostics() }
                        .controlSize(.small)
                    Button("Show log file in Finder") { model.revealLogFile() }
                        .controlSize(.small)
                    Spacer(minLength: 0)
                }
            }
        }
    }

    /// Where someone looks once the settings are set: what this build is, what changed, and the
    /// source. The version is read from the stamped Info.plist, never hard-coded.
    private var versionFooter: some View {
        let version = AppVersion.current
        return VStack(alignment: .leading, spacing: 12) {
            Hairline()
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(version.title)
                        .foregroundStyle(OrejaTheme.Palette.ink)
                    Text(version.detail)
                        .foregroundStyle(OrejaTheme.Palette.inkSoft)
                        .textSelection(.enabled)
                }
                Spacer(minLength: 12)
                Button("Copy") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString("Oreja \(version.title) — \(version.detail)", forType: .string)
                }
                .controlSize(.small)
                .help("Copy the version and build details, for a bug report")
            }
            HStack(spacing: 8) {
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
                Spacer(minLength: 0)
            }
        }
        .font(OrejaTheme.Typography.micro)
        .padding(.top, 2)
    }

    /// Footer links are small by design, so they get a 24 pt target and an explicit label.
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
}

private enum SettingsPage: String, CaseIterable, Identifiable {
    case audio
    case playback
    case automation
    case privacy

    var id: Self { self }

    var title: String {
        switch self {
        case .audio: "Audio"
        case .playback: "Playback"
        case .automation: "Automation"
        case .privacy: "Privacy"
        }
    }

    var subtitle: String {
        switch self {
        case .audio: "What Oreja listens to, and how closely."
        case .playback: "What happens to your music while someone speaks."
        case .automation: "Hooks, and whether Oreja starts at login."
        case .privacy: "Permissions, diagnostics and this build."
        }
    }

    var symbol: String {
        switch self {
        case .audio: "waveform"
        case .playback: "playpause"
        case .automation: "bolt.horizontal"
        case .privacy: "hand.raised"
        }
    }
}
