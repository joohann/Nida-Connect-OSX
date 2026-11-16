import AppKit

/// Draws the app icon on the macOS icon grid (1024 canvas, 824 body, corner radius 185), so macOS
/// shows it as is instead of placing it on a grey plate. The mosque comes from Nida's own icon
/// (AppIcon-source.png); background and gold edge are drawn here in Nida's colours.
enum IconDrawing {
    static let body = CGRect(x: 100, y: 100, width: 824, height: 824)
    static let radius: CGFloat = 185
    /// Part of the source that holds the artwork, inside its own gold edge (pixels, top-left origin).
    static let sourceCrop = CGRect(x: 40, y: 40, width: 944, height: 944)

    static func image(size: CGFloat, source: NSImage) -> NSBitmapImageRep {
        let px = Int(size)
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                                   samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                   colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSGraphicsContext.current?.imageInterpolation = .high
        let ctx = NSGraphicsContext.current!.cgContext
        ctx.scaleBy(x: size / 1024, y: size / 1024)
        draw(ctx, source: source)
        NSGraphicsContext.restoreGraphicsState()
        return rep
    }

    private static func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> NSColor {
        NSColor(srgbRed: CGFloat((hex >> 16) & 0xff) / 255, green: CGFloat((hex >> 8) & 0xff) / 255,
                blue: CGFloat(hex & 0xff) / 255, alpha: alpha)
    }

    private static func draw(_ ctx: CGContext, source: NSImage) {
        let shape = CGPath(roundedRect: body, cornerWidth: radius, cornerHeight: radius, transform: nil)

        // Soft shadow under the tile, like system icons.
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 24, color: NSColor.black.withAlphaComponent(0.3).cgColor)
        ctx.addPath(shape)
        ctx.setFillColor(color(0x09281b).cgColor)
        ctx.fillPath()
        ctx.restoreGState()

        // Background: Nida's dark green, lighter at the top.
        ctx.saveGState()
        ctx.addPath(shape)
        ctx.clip()
        let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                  colors: [color(0x17422e).cgColor, color(0x09281b).cgColor] as CFArray,
                                  locations: [0, 1])!
        ctx.drawLinearGradient(gradient, start: CGPoint(x: 512, y: body.maxY), end: CGPoint(x: 512, y: body.minY), options: [])

        // The mosque, from inside the source's own edge, filling the tile.
        let h = source.size.height
        let from = NSRect(x: sourceCrop.minX, y: h - sourceCrop.maxY, width: sourceCrop.width, height: sourceCrop.height)
        source.draw(in: body, from: from, operation: .sourceOver, fraction: 1)
        ctx.restoreGState()

        // Gold edge, as on Nida's own icon.
        let inset: CGFloat = 12
        let edge = CGPath(roundedRect: body.insetBy(dx: inset, dy: inset), cornerWidth: radius - inset,
                          cornerHeight: radius - inset, transform: nil)
        ctx.addPath(edge)
        ctx.setStrokeColor(color(0xf8cb5b, 0.8).cgColor)
        ctx.setLineWidth(9)
        ctx.strokePath()
    }
}
