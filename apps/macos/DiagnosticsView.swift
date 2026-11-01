import SwiftUI
import OrejaCore

/// Troubleshooting surface. It only ever shows Oreja's own state and permission results; no audio,
/// prompt or reply content exists to display.
struct DiagnosticsView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            summary
            Divider()
            if let report = model.report {
                checkList(report)
                Divider()
            }
            logHeader
            logList
        }
        .padding(18)
        .frame(minWidth: 600, minHeight: 520)
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: model.state.menuBarSymbol)
                    .foregroundStyle(model.state.tint)
                Text(model.state.title)
                    .font(.headline)
                Spacer()
                Button(model.isRunningCheck ? "Checking…" : "Run checks") { model.runConnectionCheck() }
                    .disabled(model.isRunningCheck)
            }
            Text(model.state.detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 4) {
                GridRow {
                    metric("Monitored source", model.sourceDescription.isEmpty ? "—" : model.sourceDescription)
                    metric("Pauses issued", "\(model.coordinator.statistics.pausesIssued)")
                }
                GridRow {
                    metric("Last pause latency", milliseconds(model.coordinator.statistics.lastPauseLatency))
                    metric("Last resume latency", milliseconds(model.coordinator.statistics.lastResumeLatency))
                }
                GridRow {
                    metric("Failed commands", "\(model.coordinator.statistics.failedCommands)")
                    metric("Manual overrides", "\(model.coordinator.statistics.manualOverrides)")
                }
            }
            .padding(.top, 4)
        }
    }

    private func metric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 12, design: .monospaced))
        }
    }

    private func milliseconds(_ value: TimeInterval?) -> String {
        guard let value else { return "—" }
        return String(format: "%.0f ms", value * 1000)
    }

    private func checkList(_ report: ConnectionCheckReport) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Last check")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            ForEach(report.steps) { step in
                CheckRow(step: step)
            }
        }
    }

    private var logHeader: some View {
        HStack {
            Text("Events")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Spacer()
            Button("Clear") { model.diagnostics.clear() }
                .buttonStyle(.link)
                .font(.caption)
        }
    }

    private var logList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 4) {
                ForEach(model.diagnostics.events.reversed()) { event in
                    HStack(alignment: .top, spacing: 8) {
                        Text(event.date, format: .dateTime.hour().minute().second())
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.secondary)
                        Text(event.category.rawValue)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .frame(width: 74, alignment: .leading)
                        Text(event.message)
                            .font(.system(size: 11))
                            .foregroundStyle(color(for: event.level))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minHeight: 220)
    }

    private func color(for level: DiagnosticEvent.Level) -> Color {
        switch level {
        case .error: .red
        case .warning: .orange
        case .success, .info: .primary
        }
    }
}
