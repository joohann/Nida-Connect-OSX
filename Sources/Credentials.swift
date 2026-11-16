import Foundation
import Security

/// Where Home Assistant lives. Value object; validates and normalises the address.
struct ServerAddress: Equatable {
    let baseURL: URL

    /// Accepts "https://ha.example.nl", "http://192.168.1.10" or an address without scheme.
    /// Without scheme, a local address ("homeassistant.local", an IP, a bare name) gets http,
    /// like a default Home Assistant install; anything else gets https.
    init?(_ text: String) {
        var s = text.trimmingCharacters(in: .whitespacesAndNewlines)
        while s.hasSuffix("/") { s.removeLast() }
        guard !s.isEmpty else { return nil }
        if !s.contains("://") {
            let host = URL(string: "http://" + s)?.host ?? ""
            s = (Self.isLocal(host) ? "http://" : "https://") + s
        }
        guard let url = URL(string: s), let scheme = url.scheme?.lowercased(),
              scheme == "https" || scheme == "http", url.host?.isEmpty == false,
              url.query == nil, url.fragment == nil, url.user == nil else { return nil }
        baseURL = url
    }

    static func isLocal(_ host: String) -> Bool {
        let h = host.lowercased()
        if h.isEmpty { return false }
        if h.hasSuffix(".local") || h == "localhost" || !h.contains(".") { return true }
        // IPv4 private ranges and link-local.
        let parts = h.split(separator: ".").compactMap { Int($0) }
        guard parts.count == 4 else { return false }
        return parts[0] == 10 || parts[0] == 127 || (parts[0] == 192 && parts[1] == 168)
            || (parts[0] == 172 && (16...31).contains(parts[1])) || (parts[0] == 169 && parts[1] == 254)
    }

    var isLocal: Bool { Self.isLocal(baseURL.host ?? "") }

    var isEncrypted: Bool { baseURL.scheme?.lowercased() == "https" }

    var webSocketURL: URL {
        var c = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)!
        c.scheme = isEncrypted ? "wss" : "ws"
        c.path = (c.path.hasSuffix("/") ? String(c.path.dropLast()) : c.path) + "/api/websocket"
        return c.url!
    }

    var display: String {
        var s = baseURL.host ?? baseURL.absoluteString
        if let port = baseURL.port { s += ":\(port)" }
        return s
    }
}

/// Stores the Home Assistant access token. The server address is not secret; the token is.
protocol TokenStoring {
    func token() -> String?
    func save(_ token: String) throws
    func delete()
}

/// Keychain storage, readable only by this app (other apps get a macOS prompt).
struct KeychainTokenStore: TokenStoring {
    let service: String
    private let account = "home-assistant-token"

    private var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    func token() -> String? {
        var q = query
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func save(_ token: String) throws {
        let data = Data(token.utf8)
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var add = query
            add[kSecValueData as String] = data
            add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            let added = SecItemAdd(add as CFDictionary, nil)
            guard added == errSecSuccess else { throw KeychainError(status: added) }
        } else if status != errSecSuccess {
            throw KeychainError(status: status)
        }
    }

    func delete() {
        SecItemDelete(query as CFDictionary)
    }
}

struct KeychainError: Error {
    let status: OSStatus
}
