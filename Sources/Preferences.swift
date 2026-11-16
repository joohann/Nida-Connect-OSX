import Foundation

/// All user settings, as one value object.
struct AppSettings: Equatable {
    /// Nida in Home Assistant, or the app on its own with Aladhan and the Nida sound library.
    var source: PrayerSource = .homeAssistant
    // Menu bar
    var showIcon = false
    /// Only Nida's logo in the menu bar, no countdown.
    var iconOnly = false
    /// The clock time of the next prayer instead of the countdown.
    var prayerTimeOnly = false
    var showPrayerName = false
    var showSeconds = true
    var showSecondsAlways = false
    var colorPreAdhan = true
    /// The colon blinks with the system clock, so you can see the app is running.
    var blinkColon = true
    /// At the adhan the countdown becomes a gold label with the prayer's name, for a few minutes.
    /// A quiet signal that also shows when Focus mutes the notification.
    var prayerSignal = true
    var prayerSignalMinutes = 5
    static let prayerSignalChoices = [1, 5, 10, 15]
    // Sound
    var playbackMode: PlaybackMode = .away
    // Notifications
    var notifyPreAdhan1 = true
    var notifyPreAdhan2 = true
    var notifyAtPrayer = true
    // Updates
    var checkForUpdates = true
    var notifyUpdate = true

    var wantsNotifications: Bool {
        notifyPreAdhan1 || notifyPreAdhan2 || notifyAtPrayer || (checkForUpdates && notifyUpdate)
    }
}

/// Persists settings, the server address and the last known prayer day (for offline starts).
protocol PreferencesStoring: AnyObject {
    func load() -> AppSettings
    func save(_ settings: AppSettings)
    var serverAddress: String? { get set }
    var lastDay: PrayerDay? { get set }
    var lastPreAdhan: PreAdhanSettings? { get set }
    var lastAudio: NidaAudioSettings? { get set }
    var lastCalculation: NidaCalculation? { get set }
    /// Home Assistant's internal, external and Nabu Casa addresses, as last reported.
    var endpoints: HAEndpoints? { get set }
    /// The last version an update notification was posted for, so each version notifies once.
    var notifiedUpdateVersion: String? { get set }
    /// True once the first-launch setup was finished or closed.
    var setupDone: Bool { get set }
    /// Settings for running without Home Assistant.
    var standalone: StandaloneSettings? { get set }
    /// The last prayer day calculated without Home Assistant, for offline starts.
    var lastStandaloneDay: PrayerDay? { get set }
}

final class UserDefaultsPreferences: PreferencesStoring {
    private typealias Flag = (key: String, path: WritableKeyPath<AppSettings, Bool>)

    private static let flags: [Flag] = [
        ("showIcon", \.showIcon),
        ("iconOnly", \.iconOnly),
        ("prayerTimeOnly", \.prayerTimeOnly),
        ("showPrayerName", \.showPrayerName),
        ("showSeconds", \.showSeconds),
        ("showSecondsAlways", \.showSecondsAlways),
        ("colorPreAdhan", \.colorPreAdhan),
        ("blinkColon", \.blinkColon),
        ("prayerSignal", \.prayerSignal),
        ("notifyPreAdhan1", \.notifyPreAdhan1),
        ("notifyPreAdhan2", \.notifyPreAdhan2),
        ("notifyAtPrayer", \.notifyAtPrayer),
        ("checkForUpdates", \.checkForUpdates),
        ("notifyUpdate", \.notifyUpdate),
    ]
    private enum Key {
        static let serverAddress = "serverAddress"
        static let lastDay = "lastDay"
        static let lastPreAdhan = "lastPreAdhan"
        static let notifiedUpdateVersion = "notifiedUpdateVersion"
    }
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let d = AppSettings()
        var registered: [String: Any] = [:]
        Self.flags.forEach { registered[$0.key] = d[keyPath: $0.path] }
        registered["prayerSignalMinutes"] = d.prayerSignalMinutes
        defaults.register(defaults: registered)
    }

    func load() -> AppSettings {
        var s = AppSettings()
        for f in Self.flags { s[keyPath: f.path] = defaults.bool(forKey: f.key) }
        s.playbackMode = defaults.string(forKey: "playbackMode").flatMap(PlaybackMode.init) ?? .away
        s.source = defaults.string(forKey: "source").flatMap(PrayerSource.init) ?? .homeAssistant
        let minutes = defaults.integer(forKey: "prayerSignalMinutes")
        s.prayerSignalMinutes = AppSettings.prayerSignalChoices.contains(minutes) ? minutes : s.prayerSignalMinutes
        return s
    }

    func save(_ s: AppSettings) {
        for f in Self.flags { defaults.set(s[keyPath: f.path], forKey: f.key) }
        defaults.set(s.playbackMode.rawValue, forKey: "playbackMode")
        defaults.set(s.source.rawValue, forKey: "source")
        defaults.set(s.prayerSignalMinutes, forKey: "prayerSignalMinutes")
    }

    var serverAddress: String? {
        get { defaults.string(forKey: Key.serverAddress) }
        set { defaults.set(newValue, forKey: Key.serverAddress) }
    }

    var lastDay: PrayerDay? {
        get { decode(Key.lastDay) }
        set { encode(newValue, Key.lastDay) }
    }

    var lastCalculation: NidaCalculation? {
        get { decode("lastCalculation") }
        set { encode(newValue, "lastCalculation") }
    }

    var lastAudio: NidaAudioSettings? {
        get { decode("lastAudio") }
        set { encode(newValue, "lastAudio") }
    }

    var endpoints: HAEndpoints? {
        get { decode("endpoints") }
        set { encode(newValue, "endpoints") }
    }

    var lastPreAdhan: PreAdhanSettings? {
        get { decode(Key.lastPreAdhan) }
        set { encode(newValue, Key.lastPreAdhan) }
    }

    var standalone: StandaloneSettings? {
        get { decode("standalone") }
        set { encode(newValue, "standalone") }
    }

    var lastStandaloneDay: PrayerDay? {
        get { decode("lastStandaloneDay") }
        set { encode(newValue, "lastStandaloneDay") }
    }

    var setupDone: Bool {
        get { defaults.bool(forKey: "setupDone") }
        set { defaults.set(newValue, forKey: "setupDone") }
    }

    var notifiedUpdateVersion: String? {
        get { defaults.string(forKey: Key.notifiedUpdateVersion) }
        set { defaults.set(newValue, forKey: Key.notifiedUpdateVersion) }
    }

    private func decode<T: Decodable>(_ key: String) -> T? {
        defaults.data(forKey: key).flatMap { try? JSONDecoder().decode(T.self, from: $0) }
    }

    private func encode<T: Encodable>(_ value: T?, _ key: String) {
        defaults.set(value.flatMap { try? JSONEncoder().encode($0) }, forKey: key)
    }
}
