import OrejaAudio
import OrejaCore
import SwiftUI

/// Multi-select list of the apps Oreja can listen to, grouped by category. Used by onboarding and
/// Settings so both show the same choices and the same status.
struct AudioSourcePicker: View {
    var selected: [AISourceSelection]
    var onToggle: (AISourceSelection) -> Void

    @State private var choices: [AudioAppChoice] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(groups, id: \.category) { group in
                VStack(alignment: .leading, spacing: 8) {
                    Eyebrow(text: group.category.title)
                    VStack(spacing: 8) {
                        ForEach(group.choices) { choice in
                            row(choice)
                        }
                    }
                }
            }

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

    private var groups: [(category: AudioSourceCategory, choices: [AudioAppChoice])] {
        AudioSourceCategory.allCases.compactMap { category in
            let items = choices.filter { $0.category == category }
            return items.isEmpty ? nil : (category, items)
        }
    }

    private func reload() {
        choices = RunningApplicationCatalog.choices(including: selected)
    }

    private func isSelected(_ choice: AudioAppChoice) -> Bool {
        selected.contains { $0.bundleIdentifier == choice.id }
    }

    private func row(_ choice: AudioAppChoice) -> some View {
        let on = isSelected(choice)
        return Button {
            onToggle(choice.selection)
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
                    Text(status(for: choice))
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
        .accessibilityLabel(choice.selection.displayName)
        .accessibilityValue(status(for: choice))
        .accessibilityAddTraits(on ? [.isSelected] : [])
    }

    private func status(for choice: AudioAppChoice) -> String {
        if choice.isProducingOutput { return "Playing audio now" }
        if choice.isRunning { return "Running" }
        if choice.isInstalled { return "Installed, not running" }
        return "Not running"
    }
}
