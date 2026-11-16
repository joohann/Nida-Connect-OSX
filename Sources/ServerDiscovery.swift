import Foundation
import Network
import dnssd

/// A Home Assistant found on the local network. Value object.
struct DiscoveredServer: Equatable, Identifiable {
    let id: String
    let name: String
    /// The address to use: with the host name (ha.local) when the network knows one, else as announced.
    var address: String
    let version: String?
    /// The IP address Home Assistant announced, when `address` uses the host name instead.
    var ipAddress: String?

    /// The same address with its IP replaced by `hostname`, keeping scheme and port.
    func withHostname(_ hostname: String) -> DiscoveredServer {
        guard var c = URLComponents(string: address), c.host != hostname else { return self }
        let ip = c.host
        c.host = hostname
        var copy = self
        copy.address = c.url?.absoluteString ?? address
        copy.ipAddress = ip
        return copy
    }
}

/// Finds Home Assistant on the local network, like the Home Assistant iOS app does.
@MainActor
protocol ServerDiscovering: AnyObject {
    var servers: [DiscoveredServer] { get }
    /// True when macOS blocks local network access for this app (Privacy, Local Network).
    var isDenied: Bool { get }
    var onChange: (() -> Void)? { get set }
    func start()
    func stop()
}

/// Home Assistant announces itself over Bonjour as `_home-assistant._tcp`, with its address,
/// name and version in the TXT record. Only addresses Home Assistant publishes itself are used.
@MainActor
final class BonjourServerDiscovery: ServerDiscovering {
    static let serviceType = "_home-assistant._tcp"

    private(set) var servers: [DiscoveredServer] = []
    private(set) var isDenied = false
    var onChange: (() -> Void)?
    private var browser: NWBrowser?

    func start() {
        guard browser == nil else { return }
        let parameters = NWParameters()
        parameters.includePeerToPeer = false
        let browser = NWBrowser(for: .bonjourWithTXTRecord(type: Self.serviceType, domain: nil), using: parameters)
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            let found = results.compactMap(Self.server(from:))
            Task { @MainActor in self?.update(found) }
            // Look up the host name for announced IP addresses (ha.local, homeassistant.local, …).
            Task.detached { [weak self] in
                let named = found.map { server in
                    Self.hostname(for: server.address).map(server.withHostname) ?? server
                }
                await MainActor.run { self?.update(named) }
            }
        }
        browser.stateUpdateHandler = { [weak self] state in
            let denied: Bool
            switch state {
            case .waiting(let error), .failed(let error):
                Log.connection.info("discovery: \(String(describing: error), privacy: .public)")
                denied = Self.isPolicyDenied(error)
            case .ready:
                denied = false
            default:
                return
            }
            Task { @MainActor in self?.setDenied(denied) }
        }
        self.browser = browser
        browser.start(queue: .main)
    }

    func stop() {
        browser?.cancel()
        browser = nil
    }

    /// Reverse lookup of an IP address through the system resolver, which also asks the local
    /// network (mDNS). Returns a ".local" name only, and only when it resolves back to the same IP.
    nonisolated static func hostname(for address: String) -> String? {
        guard let host = URLComponents(string: address)?.host, !host.isEmpty,
              host.split(separator: ".").count == 4, host.split(separator: ".").allSatisfy({ Int($0) != nil }) else {
            return nil
        }
        var sin = sockaddr_in()
        sin.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        sin.sin_family = sa_family_t(AF_INET)
        guard inet_pton(AF_INET, host, &sin.sin_addr) == 1 else { return nil }
        var buffer = [CChar](repeating: 0, count: Int(NI_MAXHOST))
        let length = socklen_t(MemoryLayout<sockaddr_in>.size)
        let size = socklen_t(buffer.count)
        let ok = withUnsafePointer(to: &sin) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                getnameinfo($0, length, &buffer, size, nil, 0, NI_NAMEREQD)
            }
        }
        guard ok == 0 else { return nil }
        let name = String(cString: buffer).lowercased()
        guard name.hasSuffix(".local"), resolves(name, to: host) else { return nil }
        return name
    }

    /// Forward check, so a stale reverse record never sends the app to another machine.
    nonisolated private static func resolves(_ name: String, to ip: String) -> Bool {
        var hints = addrinfo()
        hints.ai_family = AF_INET
        var result: UnsafeMutablePointer<addrinfo>?
        guard getaddrinfo(name, nil, &hints, &result) == 0, let first = result else { return false }
        defer { freeaddrinfo(first) }
        var node: UnsafeMutablePointer<addrinfo>? = first
        while let n = node {
            if let sa = n.pointee.ai_addr, sa.pointee.sa_family == sa_family_t(AF_INET) {
                var text = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
                var addr = sa.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0.pointee.sin_addr }
                if inet_ntop(AF_INET, &addr, &text, socklen_t(text.count)) != nil, String(cString: text) == ip {
                    return true
                }
            }
            node = n.pointee.ai_next
        }
        return false
    }

    /// macOS answers a blocked Bonjour browse with the DNS-SD error "policy denied".
    nonisolated static func isPolicyDenied(_ error: NWError) -> Bool {
        if case .dns(let code) = error { return code == DNSServiceErrorType(kDNSServiceErr_PolicyDenied) }
        return false
    }

    private func setDenied(_ denied: Bool) {
        guard denied != isDenied else { return }
        isDenied = denied
        onChange?()
    }

    private func update(_ found: [DiscoveredServer]) {
        // One entry per instance, sorted by name.
        var seen = Set<String>()
        let unique = found.filter { seen.insert($0.id).inserted }.sorted { $0.name < $1.name }
        guard unique != servers else { return }
        servers = unique
        onChange?()
    }

    nonisolated private static func server(from result: NWBrowser.Result) -> DiscoveredServer? {
        guard case .bonjour(let txt) = result.metadata else { return nil }
        let candidates = [txt["internal_url"], txt["base_url"], txt["external_url"]]
            .compactMap { $0?.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard let address = candidates.first, ServerAddress(address) != nil else { return nil }
        var serviceName = ""
        if case .service(let name, _, _, _) = result.endpoint { serviceName = name }
        let name = txt["location_name"].flatMap { $0.isEmpty ? nil : $0 } ?? serviceName
        return DiscoveredServer(id: txt["uuid"] ?? address, name: name.isEmpty ? address : name,
                                address: address, version: txt["version"], ipAddress: nil)
    }
}
