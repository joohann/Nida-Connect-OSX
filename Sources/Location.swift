import CoreLocation
import Foundation

/// A place on earth. Value object.
struct Coordinate: Equatable, Codable {
    let latitude: Double
    let longitude: Double

    /// Rounded to two decimals (about 1 km): precise enough for prayer times, no more than needed.
    var rounded: Coordinate {
        Coordinate(latitude: (latitude * 100).rounded() / 100, longitude: (longitude * 100).rounded() / 100)
    }

    /// Great-circle distance in kilometres (haversine).
    func distanceKm(to other: Coordinate) -> Double {
        let r = 6371.0
        let dLat = (other.latitude - latitude) * .pi / 180
        let dLon = (other.longitude - longitude) * .pi / 180
        let a = sin(dLat / 2) * sin(dLat / 2)
            + cos(latitude * .pi / 180) * cos(other.latitude * .pi / 180) * sin(dLon / 2) * sin(dLon / 2)
        return 2 * r * asin(min(1, sqrt(a)))
    }
}

/// How Nida calculates: the Aladhan method and the place the times are for. Value object.
struct NidaCalculation: Equatable, Codable {
    var method: Int
    /// Nida's own location (city picked in Nida), or Home Assistant's home when Nida has none.
    var home: Coordinate?

    static let nidaDefault = NidaCalculation(method: 3, home: nil)

    init(method: Int, home: Coordinate?) {
        self.method = method
        self.home = home
    }

    /// From Nida's options (`method`, `latitude`, `longitude`), falling back to Home Assistant's home.
    init(nidaOptions o: [String: Any], haHome: Coordinate?) {
        method = (o["method"] as? NSNumber)?.intValue ?? Int(o["method"] as? String ?? "") ?? 3
        if let lat = (o["latitude"] as? NSNumber)?.doubleValue, let lon = (o["longitude"] as? NSNumber)?.doubleValue {
            home = Coordinate(latitude: lat, longitude: lon)
        } else {
            home = haHome
        }
    }
}

/// Where the Mac is. The model only talks to this protocol.
@MainActor
protocol LocationProviding: AnyObject {
    var status: LocationStatus { get }
    var current: Coordinate? { get }
    /// Name of the place, such as "Utrecht", when known.
    var placeName: String? { get }
    var onChange: (() -> Void)? { get set }
    func requestPermission()
    func start()
    /// Places matching a name, such as "Utrecht", for picking a place by hand.
    func search(_ query: String) async -> [NamedPlace]
}

enum LocationStatus: Equatable {
    case notDetermined
    case denied
    case authorized
}

/// CoreLocation at kilometre accuracy, updating on significant moves only, so it costs little power.
@MainActor
final class CoreLocationProvider: NSObject, LocationProviding, CLLocationManagerDelegate {
    private(set) var status: LocationStatus = .notDetermined
    private(set) var current: Coordinate?
    private(set) var placeName: String?
    var onChange: (() -> Void)?
    private let manager = CLLocationManager()
    private let geocoder = CLGeocoder()
    private var namedFor: Coordinate?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
        manager.distanceFilter = 1000
        status = Self.map(manager.authorizationStatus)
    }

    func requestPermission() {
        if manager.authorizationStatus == .notDetermined {
            manager.requestWhenInUseAuthorization()
        } else {
            start()
        }
    }

    func start() {
        guard status == .authorized else { return }
        manager.startMonitoringSignificantLocationChanges()
        manager.requestLocation()
    }

    func search(_ query: String) async -> [NamedPlace] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard q.count >= 2 else { return [] }
        let marks = (try? await CLGeocoder().geocodeAddressString(q)) ?? []
        return marks.compactMap { m in
            guard let c = m.location?.coordinate else { return nil }
            let parts = [m.locality ?? m.name, m.country].compactMap { $0 }
            return NamedPlace(name: parts.joined(separator: ", "),
                              coordinate: Coordinate(latitude: c.latitude, longitude: c.longitude))
        }
    }

    nonisolated private static func map(_ s: CLAuthorizationStatus) -> LocationStatus {
        switch s {
        case .notDetermined: return .notDetermined
        case .authorized, .authorizedAlways: return .authorized
        default: return .denied
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let mapped = Self.map(manager.authorizationStatus)
        Task { @MainActor in
            self.status = mapped
            self.start()
            self.onChange?()
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let last = locations.last else { return }
        let c = Coordinate(latitude: last.coordinate.latitude, longitude: last.coordinate.longitude)
        Task { @MainActor in self.update(c, location: last) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Log.connection.info("location unavailable")
    }

    private func update(_ c: Coordinate, location: CLLocation) {
        current = c
        onChange?()
        // Name the place again only after a real move.
        if let namedFor, namedFor.distanceKm(to: c) < 5 { return }
        namedFor = c
        geocoder.reverseGeocodeLocation(location) { [weak self] marks, _ in
            let name = marks?.first.flatMap { $0.locality ?? $0.administrativeArea }
            Task { @MainActor in
                self?.placeName = name
                self?.onChange?()
            }
        }
    }
}

/// Prayer times for any place from Aladhan, calculated the same way Nida does it
/// (`/timings/<date>?latitude=…&longitude=…&method=…`).
struct AladhanClient {
    let baseURL: URL
    let session: URLSession

    init(baseURL: URL, session: URLSession = URLSession(configuration: .ephemeral)) {
        self.baseURL = baseURL
        self.session = session
    }

    func day(for date: Date, at place: Coordinate, method: Int) async throws -> PrayerDay {
        let p = place.rounded
        let f = DateFormatter()
        f.dateFormat = "dd-MM-yyyy"
        f.locale = Locale(identifier: "en_US_POSIX")
        var c = URLComponents(url: baseURL.appendingPathComponent("timings/\(f.string(from: date))"),
                              resolvingAgainstBaseURL: false)!
        c.queryItems = [
            URLQueryItem(name: "latitude", value: String(p.latitude)),
            URLQueryItem(name: "longitude", value: String(p.longitude)),
            URLQueryItem(name: "method", value: String(method)),
        ]
        var request = URLRequest(url: c.url!)
        request.timeoutInterval = 15
        let (data, response) = try await session.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw AuthError.unreachable }
        return try Self.parse(data, date: date)
    }

    /// Times come as "HH:mm" (sometimes with " (CET)") in the place's own time zone.
    static func parse(_ data: Data, date: Date) throws -> PrayerDay {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let d = json["data"] as? [String: Any], let timings = d["timings"] as? [String: String] else {
            throw AuthError.unreachable
        }
        let zone = ((d["meta"] as? [String: Any])?["timezone"] as? String).flatMap(TimeZone.init(identifier:)) ?? .current
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        var day = PrayerDay()
        for prayer in Prayer.allCases {
            guard let raw = timings[prayer.rawValue.capitalized] else { continue }
            let hm = raw.split(separator: " ").first?.split(separator: ":").compactMap { Int($0) } ?? []
            guard hm.count == 2 else { continue }
            var c = parts
            c.hour = hm[0]
            c.minute = hm[1]
            day.times[prayer] = calendar.date(from: c)
        }
        if let h = (d["date"] as? [String: Any])?["hijri"] as? [String: Any],
           let dd = Int(h["day"] as? String ?? ""), let yy = Int(h["year"] as? String ?? ""),
           let mm = (h["month"] as? [String: Any])?["number"] as? Int {
            let holiday = (h["holidays"] as? [String])?.first
            day.hijri = HijriDate(day: dd, month: mm, year: yy, holiday: holiday)
        }
        guard day.isComplete else { throw AuthError.unreachable }
        return day
    }
}
