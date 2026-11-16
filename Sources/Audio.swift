import AVFoundation
import Foundation

/// The sounds Nida plays, from Nida's own settings (`nida/get_settings`). Value object.
struct NidaAudioSettings: Equatable, Codable {
    enum Category: String, Codable, CaseIterable {
        case fajrAdhan = "fajr_adhan"
        case adhan
        case preAdhanJingle = "pre_adhan_jingle"
    }

    /// Prayers whose adhan is switched off in Nida.
    var adhanDisabled: Set<Prayer>
    var preAdhanAudio: Bool
    /// File per category, relative to Nida's sounds folder, e.g. "adhan/adhan_day_….mp3".
    var sounds: [Category: String]
    /// 0…100, as set in Nida.
    var volumes: [Category: Int]
    var guestModeEnabled: Bool
    var guestModeUntil: Date?

    static let nidaDefault = NidaAudioSettings(nidaOptions: [:])

    init(nidaOptions o: [String: Any]) {
        adhanDisabled = Set(Prayer.allCases.filter { (o["enabled_\($0.rawValue)"] as? Bool) == false })
        preAdhanAudio = (o["pre_adhan_audio_enabled"] as? Bool) ?? true
        let defaultSounds: [Category: String] = [
            .fajrAdhan: "adhan/adhan_fajr_ahmed_saeed_al-omrany.mp3",
            .adhan: "adhan/adhan_day_ahmed_saeed_al-omrany.mp3",
            .preAdhanJingle: "pre_adhan_jingle/announcement.mp3",
        ]
        let defaultVolumes: [Category: Int] = [.fajrAdhan: 10, .adhan: 20, .preAdhanJingle: 20]
        var sounds: [Category: String] = [:]
        var volumes: [Category: Int] = [:]
        for c in Category.allCases {
            let file = (o["sound_\(c.rawValue)"] as? String).flatMap { $0.isEmpty ? nil : $0 }
            sounds[c] = file.flatMap { SoundLibrary.isSafe($0) ? $0 : nil } ?? defaultSounds[c]
            let raw = (o["volume_\(c.rawValue)"] as? NSNumber)?.intValue ?? Int(o["volume_\(c.rawValue)"] as? String ?? "")
            volumes[c] = min(100, max(0, raw ?? defaultVolumes[c] ?? 20))
        }
        self.sounds = sounds
        self.volumes = volumes
        guestModeEnabled = (o["guest_mode_enabled"] as? Bool) ?? false
        guestModeUntil = (o["guest_mode_until"] as? String).flatMap(NidaEntities.parseTimestamp)
    }

    /// Nida's guest mode mutes scheduled audio until a set moment (or until switched off).
    func guestModeActive(at now: Date) -> Bool {
        guard guestModeEnabled else { return false }
        guard let until = guestModeUntil else { return true }
        return now < until
    }

    static func category(for prayer: Prayer) -> Category { prayer == .fajr ? .fajrAdhan : .adhan }
}

/// When the Mac itself plays the sounds.
enum PlaybackMode: String, CaseIterable {
    /// Only while connected through Nabu Casa or the external address: at home Home Assistant plays.
    case away
    case always
    case off
}

/// Something to play now.
struct PlannedSound: Equatable {
    enum Kind: Equatable { case preAdhan, adhan }
    let prayer: Prayer
    let kind: Kind
    let file: String
    let volume: Int
}

/// Decides which sound is due between two ticks. Pure logic.
struct SoundPlanner {
    /// Longer gaps (sleep, a frozen app) skip sounds instead of playing them late.
    static let maxLateness: TimeInterval = 30

    func due(from last: Date, to now: Date, day: PrayerDay, preAdhan: PreAdhanSettings,
             audio: NidaAudioSettings, calendar: Calendar = .current) -> PlannedSound? {
        guard now > last, now.timeIntervalSince(last) <= Self.maxLateness, !audio.guestModeActive(at: now) else {
            return nil
        }
        var times = Prayer.allCases.compactMap { p in day.times[p].map { (p, $0) } }
        if let fajr = day.times[.fajr], let tomorrow = calendar.date(byAdding: .day, value: 1, to: fajr) {
            times.append((.fajr, tomorrow))
        }
        func inWindow(_ d: Date) -> Bool { d > last && d <= now }
        for (prayer, date) in times {
            if !audio.adhanDisabled.contains(prayer), inWindow(date) {
                let c = NidaAudioSettings.category(for: prayer)
                return PlannedSound(prayer: prayer, kind: .adhan, file: audio.sounds[c] ?? "", volume: audio.volumes[c] ?? 20)
            }
            guard audio.preAdhanAudio else { continue }
            for minutes in [preAdhan.first(for: prayer), preAdhan.second(for: prayer)].compactMap({ $0 }) {
                if inWindow(date.addingTimeInterval(-Double(minutes) * 60)) {
                    return PlannedSound(prayer: prayer, kind: .preAdhan,
                                        file: audio.sounds[.preAdhanJingle] ?? "",
                                        volume: audio.volumes[.preAdhanJingle] ?? 20)
                }
            }
        }
        return nil
    }
}

/// Keeps local copies of Nida's sound files, so they also play without a connection.
/// Files come from Home Assistant's /local/nida/sounds/, the folder Nida serves them from.
protocol SoundCaching {
    func localURL(for file: String) -> URL?
    func fetch(_ files: [String], from server: ServerAddress) async
}

struct SoundLibrary: SoundCaching {
    let folder: URL
    let session: URLSession

    init(bundleId: String, session: URLSession = URLSession(configuration: .ephemeral)) {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        folder = base.appendingPathComponent(bundleId, isDirectory: true).appendingPathComponent("sounds", isDirectory: true)
        self.session = session
    }

    /// Only plain relative paths from Nida: no "..", no absolute paths, no odd characters.
    static func isSafe(_ file: String) -> Bool {
        guard !file.isEmpty, !file.hasPrefix("/"), file.count < 256 else { return false }
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-./")
        guard file.unicodeScalars.allSatisfy(allowed.contains) else { return false }
        return !file.split(separator: "/").contains { $0 == ".." || $0 == "." || $0.isEmpty }
    }

    func localURL(for file: String) -> URL? {
        guard Self.isSafe(file) else { return nil }
        let url = folder.appendingPathComponent(file)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    func fetch(_ files: [String], from server: ServerAddress) async {
        for file in Set(files) where Self.isSafe(file) && localURL(for: file) == nil {
            let remote = server.baseURL.appendingPathComponent("local/nida/sounds").appendingPathComponent(file)
            do {
                let (data, response) = try await session.data(from: remote)
                guard (response as? HTTPURLResponse)?.statusCode == 200, data.count > 1000, data.count < 50_000_000 else {
                    continue
                }
                let target = folder.appendingPathComponent(file)
                try FileManager.default.createDirectory(at: target.deletingLastPathComponent(),
                                                        withIntermediateDirectories: true)
                try data.write(to: target, options: .atomic)
            } catch {
                Log.connection.info("sound download failed")
            }
        }
    }
}

/// Plays one sound at a time. The UI only talks to this protocol.
@MainActor
protocol SoundPlaying: AnyObject {
    var onFinish: (() -> Void)? { get set }
    func play(_ url: URL, volume: Int) -> Bool
    func stop()
}

@MainActor
final class AVSoundPlayer: NSObject, SoundPlaying, AVAudioPlayerDelegate {
    var onFinish: (() -> Void)?
    private var player: AVAudioPlayer?

    func play(_ url: URL, volume: Int) -> Bool {
        stop()
        guard let player = try? AVAudioPlayer(contentsOf: url) else { return false }
        player.volume = Float(min(100, max(0, volume))) / 100
        player.delegate = self
        self.player = player
        return player.play()
    }

    func stop() {
        player?.stop()
        player = nil
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            self.player = nil
            self.onFinish?()
        }
    }
}
