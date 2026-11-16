import Foundation

/// The three ways the menu bar shows the countdown, picked in the setup and the settings.
/// A view on top of the separate flags, so the fine-grained switches under Advanced keep working.
enum MenuBarStyle: String, CaseIterable {
    /// Only Nida's logo.
    case icon
    /// The clock time of the next prayer.
    case time
    /// Countdown only.
    case compact
    /// Prayer name and countdown.
    case named
    /// Prayer name and countdown with seconds.
    case precise
}

extension AppSettings {
    var menuBarStyle: MenuBarStyle {
        get {
            if iconOnly { return .icon }
            if prayerTimeOnly { return .time }
            if showSecondsAlways { return .precise }
            return showPrayerName ? .named : .compact
        }
        set {
            iconOnly = newValue == .icon
            prayerTimeOnly = newValue == .time
            guard newValue != .icon && newValue != .time else { return }
            showPrayerName = newValue != .compact
            showSecondsAlways = newValue == .precise
        }
    }

    /// The moon shows only with the name styles; icon only, prayer time and compact stay bare.
    var showsMoon: Bool { showIcon && (menuBarStyle == .named || menuBarStyle == .precise) }

    /// One switch for all prayer notifications.
    var notifiesPrayers: Bool {
        get { notifyPreAdhan1 || notifyPreAdhan2 || notifyAtPrayer }
        set { notifyPreAdhan1 = newValue; notifyPreAdhan2 = newValue; notifyAtPrayer = newValue }
    }
}
