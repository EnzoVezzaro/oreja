import AppKit
import Foundation

/// Generates the Oreja app icon: an ear listening on a deep indigo field with a quiet swirl,
/// a reference to the warm night paintings the name nods to. Run by scripts/build.sh.
@main
struct IconBuilder {
    static func main() {
        let outputDirectory = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "build"
        let iconset = URL(fileURLWithPath: outputDirectory).appendingPathComponent("AppIcon.iconset")
        let fileManager = FileManager.default

        try? fileManager.removeItem(at: iconset)
        try? fileManager.createDirectory(at: iconset, withIntermediateDirectories: true)

        let variants: [(name: String, pixels: Int)] = [
            ("icon_16x16", 16), ("icon_16x16@2x", 32),
            ("icon_32x32", 32), ("icon_32x32@2x", 64),
            ("icon_128x128", 128), ("icon_128x128@2x", 256),
            ("icon_256x256", 256), ("icon_256x256@2x", 512),
            ("icon_512x512", 512), ("icon_512x512@2x", 1024),
        ]

        for variant in variants {
            let image = render(pixels: variant.pixels)
            guard
                let tiff = image.tiffRepresentation,
                let representation = NSBitmapImageRep(data: tiff),
                let png = representation.representation(using: .png, properties: [:])
            else {
                FileHandle.standardError.write(Data("Could not render \(variant.name)\n".utf8))
                exit(1)
            }
            try? png.write(to: iconset.appendingPathComponent("\(variant.name).png"))
        }

        let icns = URL(fileURLWithPath: outputDirectory).appendingPathComponent("AppIcon.icns")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
        process.arguments = ["-c", "icns", iconset.path, "-o", icns.path]
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            FileHandle.standardError.write(Data("iconutil failed: \(error)\n".utf8))
            exit(1)
        }
        guard process.terminationStatus == 0 else {
            FileHandle.standardError.write(Data("iconutil exited \(process.terminationStatus)\n".utf8))
            exit(1)
        }
        print(icns.path)
    }

    static func render(pixels: Int) -> NSImage {
        let size = CGFloat(pixels)
        let image = NSImage(size: NSSize(width: size, height: size))
        image.lockFocus()
        defer { image.unlockFocus() }
        guard let context = NSGraphicsContext.current?.cgContext else { return image }

        // Big Sur icon grid: an 824pt rounded square inside a 1024pt canvas.
        let scale = size / 1024
        let inset = 100 * scale
        let side = size - inset * 2
        let body = CGRect(x: inset, y: inset, width: side, height: side)
        let squircle = CGPath(
            roundedRect: body,
            cornerWidth: side * 0.225,
            cornerHeight: side * 0.225,
            transform: nil
        )

        context.saveGState()
        context.addPath(squircle)
        context.clip()

        let colors = [
            NSColor(srgbRed: 0.24, green: 0.26, blue: 0.55, alpha: 1).cgColor,
            NSColor(srgbRed: 0.09, green: 0.09, blue: 0.22, alpha: 1).cgColor,
        ] as CFArray
        if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) {
            context.drawLinearGradient(
                gradient,
                start: CGPoint(x: body.minX, y: body.maxY),
                end: CGPoint(x: body.maxX, y: body.minY),
                options: []
            )
        }

        // A single quiet swirl, kept subtle so the glyph stays legible at 16pt.
        context.setStrokeColor(NSColor(srgbRed: 0.62, green: 0.68, blue: 1.0, alpha: 0.22).cgColor)
        context.setLineWidth(side * 0.045)
        context.setLineCap(.round)
        for index in 0..<2 {
            let radius = side * (0.30 + 0.13 * CGFloat(index))
            let center = CGPoint(
                x: body.midX + side * 0.10,
                y: body.midY + side * (0.16 - 0.05 * CGFloat(index))
            )
            context.addArc(
                center: center,
                radius: radius,
                startAngle: .pi * 0.75,
                endAngle: .pi * 1.65,
                clockwise: false
            )
            context.strokePath()
        }
        context.restoreGState()

        // Warm cream rim light along the top edge.
        context.saveGState()
        context.addPath(squircle)
        context.clip()
        context.setStrokeColor(NSColor(srgbRed: 1.0, green: 0.92, blue: 0.78, alpha: 0.30).cgColor)
        context.setLineWidth(side * 0.012)
        context.addPath(squircle)
        context.strokePath()
        context.restoreGState()

        drawEar(in: context, body: body)
        return image
    }

    static func drawEar(in context: CGContext, body: CGRect) {
        let configuration = NSImage.SymbolConfiguration(pointSize: body.width * 0.52, weight: .regular)
        guard
            let symbol = NSImage(systemSymbolName: "ear", accessibilityDescription: nil)?
                .withSymbolConfiguration(configuration)
        else { return }

        let symbolSize = symbol.size
        let target = CGRect(
            x: body.midX - symbolSize.width / 2,
            y: body.midY - symbolSize.height / 2,
            width: symbolSize.width,
            height: symbolSize.height
        )

        let tinted = NSImage(size: symbolSize)
        tinted.lockFocus()
        symbol.draw(in: CGRect(origin: .zero, size: symbolSize))
        NSColor(srgbRed: 1.0, green: 0.90, blue: 0.76, alpha: 1).set()
        CGRect(origin: .zero, size: symbolSize).fill(using: .sourceAtop)
        tinted.unlockFocus()

        tinted.draw(in: target, from: .zero, operation: .sourceOver, fraction: 1.0)
    }
}
