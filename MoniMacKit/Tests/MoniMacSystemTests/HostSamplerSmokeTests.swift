import Foundation
import Testing
import MoniMacCore
import MoniMacSystem

/// Runs against the real Mac. Checks fields are present and in range, not exact values.
struct HostSamplerSmokeTests {
    @Test func firstSampleIsWarmingUp() {
        let snapshot = HostSampler().sample()

        #expect(snapshot.cpu == .unavailable(.warmingUp))
    }

    @Test func secondSampleReportsCPUInRange() async throws {
        let sampler = HostSampler()
        _ = sampler.sample()
        try await Task.sleep(for: .milliseconds(250))

        let cpu = try #require(sampler.sample().cpu.value)

        for share in [cpu.user, cpu.system, cpu.idle] {
            #expect((0...1).contains(share))
        }
        #expect(abs(cpu.user + cpu.system + cpu.idle - 1) < 1e-9)
    }
}
