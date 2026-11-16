import Foundation

/// Decides which notifications are due. Pure logic, no side effects.
struct NotificationPlanner {
    static let updateId = "update.available"
    static let kinds = ["pre1", "pre2", "adhan"]
    /// Every id a prayer plan can use, so a new plan replaces the old one completely.
    static let prayerIds: [String] = Prayer.allCases.flatMap { p in kinds.map { "prayer.\(p.rawValue).\($0)" } }

    let l: Localizing

    /// Reminders for every prayer still ahead today, plus tomorrow's Fajr (estimated) after Isha.
    func prayerPlan(day: PrayerDay, preAdhan: PreAdhanSettings, now: Date, settings: AppSettings,
                    calendar: Calendar = .current) -> [PlannedNotification] {
        var upcoming = Prayer.allCases.compactMap { p in day.times[p].map { (p, $0) } }.filter { $0.1 > now }
        if upcoming.isEmpty, let fajr = day.times[.fajr],
           let tomorrow = calendar.date(byAdding: .day, value: 1, to: fajr) {
            upcoming = [(.fajr, tomorrow)]
        }
        var plan: [PlannedNotification] = []
        for (prayer, date) in upcoming {
            let name = l.t(prayer.localizationKey)
            let at = l.t("notify.at", Formatters.time.string(from: date))
            if settings.notifyPreAdhan1, let m = preAdhan.first(for: prayer) {
                plan.append(note(prayer, "pre1", l.t("notify.soon.title", name, m), at, date, minus: m, now))
            }
            if settings.notifyPreAdhan2, let m = preAdhan.second(for: prayer) {
                plan.append(note(prayer, "pre2", l.t("notify.soon.title", name, m), at, date, minus: m, now))
            }
            if settings.notifyAtPrayer {
                plan.append(note(prayer, "adhan", l.t("notify.now.title", name), at, date, minus: 0, now))
            }
        }
        return plan.filter { ($0.date ?? now) > now }
    }

    /// One notification per new version, only when update checks and their notification are on.
    func updateNote(version: String, settings: AppSettings, notified: String?) -> PlannedNotification? {
        guard settings.checkForUpdates, settings.notifyUpdate, version != notified else { return nil }
        return PlannedNotification(id: Self.updateId, title: l.t("notify.update.title", version),
                                   body: l.t("notify.update.body"), date: nil)
    }

    private func note(_ prayer: Prayer, _ kind: String, _ title: String, _ body: String, _ date: Date,
                      minus minutes: Int, _ now: Date) -> PlannedNotification {
        PlannedNotification(id: "prayer.\(prayer.rawValue).\(kind)", title: title, body: body,
                            date: date.addingTimeInterval(-Double(minutes) * 60),
                            category: UserNotificationService.stopCategory)
    }
}
