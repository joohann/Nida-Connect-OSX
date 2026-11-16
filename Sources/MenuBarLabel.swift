import AppKit
import SwiftUI

/// What sits in the menu bar: optional moon, optional prayer name and the countdown, e.g. "☾ Asr 47:09".
/// Drawn as an image because the menu bar ignores text colours: a template image (follows the menu bar)
/// normally, orange during pre-adhan 1 and red during pre-adhan 2.
struct MenuBarLabel: View {
    @ObservedObject var model: PrayerModel
    let l: Localizing

    var body: some View {
        Image(nsImage: MenuBarRenderer.image(symbol: model.settings.showIcon ? symbol : nil,
                                             text: text, color: color, hideColons: !model.colonVisible))
            .accessibilityLabel(text)
    }

    private var symbol: String {
        model.connection == .connected || model.connection == .connecting ? "moon.stars.fill" : "moon.stars"
    }

    private var text: String {
        guard let next = model.upcoming else {
            return model.settings.showIcon ? "" : l.t("bar.noData")
        }
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
    /// `hideColons` draws the colons transparent, so the width stays the same while they blink.
    static func image(symbol: String?, text: String, color: NSColor?, hideColons: Bool = false) -> NSImage {
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
        if let symbol {
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
