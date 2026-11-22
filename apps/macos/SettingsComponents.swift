import SwiftUI

/// A label on the left, its control on the right edge, and an optional explanation underneath.
/// Every settings toggle uses it, so switches line up in one column instead of trailing their text.
struct SettingRow<Control: View>: View {
    var title: String
    var detail: String?
    private let control: () -> Control

    init(_ title: String, detail: String? = nil, @ViewBuilder control: @escaping () -> Control) {
        self.title = title
        self.detail = detail
        self.control = control
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .center, spacing: 12) {
                Text(title)
                    .font(.system(size: 13))
                    .foregroundStyle(OrejaTheme.Palette.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 12)
                control()
            }
            if let detail {
                SettingDetail(detail)
            }
        }
    }
}

/// Secondary text under a control.
struct SettingDetail: View {
    var text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(OrejaTheme.Typography.micro)
            .foregroundStyle(OrejaTheme.Palette.inkSoft)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// A switch aligned to the right edge of its row.
struct SettingToggle: View {
    var title: String
    var detail: String?
    @Binding var isOn: Bool

    init(_ title: String, detail: String? = nil, isOn: Binding<Bool>) {
        self.title = title
        self.detail = detail
        self._isOn = isOn
    }

    var body: some View {
        SettingRow(title, detail: detail) {
            Toggle(title, isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .tint(OrejaTheme.Palette.accent)
        }
    }
}

/// A labelled slider with its current value on the right, in even-width digits.
struct SettingSlider: View {
    var title: String
    var valueText: String
    var detail: String?
    @Binding var value: Double
    var range: ClosedRange<Double>
    var step: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                    .font(.system(size: 13))
                    .foregroundStyle(OrejaTheme.Palette.ink)
                Spacer(minLength: 8)
                Text(valueText)
                    .font(.system(size: 12, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(OrejaTheme.Palette.inkSoft)
            }
            // No `step:` on the slider itself: macOS would draw a tick mark per step (up to 100).
            // The value snaps to the step in the binding instead.
            Slider(value: Binding(
                get: { value },
                set: { newValue in
                    let snapped = step > 0 ? (newValue / step).rounded() * step : newValue
                    value = min(max(snapped, range.lowerBound), range.upperBound)
                }
            ), in: range) { Text(title) }
                .labelsHidden()
                .tint(OrejaTheme.Palette.accent)
                .accessibilityValue(valueText)
            if let detail {
                SettingDetail(detail)
            }
        }
    }
}

enum StatusTone {
    case good
    case attention
    case neutral

    var color: Color {
        switch self {
        case .good: OrejaTheme.Palette.accent
        case .attention: OrejaTheme.Palette.warning
        case .neutral: OrejaTheme.Palette.inkSoft
        }
    }
}

/// A small dot-and-word status, such as "Granted" or "Missing".
struct StatusChip: View {
    var text: String
    var tone: StatusTone

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(tone.color)
                .frame(width: 6, height: 6)
                .accessibilityHidden(true)
            Text(text)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(tone == .neutral ? OrejaTheme.Palette.inkSoft : OrejaTheme.Palette.ink)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Capsule().fill(tone.color.opacity(0.12)))
        .fixedSize()
    }
}

/// One macOS permission: what it is for, whether Oreja has it, and the button that fixes it.
struct PermissionRow: View {
    var title: String
    var detail: String
    var status: String
    var tone: StatusTone
    var actionTitle: String
    var action: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(OrejaTheme.Palette.ink)
                SettingDetail(detail)
            }
            Spacer(minLength: 12)
            StatusChip(text: status, tone: tone)
            Button(actionTitle, action: action)
                .controlSize(.small)
        }
        .accessibilityElement(children: .contain)
    }
}
