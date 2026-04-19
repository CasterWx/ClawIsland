import Cocoa
import SwiftUI

struct SoundSettingsKey {
    static let soundEnabled = "soundEnabled"
    static let soundVolume = "soundVolume"
    static let soundSessionStart = "soundSessionStart"
    static let soundTaskComplete = "soundTaskComplete"
    static let soundTaskError = "soundTaskError"
    static let soundApprovalNeeded = "soundApprovalNeeded"
    static let soundPromptSubmit = "soundPromptSubmit"
    
    static func soundCustomPath(_ name: String) -> String {
        return "customSound_\(name)"
    }
}

@MainActor
class SoundManager {
    static let shared = SoundManager()

    private let defaults = UserDefaults.standard
    private var soundCache: [String: NSSound] = [:]

    // (event name, asset data name, settings toggle key)
    static let eventSounds: [(event: String, sound: String, key: String)] = [
        ("SessionStart",      "8bit_start",    SoundSettingsKey.soundSessionStart),
        ("SessionEnd",        "8bit_complete", SoundSettingsKey.soundTaskComplete),
        ("Stop",              "8bit_complete", SoundSettingsKey.soundTaskComplete),
        ("Error",             "8bit_error",    SoundSettingsKey.soundTaskError),
        ("PermissionRequest", "8bit_approval", SoundSettingsKey.soundApprovalNeeded),
        ("UserPromptSubmit",  "8bit_submit",   SoundSettingsKey.soundPromptSubmit)
    ]

    private init() {
        // Pre-load sounds into cache natively from NSDataAsset
        for entry in Self.eventSounds {
            if let sound = loadSound(entry.sound) {
                soundCache[entry.sound] = sound
            }
        }
    }

    /// Primary event handler identical to CodeIsland.
    func playSound(for eventName: String) {
        guard defaults.bool(forKey: SoundSettingsKey.soundEnabled) else { return }
        guard let entry = Self.eventSounds.first(where: { $0.event == eventName }) else { return }
        guard defaults.bool(forKey: entry.key) else { return }
        play(entry.sound)
    }

    func setupDefaultsIfNeeded() {
        if defaults.object(forKey: SoundSettingsKey.soundEnabled) == nil {
            defaults.set(true, forKey: SoundSettingsKey.soundEnabled)
            defaults.set(80, forKey: SoundSettingsKey.soundVolume)
            defaults.set(true, forKey: SoundSettingsKey.soundSessionStart)
            defaults.set(true, forKey: SoundSettingsKey.soundTaskComplete)
            defaults.set(true, forKey: SoundSettingsKey.soundTaskError)
            defaults.set(true, forKey: SoundSettingsKey.soundApprovalNeeded)
            defaults.set(true, forKey: SoundSettingsKey.soundPromptSubmit)
        }
    }

    func preview(_ soundName: String) {
        play(soundName)
    }

    func previewCustom(_ path: String) {
        let sound: NSSound? = NSSound(contentsOfFile: path, byReference: false)
        guard let s = sound else {
            NSSound.beep()
            return
        }
        if s.isPlaying { s.stop() }
        let volume = defaults.integer(forKey: SoundSettingsKey.soundVolume)
        s.volume = Float(volume) / 100.0
        s.play()
    }

    private func play(_ name: String) {
        let sound: NSSound? = loadCustomSound(name) ?? soundCache[name] ?? loadSound(name)
        guard let sound else {
            NSSound.beep()
            return
        }
        if sound.isPlaying { sound.stop() }
        let volume = defaults.integer(forKey: SoundSettingsKey.soundVolume)
        sound.volume = Float(volume) / 100.0
        sound.play()
    }

    private func loadCustomSound(_ name: String) -> NSSound? {
        guard let path = defaults.string(forKey: SoundSettingsKey.soundCustomPath(name)),
              !path.isEmpty,
              FileManager.default.fileExists(atPath: path) else { return nil }
        return NSSound(contentsOfFile: path, byReference: false)
    }

    private func loadSound(_ name: String) -> NSSound? {
        if let asset = NSDataAsset(name: name) {
            return NSSound(data: asset.data)
        }
        return nil
    }
}
