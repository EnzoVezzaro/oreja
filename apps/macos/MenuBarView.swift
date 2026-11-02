import AppKit
import SwiftUI
import OrejaCore

/// The menu bar panel: one status, one switch, and the few actions a user actually needs.
struct MenuBarView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            header
            Hairline()
            statusBlock
            if let error = model.lastError, model.state == .error || model.state == .permissionRequired {
                noticeBlock(error)
            }
            musicBlock
            Hairline()
            actions
        }
        .frame(width: OrejaTheme.Metrics.panelWidth)
        .background(OrejaTheme.Palette.paper)
        .tint(OrejaTheme.Palette.accent)
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 9) {
            BrandMark(size: 32)
            BrandWordmark(size: 19)
            Spacer(minLength: 8)
            Toggle(
                "Automation",
                isOn: Binding(
                    get: { model.settings.automationEnabled },
                    set: { model.setAutomationEnabled($0) }
                )
            )
            .toggleStyle(.switch)
            .labelsHidden()
            .controlSize(.regular)
            .tint(OrejaTheme.Palette.accent)
            .accessibilityLabel("Automation")
            .accessibilityHint("Pauses music while ChatGPT speaks and resumes it afterwards.")
        }
        .padding(.horizontal, OrejaTheme.Metrics.gutter)
        .padding(.top, 18)
        .padding(.bottom, 16)
    }

    // MARK: Status

    private var statusBlock: some View {
        HStack(alignment: .top, spacing: 9) {
            StatusDot(color: model.state.tint, isActive: model.state.isActive)
                .padding(.top, 6)
            VStack(alignment: .leading, spacing: 3) {
                Text(model.state.title)
                    .font(.system(size: 14, weight: .semibold))
                    .tracking(-0.15)
                    .foregroundStyle(OrejaTheme.Palette.ink)
                Text(model.state.detail)
                    .font(.system(size: 12))
                    .lineSpacing(1.5)
                    .foregroundStyle(OrejaTheme.Palette.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
                if model.state == .permissionRequired {
                    HStack(spacing: 12) {
                        Button("Audio settings") { model.openSystemAudioSettings() }
                        Button("Automation settings") { model.openAutomationSettings() }
                    }
                    .buttonStyle(.link)
                    .font(.system(size: 11))
                    .padding(.top, 3)
                }
            }
            Spacer(minLength: 0)
            VincentCompanion(size: 80, isListening: model.state.isActive, isMusicPlaying: model.music?.isPlaying == true)
        }
        .padding(.horizontal, OrejaTheme.Metrics.gutter)
        .padding(.top, 18)
        .padding(.bottom, 18)
    }

    private func noticeBlock(_ error: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 10))
                .foregroundStyle(OrejaTheme.Palette.warning)
                .padding(.top, 1)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 5) {
                Text(error)
                    .font(OrejaTheme.Typography.micro)
                    .foregroundStyle(OrejaTheme.Palette.ink)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 12) {
                    Button("Retry") {
                        model.coordinator.retryAfterError()
                        model.startMonitoringIfNeeded()
                    }
                    Button("Diagnostics") { model.showDiagnostics() }
                }
                .buttonStyle(.link)
                .font(.system(size: 10.5))
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(OrejaTheme.Palette.warning.opacity(0.09))
        )
        .padding(.horizontal, OrejaTheme.Metrics.gutter)
        .padding(.bottom, 10)
    }

    // MARK: Music

    private var musicBlock: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 7) {
                Image(systemName: model.music?.isPlaying == true ? "music.note" : "music.note.list")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(OrejaTheme.Palette.inkSoft)
                    .frame(width: 12)
                    .accessibilityHidden(true)
                Text(musicTitle)
                    .font(.system(size: 11))
                    .foregroundStyle(OrejaTheme.Palette.inkSoft)
                    .lineLimit(1)
            }
            if let track = model.music?.track,
               model.music?.isPlaying == true || model.music?.isPaused == true {
                Text(track.displayName)
                    .font(OrejaTheme.Typography.micro)
                    .foregroundStyle(OrejaTheme.Palette.inkSoft)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .padding(.leading, 19)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, OrejaTheme.Metrics.gutter)
        .padding(.bottom, 18)
    }

    private var musicTitle: String {
        guard let music = model.music else { return "Apple Music: not checked yet" }
        switch music.state {
        case .playing: return "Apple Music is playing"
        case .paused: return "Apple Music is paused"
        case .stopped: return "Apple Music is idle"
        case .permissionRequired: return "Apple Music needs automation permission"
        case .unavailable: return "Apple Music is not available"
        }
    }

    // MARK: Actions

    private var actions: some View {
        VStack(spacing: 2) {
            if model.state.holdsPause {
                Button {
                    model.coordinator.setAutomationEnabled(false)
                    model.setAutomationEnabled(false)
                } label: {
                    HStack(spacing: 7) {
                        Image(systemName: "play.fill")
                            .font(.system(size: 9, weight: .semibold))
                        Text("Resume music now")
                            .font(.system(size: 12, weight: .medium))
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 10)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(OrejaTheme.Palette.onAccent)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(OrejaTheme.Palette.accent)
                )
                .padding(.bottom, 4)
            }

            QuietRow(
                title: model.isRunningCheck ? "Running checks…" : "Connection test",
                systemImage: "checkmark.shield",
                isEnabled: !model.isRunningCheck
            ) {
                model.runConnectionCheck()
                model.showDiagnostics()
            }

            QuietRow(title: "Settings", systemImage: "gearshape", shortcut: "⌘,", key: ",") {
                model.showSettings()
            }

            QuietRow(title: "Diagnostics", systemImage: "stethoscope", action: model.showDiagnostics)

            QuietRow(title: "Quit Oreja", systemImage: "power", shortcut: "⌘Q", key: "q") {
                NSApplication.shared.terminate(nil)
            }
        }
        .padding(8)
    }
}
