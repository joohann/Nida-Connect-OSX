import AppKit

// Writes a complete .iconset folder; build.sh turns it into AppIcon.icns with iconutil.
//   icon-generator <source.png> <out.iconset> [preview.png]
let source = NSImage(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))!
// Work in pixels: the source is 1024 px, whatever its point size says.
if let rep = source.representations.first { source.size = NSSize(width: rep.pixelsWide, height: rep.pixelsHigh) }
let dir = URL(fileURLWithPath: CommandLine.arguments[2])
try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = scale == 1 ? "icon_\(base)x\(base).png" : "icon_\(base)x\(base)@2x.png"
        let png = IconDrawing.image(size: CGFloat(base * scale), source: source).representation(using: .png, properties: [:])!
        try! png.write(to: dir.appendingPathComponent(name))
    }
}
if CommandLine.arguments.count > 3 {
    try! IconDrawing.image(size: 1024, source: source).representation(using: .png, properties: [:])!
        .write(to: URL(fileURLWithPath: CommandLine.arguments[3]))
}
