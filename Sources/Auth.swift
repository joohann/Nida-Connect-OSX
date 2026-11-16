import Foundation

/// How the app signs in to Home Assistant. Value object, stored as JSON in the Keychain.
enum HACredential: Codable, Equatable {
    /// Signed in through Home Assistant's login page; the refresh token renews short-lived access tokens.
    case oauth(refreshToken: String, clientId: String)
    /// A long-lived access token made by the user in their Home Assistant profile.
    case longLived(token: String)
}

enum AuthError: Error, Equatable {
    /// Home Assistant refused the credential (revoked, expired, wrong token).
    case rejected
    /// No answer from Home Assistant; worth trying again later.
    case unreachable
    case cancelled
    case timedOut
    /// The callback did not belong to this login attempt.
    case stateMismatch
    /// The user cancelled on the login page.
    case denied
}

protocol CredentialStoring {
    func load() -> HACredential?
    func save(_ credential: HACredential) throws
    func delete()
}

/// Keeps the credential in the Keychain. A plain string from version 1.0 counts as a long-lived token.
struct KeychainCredentialStore: CredentialStoring {
    let store: TokenStoring

    func load() -> HACredential? {
        guard let raw = store.token() else { return nil }
        if let credential = try? JSONDecoder().decode(HACredential.self, from: Data(raw.utf8)) { return credential }
        return .longLived(token: raw)
    }

    func save(_ credential: HACredential) throws {
        let data = try JSONEncoder().encode(credential)
        try store.save(String(decoding: data, as: UTF8.self))
    }

    func delete() { store.delete() }
}

/// Hands out a valid access token for the WebSocket. The client only talks to this protocol.
@MainActor
protocol AccessTokenProviding: AnyObject {
    /// True when a rejected token can be retried with a fresh one.
    var canRefresh: Bool { get }
    /// `server` is the address in use, so a refresh goes the same way as the connection.
    func accessToken(forceRefresh: Bool, server: ServerAddress) async throws -> String
}

/// Access tokens for one Home Assistant, whichever address it is reached on. OAuth access tokens
/// live about 30 minutes, so they are renewed with the refresh token shortly before they expire.
@MainActor
final class HomeAssistantAuth: AccessTokenProviding {
    let credential: HACredential
    private let api: HomeAssistantTokenAPI
    private let clock: () -> Date
    private var cached: (token: String, expires: Date)?

    init(credential: HACredential, api: HomeAssistantTokenAPI = HomeAssistantTokenAPI(),
         seed: (token: String, expires: Date)? = nil, clock: @escaping () -> Date = Date.init) {
        self.credential = credential
        self.api = api
        self.cached = seed
        self.clock = clock
    }

    var canRefresh: Bool {
        if case .oauth = credential { return true }
        return false
    }

    func accessToken(forceRefresh: Bool, server: ServerAddress) async throws -> String {
        switch credential {
        case .longLived(let token):
            return token
        case .oauth(let refreshToken, let clientId):
            if !forceRefresh, let cached, cached.expires > clock().addingTimeInterval(60) { return cached.token }
            let grant = try await api.refresh(server: server, refreshToken: refreshToken, clientId: clientId)
            cached = (grant.accessToken, clock().addingTimeInterval(grant.expiresIn))
            return grant.accessToken
        }
    }
}

/// Home Assistant's OAuth endpoints (/auth/token, /auth/revoke). Form-encoded, as Home Assistant expects.
struct HomeAssistantTokenAPI {
    struct Grant {
        let accessToken: String
        let refreshToken: String?
        let expiresIn: TimeInterval
    }

    let session: URLSession

    init(session: URLSession = URLSession(configuration: .ephemeral)) {
        self.session = session
    }

    func exchange(server: ServerAddress, code: String, clientId: String, verifier: String) async throws -> Grant {
        try await post(server, "auth/token", ["grant_type": "authorization_code", "code": code,
                                              "client_id": clientId, "code_verifier": verifier])
    }

    func refresh(server: ServerAddress, refreshToken: String, clientId: String) async throws -> Grant {
        try await post(server, "auth/token", ["grant_type": "refresh_token", "refresh_token": refreshToken,
                                              "client_id": clientId])
    }

    /// Best effort: signing out should not fail because Home Assistant is offline.
    func revoke(server: ServerAddress, refreshToken: String) async {
        _ = try? await send(server, "auth/revoke", ["token": refreshToken])
    }

    private func post(_ server: ServerAddress, _ path: String, _ form: [String: String]) async throws -> Grant {
        let (data, status) = try await send(server, path, form)
        guard status == 200 else { throw (400..<500).contains(status) ? AuthError.rejected : AuthError.unreachable }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let access = json["access_token"] as? String else { throw AuthError.unreachable }
        let expires = (json["expires_in"] as? NSNumber)?.doubleValue ?? 1800
        return Grant(accessToken: access, refreshToken: json["refresh_token"] as? String, expiresIn: expires)
    }

    private func send(_ server: ServerAddress, _ path: String, _ form: [String: String]) async throws -> (Data, Int) {
        var request = URLRequest(url: server.baseURL.appendingPathComponent(path))
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Self.formBody(form)
        do {
            let (data, response) = try await session.data(for: request)
            return (data, (response as? HTTPURLResponse)?.statusCode ?? 0)
        } catch {
            throw AuthError.unreachable
        }
    }

    static func formBody(_ form: [String: String]) -> Data {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        let pairs = form.sorted { $0.key < $1.key }.map { key, value in
            "\(key)=\(value.addingPercentEncoding(withAllowedCharacters: allowed) ?? "")"
        }
        return Data(pairs.joined(separator: "&").utf8)
    }
}
