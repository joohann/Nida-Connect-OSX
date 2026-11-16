import CryptoKit
import Foundation

/// Where the prayer times come from: Nida in Home Assistant, or the app on its own.
enum PrayerSource: String, CaseIterable {
    case homeAssistant
    case standalone
}

/// A place picked by name. Value object.
struct NamedPlace: Equatable, Codable {
    let name: String
    let coordinate: Coordinate
}

/// Everything Nida normally provides, set in the app when it runs without Home Assistant.
/// Defaults are Nida's own. Value object.
struct StandaloneSettings: Equatable, Codable {
    /// Aladhan calculation method.
    var method = 3
    /// nil follows the Mac's location.
    var manualPlace: NamedPlace?
    /// Minutes before the adhan; 0 means off.
    var firstMinutes = 25
    var secondEnabled = true
    var secondMinutes = 10
    var preAdhanDisabled: Set<Prayer> = []
    var playSounds = true
    /// Catalog id per category, from the Nida sound library.
    var sounds: [String: String] = [
        NidaAudioSettings.Category.adhan.rawValue: "adhan_day_ahmed_saeed_al_omrany",
        NidaAudioSettings.Category.fajrAdhan.rawValue: "adhan_fajr_ahmed_saeed_al_omrany",
        NidaAudioSettings.Category.preAdhanJingle.rawValue: StandaloneSettings.languageJingle,
    ]
    /// 0…100 per category.
    var volumes: [String: Int] = [
        NidaAudioSettings.Category.adhan.rawValue: 20,
        NidaAudioSettings.Category.fajrAdhan.rawValue: 10,
        NidaAudioSettings.Category.preAdhanJingle.rawValue: 20,
    ]

    static let minuteRange = 0...60
    /// Jingle choice that follows the app's language: the voiced Nida jingle (`jingle_nida_<lang>`),
    /// which says the announcement itself. Languages without one get English.
    static let languageJingle = "jingle_nida"
    static let voicedLanguages: Set<String> = ["ar", "de", "en", "fa", "fr", "id", "ms", "nl", "tr", "ur"]

    /// The choice as stored, which can be `languageJingle`.
    func soundId(_ c: NidaAudioSettings.Category) -> String? { sounds[c.rawValue] }

    /// The library sound that actually plays, for the app's language.
    func soundId(_ c: NidaAudioSettings.Category, language: String) -> String? {
        guard let id = soundId(c) else { return nil }
        guard id == Self.languageJingle else { return id }
        return "\(Self.languageJingle)_\(Self.voicedLanguages.contains(language) ? language : "en")"
    }
    func volume(_ c: NidaAudioSettings.Category) -> Int { volumes[c.rawValue] ?? 20 }

    var preAdhan: PreAdhanSettings {
        PreAdhanSettings(firstMinutes: firstMinutes, secondEnabled: secondEnabled, secondMinutes: secondMinutes,
                         disabledPrayers: preAdhanDisabled)
    }

    /// The same shape as Nida's sound settings, so planning and playing work unchanged.
    func audio(language: String) -> NidaAudioSettings {
        var files: [NidaAudioSettings.Category: String] = [:]
        var levels: [NidaAudioSettings.Category: Int] = [:]
        for c in NidaAudioSettings.Category.allCases {
            if let id = soundId(c, language: language) { files[c] = SoundLibrary.catalogFile(id) }
            levels[c] = volume(c)
        }
        return NidaAudioSettings(adhanDisabled: [], preAdhanAudio: true, sounds: files, volumes: levels)
    }
}

/// Aladhan's calculation methods, by id. Names are proper names and live in the language files.
enum CalculationMethods {
    static let ids = [3, 2, 4, 5, 1, 0, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23]
    static func key(_ id: Int) -> String { "method.\(id)" }
}

/// One sound in the Nida library on the web. Value object.
struct CatalogSound: Equatable, Identifiable {
    enum Kind: String { case day, fajr, jingle }
    let id: String
    let label: String
    let kind: Kind
    let url: URL
    let sha256: String

    /// The kind of sound each category takes.
    static func kind(for c: NidaAudioSettings.Category) -> Kind {
        switch c {
        case .adhan: return .day
        case .fajrAdhan: return .fajr
        case .preAdhanJingle: return .jingle
        }
    }
}

/// Reads the sound library's manifests. The model only talks to this protocol.
protocol SoundCatalogLoading {
    func load() async throws -> [CatalogSound]
}

/// The Nida sound library (`<base>/adhan/manifest.json`, `<base>/jingles/manifest.json`), the
/// same catalog the Nida integration uses. Only https files on the library's own host are taken.
struct NidaSoundCatalog: SoundCatalogLoading {
    let baseURL: URL
    let session: URLSession

    init(baseURL: URL, session: URLSession = URLSession(configuration: .ephemeral)) {
        self.baseURL = baseURL
        self.session = session
    }

    func load() async throws -> [CatalogSound] {
        var all: [CatalogSound] = []
        for part in ["adhan", "jingles"] {
            var request = URLRequest(url: baseURL.appendingPathComponent(part).appendingPathComponent("manifest.json"))
            request.timeoutInterval = 15
            let (data, response) = try await session.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw AuthError.unreachable }
            all += Self.parse(data, host: baseURL.host)
        }
        guard !all.isEmpty else { throw AuthError.unreachable }
        return all
    }

    static func parse(_ data: Data, host: String?) -> [CatalogSound] {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let items = json["items"] as? [[String: Any]] else { return [] }
        return items.compactMap { item in
            guard let id = item["id"] as? String, SoundLibrary.isSafeId(id),
                  let label = item["label"] as? String,
                  let kind = (item["type"] as? String).flatMap(CatalogSound.Kind.init),
                  let url = (item["url"] as? String).flatMap(URL.init(string:)),
                  url.scheme == "https", url.host == host,
                  let sha = item["sha256"] as? String, sha.count == 64 else { return nil }
            return CatalogSound(id: id, label: label, kind: kind, url: url, sha256: sha.lowercased())
        }
    }
}

extension SoundLibrary {
    /// Where a library sound is kept, relative to the sounds folder.
    static func catalogFile(_ id: String) -> String { "catalog/\(id).mp3" }

    static func isSafeId(_ id: String) -> Bool {
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789_-")
        return !id.isEmpty && id.count < 128 && id.unicodeScalars.allSatisfy(allowed.contains)
    }

    /// Downloads a library sound once and keeps it only when its SHA-256 matches the catalog.
    func fetch(_ sound: CatalogSound) async -> Bool {
        let file = Self.catalogFile(sound.id)
        if localURL(for: file) != nil { return true }
        do {
            let (data, response) = try await session.data(from: sound.url)
            guard (response as? HTTPURLResponse)?.statusCode == 200, data.count > 1000, data.count < 50_000_000 else {
                return false
            }
            let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
            guard digest == sound.sha256 else {
                Log.connection.info("sound checksum mismatch")
                return false
            }
            let target = folder.appendingPathComponent(file)
            try FileManager.default.createDirectory(at: target.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            try data.write(to: target, options: .atomic)
            return true
        } catch {
            Log.connection.info("sound download failed")
            return false
        }
    }
}
