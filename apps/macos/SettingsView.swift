import SwiftUI
import OrejaCore

struct SettingsView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        Form {
            Section("Behavior") {
                Toggle("Automation enabled", isOn: Binding(
                    get: { model.settings.automationEnabled },
                    set: { model.setAutomationEnabled($0) }
                ))
                Text("When off, Oreja never touches playback.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Quiet interval before music resumes")
                        Spacer()
                        Text("\(Int(model.settings.resumeDelay * 1000)) ms")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    Slider(
                        value: Binding(
                            get: { model.settings.resumeDelay },
                            set: { model.settings.resumeDelay = $0 }
                        ),
                        in: AppSettings.resumeDelayRange,
                        step: 0.05
                    )
                    Text("Longer values tolerate natural pauses between sentences; shorter values resume music faster.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("AI source") {
                Picker("Listen to", selection: Binding(
                    get: { model.settings.aiSource },
                    set: { model.selectSource($0) }
                )) {
                    Text("ChatGPT desktop app")
                        .tag(AISourceSelection.chatGPTDesktop)
                    Text("Google Chrome (experimental)").tag(AISourceSelection.chrome)
                    Text("Safari (experimental)").tag(AISourceSelection.safari)
                }
                Text("Browser sources capture every tab in that browser; use them only for dedicated ChatGPT windows.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Music") {
                Picker("Provider", selection: Binding(
                    get: { model.settings.musicProvider },
                    set: { model.settings.musicProvider = $0 }
                )) {
                    Text("Apple Music").tag(MediaProviderID.appleMusic)
                }
                HStack {
                    Button("Open Music") { model.launchMusic() }
                    Button("Check permissions") { model.runConnectionCheck() }
                }
                if !model.hasAudioPermission {
                    Label("Audio recording permission is missing.", systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }

            Section("Startup") {
                Toggle("Start Oreja at login", isOn: Binding(
                    get: { model.settings.launchAtLogin },
                    set: { model.settings.launchAtLogin = $0 }
                ))
                if let error = model.launchAtLoginError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Section("Privacy") {
                Toggle("Verbose diagnostics", isOn: Binding(
                    get: { model.settings.verboseDiagnostics },
                    set: { model.settings.verboseDiagnostics = $0 }
                ))
                Text("Diagnostics never contain audio, prompts or replies. Only Oreja's own state changes and permission results are kept, in memory.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Permissions") {
                HStack {
                    Button("Audio recording…") { model.openSystemAudioSettings() }
                    Button("Automation…") { model.openAutomationSettings() }
                }
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 520, minHeight: 540)
    }
}
