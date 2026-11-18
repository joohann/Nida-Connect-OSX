import AppKit
import CoreAudio

/// Pauses whatever media is playing while the Mac plays the pre-adhan or the adhan, and resumes it after.
/// The model only talks to this protocol.
protocol MediaPausing {
    /// Pauses the now-playing app when another app is sending audio out. True when it paused something.
    func pauseIfPlaying() -> Bool
    /// Resumes what `pauseIfPlaying` paused.
    func resume()
}

/// Sees who plays audio through CoreAudio's process list (public, works for every app, browsers too)
/// and pauses or resumes through the system's media controls, like the play/pause key.
/// macOS no longer lets apps read the now-playing state, so CoreAudio decides whether to pause;
/// resume is only sent after a pause of our own, so nothing starts that was not playing.
struct SystemMediaControl: MediaPausing {
    /// System helpers that hold an audio output without playing media, such as Siri listening.
    private static let ignoredPaths = ["/System/Library/PrivateFrameworks/", "/System/Library/CoreServices/", "/usr/"]

    private enum Command: UInt32 {
        case play = 0
        case pause = 1
    }

    func pauseIfPlaying() -> Bool {
        guard othersPlayAudio() else { return false }
        return send(.pause)
    }

    func resume() {
        _ = send(.play)
    }

    /// True when a process other than this app and system helpers sends audio to an output.
    func othersPlayAudio() -> Bool {
        let own = ProcessInfo.processInfo.processIdentifier
        return audioProcesses().contains { process in
            guard Self.value(process, kAudioProcessPropertyIsRunningOutput, UInt32(0)) != 0 else { return false }
            let pid = Self.value(process, kAudioProcessPropertyPID, pid_t(0))
            guard pid > 0, pid != own else { return false }
            let path = Self.executablePath(pid) ?? ""
            return !Self.ignoredPaths.contains { path.hasPrefix($0) }
        }
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
