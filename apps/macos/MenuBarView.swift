import SwiftUI
import OrejaCore

/// The menu bar panel: one status, one switch, and the few actions a user actually needs.
struct MenuBarView: View {
    @ObservedObject var model: AppModel
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            Divider()
            statusBlock
            if let error = model.lastError, model.state == .error || model.state == .permissionRequired {
                errorBlock(error)
            }
            Divider()
            musicBlock
            Divider()
            actions
        }
        .padding(16)
        .frame(width: 340)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: model.state.menuBarSymbol)
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(model.state.tint)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text("Oreja de Van Gogh")
                    .font(.headline)
                Text("Your AI talks. Your music listens.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Toggle(
                "Automation",
                isOn: Binding(
                    get: { model.settings.automationEnabled },
                    set: { model.setAutomationEnabled($0) }
                )
            )
            .toggleStyle(.switch)
            .labelsHidden()
            .controlSize(.small)
            .accessibilityLabel("Automation")
            .accessibilityHint("Pauses music while ChatGPT speaks and resumes it afterwards.")
        }
    }

    private var statusBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(model.state.title)
                .font(.system(size: 13, weight: .semibold))
            Text(model.state.detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if model.state == .permissionRequired {
                HStack(spacing: 8) {
                    Button("Open audio recording settings") { model.openSystemAudioSettings() }
                    Button("Open automation settings") { model.openAutomationSettings() }
                }
                .buttonStyle(.link)
                .font(.caption)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func errorBlock(_ error: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(error)
                    .font(.caption)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    Button("Retry") {
                        model.coordinator.retryAfterError()
                        model.startMonitoringIfNeeded()
                    }
                    Button("Diagnostics") { model.showDiagnostics() }
                }
                .buttonStyle(.link)
                .font(.caption)
            }
        }
    }

    private var musicBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: model.music?.isPlaying == true ? "music.note" : "music.note.list")
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                Text(musicTitle)
                    .font(.caption)
                    .lineLimit(1)
            }
            if let track = model.music?.track, model.music?.isPlaying == true || model.music?.isPaused == true {
                Text(track.displayName)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
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

    private var actions: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                model.runConnectionCheck()
                model.showDiagnostics()
            } label: {
                Label("Run connection test", systemImage: "checkmark.shield")
            }
            .disabled(model.isRunningCheck)

            Button {
                model.showSettings()
            } label: {
                Label("Settings…", systemImage: "gearshape")
            }
            .keyboardShortcut(",", modifiers: .command)

            Button {
                model.showDiagnostics()
            } label: {
                Label("Diagnostics…", systemImage: "stethoscope")
            }

            if model.state.holdsPause {
                Button {
                    model.coordinator.setAutomationEnabled(false)
                    model.setAutomationEnabled(false)
                } label: {
                    Label("Resume my music now", systemImage: "play.fill")
                }
            }

            Divider()

            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Label("Quit Oreja", systemImage: "power")
            }
            .keyboardShortcut("q", modifiers: .command)
        }
        .buttonStyle(.borderless)
        .labelStyle(.titleAndIcon)
        .font(.system(size: 12))
    }
}
