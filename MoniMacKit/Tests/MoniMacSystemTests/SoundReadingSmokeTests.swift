import Foundation
import MoniMacCore
import Testing
@testable import MoniMacSystem

/// Reads audio on the real Mac through the listeners. It never creates a tap, sets a gain, or changes
/// the output device or volume.
struct SoundReadingSmokeTests {
    @Test func readsTheOutputDeviceOnlyWhenAsked() async throws {
        let mixer = AudioMixer()
        #expect(mixer.reading() == .unavailable(.warmingUp))

        mixer.setReadingNeeded(true)
        var reading = mixer.reading()
        for _ in 0..<50 where reading.value == nil {
            try await Task.sleep(for: .milliseconds(100))
            reading = mixer.reading()
        }
        let sound = try #require(reading.value)
        // Every Mac has an output, unless it's a headless runner.
        if let output = sound.output {
            #expect(!output.name.isEmpty)
            #expect(sound.devices.contains { $0.uid == output.uid })
            if let rate = output.sampleRate { #expect(rate >= 8000) }
            if let volume = output.volume { #expect((0...1).contains(volume)) }
        }
        #expect(sound.access == .unused)
        #expect(sound.taps.isEmpty)
        // MoniMac's own process is never listed, nor are macOS's background services.
        #expect(!sound.processes.contains { $0.pid == getpid() })
        #expect(!sound.processes.contains { $0.appPath?.hasPrefix("/System/Library/") == true })

        mixer.setReadingNeeded(false)
        mixer.shutdown()
        #expect(mixer.reading() == .unavailable(.warmingUp))
    }

    @Test func neverAttributesProcessesMoniMacIsResponsibleFor() {
        // Seen from the process responsible for this test runner, the runner is one of its own children.
        let responsible = Responsibility.pid(for: getpid()) ?? getpid()
        #expect(AudioWatcher.identity(of: getpid(), ownPID: responsible) == nil)
    }
}
