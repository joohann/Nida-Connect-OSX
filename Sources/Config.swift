import Foundation

/// Value object for the central config.json, which is bundled into the app.
struct AppConfig: Decodable {
    struct HomeAssistant: Decodable {
        let integrationDomain: String
        let reconnectSeconds: Double
        let maxReconnectSeconds: Double
        /// Port of the one-shot 127.0.0.1 listener for the login redirect; part of the OAuth client id.
        let loginPort: UInt16
    }
    /// Prayer times away from home: own times from Aladhan beyond this distance from Nida's location.
    struct Away: Decodable {
        let distanceKm: Double
        let aladhanUrl: URL
    }
    struct Update: Decodable {
        let publicKey: String
    }
    let appName: String
    let bundleId: String
    let version: String
    let homeAssistant: HomeAssistant
    let away: Away
    let update: Update

    /// Updates need a signing key; without one the app never trusts a feed.
    var updatesEnabled: Bool { !update.publicKey.isEmpty }
}

protocol ConfigLoading {
    func load() throws -> AppConfig
}

struct BundleConfigLoader: ConfigLoading {
    let bundle: Bundle
    init(bundle: Bundle = .main) { self.bundle = bundle }

    func load() throws -> AppConfig {
        guard let url = bundle.url(forResource: "config", withExtension: "json") else {
            throw CocoaError(.fileNoSuchFile)
        }
        return try JSONDecoder().decode(AppConfig.self, from: Data(contentsOf: url))
    }
}
