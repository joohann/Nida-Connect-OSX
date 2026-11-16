import AppKit
import CryptoKit
import Foundation
import Network
import Security

/// Signs in through Home Assistant's own login page in the browser (OAuth 2 with PKCE, RFC 8252).
/// A one-shot listener on 127.0.0.1 receives the redirect; Home Assistant accepts it because the
/// client id and the redirect share the same loopback host and port.
@MainActor
final class LoopbackLogin {
    struct Result {
        let credential: HACredential
        let accessToken: String
        let expires: Date
    }

    private let preferredPort: UInt16
    private let timeout: TimeInterval
    private let api: HomeAssistantTokenAPI
    private let page: CallbackPage
    private var listener: NWListener?
    private var continuation: CheckedContinuation<(code: String, state: String), Error>?

    init(preferredPort: UInt16, timeout: TimeInterval = 300, api: HomeAssistantTokenAPI = HomeAssistantTokenAPI(),
         page: CallbackPage) {
        self.preferredPort = preferredPort
        self.timeout = timeout
        self.api = api
        self.page = page
    }

    func run(server: ServerAddress, openURL: (URL) -> Void) async throws -> Result {
        defer { stop() }
        let port = try await listen()
        let clientId = "http://127.0.0.1:\(port)/"
        let redirect = "http://127.0.0.1:\(port)/callback"
        let state = Self.randomToken()
        let verifier = Self.randomToken()

        var c = URLComponents(url: server.baseURL.appendingPathComponent("auth/authorize"),
                              resolvingAgainstBaseURL: false)!
        c.queryItems = [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: clientId),
            URLQueryItem(name: "redirect_uri", value: redirect),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "code_challenge", value: Self.challenge(for: verifier)),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
        ]
        openURL(c.url!)

        let callback = try await waitForCallback()
        guard callback.state == state else { throw AuthError.stateMismatch }
        let grant = try await api.exchange(server: server, code: callback.code, clientId: clientId, verifier: verifier)
        guard let refresh = grant.refreshToken else { throw AuthError.rejected }
        return Result(credential: .oauth(refreshToken: refresh, clientId: clientId),
                      accessToken: grant.accessToken, expires: Date().addingTimeInterval(grant.expiresIn))
    }

    func cancel() {
        finish(.failure(AuthError.cancelled))
    }

    // MARK: Listener

    /// Listens on 127.0.0.1 only; the preferred port keeps the client id stable, any free port otherwise.
    private func listen() async throws -> UInt16 {
        for candidate in [preferredPort, 0] {
            if let port = try? await start(port: candidate) { return port }
        }
        throw AuthError.unreachable
    }

    private func start(port: UInt16) async throws -> UInt16 {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: port) ?? .any)
        parameters.allowLocalEndpointReuse = true
        let listener = try NWListener(using: parameters)
        self.listener = listener
        listener.newConnectionHandler = { [weak self] connection in
            Task { @MainActor in self?.handle(connection) }
        }
        return try await withCheckedThrowingContinuation { cont in
            // The listener runs on the main queue, so this flag is only touched there.
            final class Once: @unchecked Sendable { var done = false }
            let once = Once()
            listener.stateUpdateHandler = { state in
                guard !once.done else { return }
                switch state {
                case .ready:
                    once.done = true
                    cont.resume(returning: listener.port?.rawValue ?? port)
                case .failed(let error):
                    once.done = true
                    listener.cancel()
                    cont.resume(throwing: error)
                default:
                    break
                }
            }
            listener.start(queue: .main)
        }
    }

    private func waitForCallback() async throws -> (code: String, state: String) {
        let timeout = self.timeout
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(timeout * 1e9))
            self?.finish(.failure(AuthError.timedOut))
        }
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { self.continuation = $0 }
        } onCancel: {
            Task { @MainActor [weak self] in self?.cancel() }
        }
    }

    private func finish(_ result: Swift.Result<(code: String, state: String), Error>) {
        guard let continuation else { return }
        self.continuation = nil
        continuation.resume(with: result)
    }

    private func stop() {
        listener?.cancel()
        listener = nil
        finish(.failure(AuthError.cancelled))
    }

    /// Answers one browser request: the callback gets a page saying the app is signed in, anything else a 404.
    private func handle(_ connection: NWConnection) {
        connection.start(queue: .main)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16_384) { [weak self] data, _, _, _ in
            Task { @MainActor in
                guard let self else { connection.cancel(); return }
                let request = data.map { String(decoding: $0, as: UTF8.self) } ?? ""
                let parsed = CallbackRequest(request)
                let status: String
                let body: String
                switch parsed {
                case .code(let code, let state):
                    status = "200 OK"
                    body = self.page.success()
                    self.finish(.success((code, state)))
                case .error:
                    status = "200 OK"
                    body = self.page.failure()
                    self.finish(.failure(AuthError.denied))
                case .other:
                    status = "404 Not Found"
                    body = ""
                }
                let head = "HTTP/1.1 \(status)\r\nContent-Type: text/html; charset=utf-8\r\n"
                    + "Content-Security-Policy: default-src 'none'; style-src 'unsafe-inline'\r\n"
                    + "Cache-Control: no-store\r\nConnection: close\r\nContent-Length: \(body.utf8.count)\r\n\r\n"
                connection.send(content: Data((head + body).utf8), completion: .contentProcessed { _ in
                    connection.cancel()
                })
            }
        }
    }

    // MARK: PKCE

    /// 32 random bytes, base64url: used for the state and the PKCE verifier.
    nonisolated static func randomToken() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return base64url(Data(bytes))
    }

    nonisolated static func challenge(for verifier: String) -> String {
        base64url(Data(SHA256.hash(data: Data(verifier.utf8))))
    }

    nonisolated private static func base64url(_ data: Data) -> String {
        data.base64EncodedString().replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }
}

/// The first line of the browser's request to the loopback listener.
enum CallbackRequest: Equatable {
    case code(String, state: String)
    case error
    case other

    init(_ raw: String) {
        let line = raw.split(separator: "\r\n", maxSplits: 1).first.map(String.init) ?? ""
        let parts = line.split(separator: " ")
        guard parts.count >= 2, parts[0] == "GET",
              let url = URLComponents(string: "http://127.0.0.1" + parts[1]), url.path == "/callback" else {
            self = .other
            return
        }
        let items = Dictionary(url.queryItems?.map { ($0.name, $0.value ?? "") } ?? [], uniquingKeysWith: { a, _ in a })
        if let code = items["code"], !code.isEmpty, let state = items["state"] {
            self = .code(code, state: state)
        } else {
            self = .error
        }
    }
}

/// The page the browser shows after login, from Resources/login-callback.html with escaped texts.
struct CallbackPage {
    let template: String
    let l: Localizing
    let appName: String

    init(bundle: Bundle = .main, l: Localizing, appName: String) {
        let url = bundle.url(forResource: "login-callback", withExtension: "html")
        template = url.flatMap { try? String(contentsOf: $0, encoding: .utf8) } ?? "{{title}}"
        self.l = l
        self.appName = appName
    }

    func success() -> String { render(l.t("login.done.title"), l.t("login.done.body", appName)) }
    func failure() -> String { render(l.t("login.failed.title"), l.t("login.failed.body", appName)) }

    private func render(_ title: String, _ body: String) -> String {
        template
            .replacingOccurrences(of: "{{lang}}", with: Self.escape(l.locale.identifier))
            .replacingOccurrences(of: "{{dir}}", with: l.isRightToLeft ? "rtl" : "ltr")
            .replacingOccurrences(of: "{{title}}", with: Self.escape(title))
            .replacingOccurrences(of: "{{body}}", with: Self.escape(body))
    }

    static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }
}
