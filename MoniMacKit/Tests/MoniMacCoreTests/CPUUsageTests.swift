import Testing
import MoniMacCore

struct CPUUsageTests {
    @Test func splitsElapsedTicksIntoShares() throws {
        let usage = try #require(CPUUsage(
            from: CPUTicks(user: 100, system: 50, idle: 800, nice: 0),
            to: CPUTicks(user: 120, system: 60, idle: 870, nice: 0)
        ))

        #expect(usage.user == 0.2)
        #expect(usage.system == 0.1)
        #expect(usage.idle == 0.7)
        #expect(abs(usage.total - 0.3) < 1e-12)
    }

    @Test func countsNiceAsUser() throws {
        let usage = try #require(CPUUsage(
            from: CPUTicks(user: 0, system: 0, idle: 0, nice: 0),
            to: CPUTicks(user: 10, system: 0, idle: 80, nice: 10)
        ))

        #expect(usage.user == 0.2)
    }

    @Test func handlesCounterWraparound() throws {
        let usage = try #require(CPUUsage(
            from: CPUTicks(user: UInt32.max - 9, system: 0, idle: UInt32.max - 29, nice: 0),
            to: CPUTicks(user: 10, system: 0, idle: 50, nice: 0)
        ))

        // 20 user ticks and 80 idle ticks elapsed across the wrap.
        #expect(usage.user == 0.2)
        #expect(usage.idle == 0.8)
    }

    @Test func isNilWhenNoTimeElapsed() {
        let ticks = CPUTicks(user: 5, system: 5, idle: 5, nice: 5)

        #expect(CPUUsage(from: ticks, to: ticks) == nil)
    }
}
