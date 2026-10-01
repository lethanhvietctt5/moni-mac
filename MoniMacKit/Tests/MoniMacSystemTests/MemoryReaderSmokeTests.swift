import Foundation
import Testing
import MoniMacCore
@testable import MoniMacSystem

/// Runs against the real Mac. Checks fields are present and consistent, not exact values.
@MainActor
struct MemoryReaderSmokeTests {
    @Test func readsAConsistentBreakdown() throws {
        let memory = try #require(MemoryReader().sample().value)

        #expect(memory.total == ProcessInfo.processInfo.physicalMemory)
        #expect(memory.used > 0)
        #expect(memory.used <= memory.total)
        #expect(memory.app > 0)
        #expect(memory.wired > 0)
        #expect(memory.cached > 0)
        // The five segments cover installed memory, unless the counters overlap it and Free clamps to zero.
        #expect(memory.used + memory.cached + memory.free == memory.total || memory.free == 0)
        #expect(memory.compressedOriginal >= memory.compressed)
    }

    @Test func readsPressureAndSwap() throws {
        let memory = try #require(MemoryReader().sample().value)

        #expect(memory.pressureLevel != nil)
        let pressure = try #require(memory.pressure)
        #expect((0...1).contains(pressure))
        let swap = try #require(memory.swap)
        #expect(swap.used <= swap.total)
    }

    @Test func hostSamplerIncludesMemory() {
        #expect(HostSampler().sample().memory.value != nil)
    }
}
