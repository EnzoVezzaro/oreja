import SwiftUI
import OrejaAudio
import OrejaCore

/// Six-step setup. Every step states what it needs and what it will verify; nothing is reported as
/// working until the corresponding check actually succeeds.
struct OnboardingView: View {
    @ObservedObject var model: AppModel
    @State private var step = 0
    @State private var runningApplications: [RunningAudioApplication] = []

    private let stepTitles = [
        "Welcome",
        "AI source",
        "Music",
        "Audio access",
        "Live test",
        "Ready",
    ]

    var body: some View {
        VStack(spacing: 0) {
            header
            progress
            ScrollView {
                page
                    .frame(maxWidth: 520, alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.horizontal, 32)
                    .padding(.vertical, 30)
            }
            Hairline()
            footer
        }
        .frame(minWidth: 620, minHeight: 660)
        .background(OrejaTheme.Palette.paper)
        .tint(OrejaTheme.Palette.accent)
        .onAppear { runningApplications = RunningApplicationCatalog.runningApplications() }
    }

    // MARK: Chrome

    private var header: some View {
        HStack(spacing: 10) {
            BrandMark(size: 24)
            BrandWordmark(size: 14)
            Spacer(minLength: 12)
            Text(stepTitles[step])
                .font(.system(size: 11))
                .foregroundStyle(OrejaTheme.Palette.inkSoft)
            Text("\(step + 1)/\(stepTitles.count)")
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .monospacedDigit()
                .foregroundStyle(OrejaTheme.Palette.inkSoft)
        }
        .padding(.horizontal, 22)
        .padding(.top, 18)
        .padding(.bottom, 14)
    }

    private var progress: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(OrejaTheme.Palette.hairline)
                Rectangle()
                    .fill(OrejaTheme.Palette.wheat)
                    .frame(width: proxy.size.width * CGFloat(step + 1) / CGFloat(stepTitles.count))
            }
        }
        .frame(height: 2)
        .animation(.easeOut(duration: 0.22), value: step)
        .accessibilityHidden(true)
    }

    private var footer: some View {
        HStack(spacing: 14) {
            if step > 0 {
                Button("Back") { step -= 1 }
                    .buttonStyle(.plain)
                    .font(.system(size: 12))
                    .foregroundStyle(OrejaTheme.Palette.inkSoft)
            }
            Spacer(minLength: 12)
            if step >= 1 && step <= 4 {
                Text("You can change all of this later in Settings.")
                    .font(OrejaTheme.Typography.micro)
                    .foregroundStyle(OrejaTheme.Palette.inkSoft)
            }
            if step < stepTitles.count - 1 {
                Button("Continue") { step += 1 }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .keyboardShortcut(.defaultAction)
            } else {
                Button("Start using Oreja") { model.finishOnboarding() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 16)
    }

    // MARK: Pages

    @ViewBuilder
    private var page: some View {
        switch step {
        case 0: welcome
        case 1: chooseSource
        case 2: chooseMusic
        case 3: allowMonitoring
        case 4: liveTest
        default: finish
        }
    }

    private func pageHeader(_ eyebrow: String, _ title: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Eyebrow(text: eyebrow)
            Text(title)
                .font(OrejaTheme.Typography.pageTitle)
                .tracking(-0.6)
                .foregroundStyle(OrejaTheme.Palette.ink)
                .fixedSize(horizontal: false, vertical: true)
            Text(text)
                .font(OrejaTheme.Typography.body)
                .lineSpacing(3)
                .foregroundStyle(OrejaTheme.Palette.inkSoft)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var welcome: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 18) {
                pageHeader(
                    "Welcome",
                    "One job, done automatically.",
                    "Oreja pauses Apple Music or lowers its volume when ChatGPT starts speaking, then restores playback when the reply ends. It sits in the menu bar and stays out of the way."
                )
                Spacer(minLength: 12)
                VincentCompanion(size: 80, isListening: false, isMusicPlaying: false)
                    .padding(.top, 4)
            }
            ThemeCard {
                BulletList(items: [
                    "It listens to ChatGPT's own audio output. Microphone access is optional if you want Music to stay interrupted while you speak.",
                    "Nothing is recorded, transcribed or uploaded. Audio levels are discarded immediately.",
                    "Music keeps its track, queue and position. In lower-volume mode, Oreja restores the volume it found before speaking started.",
                    "It never starts music you had paused yourself.",
                ])
            }
            Text("Oreja is an independent companion app. It is not affiliated with OpenAI or Apple.")
                .font(OrejaTheme.Typography.micro)
                .foregroundStyle(OrejaTheme.Palette.inkSoft)
        }
    }

    private var chooseSource: some View {
        VStack(alignment: .leading, spacing: 16) {
            pageHeader(
                "AI source",
                "What should Oreja listen to?",
                "Pick the application that talks to you. Oreja only monitors the application you choose here."
            )

            sourceRow(
                selection: .chatGPTDesktop,
                subtitle: model.settings.aiSource == .chatGPTDesktop ? "Selected" : "Recommended"
            )

            VStack(alignment: .leading, spacing: 6) {
                Eyebrow(text: "Experimental: browser sessions")
                Text("A browser tap captures every tab in that browser, so other tabs can look like AI audio. Use it only if you keep ChatGPT in a dedicated window.")
                    .font(OrejaTheme.Typography.micro)
                    .lineSpacing(2)
                    .foregroundStyle(OrejaTheme.Palette.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }

            let browsers = runningApplications.filter { AISourceCatalog.isBrowser(bundleIdentifier: $0.bundleIdentifier) }
            if browsers.isEmpty {
                Text("No supported browser is running right now.")
                    .font(OrejaTheme.Typography.caption)
                    .foregroundStyle(OrejaTheme.Palette.inkSoft)
            } else {
                VStack(spacing: 8) {
                    ForEach(browsers) { app in
                        sourceRow(
                            selection: AISourceSelection(
                                kind: .browser,
                                bundleIdentifier: app.bundleIdentifier,
                                displayName: app.name
                            ),
                            subtitle: "Experimental"
                        )
                    }
                }
            }
        }
    }

    private func sourceRow(selection: AISourceSelection, subtitle: String) -> some View {
        let isSelected = model.settings.aiSource.bundleIdentifier == selection.bundleIdentifier
            && model.settings.aiSource.kind == selection.kind
        return Button {
            model.selectSource(selection)
        } label: {
            HStack(spacing: 11) {
                ZStack {
                    Circle()
                        .strokeBorder(
                            isSelected ? OrejaTheme.Palette.accent : OrejaTheme.Palette.hairline,
                            lineWidth: 1
                        )
                        .frame(width: 14, height: 14)
                    if isSelected {
                        Circle()
                            .fill(OrejaTheme.Palette.accent)
                            .frame(width: 7, height: 7)
                    }
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(selection.kind == .chatGPTDesktop ? "ChatGPT desktop app" : selection.displayName)
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(OrejaTheme.Palette.ink)
                    Text(subtitle)
                        .font(OrejaTheme.Typography.micro)
                        .foregroundStyle(OrejaTheme.Palette.inkSoft)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isSelected ? OrejaTheme.Palette.accentWash : OrejaTheme.Palette.card)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(
                        isSelected ? OrejaTheme.Palette.accent.opacity(0.35) : OrejaTheme.Palette.hairline,
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    private var chooseMusic: some View {
        VStack(alignment: .leading, spacing: 16) {
            pageHeader(
                "Music",
                "Which music app?",
                "Apple Music is the only provider in this release. Oreja can pause and resume it, or lower and restore its volume, through macOS automation, which asks for your permission the first time."
            )

            ThemeCard {
                HStack(spacing: 11) {
                    Image(systemName: model.media.isMusicRunning ? "music.note" : "music.note.slash")
                        .font(.system(size: 13))
                        .foregroundStyle(model.media.isMusicRunning ? OrejaTheme.Palette.positive : OrejaTheme.Palette.inkSoft)
                        .frame(width: 16)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(model.media.isMusicRunning ? "Music is running" : "Music is not running")
                            .font(.system(size: 12.5, weight: .medium))
                            .foregroundStyle(OrejaTheme.Palette.ink)
                        Text(model.media.isMusicRunning
                             ? (model.music?.track.map { "Loaded: \($0.displayName)" } ?? "No track loaded")
                             : "Oreja never launches your music app on its own.")
                            .font(OrejaTheme.Typography.micro)
                            .foregroundStyle(OrejaTheme.Palette.inkSoft)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 8)
                    if !model.media.isMusicRunning {
                        Button("Open Music") { model.launchMusic() }
                            .controlSize(.small)
                    }
                }
            }

            HStack(spacing: 12) {
                Button("Check Music access") { model.runConnectionCheck() }
                    .controlSize(.large)
                    .disabled(model.isRunningCheck)
                Text("macOS asks whether Oreja may control Music. Without it Oreja cannot pause or resume anything.")
                    .font(OrejaTheme.Typography.micro)
                    .foregroundStyle(OrejaTheme.Palette.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var allowMonitoring: some View {
        VStack(alignment: .leading, spacing: 16) {
            pageHeader(
                "Audio access",
                "Allow audio monitoring",
                "To know when ChatGPT is speaking, Oreja captures a copy of that application's audio output using Apple's Core Audio process taps. Only levels are computed; audio is never stored."
            )
            ThemeCard {
                BulletList(items: [
                    "macOS asks for Screen & System Audio Recording permission. Oreja needs the audio part only.",
                    "You do not need to share your screen. Microphone access is optional and only supports “Pause while I speak.”",
                    "The permission is required by macOS 14.2+ for any process tap, including this one.",
                ])
            }
            HStack(spacing: 10) {
                Button("Open System Settings") { model.openSystemAudioSettings() }
                    .controlSize(.large)
                Button("Try audio capture now") { model.runConnectionCheck() }
                    .buttonStyle(.link)
                    .font(.system(size: 12))
                    .disabled(model.isRunningCheck)
            }
            if !model.hasAudioPermission {
                InlineNotice(
                    text: "Audio capture permission is missing right now.",
                    symbol: "exclamationmark.triangle.fill"
                )
            }
        }
    }

    private var liveTest: some View {
        VStack(alignment: .leading, spacing: 16) {
            pageHeader(
                "Live test",
                "Verify it actually works",
                "Follow these steps in order. Oreja reports only what it could verify."
            )
            ThemeCard {
                NumberedList(items: [
                    "Start a song in Apple Music.",
                    "Start a voice conversation in ChatGPT and ask a question.",
                    "Watch the check below report ChatGPT audio activity.",
                    "Confirm the music paused while the reply played.",
                    "Confirm the music resumed after the reply ended.",
                ])
            }
            HStack(spacing: 12) {
                Button {
                    model.runConnectionCheck()
                } label: {
                    Text(model.isRunningCheck ? "Checking…" : "Run the checks")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(model.isRunningCheck)
            }

            if let report = model.report {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(report.steps) { step in
                        CheckRow(step: step)
                    }
                }
                .padding(.top, 2)
                Text(report.hasFailure
                     ? "Some checks failed. That is expected until the missing permission or app is in place."
                     : "Checks passed. Oreja will keep watching and act on real ChatGPT audio.")
                    .font(OrejaTheme.Typography.micro)
                    .foregroundStyle(report.hasFailure ? OrejaTheme.Palette.warning : OrejaTheme.Palette.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("No checks have been run in this session.")
                    .font(OrejaTheme.Typography.micro)
                    .foregroundStyle(OrejaTheme.Palette.inkSoft)
            }
        }
    }

    private var finish: some View {
        VStack(alignment: .leading, spacing: 16) {
            pageHeader(
                "Ready",
                "Oreja now runs from the menu bar",
                "Closing this window leaves automation running. Your music is only touched while ChatGPT is speaking."
            )

            ThemeCard {
                VStack(alignment: .leading, spacing: 12) {
                    Toggle("Enable automation now", isOn: Binding(
                        get: { model.settings.automationEnabled },
                        set: { model.setAutomationEnabled($0) }
                    ))
                    .toggleStyle(.switch)
                    .tint(OrejaTheme.Palette.accent)
                    .font(.system(size: 12.5))

                    Hairline()

                    Toggle("Start Oreja at login", isOn: Binding(
                        get: { model.settings.launchAtLogin },
                        set: { model.settings.launchAtLogin = $0 }
                    ))
                    .toggleStyle(.switch)
                    .tint(OrejaTheme.Palette.accent)
                    .font(.system(size: 12.5))

                    if let error = model.launchAtLoginError {
                        InlineNotice(text: error, symbol: "exclamationmark.triangle.fill")
                    }

                    Hairline()

                    HStack {
                        Text("Quiet interval before music resumes")
                            .font(.system(size: 12))
                            .foregroundStyle(OrejaTheme.Palette.ink)
                        Spacer(minLength: 8)
                        Text("\(Int(model.settings.resumeDelay * 1000)) ms")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(OrejaTheme.Palette.inkSoft)
                    }
                }
            }
        }
    }
}

// MARK: - Small building blocks

struct CheckRow: View {
    var step: CheckStep

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: step.symbol)
                .font(.system(size: 11))
                .foregroundStyle(checkColor)
                .padding(.top, 1)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(step.title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(OrejaTheme.Palette.ink)
                Text(step.message)
                    .font(OrejaTheme.Typography.micro)
                    .foregroundStyle(OrejaTheme.Palette.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(step.title): \(statusWord)")
    }

    private var statusWord: String {
        switch step.status {
        case .pending: "not checked"
        case .running: "checking"
        case .passed: "passed"
        case .failed: "failed"
        case .skipped: "skipped"
        }
    }

    private var checkColor: Color {
        switch step.status {
        case .passed: OrejaTheme.Palette.positive
        case .failed: OrejaTheme.Palette.warning
        case .pending, .running, .skipped: OrejaTheme.Palette.inkSoft
        }
    }
}

/// A one-line warning or note. Used where a bare colour would not say what went wrong.
struct InlineNotice: View {
    var text: String
    var symbol: String = "info.circle"

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 10))
                .foregroundStyle(OrejaTheme.Palette.warning)
                .padding(.top, 1)
                .accessibilityHidden(true)
            Text(text)
                .font(OrejaTheme.Typography.micro)
                .foregroundStyle(OrejaTheme.Palette.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(OrejaTheme.Palette.warning.opacity(0.09))
        )
    }
}

struct BulletList: View {
    var items: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            ForEach(items, id: \.self) { item in
                HStack(alignment: .top, spacing: 9) {
                    Circle()
                        .fill(OrejaTheme.Palette.wheat)
                        .frame(width: 4, height: 4)
                        .padding(.top, 6)
                        .accessibilityHidden(true)
                    Text(item)
                        .font(OrejaTheme.Typography.body)
                        .lineSpacing(2)
                        .foregroundStyle(OrejaTheme.Palette.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

struct NumberedList: View {
    var items: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                HStack(alignment: .top, spacing: 10) {
                    Text("\(index + 1)")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(OrejaTheme.Palette.inkSoft)
                        .frame(width: 14, alignment: .leading)
                        .padding(.top, 1)
                    Text(item)
                        .font(OrejaTheme.Typography.body)
                        .lineSpacing(2)
                        .foregroundStyle(OrejaTheme.Palette.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}
