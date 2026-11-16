import AppKit

// Cuts the mosque out of Nida's icon as a one-colour silhouette for the menu bar (a template image:
// macOS colours it like the rest of the menu bar). Light pixels become ink, the dark green background
// becomes transparent.
//   menubar-logo <AppIcon-source.png> <out.png> <out@2x.png>

/// The mosque in the 1024 source, top-left origin.
let crop = CGRect(x: 150, y: 225, width: 725, height: 612)
let heightPt: CGFloat = 16

func render(source: CGImage, scale: CGFloat) -> Data {
    let w = Int(source.width), h = Int(source.height)
    var pixels = [UInt8](repeating: 0, count: w * h * 4)
    let space = CGColorSpaceCreateDeviceRGB()
    let read = CGContext(data: &pixels, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: space,
                         bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    read.draw(source, in: CGRect(x: 0, y: 0, width: w, height: h))
    // Mask: brightness above the background's, eased so edges stay smooth.
    var mask = [UInt8](repeating: 0, count: w * h * 4)
    for i in stride(from: 0, to: pixels.count, by: 4) {
        let r = Double(pixels[i]), g = Double(pixels[i + 1]), b = Double(pixels[i + 2])
        let luma = (0.3 * r + 0.59 * g + 0.11 * b) / 255
        let a = min(1, max(0, (luma - 0.18) / 0.12))
        mask[i + 3] = UInt8(a * 255)
    }
    let maskContext = CGContext(data: &mask, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: space,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    let full = maskContext.makeImage()!
    let cut = full.cropping(to: crop)!

    let outH = Int(heightPt * scale)
    let outW = Int((crop.width / crop.height * heightPt * scale).rounded(.up))
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: outW, pixelsHigh: outH, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: CGFloat(outW) / scale, height: heightPt)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGraphicsContext.current?.imageInterpolation = .high
    NSGraphicsContext.current!.cgContext.draw(cut, in: CGRect(x: 0, y: 0, width: CGFloat(outW) / scale, height: heightPt))
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let args = CommandLine.arguments
guard args.count == 4, let image = NSImage(contentsOfFile: args[1]),
      let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
    FileHandle.standardError.write("usage: menubar-logo <AppIcon-source.png> <out.png> <out@2x.png>\n".data(using: .utf8)!)
    exit(1)
}
try! render(source: cg, scale: 1).write(to: URL(fileURLWithPath: args[2]))
try! render(source: cg, scale: 2).write(to: URL(fileURLWithPath: args[3]))
