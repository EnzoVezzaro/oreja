import AppKit
import Foundation

/// Generates the Oreja app icon: a cream ear on a deep indigo field, one wheat arc behind it, and
/// a warm rim light. Matches the mark in `site/assets/mark.svg` and `docs/brand.md`.
/// Run by scripts/build.sh.
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
            NSColor(srgbRed: 0.141, green: 0.173, blue: 0.353, alpha: 1).cgColor,
            NSColor(srgbRed: 0.090, green: 0.114, blue: 0.247, alpha: 1).cgColor,
        ] as CFArray
        if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) {
            context.drawLinearGradient(
                gradient,
                start: CGPoint(x: body.minX, y: body.maxY),
                end: CGPoint(x: body.maxX, y: body.minY),
                options: []
            )
        }

        // The listening mark: a bright dot with two waves, the same geometry as site/assets/mark.svg.
        let dotCenter = CGPoint(x: body.midX - side * 0.06, y: body.midY)
        let cream = NSColor(srgbRed: 0.969, green: 0.949, blue: 0.906, alpha: 1).cgColor
        let wheat = NSColor(srgbRed: 0.906, green: 0.706, blue: 0.298, alpha: 1).cgColor
        context.setStrokeColor(cream)
        context.setLineWidth(side * 0.055)
        context.setLineCap(.round)
        context.addArc(
            center: dotCenter,
            radius: side * 0.155,
            startAngle: -.pi * (50 / 180),
            endAngle: .pi * (50 / 180),
            clockwise: false
        )
        context.strokePath()
        context.setStrokeColor(wheat)
        context.addArc(
            center: dotCenter,
            radius: side * 0.265,
            startAngle: -.pi * (50 / 180),
            endAngle: .pi * (50 / 180),
            clockwise: false
        )
        context.strokePath()
        context.setFillColor(cream)
        context.fillEllipse(
            in: CGRect(
                x: dotCenter.x - side * 0.055,
                y: dotCenter.y - side * 0.055,
                width: side * 0.11,
                height: side * 0.11
            )
        )
        context.restoreGState()

        // Warm cream rim light along the top edge.
        context.saveGState()
        context.addPath(squircle)
        context.clip()
        context.setStrokeColor(NSColor(srgbRed: 0.969, green: 0.949, blue: 0.906, alpha: 0.30).cgColor)
        context.setLineWidth(side * 0.012)
        context.addPath(squircle)
        context.strokePath()
        context.restoreGState()

        return image
    }
}
