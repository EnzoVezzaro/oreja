import AppKit
import SwiftUI

/// Warm, quiet brand surfaces with appearance-aware contrast.
enum OrejaTheme {
    enum Palette {
        static let paper = Color(nsColor: .oreja(light: 0xFBF7F0, dark: 0x16130F))
        static let card = Color(nsColor: .oreja(light: 0xFFFDFA, dark: 0x221E19))
        static let cardMuted = Color(nsColor: .oreja(light: 0xF8F0E4, dark: 0x1B1713))
        static let ink = Color(nsColor: .oreja(light: 0x242320, dark: 0xFAF9F6))
        static let inkSoft = Color(nsColor: .oreja(light: 0x706C65, dark: 0xBDB6AC))
        static let hairline = Color(nsColor: .oreja(light: 0xE5DFD7, dark: 0x494139))
        static let accent = Color(nsColor: .oreja(light: 0xA7472A, dark: 0xF3A88E))
        static let onAccent = Color(nsColor: .oreja(light: 0xFFFFFF, dark: 0x242320))
        static let accentWash = Color(nsColor: .oreja(light: 0xFDE7D5, dark: 0x33241C))
        /// Coral is decorative; interactive controls use the higher-contrast accent.
        static let coral = Color(nsColor: .srgb(0xE77952))
        // Compatibility for status presenters outside these views.
        static let wheat = accent
        static let positive = Color(nsColor: .oreja(light: 0x4C6A51, dark: 0x9CC2A3))
        static let warning = accent
        static let cream = Color(nsColor: .srgb(0xFAF9F6))
    }

    enum Metrics {
        static let panelWidth: CGFloat = 352
        static let gutter: CGFloat = 20
        static let cardRadius: CGFloat = 18
        static let controlRadius: CGFloat = 9
    }

    enum Typography {
        static let eyebrow = Font.system(size: 12, weight: .medium)
        static let wordmark = Font.system(size: 13, weight: .semibold)
        static let wordmarkSuffix = Font.system(size: 8.5, weight: .semibold)
        static let pageTitle = Font.system(size: 25, weight: .semibold)
        static let sectionTitle = Font.system(size: 14, weight: .semibold)
        static let body = Font.system(size: 12.5)
        static let caption = Font.system(size: 12)
        static let micro = Font.system(size: 11)
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

/// The brand mark is the character: Vincent's head, cropped from the idle frame of the same sprite
/// sheet the companion uses, on the paper tile. The site draws the identical crop from the same
/// PNG (`site/assets/mark.png`), so the menu bar, the window and the landing page cannot drift.
///
/// The crop is 268 × 308 points at (26, 8) inside a 320-point frame, framed at 76% of the tile,
/// which leaves the hat brim and the collar inside the tile's rounded corners rather than resting
/// on them.
struct BrandMark: View {
    var size: CGFloat = 28
    var cornerRadius: CGFloat?

    private static let sheet: NSImage? = {
        guard let url = Bundle.main.url(forResource: "oreja-vincent", withExtension: "png") else { return nil }
        return NSImage(contentsOf: url)
    }()

    private static let framePoints: CGFloat = 320
    private static let cropOrigin = CGPoint(x: 26, y: 8)
    private static let cropSize = CGSize(width: 268, height: 308)
    /// How much of the tile the head fills. Shared with the website's `assets/mark.png`.
    private static let headShare: CGFloat = 0.76

    var body: some View {
        let radius = cornerRadius ?? size * 0.26
        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .fill(OrejaTheme.Palette.accentWash)
            .overlay(alignment: .topLeading) {
                if let sheet = Self.sheet {
                    let head = size * Self.headShare
                    let frame = head * (Self.framePoints / Self.cropSize.width)
                    Image(nsImage: sheet)
                        .resizable()
                        .interpolation(.none)
                        .frame(width: frame * 5, height: frame, alignment: .topLeading)
                        .offset(
                            x: (size - head) / 2 - frame * (Self.cropOrigin.x / Self.framePoints),
                            y: (size - head * (Self.cropSize.height / Self.cropSize.width)) / 2
                                - frame * (Self.cropOrigin.y / Self.framePoints)
                        )
                }
            }
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .accessibilityHidden(true)
    }
}

struct BrandWordmark: View {
    var size: CGFloat = 16

    var body: some View {
        Text("oreja")
            .font(.system(size: size, weight: .semibold, design: .rounded))
            .tracking(-size * 0.02)
            .foregroundStyle(OrejaTheme.Palette.ink)
            .accessibilityLabel("Oreja de Van Gogh")
    }
}

/// Vincent, the pixel painter. The bundle ships one five-frame sprite sheet (idle, idle blink,
/// listening, listening blink, ouch) generated by `scripts/vincent-sprite.py`, so the app and the
/// website always show the same character. A missing asset leaves no placeholder or footprint.
///
/// Clicking him is the joke, not a control: he plays the ouch frame (the bandage leaves his head)
/// and shakes for a moment. Nothing is sent anywhere and no playback state changes.
struct VincentCompanion: View {
    var size: CGFloat = 64
    var isListening = false
    var isMusicPlaying = false

    /// Frames in `oreja-vincent.png`, left to right. Keep in sync with the generator and the site CSS.
    static let frameCount = 5
    private static let ouchFrame = 4

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isOuching = false
    @State private var shake: CGFloat = 0

    private static let sheet: NSImage? = {
        guard let url = Bundle.main.url(forResource: "oreja-vincent", withExtension: "png") else { return nil }
        return NSImage(contentsOf: url)
    }()

    private var isActive: Bool { isListening || isMusicPlaying }

    var body: some View {
        if let sheet = Self.sheet {
            TimelineView(.periodic(from: .now, by: 0.5)) { context in
                let tick = Int(context.date.timeIntervalSinceReferenceDate / 0.5)
                // A blink every seven ticks keeps him alive without costing a frame budget.
                let blink = tick % 7 == 3
                let frame = isOuching
                    ? Self.ouchFrame
                    : (isActive ? 2 : 0) + (blink ? 1 : 0)
                Image(nsImage: sheet)
                    .resizable()
                    .interpolation(.none)
                    .frame(width: size * CGFloat(Self.frameCount), height: size, alignment: .topLeading)
                    .offset(x: -CGFloat(frame) * size)
                    .frame(width: size, height: size, alignment: .topLeading)
                    .clipped()
            }
            .frame(width: size, height: size)
            // Whole-point steps only: a rotated or fractional pixel would blur the sprite.
            .offset(x: shake)
            .contentShape(Rectangle())
            .onTapGesture(perform: snip)
            .help("Leave the other one alone.")
            .accessibilityHidden(true)
        }
    }

    /// A short self-contained sequence, and re-entrant taps are ignored until it finishes, so a
    /// click storm cannot stack animations or freeze him mid-ouch.
    private func snip() {
        guard !isOuching else { return }
        isOuching = true
        guard !reduceMotion else {
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(900))
                isOuching = false
            }
            return
        }
        Task { @MainActor in
            let step = max(1, (size * 0.04).rounded())
            withAnimation(.linear(duration: 0.06)) { shake = -step }
            try? await Task.sleep(for: .milliseconds(70))
            withAnimation(.linear(duration: 0.06)) { shake = step }
            try? await Task.sleep(for: .milliseconds(70))
            withAnimation(.linear(duration: 0.06)) { shake = -step / 2 }
            try? await Task.sleep(for: .milliseconds(70))
            withAnimation(.linear(duration: 0.08)) { shake = 0 }
            try? await Task.sleep(for: .milliseconds(520))
            isOuching = false
        }
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
        Text(text)
            .font(OrejaTheme.Typography.eyebrow)
            .tracking(0)
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
            .padding(18)
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
            VStack(alignment: .leading, spacing: 3) {
                Eyebrow(text: title)
                    .accessibilityAddTraits(.isHeader)
                if let caption {
                    Text(caption)
                        .font(OrejaTheme.Typography.micro)
                        .foregroundStyle(OrejaTheme.Palette.inkSoft)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            ThemeCard { content() }
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
            .padding(.vertical, 9)
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
