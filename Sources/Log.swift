import OSLog

/// Diagnostics only. Never log tokens or message bodies.
enum Log {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "app"
    static let connection = Logger(subsystem: subsystem, category: "connection")
    static let update = Logger(subsystem: subsystem, category: "update")
    /// When a sound starts, stops and why, and media paused for it. Read with:
    ///   log show --last 1d --info --predicate 'subsystem == "<bundle id>" AND category == "sound"'
    static let sound = Logger(subsystem: subsystem, category: "sound")
}
