import AppKit

// Draws the DMG window background: green like the app icon, a faint star pattern, the app name and
// a gold arrow from the app to Applications. No other text, so it works in every language.
// package.sh places the icons at the centres in `Layout` and combines 1x and 2x into one TIFF.
//   dmg-background <app name> <out.png> <out@2x.png>

enum Layout {
    static let size = CGSize(width: 660, height: 400)
    static let appCenter = CGPoint(x: 170, y: 205)      // top-left origin, as Finder uses
    static let folderCenter = CGPoint(x: 490, y: 205)
    /// Finder draws icon names in black on a custom background, also in dark mode, so each name
    /// gets a light plate. Centre line of the names for icon size 128 and text size 13.
    static let labelY: CGFloat = 288
    static let plate = CGSize(width: 132, height: 22)
}

private func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xff) / 255, green: CGFloat((hex >> 8) & 0xff) / 255,
            blue: CGFloat(hex & 0xff) / 255, alpha: alpha).cgColor
}

private let gold: UInt32 = 0xf8cb5b

private func draw(_ ctx: CGContext, title: String) {
    let w = Layout.size.width, h = Layout.size.height
    // Work in top-left coordinates, like the design.
    ctx.translateBy(x: 0, y: h)
    ctx.scaleBy(x: 1, y: -1)
    let space = CGColorSpaceCreateDeviceRGB()

    // Background: radial green, lighter in the middle.
    let bg = CGGradient(colorsSpace: space, colors: [color(0x1d5038), color(0x08241a)] as CFArray, locations: [0, 1])!
    ctx.saveGState()
    ctx.translateBy(x: w / 2, y: h / 2)
    ctx.scaleBy(x: 1, y: 0.75)
    ctx.drawRadialGradient(bg, startCenter: .zero, startRadius: 0, endCenter: .zero, endRadius: w * 0.62,
                           options: [.drawsAfterEndLocation])
    ctx.restoreGState()

    // Star pattern: two overlapping squares, every 56 pt, alternate rows shifted.
    ctx.saveGState()
    ctx.setStrokeColor(color(gold, 0.07))
    ctx.setLineWidth(1)
    var row = 0
    for y in stride(from: CGFloat(-20), to: h + 20, by: 56) {
        for x in stride(from: CGFloat(-20), to: w + 20, by: 56) {
            let cx = x + (row % 2 == 1 ? 28 : 0)
            for angle in [CGFloat(0), .pi / 4] {
                ctx.saveGState()
                ctx.translateBy(x: cx, y: y)
                ctx.rotate(by: angle)
                ctx.stroke(CGRect(x: -9, y: -9, width: 18, height: 18))
                ctx.restoreGState()
            }
        }
        row += 1
    }
    ctx.restoreGState()

    // Soft glow in the centre, so the pattern fades behind the icons.
    let glow = CGGradient(colorsSpace: space, colors: [color(0x164530, 0.85), color(0x164530, 0)] as CFArray, locations: [0, 1])!
    ctx.saveGState()
    ctx.translateBy(x: w / 2, y: h / 2)
    ctx.scaleBy(x: 1, y: h / w)
    ctx.drawRadialGradient(glow, startCenter: .zero, startRadius: 0, endCenter: .zero, endRadius: w / 2, options: [])
    ctx.restoreGState()

    // Light plates behind the names Finder draws under the icons.
    ctx.saveGState()
    for center in [Layout.appCenter, Layout.folderCenter] {
        let r = CGRect(x: center.x - Layout.plate.width / 2, y: Layout.labelY - Layout.plate.height / 2,
                       width: Layout.plate.width, height: Layout.plate.height)
        let plate = CGPath(roundedRect: r, cornerWidth: r.height / 2, cornerHeight: r.height / 2, transform: nil)
        ctx.addPath(plate)
        ctx.setFillColor(color(0xf6f1e4, 0.92))
        ctx.fillPath()
        ctx.addPath(plate)
        ctx.setStrokeColor(color(gold, 0.8))
        ctx.setLineWidth(1)
        ctx.strokePath()
    }
    ctx.restoreGState()

    // Title: the app name from config.json.
    let font = NSFont.systemFont(ofSize: 24, weight: .semibold)
    let text = NSAttributedString(string: title, attributes: [
        .font: font, .foregroundColor: NSColor(cgColor: color(gold))!, .kern: 0.5,
    ])
    let bounds = text.size()
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)
    text.draw(at: CGPoint(x: (w - bounds.width) / 2, y: 40))
    NSGraphicsContext.restoreGraphicsState()

    // Ornament under the title: two lines and a small diamond.
    ctx.saveGState()
    ctx.setStrokeColor(color(gold, 0.75))
    ctx.setLineWidth(1)
    let oy: CGFloat = 86
    ctx.strokeLineSegments(between: [CGPoint(x: 270, y: oy), CGPoint(x: 318, y: oy),
                                     CGPoint(x: 342, y: oy), CGPoint(x: 390, y: oy)])
    ctx.translateBy(x: 330, y: oy)
    ctx.rotate(by: .pi / 4)
    ctx.stroke(CGRect(x: -5, y: -5, width: 10, height: 10))
    ctx.restoreGState()

    // Dotted gold arrow from the app to Applications.
    ctx.saveGState()
    ctx.translateBy(x: 255, y: 170)
    ctx.setStrokeColor(color(gold))
    ctx.setLineWidth(3)
    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)
    let arc = CGMutablePath()
    arc.move(to: CGPoint(x: 6, y: 46))
    arc.addCurve(to: CGPoint(x: 140, y: 42), control1: CGPoint(x: 46, y: 6), control2: CGPoint(x: 104, y: 6))
    ctx.saveGState()
    ctx.setLineDash(phase: 0, lengths: [2, 9])
    ctx.addPath(arc)
    ctx.strokePath()
    ctx.restoreGState()
    let head = CGMutablePath()
    head.move(to: CGPoint(x: 126, y: 40))
    head.addLine(to: CGPoint(x: 141, y: 44))
    head.addLine(to: CGPoint(x: 138, y: 29))
    ctx.addPath(head)
    ctx.strokePath()
    ctx.restoreGState()
}

private func render(scale: CGFloat, title: String) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(Layout.size.width * scale),
                               pixelsHigh: Int(Layout.size.height * scale), bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = Layout.size   // 72 dpi for 1x, 144 dpi for 2x
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    // The context already maps points to pixels, because rep.size is set in points.
    draw(NSGraphicsContext.current!.cgContext, title: title)
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let args = CommandLine.arguments
guard args.count == 4 else {
    FileHandle.standardError.write("gebruik: dmg-background <naam> <out.png> <out@2x.png>\n".data(using: .utf8)!)
    exit(1)
}
try! render(scale: 1, title: args[1]).write(to: URL(fileURLWithPath: args[2]))
try! render(scale: 2, title: args[1]).write(to: URL(fileURLWithPath: args[3]))
// The layout for package.sh, so the icon positions live only here.
print("""
DMG_WIDTH=\(Int(Layout.size.width)) DMG_HEIGHT=\(Int(Layout.size.height)) \
APP_X=\(Int(Layout.appCenter.x)) APP_Y=\(Int(Layout.appCenter.y)) \
FOLDER_X=\(Int(Layout.folderCenter.x)) FOLDER_Y=\(Int(Layout.folderCenter.y))
""")
