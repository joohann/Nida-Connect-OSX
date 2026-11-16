import Foundation

enum Formatters {
    static let time: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .none
        f.timeStyle = .short
        return f
    }()

    /// Menu bar countdown, always with a leading zero.
    /// One hour or more: "02:14" (hours:minutes), or "02:14:05" with `secondsAlways`.
    /// Under an hour: "47:09" (minutes:seconds), or "00:47" (hours:minutes) without seconds.
    static func menuBarCountdown(_ remaining: TimeInterval, showSeconds: Bool, secondsAlways: Bool = false) -> String {
        let total = Int(remaining.rounded(.down))
        if secondsAlways && total >= 3600 { return fullCountdown(remaining) }
        if total >= 3600 || !(showSeconds || secondsAlways) {
            // Round minutes up so the bar never shows "00:00" before the adhan.
            let minutes = Int((remaining / 60).rounded(.up))
            return String(format: "%02d:%02d", minutes / 60, minutes % 60)
        }
        return String(format: "%02d:%02d", total / 60, total % 60)
    }

    /// Panel countdown: always "HH:MM:SS".
    static func fullCountdown(_ remaining: TimeInterval) -> String {
        let total = Int(remaining.rounded(.down))
        return String(format: "%02d:%02d:%02d", total / 3600, (total / 60) % 60, total % 60)
    }

    /// The hijri date in the user's language, e.g. "24 Jumada al-Ula 1448".
    static func hijri(_ h: HijriDate, locale: Locale = .current) -> String? {
        var calendar = Calendar(identifier: .islamicUmmAlQura)
        calendar.locale = locale
        guard let date = calendar.date(from: DateComponents(year: h.year, month: h.month, day: h.day)) else {
            return nil
        }
        let f = DateFormatter()
        f.calendar = calendar
        f.locale = locale
        f.setLocalizedDateFormatFromTemplate("dMMMMy")
        return f.string(from: date)
    }
}
