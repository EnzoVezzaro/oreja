import SwiftUI
import OrejaCore

/// Troubleshooting surface. It only ever shows Oreja's own state and permission results; no audio,
/// prompt or reply content exists to display.
struct DiagnosticsView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            header
            Hairline()
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    metrics
                    if let report = model.report {
                        checks(report)
                    }
                    events
                }
                .frame(maxWidth: 560, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.horizontal, 24)
                .padding(.vertical, 20)
            }
        }
        .frame(minWidth: 600, minHeight: 560)
        .background(OrejaTheme.Palette.paper)
        .tint(OrejaTheme.Palette.accent)
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .top, spacing: 10) {
            StatusDot(color: model.state.tint, isActive: model.state.isActive)
                .padding(.top, 7)
            VStack(alignment: .leading, spacing: 3) {
                Text(model.state.title)
                    .font(.system(size: 17, weight: .semibold))
                    .tracking(-0.25)
                    .foregroundStyle(OrejaTheme.Palette.ink)
                Text(model.state.detail)
                    .font(OrejaTheme.Typography.caption)
                    .foregroundStyle(OrejaTheme.Palette.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
            Button(model.isRunningCheck ? "Checking…" : "Run checks") { model.runConnectionCheck() }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(model.isRunningCheck)
        }
        .padding(.horizontal, 24)
        .padding(.top, 20)
        .padding(.bottom, 16)
    }

    // MARK: Metrics

    private var metrics: some View {
        ThemeSection(title: "Session") {
            Grid(alignment: .leading, horizontalSpacing: 28, verticalSpacing: 14) {
                GridRow {
                    metric("Monitored source", model.sourceDescription.isEmpty ? "—" : model.sourceDescription)
                    metric("Pauses issued", "\(model.coordinator.statistics.pausesIssued)")
                    metric("Manual overrides", "\(model.coordinator.statistics.manualOverrides)")
                }
                GridRow {
                    metric("Last pause", milliseconds(model.coordinator.statistics.lastPauseLatency))
                    metric("Last resume", milliseconds(model.coordinator.statistics.lastResumeLatency))
                    metric("Failed commands", "\(model.coordinator.statistics.failedCommands)")
                }
            }
        }
    }

    private func metric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(OrejaTheme.Typography.micro)
                .foregroundStyle(OrejaTheme.Palette.inkSoft)
            Text(value)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(OrejaTheme.Palette.ink)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func milliseconds(_ value: TimeInterval?) -> String {
        guard let value else { return "—" }
        return String(format: "%.0f ms", value * 1000)
    }

    // MARK: Checks

    private func checks(_ report: ConnectionCheckReport) -> some View {
        ThemeSection(title: "Last check") {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(report.steps) { step in
                    CheckRow(step: step)
                }
            }
        }
    }

    // MARK: Events

    private var events: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Eyebrow(text: "Events")
                Spacer(minLength: 8)
                Button("Clear") { model.diagnostics.clear() }
                    .buttonStyle(.link)
                    .font(.system(size: 10))
            }

            ThemeCard {
                if model.diagnostics.events.isEmpty {
                    Text("Nothing recorded yet.")
                        .font(OrejaTheme.Typography.micro)
                        .foregroundStyle(OrejaTheme.Palette.inkSoft)
                        .frame(maxWidth: .infinity, minHeight: 120, alignment: .center)
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 5) {
                            ForEach(model.diagnostics.events.reversed()) { event in
                                HStack(alignment: .top, spacing: 8) {
                                    Text(event.date, format: .dateTime.hour().minute().second())
                                        .font(.system(size: 9.5, design: .monospaced))
                                        .foregroundStyle(OrejaTheme.Palette.inkSoft)
                                    Text(event.category.rawValue)
                                        .font(.system(size: 9.5, design: .monospaced))
                                        .foregroundStyle(OrejaTheme.Palette.inkSoft)
                                        .frame(width: 72, alignment: .leading)
                                    Text(event.message)
                                        .font(.system(size: 10.5))
                                        .foregroundStyle(color(for: event.level))
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(height: 220)
                }
            }
        }
    }

    private func color(for level: DiagnosticEvent.Level) -> Color {
        switch level {
        case .error: OrejaTheme.Palette.warning
        case .warning: OrejaTheme.Palette.wheat
        case .success: OrejaTheme.Palette.positive
        case .info: OrejaTheme.Palette.ink
        case .debug: OrejaTheme.Palette.inkSoft
        }
    }
}
