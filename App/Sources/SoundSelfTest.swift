import AppKit
import Foundation
import MoniMacSystem
import os

private let log = Logger(subsystem: "io.github.lethanhvietctt5.MoniMac", category: "Sound")

/// Development aid for checking per-app volume by hand: `--sound-selftest <dir>`.
///
/// A verification script starts its own tone processes, then writes a phase to `<dir>/phase`:
/// - `0`: no taps.
/// - `1 <pid>`: that tone at 50%.
/// - `3 <pid> <pid> <pid>`: the tones at 50%, 25%, and muted.
/// - `end`: no taps, then MoniMac quits.
///
/// Only those pids are adjusted (as `SoundTarget.process`), never an app, and the user's settings are
/// left alone. Each second MoniMac writes what its taps hear to `<dir>/status.txt`.
@MainActor
final class SoundSelfTest {
    private let audio: AudioMixer
    private let directory: URL
    private var phase = ""
    private var timer: Timer?

    init(audio: AudioMixer, directory: URL) {
        self.audio = audio
        self.directory = directory
        log.notice("Sound self-test reading \(directory.path, privacy: .public)")
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
    }

    private func poll() {
        let text = (try? String(contentsOf: directory.appending(path: "phase"), encoding: .utf8)) ?? ""
        let phase = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if phase != self.phase {
            self.phase = phase
            apply(phase)
        }
        let status = "phase \(phase)\n\(audio.status)\n"
        try? status.write(to: directory.appending(path: "status.txt"), atomically: true, encoding: .utf8)
    }

    private func apply(_ phase: String) {
        let words = phase.split(separator: " ")
        let pids = words.dropFirst().compactMap { Int32($0) }
        log.notice("Sound self-test phase \(phase, privacy: .public)")
        switch words.first {
        case "1" where pids.count == 1:
            audio.setTestGains([pids[0]: 0.5])
        case "3" where pids.count == 3:
            audio.setTestGains([pids[0]: 0.5, pids[1]: 0.25, pids[2]: 0])
        case "end":
            audio.setTestGains([:])
            timer?.invalidate()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { NSApp.terminate(nil) }
        default:
            audio.setTestGains([:])
        }
    }
}
