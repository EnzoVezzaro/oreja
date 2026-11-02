import AppKit
import Foundation

/// Generates the Oreja icon: the character on the warm-white tile, cropped from the same sprite
/// sheet the app and the website use. Run by scripts/build.sh.
@main
struct IconBuilder {
    /// The five-frame sheet, relative to the repository root that build.sh runs from.
    static let spritePath = "site/assets/oreja-vincent.png"

    static func main() {
        let outputDirectory = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "build"
        guard let sprite = NSImage(contentsOfFile: spritePath) else {
            FileHandle.standardError.write(Data("Missing sprite sheet at \(spritePath)\n".utf8))
            exit(1)
        }
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
            let image = render(pixels: variant.pixels, sprite: sprite)
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

    static func render(pixels: Int, sprite: NSImage) -> NSImage {
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

        // Same peach tile as `BrandMark` and the site's `mark.png` (accentWash), so the Dock icon,
        // the menu bar panel and the landing page header are one object at three sizes.
        context.addPath(squircle)
        context.setFillColor(NSColor(srgbRed: 253 / 255, green: 231 / 255, blue: 213 / 255, alpha: 1).cgColor)
        context.fillPath()

        // The character: frame 0 of the sheet, cropped exactly as BrandMark crops it
        // (26, 8, 268 × 308 of a 320-point frame) and drawn with no interpolation, so his pixels
        // stay square at every icon size.
        if let sheet = sprite.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            let density = CGFloat(sheet.height) / 320
            let crop = CGRect(x: 26 * density, y: 8 * density, width: 268 * density, height: 308 * density).integral
            if let head = sheet.cropping(to: crop) {
                let headShare: CGFloat = 0.76
                let headWidth = body.width * headShare
                let headHeight = headWidth * (crop.height / crop.width)
                let origin = CGPoint(
                    x: body.minX + (body.width - headWidth) / 2,
                    y: body.minY + (body.height - headHeight) / 2
                )
                context.saveGState()
                context.addPath(squircle)
                context.clip()
                context.interpolationQuality = .none
                context.draw(head, in: CGRect(x: origin.x, y: origin.y, width: headWidth, height: headHeight))
                context.restoreGState()
            }
        }

        return image
    }
}
