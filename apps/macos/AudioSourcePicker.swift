import OrejaAudio
import OrejaCore
import SwiftUI

/// Which list an `AppSelectionList` edits.
enum AppListMode {
    /// Apps whose speech starts an interruption ("Listen to").
    case sources
    /// Apps lowered or silenced while someone speaks ("Lower these apps").
    case targets
}

/// One app list: search, compact rows, selected apps first, rarely used apps behind "Show all".
///
/// Sources and targets are separate lists on separate pages. An app chosen in the other list is
/// shown with that note instead of being hidden, and choosing it here moves it (an app is never both
/// the conversation and something that gets lowered).
struct AppSelectionList: View {
    var mode: AppListMode
    var selected: [AISourceSelection]
    var otherList: [AISourceSelection]
    var onToggle: (AISourceSelection) -> Void
    /// Sources only: moves a source that is playing media into "Lower these apps".
    var onMoveToTargets: ((AISourceSelection) -> Void)?

    @State private var choices: [AudioAppChoice] = []
    @State private var searchText = ""
    @State private var showAll = false

    private static let refreshNanos: UInt64 = 3_000_000_000

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            summary

            if mode == .sources {
                ForEach(sourcesPlayingAudio) { choice in
                    mediaPlayingNotice(choice)
                }
            }

            searchField

            let groups = visibleGroups
            if groups.isEmpty {
                Text(searchText.isEmpty
                     ? "No matching app is open. Open the app you use, or show all apps."
                     : "No app matches “\(searchText)”.")
                    .font(OrejaTheme.Typography.caption)
                    .foregroundStyle(OrejaTheme.Palette.inkSoft)
            }

            ForEach(groups, id: \.category) { group in
                VStack(alignment: .leading, spacing: 4) {
                    Eyebrow(text: group.category.title)
                        .padding(.top, 4)
                    ForEach(group.choices) { choice in
                        row(choice)
                    }
                }
            }

            HStack(spacing: 12) {
                if searchText.isEmpty, hiddenCount > 0 || showAll {
                    Button(showAll ? "Show fewer apps" : "Show all apps (\(hiddenCount) more)") {
                        showAll.toggle()
                    }
                    .buttonStyle(.link)
                    .font(OrejaTheme.Typography.caption)
                }
                Spacer(minLength: 0)
                Button("Refresh list") { reload() }
                    .controlSize(.small)
            }
        }
        .onAppear { reload() }
        .task {
            // Keep "Playing audio now" honest while the page is open.
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: Self.refreshNanos)
                reload()
            }
        }
    }

    // MARK: Pieces

    private var summary: some View {
        let names = selected.map(\.displayName)
        let text: String
        switch mode {
        case .sources:
            text = names.isEmpty
                ? "Nothing selected: Oreja is not listening to any app."
                : "Listening to \(Self.list(names))."
        case .targets:
            text = names.isEmpty
                ? "No other apps are lowered. Apple Music is always handled on its own."
                : "Lowering \(Self.list(names)) while someone speaks."
        }
        return Text(text)
            .font(.system(size: 12.5, weight: .medium))
            .foregroundStyle(names.isEmpty && mode == .sources ? OrejaTheme.Palette.warning : OrejaTheme.Palette.ink)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var searchField: some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(OrejaTheme.Palette.inkSoft)
                .accessibilityHidden(true)
            TextField("Search apps", text: $searchText)
                .textFieldStyle(.plain)
                .accessibilityLabel(mode == .sources ? "Search apps to listen to" : "Search apps to lower")
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.plain)
                .foregroundStyle(OrejaTheme.Palette.inkSoft)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 30)
        .background(OrejaTheme.Palette.hairline.opacity(0.3))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func mediaPlayingNotice(_ choice: AudioAppChoice) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            InlineNotice(
                text: "\(choice.selection.displayName) is playing audio now. If that is music or a video, Oreja treats it as speech and keeps interrupting. To lower it while someone speaks instead, move it to “Lower these apps”.",
                symbol: "exclamationmark.triangle.fill"
            )
            if let onMoveToTargets {
                Button("Lower \(choice.selection.displayName) instead") { onMoveToTargets(choice.selection) }
                    .controlSize(.small)
            }
        }
    }

    private func row(_ choice: AudioAppChoice) -> some View {
        let on = isSelected(choice)
        let inOtherList = otherList.contains { $0.bundleIdentifier == choice.id }
        let supported = isSupported(choice)
        let status = statusText(choice, on: on, inOtherList: inOtherList, supported: supported)
        return Button {
            onToggle(choice.selection)
        } label: {
            HStack(spacing: 10) {
                checkbox(on)
                Text(choice.selection.displayName)
                    .font(.system(size: 12.5, weight: on ? .semibold : .regular))
                    .foregroundStyle(supported || on ? OrejaTheme.Palette.ink : OrejaTheme.Palette.inkSoft)
                    .lineLimit(1)
                // The browser group title already says "experimental"; repeating it per row is noise.
                if choice.selection.isExperimental, choice.category != .browser {
                    Text("experimental")
                        .font(OrejaTheme.Typography.micro)
                        .foregroundStyle(OrejaTheme.Palette.warning)
                }
                Spacer(minLength: 8)
                if choice.isProducingOutput {
                    Image(systemName: "speaker.wave.2.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(OrejaTheme.Palette.accent)
                        .accessibilityHidden(true)
                }
                Text(status)
                    .font(OrejaTheme.Typography.micro)
                    .foregroundStyle(OrejaTheme.Palette.inkSoft)
                    .lineLimit(1)
            }
            .padding(.horizontal, 10)
            .frame(minHeight: 30)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(on ? OrejaTheme.Palette.accent.opacity(0.10) : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .disabled(!supported && !on)
        .help(helpText(choice, inOtherList: inOtherList, supported: supported))
        .accessibilityLabel(choice.selection.displayName)
        .accessibilityValue(status)
        .accessibilityAddTraits(on ? [.isSelected] : [])
    }

    private func checkbox(_ on: Bool) -> some View {
        RoundedRectangle(cornerRadius: 4, style: .continuous)
            .strokeBorder(on ? OrejaTheme.Palette.accent : OrejaTheme.Palette.inkSoft.opacity(0.5), lineWidth: 1)
            .background(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(on ? OrejaTheme.Palette.accent : Color.clear)
            )
            .frame(width: 14, height: 14)
            .overlay {
                if on {
                    Image(systemName: "checkmark")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(OrejaTheme.Palette.paper)
                }
            }
            .accessibilityHidden(true)
    }

    // MARK: Rules

    private func isSelected(_ choice: AudioAppChoice) -> Bool {
        selected.contains { $0.bundleIdentifier == choice.id }
    }

    /// Whether the app may be chosen in this list at all.
    private func isSupported(_ choice: AudioAppChoice) -> Bool {
        switch mode {
        case .sources: AISourceCatalog.isSelectable(bundleIdentifier: choice.id)
        case .targets: AISourceCatalog.isTargetSelectable(bundleIdentifier: choice.id)
        }
    }

    /// Whether the app belongs in the list without "Show all apps".
    private func isRelevant(_ choice: AudioAppChoice) -> Bool {
        if isSelected(choice) || choice.isProducingOutput { return true }
        switch mode {
        case .sources:
            switch choice.category {
            case .aiAssistant: return true
            case .music: return false
            case .other: return false
            default: return choice.isRunning
            }
        case .targets:
            switch choice.category {
            case .browser: return choice.isRunning || choice.isInstalled
            case .music: return choice.isRunning || choice.isInstalled
            case .media: return choice.isRunning
            default: return false
            }
        }
    }

    /// Apps that can never appear in this list (a music player is never a speech source).
    private func isListable(_ choice: AudioAppChoice) -> Bool {
        mode == .targets || choice.category != .music
    }

    private var listable: [AudioAppChoice] {
        choices.filter(isListable)
    }

    private var hiddenCount: Int {
        listable.filter { !isRelevant($0) }.count
    }

    private var visibleGroups: [(category: AudioSourceCategory, choices: [AudioAppChoice])] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let visible = listable.filter { choice in
            if !query.isEmpty { return choice.selection.displayName.localizedCaseInsensitiveContains(query) }
            return showAll || isRelevant(choice)
        }
        return categoryOrder.compactMap { category in
            let items = visible
                .filter { $0.category == category }
                .sorted { lhs, rhs in
                    let left = isSelected(lhs), right = isSelected(rhs)
                    if left != right { return left }
                    return lhs.selection.displayName.localizedCaseInsensitiveCompare(rhs.selection.displayName) == .orderedAscending
                }
            return items.isEmpty ? nil : (category, items)
        }
    }

    /// The lowered list leads with what people actually lower: browsers and music players.
    private var categoryOrder: [AudioSourceCategory] {
        switch mode {
        case .sources: [.aiAssistant, .browser, .codingAgent, .calling, .media, .other]
        case .targets: [.browser, .music, .media, .calling, .aiAssistant, .codingAgent, .other]
        }
    }

    private var sourcesPlayingAudio: [AudioAppChoice] {
        choices.filter { choice in
            isSelected(choice)
                && choice.isProducingOutput
                && [.browser, .media, .other].contains(choice.category)
                && AISourceCatalog.isTargetSelectable(bundleIdentifier: choice.id)
        }
    }

    private func statusText(_ choice: AudioAppChoice, on: Bool, inOtherList: Bool, supported: Bool) -> String {
        if !supported {
            return on ? "Not supported, click to remove" : "Not supported"
        }
        if inOtherList {
            return mode == .sources ? "Lowered in Playback" : "Used in Listen to"
        }
        if choice.isProducingOutput { return "Playing audio now" }
        if choice.isRunning { return "Running" }
        if choice.isInstalled { return "Not running" }
        return "Not found"
    }

    private func helpText(_ choice: AudioAppChoice, inOtherList: Bool, supported: Bool) -> String {
        if !supported {
            if choice.id == "com.apple.Safari" {
                return "Safari plays audio through a WebKit process shared with other apps, so Oreja cannot lower it alone."
            }
            if choice.id == "com.apple.Music" {
                return "Apple Music is paused or lowered directly; it does not need to be in this list."
            }
            return "This app cannot be used here."
        }
        if inOtherList {
            return mode == .sources
                ? "Selected under “Lower these apps”. Choosing it here moves it: an app is either the conversation or something that gets lowered."
                : "Selected under “Listen to”. Choosing it here moves it: an app is either the conversation or something that gets lowered."
        }
        return choice.selection.displayName
    }

    private func reload() {
        choices = RunningApplicationCatalog.choices(including: selected + otherList)
    }

    private static func list(_ names: [String]) -> String {
        switch names.count {
        case 0: return ""
        case 1: return names[0]
        case 2: return "\(names[0]) and \(names[1])"
        default: return names.dropLast().joined(separator: ", ") + " and " + (names.last ?? "")
        }
    }
}

/// Onboarding shows both lists on one step; Settings shows them on separate pages.
struct AudioSourcePicker: View {
    var primary: [AISourceSelection]
    var targets: [AISourceSelection]
    var onTogglePrimary: (AISourceSelection) -> Void
    var onToggleTarget: (AISourceSelection) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Listen to").font(OrejaTheme.Typography.sectionTitle).foregroundStyle(OrejaTheme.Palette.ink)
                AppSelectionList(
                    mode: .sources,
                    selected: primary,
                    otherList: targets,
                    onToggle: onTogglePrimary,
                    onMoveToTargets: onToggleTarget
                )
            }
            Hairline()
            VStack(alignment: .leading, spacing: 6) {
                Text("Lower these apps").font(OrejaTheme.Typography.sectionTitle).foregroundStyle(OrejaTheme.Palette.ink)
                AppSelectionList(
                    mode: .targets,
                    selected: targets,
                    otherList: primary,
                    onToggle: onToggleTarget
                )
            }
        }
    }
}
