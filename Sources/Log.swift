import OSLog

/// Diagnostics only. Never log tokens or message bodies.
enum Log {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "app"
    static let connection = Logger(subsystem: subsystem, category: "connection")
    static let update = Logger(subsystem: subsystem, category: "update")
}
