import Foundation

/// The five daily prayers, in order. Raw values match Nida's entity suffixes.
enum Prayer: String, CaseIterable, Codable {
    case fajr, dhuhr, asr, maghrib, isha

    var localizationKey: String { "prayer.\(rawValue)" }
}

/// Today's prayer times as reported by Nida, plus the hijri date. Value object.
struct PrayerDay: Equatable, Codable {
    var times: [Prayer: Date]
    var hijri: HijriDate?

    init(times: [Prayer: Date] = [:], hijri: HijriDate? = nil) {
        self.times = times
        self.hijri = hijri
    }

    var isComplete: Bool { Prayer.allCases.allSatisfy { times[$0] != nil } }
}

/// Hijri date fields from Nida's sensors. `holiday` is nil when there is none.
struct HijriDate: Equatable, Codable {
    let day: Int
    let month: Int
    let year: Int
    let holiday: String?
}

/// Pre-adhan reminders as configured in Nida, so the colours match Home Assistant.
struct PreAdhanSettings: Equatable, Codable {
    /// Minutes before the adhan for the first reminder; 0 means off.
    var firstMinutes: Int
    var secondEnabled: Bool
    var secondMinutes: Int
    /// Prayers whose pre-adhan reminders are switched off in Nida.
    var disabledPrayers: Set<Prayer>

    static let nidaDefault = PreAdhanSettings(firstMinutes: 25, secondEnabled: false, secondMinutes: 10,
                                              disabledPrayers: [])

    func first(for prayer: Prayer) -> Int? {
        guard firstMinutes > 0, !disabledPrayers.contains(prayer) else { return nil }
        return firstMinutes
    }

    func second(for prayer: Prayer) -> Int? {
        guard secondEnabled, secondMinutes > 0, !disabledPrayers.contains(prayer) else { return nil }
        return secondMinutes
    }

    /// Reads Nida's config entry options (`nida/get_settings`), with Nida's own defaults for missing keys.
    init(nidaOptions o: [String: Any]) {
        func int(_ key: String, _ fallback: Int) -> Int {
            (o[key] as? NSNumber)?.intValue ?? Int(o[key] as? String ?? "") ?? fallback
        }
        firstMinutes = int("pre_adhan_minutes", 25)
        secondEnabled = (o["pre_adhan_two_enabled"] as? Bool) ?? false
        secondMinutes = int("pre_adhan_minutes_2", 10)
        disabledPrayers = Set(Prayer.allCases.filter { (o["pre_adhan_enabled_\($0.rawValue)"] as? Bool) == false })
    }

    init(firstMinutes: Int, secondEnabled: Bool, secondMinutes: Int, disabledPrayers: Set<Prayer>) {
        self.firstMinutes = firstMinutes
        self.secondEnabled = secondEnabled
        self.secondMinutes = secondMinutes
        self.disabledPrayers = disabledPrayers
    }
}

/// Where we are relative to the upcoming prayer.
enum CountdownPhase: Equatable {
    case normal
    case preAdhan1
    case preAdhan2
}

/// The upcoming prayer at a given moment. Pure value, computed by PrayerClock.
struct UpcomingPrayer: Equatable {
    let prayer: Prayer
    let date: Date
    let previous: Date?
    let phase: CountdownPhase
    /// True when the time is today's time moved to tomorrow, until Nida reports the new day.
    let isEstimate: Bool

    func remaining(at now: Date) -> TimeInterval { max(0, date.timeIntervalSince(now)) }

    /// 0…1 from the previous prayer to this one.
    func progress(at now: Date) -> Double? {
        guard let previous, date > previous else { return nil }
        return min(1, max(0, now.timeIntervalSince(previous) / date.timeIntervalSince(previous)))
    }
}

/// Finds the upcoming prayer and its phase. Pure logic.
struct PrayerClock {
    /// The prayer whose time began less than `duration` ago, with its time; nil otherwise.
    func justStarted(day: PrayerDay, now: Date, duration: TimeInterval) -> (prayer: Prayer, date: Date)? {
        Prayer.allCases.reversed().lazy
            .compactMap { p in day.times[p].map { (prayer: p, date: $0) } }
            .first { $0.date <= now && now.timeIntervalSince($0.date) < duration }
    }

    func upcoming(day: PrayerDay, preAdhan: PreAdhanSettings, now: Date,
                  calendar: Calendar = .current) -> UpcomingPrayer? {
        let today = Prayer.allCases.compactMap { p in day.times[p].map { (prayer: p, date: $0) } }
        guard !today.isEmpty else { return nil }

        var next = today.first { $0.date > now }
        var previous = today.last { $0.date <= now }?.date
        var estimate = false
        if next == nil, let fajr = day.times[.fajr],
           let tomorrow = calendar.date(byAdding: .day, value: 1, to: fajr) {
            // After Isha: tomorrow's Fajr, estimated from today's until Nida rolls over.
            next = (.fajr, tomorrow)
            estimate = true
        }
        if previous == nil, let isha = day.times[.isha] {
            previous = calendar.date(byAdding: .day, value: -1, to: isha)
        }
        guard let next else { return nil }

        let remaining = next.date.timeIntervalSince(now)
        var phase = CountdownPhase.normal
        if let m2 = preAdhan.second(for: next.prayer), remaining <= Double(m2) * 60 {
            phase = .preAdhan2
        } else if let m1 = preAdhan.first(for: next.prayer), remaining <= Double(m1) * 60 {
            phase = .preAdhan1
        }
        return UpcomingPrayer(prayer: next.prayer, date: next.date, previous: previous,
                              phase: phase, isEstimate: estimate)
    }
}
