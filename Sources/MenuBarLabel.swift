import AppKit
import SwiftUI

/// What sits in the menu bar: optional moon, optional prayer name and the countdown, e.g. "☾ Asr 47:09".
/// Drawn as an image because the menu bar ignores text colours: a template image (follows the menu bar)
/// normally, orange during pre-adhan 1 and red during pre-adhan 2. At the adhan it becomes a gold
/// label with the prayer's name for a few minutes, pulsing with the system seconds.
struct MenuBarLabel: View {
    @ObservedObject var model: PrayerModel
    let l: Localizing

    var body: some View {
        if model.settings.iconOnly && model.prayerSignal == nil {
            Image(nsImage: MenuBarRenderer.image(symbol: symbol, text: "", color: color, useLogo: true))
                .accessibilityLabel(text)
        } else if let prayer = model.prayerSignal {
            let name = l.t(prayer.localizationKey)
            Image(nsImage: MenuBarRenderer.badge(symbol: model.settings.showsMoon ? symbol : nil,
                                                 text: name, dimmed: !model.colonVisible))
                .accessibilityLabel(name)
        } else {
            Image(nsImage: MenuBarRenderer.image(symbol: model.settings.showsMoon ? symbol : nil,
                                                 text: text, color: color, hideColons: !model.colonVisible))
                .accessibilityLabel(text)
        }
    }

    private var symbol: String {
        model.connection == .connected || model.connection == .connecting ? "moon.stars.fill" : "moon.stars"
    }

    private var text: String {
        guard let next = model.upcoming else {
            return model.settings.showIcon ? "" : l.t("bar.noData")
        }
        if model.settings.prayerTimeOnly { return Formatters.time.string(from: next.date) }
        let time = Formatters.menuBarCountdown(next.remaining(at: model.now), showSeconds: model.settings.showSeconds,
                                                secondsAlways: model.settings.showSecondsAlways)
        return model.settings.showPrayerName ? "\(l.t(next.prayer.localizationKey)) \(time)" : time
    }

    private var color: NSColor? {
        switch model.menuBarPhase {
        case .normal: return nil
        case .preAdhan1: return .systemOrange
        case .preAdhan2: return .systemRed
        }
    }
}

enum MenuBarRenderer {
    /// Nida's gold, with dark text on it, as in the app icon.
    static let gold = NSColor(srgbRed: 0xf8 / 255, green: 0xcb / 255, blue: 0x5b / 255, alpha: 1)
    static var goldColor: Color { Color(nsColor: gold) }
    static let goldInk = NSColor(srgbRed: 0x3a / 255, green: 0x2a / 255, blue: 0x05 / 255, alpha: 1)

    /// A gold rounded label with the prayer's name. `dimmed` draws it lighter, for the pulse; the
    /// size never changes, so the menu bar does not shift.
    static func badge(symbol: String?, text: String, dimmed: Bool) -> NSImage {
        let font = NSFont.systemFont(ofSize: NSFont.systemFontSize, weight: .semibold)
        let attributed = NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: goldInk])
        let textSize = attributed.size()
        var icon: NSImage?
        if let symbol {
            let config = NSImage.SymbolConfiguration(pointSize: 12, weight: .semibold)
            icon = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?.withSymbolConfiguration(config)
        }
        let iconSize = icon?.size ?? .zero
        let gap: CGFloat = icon != nil ? 4 : 0
        let padding: CGFloat = 7
        let height: CGFloat = 18
        let pill = NSRect(x: 0, y: 1, width: ceil(padding * 2 + iconSize.width + gap + textSize.width), height: 16)

        let image = NSImage(size: NSSize(width: pill.width, height: height), flipped: false) { _ in
            NSGraphicsContext.current?.cgContext.setAlpha(dimmed ? 0.55 : 1)
            NSGraphicsContext.current?.cgContext.beginTransparencyLayer(auxiliaryInfo: nil)
            gold.setFill()
            NSBezierPath(roundedRect: pill, xRadius: 5, yRadius: 5).fill()
            if let icon {
                let rect = NSRect(x: padding, y: (height - iconSize.height) / 2,
                                  width: iconSize.width, height: iconSize.height)
                // Tint the symbol dark inside its own layer, so the gold under it stays.
                NSGraphicsContext.current?.cgContext.beginTransparencyLayer(auxiliaryInfo: nil)
                icon.draw(in: rect)
                goldInk.set()
                rect.fill(using: .sourceAtop)
                NSGraphicsContext.current?.cgContext.endTransparencyLayer()
            }
            attributed.draw(at: NSPoint(x: padding + iconSize.width + gap, y: (height - textSize.height) / 2))
            NSGraphicsContext.current?.cgContext.endTransparencyLayer()
            return true
        }
        image.isTemplate = false
        return image
    }

    /// Nida's mosque as a template image, made by the build from the app icon.
    static let logo: NSImage? = Bundle.main.url(forResource: "MenuBarLogo", withExtension: "tiff")
        .flatMap(NSImage.init(contentsOf:))

    /// `hideColons` draws the colons transparent, so the width stays the same while they blink.
    /// `useLogo` draws Nida's logo instead of the symbol.
    static func image(symbol: String?, text: String, color: NSColor?, hideColons: Bool = false,
                      useLogo: Bool = false) -> NSImage {
        let font = NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        let ink = color ?? .black
        let attributed = NSMutableAttributedString(string: text, attributes: [.font: font, .foregroundColor: ink])
        if hideColons {
            let ns = text as NSString
            var range = ns.range(of: ":")
            while range.location != NSNotFound {
                attributed.addAttribute(.foregroundColor, value: NSColor.clear, range: range)
                let start = range.location + range.length
                range = ns.range(of: ":", range: NSRange(location: start, length: ns.length - start))
            }
        }
        let textSize = text.isEmpty ? .zero : attributed.size()

        var icon: NSImage?
        if useLogo, let logo {
            icon = logo
        } else if let symbol {
            let config = NSImage.SymbolConfiguration(pointSize: 13, weight: .regular)
            icon = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
                .withSymbolConfiguration(config)
        }
        let iconSize = icon?.size ?? .zero
        let gap: CGFloat = icon != nil && !text.isEmpty ? 4 : 0
        let height: CGFloat = 18
        let width = max(1, ceil(iconSize.width + gap + textSize.width))

        let image = NSImage(size: NSSize(width: width, height: height), flipped: false) { _ in
            if let icon {
                let rect = NSRect(x: 0, y: (height - iconSize.height) / 2,
                                  width: iconSize.width, height: iconSize.height)
                icon.draw(in: rect)
                if color != nil {
                    ink.set()
                    rect.fill(using: .sourceAtop)
                }
            }
            if !text.isEmpty {
                attributed.draw(at: NSPoint(x: iconSize.width + gap, y: (height - textSize.height) / 2))
            }
            return true
        }
        image.isTemplate = color == nil
        return image
    }
}
