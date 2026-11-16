import Foundation
import Network

/// Connection state shown on the card.
enum ConnectionState: Equatable {
    case notConfigured
    case connecting
    case connected
    case authFailed
    case nidaNotFound
    case unreachable
}

/// Events from Home Assistant, already translated into domain values.
enum NidaEvent {
    case state(ConnectionState)
    case day(PrayerDay)
    case preAdhan(PreAdhanSettings)
    case audio(NidaAudioSettings)
    /// Nida's calculation: Aladhan method and Nida's own location (nil: Nida follows Home Assistant's home).
    case calculation(method: Int, nidaHome: Coordinate?)
    /// Home Assistant's home location from `get_config`.
    case haHome(Coordinate?)
    /// Addresses Home Assistant knows itself by: internal, external and Nabu Casa.
    case endpoints(HAEndpoints)
    /// The address the live connection uses right now.
    case route(ServerAddress)
}

/// Home Assistant's own addresses. Value object; strings as Home Assistant reports them.
struct HAEndpoints: Equatable, Codable {
    var internalURL: String?
    var externalURL: String?
    var cloudURL: String?

    init(internalURL: String? = nil, externalURL: String? = nil, cloudURL: String? = nil) {
        self.internalURL = internalURL
        self.externalURL = externalURL
        self.cloudURL = cloudURL
    }

    /// From `get_config` (internal_url, external_url) and `cloud/status` (Nabu Casa remote UI).
    init(config: [String: Any]?, cloud: [String: Any]?) {
        func url(_ v: Any?) -> String? {
            guard let s = v as? String, ServerAddress(s) != nil else { return nil }
            return s
        }
        internalURL = url(config?["internal_url"])
        externalURL = url(config?["external_url"])
        if let cloud, (cloud["logged_in"] as? Bool) == true, (cloud["remote_enabled"] as? Bool) != false,
           let domain = cloud["remote_domain"] as? String, !domain.isEmpty {
            cloudURL = url("https://" + domain)
        }
    }

    /// Every address to try, local ones first, starting with the one the user picked.
    func routes(primary: ServerAddress) -> [ServerAddress] {
        var all: [ServerAddress] = [primary]
        for s in [internalURL, externalURL, cloudURL].compactMap({ $0 }) {
            if let a = ServerAddress(s), !all.contains(a) { all.append(a) }
        }
        let local = all.filter(\.isLocal)
        return local + all.filter { !$0.isLocal }
    }

    func isCloud(_ address: ServerAddress) -> Bool {
        cloudURL.flatMap(ServerAddress.init) == address
    }
}

/// Live source of Nida data. The model only talks to this protocol.
@MainActor
protocol NidaSource: AnyObject {
    var onEvent: ((NidaEvent) -> Void)? { get set }
    /// Connects to the first address that answers, in this order.
    func connect(routes: [ServerAddress], auth: AccessTokenProviding)
    /// New addresses for the next (re)connect, without dropping a working connection.
    func update(routes: [ServerAddress])
    func disconnect()
    /// Re-reads Nida's settings (pre-adhan minutes); they change without a state event.
    func refreshSettings()
}

/// Home Assistant WebSocket API: authenticates, finds Nida's entities, reads its pre-adhan settings
/// and subscribes to the prayer sensors. Tries the addresses in order (home first, then external or
/// Nabu Casa), falls over when one does not answer in time, and starts again from the top when the
/// network changes. Reconnects with backoff; pings to detect dead connections.
@MainActor
final class HomeAssistantClient: NidaSource {
    var onEvent: ((NidaEvent) -> Void)?

    private let domain: String
    private let baseDelay: Double
    private let maxDelay: Double
    private let session = URLSession(configuration: .ephemeral)
    private var task: URLSessionWebSocketTask?
    private var routes: [ServerAddress] = []
    private var routeIndex = 0
    private var server: ServerAddress? { routes.indices.contains(routeIndex) ? routes[routeIndex] : nil }
    private var authenticated = false
    private var connectTimeout: Task<Void, Never>?
    private let pathMonitor = NWPathMonitor()
    private var lastPath: String?
    private var auth: AccessTokenProviding?
    /// Set after a rejected token, so the next attempt fetches a fresh one (once).
    private var retryingAuth = false
    private var nextId = 1
    private var pending: [Int: (Bool, Any?) -> Void] = [:]
    private var subscriptionId: Int?
    private var entities = NidaEntities()
    private var states: [String: String] = [:]
    private var delay: Double
    private var generation = 0
    private var heartbeat: Task<Void, Never>?
    private var awaitingPong = false

    init(config: AppConfig.HomeAssistant) {
        domain = config.integrationDomain
        baseDelay = max(1, config.reconnectSeconds)
        maxDelay = max(baseDelay, config.maxReconnectSeconds)
        delay = baseDelay
        pathMonitor.pathUpdateHandler = { [weak self] path in
            let key = path.status == .satisfied
                ? path.availableInterfaces.map(\.name).joined(separator: ",") : "offline"
            Task { @MainActor in self?.networkChanged(key, satisfied: path.status == .satisfied) }
        }
        pathMonitor.start(queue: .main)
    }

    func connect(routes: [ServerAddress], auth: AccessTokenProviding) {
        self.routes = routes
        self.auth = auth
        routeIndex = 0
        retryingAuth = false
        delay = baseDelay
        open()
    }

    func update(routes next: [ServerAddress]) {
        guard next != routes else { return }
        let current = server
        routes = next
        routeIndex = current.flatMap { next.firstIndex(of: $0) } ?? 0
        // Connected over the internet while a home address is now known: try home first next time.
    }

    func disconnect() {
        generation += 1
        close()
        routes = []
        auth = nil
        emit(.state(.notConfigured))
    }

    /// A new network (other Wi-Fi, VPN, back online): start again with the home address.
    private func networkChanged(_ key: String, satisfied: Bool) {
        defer { lastPath = key }
        guard let lastPath, lastPath != key, satisfied, !routes.isEmpty else { return }
        Log.connection.info("network changed, reconnecting")
        routeIndex = 0
        delay = baseDelay
        open()
    }

    func refreshSettings() {
        guard task != nil, let entry = entities.entryId else { return }
        loadSettings(entry: entry)
    }

    // MARK: Connection

    private func open() {
        generation += 1
        close()
        guard let server else { return }
        emit(.state(.connecting))
        authenticated = false
        let task = session.webSocketTask(with: server.webSocketURL)
        task.maximumMessageSize = 16 * 1024 * 1024
        self.task = task
        task.resume()
        receive(task, generation: generation)
        // A home address that does not answer quickly means we are away: move on to the next one.
        let gen = generation
        let limit: Double = server.isLocal ? 4 : 12
        connectTimeout = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(limit * 1e9))
            guard let self, gen == self.generation, !self.authenticated else { return }
            Log.connection.info("no answer in time")
            self.failed()
        }
    }

    /// The current address did not work: try the next one now, or start over after a pause.
    private func failed() {
        if !authenticated, routeIndex + 1 < routes.count {
            routeIndex += 1
            open()
        } else {
            routeIndex = 0
            scheduleReconnect(state: .unreachable)
        }
    }

    private func close() {
        heartbeat?.cancel()
        heartbeat = nil
        connectTimeout?.cancel()
        connectTimeout = nil
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
        pending = [:]
        subscriptionId = nil
        awaitingPong = false
    }

    private func receive(_ task: URLSessionWebSocketTask, generation: Int) {
        task.receive { [weak self] result in
            Task { @MainActor in
                guard let self, generation == self.generation else { return }
                switch result {
                case .success(let message):
                    self.handle(message)
                    if let current = self.task, current === task { self.receive(task, generation: generation) }
                case .failure:
                    Log.connection.info("websocket closed")
                    self.failed()
                }
            }
        }
    }

    private func scheduleReconnect(state: ConnectionState) {
        close()
        emit(.state(state))
        guard server != nil, state != .authFailed else { return }
        let wait = delay
        delay = min(delay * 2, maxDelay)
        let gen = generation
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(wait * 1e9))
            guard let self, gen == self.generation else { return }
            self.open()
        }
    }

    // MARK: Messages

    private func handle(_ message: URLSessionWebSocketTask.Message) {
        let data: Data?
        switch message {
        case .string(let s): data = Data(s.utf8)
        case .data(let d): data = d
        @unknown default: data = nil
        }
        guard let data, let json = try? JSONSerialization.jsonObject(with: data) else { return }
        // Home Assistant may coalesce several messages into one array.
        let messages = (json as? [[String: Any]]) ?? [(json as? [String: Any]) ?? [:]]
        messages.forEach(handle)
    }

    private func handle(_ msg: [String: Any]) {
        switch msg["type"] as? String {
        case "auth_required":
            authenticate()
        case "auth_ok":
            delay = baseDelay
            retryingAuth = false
            authenticated = true
            connectTimeout?.cancel()
            if let server { emit(.route(server)) }
            startHeartbeat()
            discover()
            loadEndpoints()
        case "auth_invalid":
            Log.connection.info("auth invalid")
            if auth?.canRefresh == true && !retryingAuth {
                // An OAuth access token may have expired in between: renew it and try once more.
                retryingAuth = true
                open()
            } else {
                generation += 1
                close()
                emit(.state(.authFailed))
            }
        case "result":
            guard let id = msg["id"] as? Int, let callback = pending.removeValue(forKey: id) else { return }
            callback((msg["success"] as? Bool) ?? false, msg["result"])
        case "pong":
            awaitingPong = false
        case "event":
            guard let id = msg["id"] as? Int, id == subscriptionId,
                  let event = msg["event"] as? [String: Any] else { return }
            applyEntityEvent(event)
        default:
            break
        }
    }

    private func authenticate() {
        guard let auth else { return }
        let gen = generation
        let force = retryingAuth
        Task { [weak self] in
            do {
                guard let server = self?.server else { return }
                let token = try await auth.accessToken(forceRefresh: force, server: server)
                guard let self, gen == self.generation else { return }
                self.send(["type": "auth", "access_token": token], expectsReply: false)
            } catch AuthError.rejected {
                guard let self, gen == self.generation else { return }
                self.generation += 1
                self.close()
                self.emit(.state(.authFailed))
            } catch {
                guard let self, gen == self.generation else { return }
                self.failed()
            }
        }
    }

    @discardableResult
    private func send(_ payload: [String: Any], expectsReply: Bool = true,
                      reply: ((Bool, Any?) -> Void)? = nil) -> Int {
        var payload = payload
        var id = 0
        if expectsReply {
            id = nextId
            nextId += 1
            payload["id"] = id
            if let reply { pending[id] = reply }
        }
        guard let task, let data = try? JSONSerialization.data(withJSONObject: payload),
              let text = String(data: data, encoding: .utf8) else { return id }
        task.send(.string(text)) { _ in }
        return id
    }

    private func startHeartbeat() {
        heartbeat?.cancel()
        heartbeat = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 30_000_000_000)
                guard let self, !Task.isCancelled else { return }
                if self.awaitingPong {
                    Log.connection.info("no pong, reconnecting")
                    self.routeIndex = 0
                    self.scheduleReconnect(state: .unreachable)
                    return
                }
                self.awaitingPong = true
                self.send(["type": "ping"])
            }
        }
    }

    /// Asks Home Assistant for its internal, external and Nabu Casa addresses.
    /// `cloud/status` needs an administrator; without it only the configured URLs are used.
    private func loadEndpoints() {
        send(["type": "get_config"]) { [weak self] ok, config in
            self?.send(["type": "cloud/status"]) { [weak self] cloudOk, cloud in
                let configDict = ok ? config as? [String: Any] : nil
                let endpoints = HAEndpoints(config: configDict, cloud: cloudOk ? cloud as? [String: Any] : nil)
                self?.emit(.endpoints(endpoints))
                if let lat = (configDict?["latitude"] as? NSNumber)?.doubleValue,
                   let lon = (configDict?["longitude"] as? NSNumber)?.doubleValue {
                    self?.emit(.haHome(Coordinate(latitude: lat, longitude: lon)))
                }
            }
        }
    }

    // MARK: Nida

    /// Finds Nida's entities through the entity registry (stable unique ids, survives renames).
    private func discover() {
        send(["type": "config/entity_registry/list"]) { [weak self] ok, result in
            guard let self else { return }
            var found = NidaEntities()
            if ok, let list = result as? [[String: Any]] {
                found = NidaEntities(registry: list, domain: self.domain)
            }
            if found.isComplete {
                self.entitiesFound(found)
            } else {
                // Registry not available for this user: fall back to Nida's default entity ids.
                self.findEntryAndUseDefaults()
            }
        }
    }

    private func findEntryAndUseDefaults() {
        send(["type": "config_entries/get", "domain": domain]) { [weak self] ok, result in
            guard let self else { return }
            let entry = ok ? ((result as? [[String: Any]])?.first?["entry_id"] as? String) : nil
            self.entitiesFound(NidaEntities.defaults(domain: self.domain, entryId: entry))
        }
    }

    private func entitiesFound(_ found: NidaEntities) {
        entities = found
        states = [:]
        if let entry = found.entryId { loadSettings(entry: entry) }
        subscriptionId = send(["type": "subscribe_entities", "entity_ids": found.all]) { [weak self] ok, _ in
            guard let self else { return }
            if ok {
                self.emit(.state(.connected))
            } else {
                self.emit(.state(.nidaNotFound))
            }
        }
    }

    private func loadSettings(entry: String) {
        send(["type": "\(domain)/get_settings", "entry_id": entry]) { [weak self] ok, result in
            guard ok, let options = result as? [String: Any] else { return }
            self?.emit(.preAdhan(PreAdhanSettings(nidaOptions: options)))
            self?.emit(.audio(NidaAudioSettings(nidaOptions: options)))
            let calc = NidaCalculation(nidaOptions: options, haHome: nil)
            self?.emit(.calculation(method: calc.method, nidaHome: calc.home))
        }
    }

    /// subscribe_entities sends compressed states: "a" (added, full), "c" (changed, diff), "r" (removed).
    private func applyEntityEvent(_ event: [String: Any]) {
        if let added = event["a"] as? [String: [String: Any]] {
            for (id, s) in added { states[id] = s["s"] as? String }
        }
        if let changed = event["c"] as? [String: [String: Any]] {
            for (id, diff) in changed {
                if let plus = diff["+"] as? [String: Any], let s = plus["s"] as? String { states[id] = s }
            }
        }
        if let removed = event["r"] as? [String] {
            removed.forEach { states[$0] = nil }
        }
        let day = entities.day(from: states)
        if day.times.isEmpty, !states.isEmpty || event["a"] != nil {
            emit(.state(.nidaNotFound))
            return
        }
        emit(.state(.connected))
        emit(.day(day))
    }

    private func emit(_ event: NidaEvent) {
        onEvent?(event)
    }
}

/// Entity ids of Nida's sensors in this Home Assistant, and its config entry.
struct NidaEntities: Equatable {
    var prayers: [Prayer: String] = [:]
    var hijriDate: String?
    var hijriHoliday: String?
    var entryId: String?

    var isComplete: Bool { prayers.count == Prayer.allCases.count }
    var all: [String] { Array(prayers.values) + [hijriDate, hijriHoliday].compactMap { $0 } }

    init() {}

    /// From `config/entity_registry/list`: Nida's unique ids are "<entry_id>_<suffix>".
    init(registry: [[String: Any]], domain: String) {
        for e in registry where (e["platform"] as? String) == domain {
            guard let entityId = e["entity_id"] as? String, entityId.hasPrefix("sensor."),
                  let unique = e["unique_id"] as? String,
                  let entry = e["config_entry_id"] as? String,
                  unique.hasPrefix(entry + "_") else { continue }
            if entryId == nil { entryId = entry }
            guard entry == entryId else { continue }   // first Nida instance only
            let suffix = String(unique.dropFirst(entry.count + 1))
            if let p = Prayer(rawValue: suffix) { prayers[p] = entityId }
            if suffix == "hijri_date" { hijriDate = entityId }
            if suffix == "hijri_holiday" { hijriHoliday = entityId }
        }
    }

    static func defaults(domain: String, entryId: String?) -> NidaEntities {
        var e = NidaEntities()
        Prayer.allCases.forEach { e.prayers[$0] = "sensor.\(domain)_\($0.rawValue)" }
        e.hijriDate = "sensor.\(domain)_hijri_date"
        e.hijriHoliday = "sensor.\(domain)_hijri_holiday"
        e.entryId = entryId
        return e
    }

    func day(from states: [String: String]) -> PrayerDay {
        var day = PrayerDay()
        for (prayer, id) in prayers {
            if let s = states[id], let date = Self.parseTimestamp(s) { day.times[prayer] = date }
        }
        if let id = hijriDate, let s = states[id] {
            // Aladhan format "DD-MM-YYYY".
            let parts = s.split(separator: "-").compactMap { Int($0) }
            if parts.count == 3 {
                let holiday = hijriHoliday.flatMap { states[$0] }
                    .flatMap { ["None", "unknown", "unavailable", ""].contains($0) ? nil : $0 }
                day.hijri = HijriDate(day: parts[0], month: parts[1], year: parts[2], holiday: holiday)
            }
        }
        return day
    }

    private static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()
    private static let isoFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    static func parseTimestamp(_ s: String) -> Date? {
        iso.date(from: s) ?? isoFractional.date(from: s)
    }
}
