import AppKit
import SwiftUI

/// Brand tokens for every surface of the app.
///
/// Colours are dynamic, so a view never branches on `colorScheme` to stay legible. The palette is
/// the same one published in `docs/brand.md` and used by the landing page: warm paper, warm ink,
/// a deep indigo for brand and focus, and a single wheat accent. Everything else is a neutral.
enum OrejaTheme {
    enum Palette {
        /// Panel and window wash. Kept close to the system material so the menu bar popover does not
        /// look like a rectangle pasted on top of the desktop.
        static let paper = Color(nsColor: .oreja(light: 0xF7F2E8, dark: 0x11100E))
        /// Cards and grouped rows.
        static let card = Color(nsColor: .oreja(light: 0xFFFCF4, dark: 0x1B1916))
        static let cardMuted = Color(nsColor: .oreja(light: 0xF1EADA, dark: 0x17150F))
        static let ink = Color(nsColor: .oreja(light: 0x14120E, dark: 0xF3EEE2))
        static let inkSoft = Color(nsColor: .oreja(light: 0x6C6559, dark: 0xA8A091))
        static let hairline = Color(nsColor: .oreja(light: 0xE1D7C4, dark: 0x2C2823))
        /// Brand indigo. Lifts to a periwinkle in dark appearance so it still reads as an accent.
        static let accent = Color(nsColor: .oreja(light: 0x242C5A, dark: 0xB9C0F0))
        /// Text and glyphs placed on `accent`. In light appearance the accent is deep indigo, so this
        /// is cream; in dark appearance the accent lifts, so this returns to deep indigo.
        static let onAccent = Color(nsColor: .oreja(light: 0xF7F2E8, dark: 0x171D3F))
        static let accentWash = Color(nsColor: .oreja(light: 0xE9E6F3, dark: 0x232841))
        /// The one warm accent. Used for emphasis and for "music paused", never for body text.
        static let wheat = Color(nsColor: .oreja(light: 0x8A6318, dark: 0xE7B44C))
        static let positive = Color(nsColor: .oreja(light: 0x4C6A51, dark: 0x9CC2A3))
        static let warning = Color(nsColor: .oreja(light: 0xA9502C, dark: 0xE8A183))
        /// Fixed cream, for artwork placed on indigo. Never used for text on a dynamic background.
        static let cream = Color(nsColor: NSColor(srgbRed: 0.969, green: 0.949, blue: 0.906, alpha: 1))
        static let indigo = Color(nsColor: NSColor(srgbRed: 0.141, green: 0.173, blue: 0.353, alpha: 1))
        static let indigoDeep = Color(nsColor: NSColor(srgbRed: 0.090, green: 0.114, blue: 0.247, alpha: 1))
    }

    enum Metrics {
        static let panelWidth: CGFloat = 324
        static let gutter: CGFloat = 16
        static let cardRadius: CGFloat = 12
        static let controlRadius: CGFloat = 8
    }

    enum Typography {
        static let eyebrow = Font.system(size: 10, weight: .semibold, design: .monospaced)
        static let wordmark = Font.system(size: 13, weight: .semibold)
        static let wordmarkSuffix = Font.system(size: 8.5, weight: .semibold)
        static let pageTitle = Font.system(size: 25, weight: .semibold)
        static let sectionTitle = Font.system(size: 14, weight: .semibold)
        static let body = Font.system(size: 12.5)
        static let caption = Font.system(size: 11)
        static let micro = Font.system(size: 10)
    }
}

// MARK: - Colour construction

private extension NSColor {
    /// A colour that resolves per appearance. `NSColor(name:dynamicProvider:)` is the only dynamic
    /// colour API available at the macOS 14.2 floor.
    static func oreja(light: UInt32, dark: UInt32) -> NSColor {
        NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return isDark ? srgb(dark) : srgb(light)
        }
    }

    static func srgb(_ hex: UInt32) -> NSColor {
        NSColor(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}

// MARK: - Shared small views

/// The listening mark: a dot with two waves. It is the same geometry as `site/assets/mark.svg`,
/// the app icon and the wordmark, drawn from primitives so it stays crisp at every size and needs
/// no symbol artwork.
struct ListeningMark: View {
    var color: Color = OrejaTheme.Palette.cream
    var accent: Color = OrejaTheme.Palette.wheat

    var body: some View {
        GeometryReader { proxy in
            let scale = min(proxy.size.width, proxy.size.height) / 64
            let center = CGPoint(x: 25 * scale, y: 32 * scale)
            ZStack {
                Circle()
                    .fill(color)
                    .frame(width: 6.8 * scale, height: 6.8 * scale)
                    .position(center)
                arc(center: center, radius: 10 * scale)
                    .stroke(color, style: StrokeStyle(lineWidth: 3.4 * scale, lineCap: .round))
                arc(center: center, radius: 17 * scale)
                    .stroke(accent, style: StrokeStyle(lineWidth: 3.4 * scale, lineCap: .round))
            }
        }
        .accessibilityHidden(true)
    }

    private func arc(center: CGPoint, radius: CGFloat) -> Path {
        Path { path in
            path.addArc(
                center: center,
                radius: radius,
                startAngle: .degrees(-50),
                endAngle: .degrees(50),
                clockwise: false
            )
        }
    }
}

/// The brand lockup used in the panel and windows.
struct BrandMark: View {
    var size: CGFloat = 22
    var cornerRadius: CGFloat?

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius ?? size * 0.29, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [OrejaTheme.Palette.indigo, OrejaTheme.Palette.indigoDeep],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay {
                ListeningMark()
                    .frame(width: size * 0.62, height: size * 0.62)
            }
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

/// Lowercase wordmark with the quiet suffix. Live text, never a traced image.
struct BrandWordmark: View {
    var size: CGFloat = 13

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            Text("oreja")
                .font(.system(size: size, weight: .semibold))
                .tracking(-size * 0.02)
                .foregroundStyle(OrejaTheme.Palette.ink)
            Text("DE VAN GOGH")
                .font(.system(size: size * 0.63, weight: .semibold))
                .tracking(size * 0.09)
                .foregroundStyle(OrejaTheme.Palette.inkSoft)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Oreja de Van Gogh")
    }
}

/// One status light. A dot, not a badge: it is the first thing the eye finds in the panel.
struct StatusDot: View {
    var color: Color
    var isActive: Bool = false

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 7, height: 7)
            .overlay {
                if isActive {
                    Circle()
                        .stroke(color.opacity(0.35), lineWidth: 1)
                        .scaleEffect(2.1)
                }
            }
            .accessibilityHidden(true)
    }
}

struct Hairline: View {
    var body: some View {
        Rectangle()
            .fill(OrejaTheme.Palette.hairline)
            .frame(height: 1)
    }
}

struct Eyebrow: View {
    var text: String

    var body: some View {
        Text(text.uppercased())
            .font(OrejaTheme.Typography.eyebrow)
            .tracking(1.3)
            .foregroundStyle(OrejaTheme.Palette.inkSoft)
    }
}

/// A grouped block used by settings and by long-form setup steps.
struct ThemeCard<Content: View>: View {
    var fill: Color = OrejaTheme.Palette.card
    private let content: () -> Content

    init(fill: Color = OrejaTheme.Palette.card, @ViewBuilder content: @escaping () -> Content) {
        self.fill = fill
        self.content = content
    }

    var body: some View {
        content()
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: OrejaTheme.Metrics.cardRadius, style: .continuous)
                    .fill(fill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: OrejaTheme.Metrics.cardRadius, style: .continuous)
                    .strokeBorder(OrejaTheme.Palette.hairline, lineWidth: 1)
            )
    }
}

struct ThemeSection<Content: View>: View {
    var title: String
    var caption: String?
    private let content: () -> Content

    init(
        title: String,
        caption: String? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.caption = caption
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Eyebrow(text: title)
            ThemeCard { content() }
            if let caption {
                Text(caption)
                    .font(OrejaTheme.Typography.micro)
                    .foregroundStyle(OrejaTheme.Palette.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// A quiet action row: icon, label, optional shortcut hint, hover wash. No bordered buttons stacked
/// on top of each other, so the panel keeps a single visual weight.
struct QuietRow: View {
    var title: String
    var systemImage: String
    var shortcut: String?
    var key: KeyEquivalent?
    var isEnabled: Bool = true
    var action: () -> Void

    @State private var isHovering = false

    var body: some View {
        if let key {
            row.keyboardShortcut(key, modifiers: .command)
        } else {
            row
        }
    }

    private var row: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: systemImage)
                    .font(.system(size: 11, weight: .medium))
                    .frame(width: 16)
                    .foregroundStyle(OrejaTheme.Palette.inkSoft)
                Text(title)
                    .font(.system(size: 12))
                    .foregroundStyle(OrejaTheme.Palette.ink)
                Spacer(minLength: 8)
                if let shortcut {
                    Text(shortcut)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(OrejaTheme.Palette.inkSoft)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(isHovering ? OrejaTheme.Palette.cardMuted : .clear)
            )
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.5)
        .onHover { isHovering = $0 && isEnabled }
    }
}
