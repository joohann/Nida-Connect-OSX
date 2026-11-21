import AppKit
import CoreAudio

/// Pauses whatever media is playing while the Mac plays the pre-adhan or the adhan, and resumes it after.
/// The model only talks to this protocol.
@MainActor
protocol MediaPausing: AnyObject {
    /// Pauses the media that is playing. True when it sent a pause.
    func pauseIfPlaying() -> Bool
    /// Resumes only what `pauseIfPlaying` is sure it paused, so nothing starts that was not playing.
    func resume()
}

/// Knows what plays in two ways, because macOS no longer lets apps read the now-playing state:
/// - Music and Spotify announce every play and pause, so their state is exact.
/// - Other apps (browsers, video players) are seen through CoreAudio's process list. An app can hold
///   its audio output while paused, so a pause only counts once that app has really gone quiet.
/// Commands go through the system's media controls, like the play/pause key.
@MainActor
final class SystemMediaControl: MediaPausing {
    /// System helpers that hold an audio output without playing media, such as Siri listening.
    private static let ignoredPaths = ["/System/Library/PrivateFrameworks/", "/System/Library/CoreServices/", "/usr/"]
    /// Players that announce their state, with the notification they post.
    private static let announcing = ["com.apple.Music": "com.apple.Music.playerInfo",
                                     "com.spotify.client": "com.spotify.client.PlaybackStateChanged"]
    /// How long another app gets to go quiet after the pause.
    private static let settleTime: TimeInterval = 1.5

    private enum Command: UInt32 {
        case play = 0
        case pause = 1
    }

    /// Announcing players that said they are playing, by bundle ID.
    private var playingApps: Set<String> = []
    /// True once a pause is known to have stopped something.
    private var confirmed = false
    /// Counts pauses, so a late check of an earlier pause does nothing.
    private var generation = 0

    init() {
        let center = DistributedNotificationCenter.default()
        for (bundle, name) in Self.announcing {
            center.addObserver(forName: Notification.Name(name), object: nil, queue: .main) { [weak self] note in
                let playing = note.userInfo?["Player State"] as? String == "Playing"
                MainActor.assumeIsolated { self?.update(bundle, playing: playing) }
            }
        }
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didTerminateApplicationNotification,
                                                          object: nil, queue: .main) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            guard let bundle = app?.bundleIdentifier else { return }
            MainActor.assumeIsolated { self?.update(bundle, playing: false) }
        }
    }

    private func update(_ bundle: String, playing: Bool) {
        if playing { playingApps.insert(bundle) } else { playingApps.remove(bundle) }
    }

    func pauseIfPlaying() -> Bool {
        generation += 1
        confirmed = false
        let announced = !playingApps.isEmpty
        let others = otherAudioProcesses()
        guard announced || !others.isEmpty else { return false }
        guard send(.pause) else { return false }
        if announced {
            confirmed = true
            Log.sound.notice("paused \(self.playingApps.sorted().joined(separator: ", "), privacy: .public)")
        } else {
            let pauseGeneration = generation
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.settleTime) { [weak self] in
                MainActor.assumeIsolated { self?.check(others, pauseGeneration) }
            }
        }
        return true
    }

    /// After the pause: did one of the apps that held an output go quiet? Then that was us.
    private func check(_ before: [pid_t: String], _ pauseGeneration: Int) {
        guard pauseGeneration == generation else { return }
        let still = otherAudioProcesses()
        let stopped = before.filter { still[$0.key] == nil }
        confirmed = !stopped.isEmpty
        Log.sound.notice("""
            \(self.confirmed ? "paused" : "nothing went quiet, will not resume", privacy: .public): \
            \(before.values.sorted().joined(separator: ", "), privacy: .public)
            """)
    }

    func resume() {
        generation += 1
        guard confirmed else { return }
        confirmed = false
        _ = send(.play)
    }

    /// Processes other than this app, system helpers and announcing players that send audio to an output,
    /// by PID with their name. Announcing players are left out: their output stays open while paused.
    private func otherAudioProcesses() -> [pid_t: String] {
        let own = ProcessInfo.processInfo.processIdentifier
        var result: [pid_t: String] = [:]
        for process in audioProcesses() {
            guard Self.value(process, kAudioProcessPropertyIsRunningOutput, UInt32(0)) != 0 else { continue }
            let pid = Self.value(process, kAudioProcessPropertyPID, pid_t(0))
            guard pid > 0, pid != own else { continue }
            let path = Self.executablePath(pid) ?? ""
            guard !Self.ignoredPaths.contains(where: { path.hasPrefix($0) }) else { continue }
            if let bundle = NSRunningApplication(processIdentifier: pid)?.bundleIdentifier,
               Self.announcing[bundle] != nil { continue }
            result[pid] = (path as NSString).lastPathComponent
        }
        return result
    }

    private func audioProcesses() -> [AudioObjectID] {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyProcessObjectList,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        let system = AudioObjectID(kAudioObjectSystemObject)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr, size > 0 else { return [] }
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(system, &address, 0, nil, &size, &ids) == noErr else { return [] }
        return ids
    }

    private static func value<T>(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector, _ fallback: T) -> T {
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var result = fallback
        var size = UInt32(MemoryLayout<T>.size)
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &result) == noErr else { return fallback }
        return result
    }

    private static func executablePath(_ pid: pid_t) -> String? {
        var buffer = [CChar](repeating: 0, count: 4096)
        guard proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0 else { return nil }
        return String(cString: buffer)
    }

    /// The system's media remote; private, so it is looked up at run time and fails quietly.
    private func send(_ command: Command) -> Bool {
        typealias SendCommand = @convention(c) (UInt32, CFDictionary?) -> Bool
        guard let framework = dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_LAZY),
              let symbol = dlsym(framework, "MRMediaRemoteSendCommand") else {
            Log.connection.info("media remote not available")
            return false
        }
        return unsafeBitCast(symbol, to: SendCommand.self)(command.rawValue, nil)
    }
}
