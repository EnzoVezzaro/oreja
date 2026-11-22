import OrejaCore
import SwiftUI

/// Settings › Playback: what happens to playback while someone speaks.
struct PlaybackSettingsPage: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            whenSomeoneSpeaks
            timing
            appleMusic
            otherApps
        }
    }

    // MARK: When someone speaks

    private var whenSomeoneSpeaks: some View {
        ThemeSection(title: "When someone speaks") {
            VStack(alignment: .leading, spacing: 14) {
                SettingToggle(
                    "Automation",
                    detail: "When off, Oreja never touches playback.",
                    isOn: Binding(
                        get: { model.settings.automationEnabled },
                        set: { model.setAutomationEnabled($0) }
                    )
                )

                Hairline()

                VStack(alignment: .leading, spacing: 4) {
                    SettingRow("Interruption") {
                        Picker("Interruption", selection: Binding(
                            get: { model.settings.interruptionMode },
                            set: { model.settings.interruptionMode = $0 }
                        )) {
                            Text("Pause").tag(MusicInterruptionMode.pause)
                            Text("Lower volume").tag(MusicInterruptionMode.duck)
                        }
                        .labelsHidden()
                        .pickerStyle(.segmented)
                        .frame(width: 210)
                    }
                    SettingDetail(model.settings.interruptionMode == .duck
                        ? "Apple Music and the apps under “Lower these apps” drop to the level below, then come back."
                        : "Apple Music pauses and resumes where it was. Apps under “Lower these apps” are silenced instead, because they offer no pause control Oreja can reach.")
                }

                if model.settings.interruptionMode == .duck {
                    SettingSlider(
                        title: "Lower to",
                        valueText: "\(model.settings.duckVolumePercent)%",
                        detail: nil,
                        value: Binding(
                            get: { Double(model.settings.duckVolumePercent) },
                            set: { model.settings.duckVolumePercent = Int($0.rounded()) }
                        ),
                        range: 1...100,
                        step: 1
                    )
                    SettingSlider(
                        title: "Return Apple Music to",
                        valueText: "\(model.settings.restoreVolumePercent)%",
                        detail: "Other apps always return to their own volume.",
                        value: Binding(
                            get: { Double(model.settings.restoreVolumePercent) },
                            set: { model.settings.restoreVolumePercent = Int($0.rounded()) }
                        ),
                        range: 1...100,
                        step: 1
                    )
                }

                Hairline()

                SettingRow(
                    "Try your setup",
                    detail: model.settings.automationEnabled
                        ? "Runs the interruption for 4 seconds, as if someone spoke. Start some music first."
                        : "Turn automation on to try the interruption."
                ) {
                    Button(model.isPreviewingInterruption ? "Testing…" : "Test interruption") {
                        model.previewInterruption()
                    }
                    .controlSize(.regular)
                    .disabled(model.isPreviewingInterruption || !model.settings.automationEnabled)
                }
            }
        }
    }

    // MARK: Timing

    private var timing: some View {
        ThemeSection(
            title: "Timing",
            caption: "Two waits decide when playback comes back. The longer one wins."
        ) {
            VStack(alignment: .leading, spacing: 14) {
                SettingSlider(
                    title: "Wait after speech stops",
                    valueText: model.settings.resumeDelay < 0.025
                        ? "No wait"
                        : String(format: model.settings.resumeDelay.truncatingRemainder(dividingBy: 0.1) < 0.025 ? "%.1f s" : "%.2f s", model.settings.resumeDelay),
                    detail: "Bridges the short pauses between sentences.",
                    value: Binding(
                        get: { model.settings.resumeDelay },
                        set: { model.settings.resumeDelay = $0 }
                    ),
                    range: AppSettings.resumeDelayRange,
                    step: 0.05
                )

                Hairline()

                SettingToggle(
                    "Hold through a conversation",
                    detail: "Keeps playback paused or lowered while the assistant thinks and you answer.",
                    isOn: Binding(
                        get: { model.settings.holdThroughConversation },
                        set: { model.settings.holdThroughConversation = $0 }
                    )
                )

                if model.settings.holdThroughConversation {
                    SettingSlider(
                        title: "Restore after",
                        valueText: holdText,
                        detail: "Seconds of complete quiet before the conversation counts as over. Raise it if playback returns while the assistant is still working.",
                        value: Binding(
                            get: { model.settings.conversationHold },
                            set: { model.settings.conversationHold = $0 }
                        ),
                        range: AppSettings.conversationHoldRange,
                        step: 1
                    )
                }
            }
        }
    }

    private var holdText: String {
        let seconds = Int(model.settings.conversationHold)
        return seconds < 60 ? "\(seconds) s" : "\(seconds / 60) min"
    }

    // MARK: Apple Music

    private var appleMusic: some View {
        ThemeSection(
            title: "Apple Music",
            caption: "Paused and resumed, or lowered and restored, directly. Oreja never starts music you paused yourself."
        ) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 10) {
                    Image(systemName: "music.note")
                        .foregroundStyle(OrejaTheme.Palette.accent)
                        .frame(width: 18)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Apple Music")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(OrejaTheme.Palette.ink)
                        Text(musicStatus)
                            .font(OrejaTheme.Typography.micro)
                            .foregroundStyle(OrejaTheme.Palette.inkSoft)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 8)
                    Button("Open Music") { model.launchMusic() }
                        .controlSize(.small)
                    Button(model.isRunningCheck ? "Checking…" : "Check connection") { model.runConnectionCheck() }
                        .controlSize(.small)
                        .disabled(model.isRunningCheck)
                }
                .accessibilityElement(children: .contain)

                if let report = model.report {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(report.steps) { step in
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Image(systemName: step.symbol)
                                    .foregroundStyle(step.isFailure ? OrejaTheme.Palette.warning : OrejaTheme.Palette.accent)
                                    .accessibilityHidden(true)
                                Text(step.title)
                                    .font(.system(size: 12))
                                    .foregroundStyle(OrejaTheme.Palette.ink)
                                Spacer(minLength: 8)
                                Text(step.message)
                                    .font(OrejaTheme.Typography.micro)
                                    .foregroundStyle(OrejaTheme.Palette.inkSoft)
                                    .multilineTextAlignment(.trailing)
                            }
                            .accessibilityElement(children: .combine)
                        }
                    }
                }

                if !model.hasAudioPermission {
                    InlineNotice(text: "Audio recording permission is missing, so Oreja cannot hear the selected apps.", symbol: "exclamationmark.triangle.fill")
                }

                InlineNotice(
                    text: "Spotify, VLC, a browser playing YouTube and other players are handled under “Lower these apps” below: lowered, or silenced in pause mode. Oreja cannot pause them, because they offer no supported control.",
                    symbol: "info.circle",
                    isInformational: true
                )
            }
        }
    }

    private var musicStatus: String {
        guard let music = model.music else { return "Checking…" }
        switch music.state {
        case .playing:
            if let track = music.track { return "Playing “\(track.title)”" }
            return "Playing"
        case .paused: return model.state == .musicPausedByOreja ? "Paused by Oreja" : "Paused"
        case .stopped: return "Stopped"
        case .unavailable: return "Not running"
        case .permissionRequired: return "Needs Automation permission (Privacy page)"
        }
    }

    // MARK: Other apps

    private var otherApps: some View {
        ThemeSection(
            title: "Lower these apps",
            caption: "Any app that plays audio: a browser with YouTube, Spotify, VLC. While someone speaks Oreja lowers it to your level, or silences it in pause mode, then restores it. Safari is not supported. A browser you use for ChatGPT Web cannot also be lowered, so play music in another browser."
        ) {
            AppSelectionList(
                mode: .targets,
                selected: model.settings.targetAudioApps,
                otherList: model.settings.aiSources,
                onToggle: model.toggleTargetAudioApp
            )
        }
    }
}
