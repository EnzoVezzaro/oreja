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
        "Choose the AI",
        "Choose your music",
        "Allow audio monitoring",
        "Live test",
        "Finish",
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            ScrollView {
                Group {
                    switch step {
                    case 0: welcome
                    case 1: chooseSource
                    case 2: chooseMusic
                    case 3: allowMonitoring
                    case 4: liveTest
                    default: finish
                    }
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Divider()
            footer
        }
        .frame(minWidth: 600, minHeight: 620)
        .onAppear { runningApplications = RunningApplicationCatalog.runningApplications() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Image(systemName: "ear")
                    .font(.system(size: 22, weight: .medium))
                VStack(alignment: .leading, spacing: 1) {
                    Text("Oreja de Van Gogh")
                        .font(.title3.weight(.semibold))
                    Text("Your AI talks. Your music listens.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            HStack(spacing: 6) {
                ForEach(0..<stepTitles.count, id: \.self) { index in
                    Capsule()
                        .fill(index <= step ? Color.accentColor : Color.secondary.opacity(0.25))
                        .frame(height: 4)
                        .accessibilityHidden(true)
                }
            }
            Text("Step \(step + 1) of \(stepTitles.count) — \(stepTitles[step])")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(20)
    }

    private var footer: some View {
        HStack {
            Button("Back") { step = max(0, step - 1) }
                .disabled(step == 0)
            Spacer()
            if step >= 1 && step <= 4 {
                Text("You can change all of this later in Settings.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if step < stepTitles.count - 1 {
                Button("Continue") { step += 1 }
                    .keyboardShortcut(.defaultAction)
            } else {
                Button("Start using Oreja") {
                    model.finishOnboarding()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
    }

    // MARK: Steps

    private var welcome: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("One job, done automatically.")
                .font(.title2.weight(.semibold))
            Text("Oreja pauses Apple Music when ChatGPT starts speaking, and resumes it when the reply ends. It sits in the menu bar and stays out of the way.")
                .fixedSize(horizontal: false, vertical: true)
            BulletList(items: [
                "It listens to ChatGPT's own audio output, not your microphone.",
                "Nothing is recorded, transcribed or uploaded. Audio levels are discarded immediately.",
                "Music keeps its track, queue, position and volume.",
                "It never starts music you had paused yourself.",
            ])
            Text("Oreja is an independent companion app. It is not affiliated with OpenAI or Apple.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.top, 6)
        }
    }

    private var chooseSource: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("What should Oreja listen to?")
                .font(.title3.weight(.semibold))
            Text("Pick the application that talks to you. Oreja only monitors the application you choose here.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            sourceRow(
                selection: .chatGPTDesktop,
                subtitle: model.settings.aiSource == .chatGPTDesktop ? "Selected" : "Recommended"
            )

            Text("Experimental: browser sessions")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text("A browser tap captures every tab in that browser, so notifications or other tabs can look like AI audio. Use it only if you keep ChatGPT in a dedicated window.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            let browsers = runningApplications.filter { AISourceCatalog.isBrowser(bundleIdentifier: $0.bundleIdentifier) }
            if browsers.isEmpty {
                Text("No supported browser is running right now.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
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

    private func sourceRow(selection: AISourceSelection, subtitle: String) -> some View {
        let isSelected = model.settings.aiSource.bundleIdentifier == selection.bundleIdentifier
            && model.settings.aiSource.kind == selection.kind
        return Button {
            model.selectSource(selection)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(selection.kind == .chatGPTDesktop ? "ChatGPT desktop app" : "\(selection.displayName)")
                        .font(.system(size: 13, weight: .medium))
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .contentShape(Rectangle())
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? Color.accentColor.opacity(0.12) : Color.secondary.opacity(0.08))
            )
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    private var chooseMusic: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Which music app?")
                .font(.title3.weight(.semibold))
            Text("Apple Music is the only provider in this release. Oreja pauses and resumes it through macOS automation, which asks for your permission the first time.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 10) {
                Image(systemName: model.media.isMusicRunning ? "music.note" : "music.note.slash")
                    .foregroundStyle(model.media.isMusicRunning ? Color.accentColor : Color.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.media.isMusicRunning ? "Music is running" : "Music is not running")
                        .font(.system(size: 13, weight: .medium))
                    Text(model.media.isMusicRunning
                         ? (model.music?.track.map { "Loaded: \($0.displayName)" } ?? "No track loaded")
                         : "Oreja never launches your music app on its own.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if !model.media.isMusicRunning {
                    Button("Open Music") { model.launchMusic() }
                }
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.08)))

            Button("Check Music access") { model.runConnectionCheck() }
            Text("macOS will ask whether Oreja may control Music. Choose OK; without it Oreja cannot pause or resume anything.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var allowMonitoring: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Allow audio monitoring")
                .font(.title3.weight(.semibold))
            Text("To know when ChatGPT is speaking, Oreja captures a copy of that application's audio output using Apple's Core Audio process taps. Only levels are computed; audio is never stored.")
                .fixedSize(horizontal: false, vertical: true)
            BulletList(items: [
                "macOS will ask for Screen & System Audio Recording permission. Oreja needs the audio part only.",
                "You do not need to share your screen, and Oreja does not request microphone access.",
                "The permission is required by macOS 14.2+ for any process tap, including this one.",
            ])
            HStack {
                Button("Open System Settings") { model.openSystemAudioSettings() }
                Button("Try audio capture now") { model.runConnectionCheck() }
            }
            if !model.hasAudioPermission {
                Label("Audio capture permission is missing right now.", systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
    }

    private var liveTest: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Verify it actually works")
                .font(.title3.weight(.semibold))
            Text("Follow these steps in order. Oreja reports only what it could verify.")
                .foregroundStyle(.secondary)
            NumberedList(items: [
                "Start a song in Apple Music.",
                "Start a voice conversation in ChatGPT and ask a question.",
                "Watch the check below report ChatGPT audio activity.",
                "Confirm the music paused while the reply played.",
                "Confirm the music resumed after the reply ended.",
            ])
            Button {
                model.runConnectionCheck()
            } label: {
                Label(model.isRunningCheck ? "Checking…" : "Run the checks", systemImage: "checkmark.shield")
            }
            .disabled(model.isRunningCheck)

            if let report = model.report {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(report.steps) { step in
                        CheckRow(step: step)
                    }
                }
                .padding(.top, 4)
                Text(report.hasFailure
                     ? "Some checks failed. That is expected until the missing permission or app is in place."
                     : "Checks passed. Oreja will keep watching and act on real ChatGPT audio.")
                    .font(.caption)
                    .foregroundStyle(report.hasFailure ? Color.orange : Color.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var finish: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Ready")
                .font(.title3.weight(.semibold))
            Text("Oreja now runs from the menu bar. Closing this window leaves automation running.")
                .fixedSize(horizontal: false, vertical: true)

            Toggle("Start Oreja at login", isOn: Binding(
                get: { model.settings.launchAtLogin },
                set: { model.settings.launchAtLogin = $0 }
            ))
            if let error = model.launchAtLoginError {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Toggle("Enable automation now", isOn: Binding(
                get: { model.settings.automationEnabled },
                set: { model.setAutomationEnabled($0) }
            ))

            Text("Quiet interval before music resumes: \(Int(model.settings.resumeDelay * 1000)) ms. You can change it in Settings.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Small building blocks

struct CheckRow: View {
    var step: CheckStep

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: step.symbol)
                .foregroundStyle(step.isFailure ? Color.orange : Color.accentColor)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(step.title)
                    .font(.system(size: 12, weight: .medium))
                Text(step.message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
}

struct BulletList: View {
    var items: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(items, id: \.self) { item in
                HStack(alignment: .top, spacing: 8) {
                    Text("•").foregroundStyle(.secondary)
                    Text(item)
                        .font(.callout)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

struct NumberedList: View {
    var items: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                HStack(alignment: .top, spacing: 8) {
                    Text("\(index + 1).")
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(.secondary)
                    Text(item)
                        .font(.callout)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}
