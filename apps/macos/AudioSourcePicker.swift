import OrejaAudio
import OrejaCore
import SwiftUI

/// Shared app picker for primary speech sources and apps whose audio should yield during speech.
struct AudioSourcePicker: View {
    var primary: [AISourceSelection]
    var targets: [AISourceSelection]
    var onTogglePrimary: (AISourceSelection) -> Void
    var onToggleTarget: (AISourceSelection) -> Void

    @State private var choices: [AudioAppChoice] = []
    @State private var searchText = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            selectionSection(
                title: "Listen to",
                caption: "Any selected app can trigger an interruption.",
                selected: primary,
                isTarget: false
            )
            selectionSection(
                title: "Other app audio",
                caption: "Selected apps are muted while speech is active. Browser media is a separate playback target in Playback settings.",
                selected: targets,
                isTarget: true
            )

            if choices.isEmpty {
                Text("No supported app is open. Open the app you use, then refresh the list.")
                    .font(OrejaTheme.Typography.caption)
                    .foregroundStyle(OrejaTheme.Palette.inkSoft)
            }

            Button("Refresh list") { reload() }
                .controlSize(.small)
        }
        .onAppear { reload() }
    }

    private func groups(isTarget: Bool) -> [(category: AudioSourceCategory, choices: [AudioAppChoice])] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return AudioSourceCategory.allCases.compactMap { category in
            if isTarget && category == .browser { return nil }
            let items = choices.filter {
                $0.category == category
                    && (!isTarget || !AISourceCatalog.isBrowser(bundleIdentifier: $0.id))
                    && (query.isEmpty || $0.selection.displayName.localizedCaseInsensitiveContains(query))
            }
            return items.isEmpty ? nil : (category, items)
        }
    }

    private func reload() {
        choices = RunningApplicationCatalog.choices(including: AISourceCatalog.normalized(primary + targets))
    }

    private func selectionSection(
        title: String,
        caption: String,
        selected: [AISourceSelection],
        isTarget: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(title).font(OrejaTheme.Typography.body).foregroundStyle(OrejaTheme.Palette.ink)
            Text(caption).font(OrejaTheme.Typography.caption).foregroundStyle(OrejaTheme.Palette.inkSoft)
            if title == "Listen to" {
                HStack(spacing: 7) {
                    Image(systemName: "magnifyingglass").foregroundStyle(OrejaTheme.Palette.inkSoft)
                    TextField("Search apps", text: $searchText)
                        .textFieldStyle(.plain)
                        .accessibilityLabel("Search audio apps")
                }
                .padding(.horizontal, 10)
                .frame(height: 32)
                .background(OrejaTheme.Palette.hairline.opacity(0.3))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            ForEach(groups(isTarget: isTarget), id: \.category) { group in
                VStack(alignment: .leading, spacing: 8) {
                    Eyebrow(text: group.category.title)
                    VStack(spacing: 8) {
                        ForEach(group.choices) { choice in
                            row(choice, selected: selected, isTarget: isTarget)
                        }
                    }
                }
            }
        }
    }

    private func row(_ choice: AudioAppChoice, selected: [AISourceSelection], isTarget: Bool) -> some View {
        let on = selected.contains { $0.bundleIdentifier == choice.id }
        let supported = !isTarget || targetControlSupported(choice.id)
        return Button {
            if isTarget { onToggleTarget(choice.selection) } else { onTogglePrimary(choice.selection) }
        } label: {
            HStack(spacing: 11) {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .strokeBorder(on ? OrejaTheme.Palette.accent : OrejaTheme.Palette.hairline, lineWidth: 1)
                    .background(
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(on ? OrejaTheme.Palette.accent : Color.clear)
                    )
                    .frame(width: 14, height: 14)
                    .overlay {
                        if on {
                            Image(systemName: "checkmark")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundStyle(OrejaTheme.Palette.ink)
                        }
                    }

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(choice.selection.displayName)
                            .font(.system(size: 12.5, weight: .medium))
                            .foregroundStyle(OrejaTheme.Palette.ink)
                        if choice.selection.isExperimental {
                            Text("experimental")
                                .font(OrejaTheme.Typography.micro)
                                .foregroundStyle(OrejaTheme.Palette.warning)
                        }
                    }
                    Text(supported ? status(for: choice) : (on ? "Selected, but this app has no supported audio control; click to remove" : "Audio control is not available for this app"))
                        .font(OrejaTheme.Typography.micro)
                        .foregroundStyle(OrejaTheme.Palette.inkSoft)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(on ? OrejaTheme.Palette.accent.opacity(0.08) : OrejaTheme.Palette.hairline.opacity(0.3))
            )
        }
        .buttonStyle(.plain)
        .disabled(!supported && !on)
        .accessibilityLabel(choice.selection.displayName)
        .accessibilityValue(supported ? status(for: choice) : (on ? "Selected but unsupported; activate to remove" : "Audio control is not available"))
        .accessibilityAddTraits(on ? [.isSelected] : [])
    }

    private func status(for choice: AudioAppChoice) -> String {
        if choice.isProducingOutput { return "Playing audio now" }
        if choice.isRunning { return "Running" }
        if choice.isInstalled { return "Installed, not running" }
        return "Not running"
    }

    private func targetControlSupported(_ bundleIdentifier: String) -> Bool {
        if AISourceCatalog.isBrowser(bundleIdentifier: bundleIdentifier) {
            return BrowserAudioController.supportedBrowserBundleIDs.contains(bundleIdentifier)
        }
        return AISourceCatalog.supportsTargetMute(bundleIdentifier: bundleIdentifier)
    }
}
