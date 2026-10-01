import Foundation
import Testing
import MoniMacCore
@testable import MoniMacSystem

/// Runs against the real Mac. Checks fields are present and in range, not exact values.
@MainActor
struct HostSamplerSmokeTests {
    @Test func firstSampleIsWarmingUp() {
        let snapshot = HostSampler().sample()

        #expect(snapshot.cpu == .unavailable(.warmingUp))
        #expect(snapshot.processes == .unavailable(.warmingUp))
    }

    @Test func secondSampleReportsCPUInRange() async throws {
        let sampler = HostSampler()
        _ = sampler.sample()
        try await Task.sleep(for: .seconds(1))

        let snapshot = sampler.sample()
        let cpu = try #require(snapshot.cpu.value, "cpu reading: \(snapshot.cpu)")
        for share in [cpu.user, cpu.system, cpu.idle] {
            #expect((0...1).contains(share))
        }
        #expect(abs(cpu.user + cpu.system + cpu.idle - 1) < 1e-9)

        let cores = try #require(snapshot.cores.value)
        #expect(cores.count == snapshot.system.logicalCores)
        #expect(cores.filter { $0.kind == .efficiency }.count == snapshot.system.efficiencyCores)
        #expect(cores.allSatisfy { (0...1).contains($0.usage) })
        #expect(snapshot.loadAverage.value != nil)
        let tasks = try #require(snapshot.taskCounts.value)
        #expect(tasks.processes > 50)
        #expect(tasks.threads > tasks.processes)
        #expect(snapshot.system.chipName.hasPrefix("Apple"))
        #expect(snapshot.system.bootTime.map { $0 < Date() } == true)
    }

    /// A busy `yes` must read about one full core. Catches Mach-time vs nanosecond unit mistakes.
    @Test func busyProcessReadsAboutOneCore() async throws {
        let busy = Process()
        busy.executableURL = URL(fileURLWithPath: "/usr/bin/yes")
        busy.standardOutput = FileHandle.nullDevice
        try busy.run()
        defer { busy.terminate() }

        let sampler = HostSampler()
        _ = sampler.sample()
        try await Task.sleep(for: .seconds(2))

        let processes = try #require(sampler.sample().processes.value)
        let yes = try #require(processes.first { $0.pid == busy.processIdentifier })
        #expect((0.8...1.1).contains(yes.cpu), "yes used \(yes.cpu) cores")
        #expect(yes.path == "/usr/bin/yes")
        #expect(processes.contains { $0.pid == getpid() })
    }

    @Test func parsesPSOutput() {
        let rows = OtherUsersProcessReader.parse("""
              600    88 1266:23.49 /System/Library/PrivateFrameworks/SkyLight.framework/Resources/WindowServer
                1     0   12:01.50 /sbin/launchd
              999   501    0:00.02 /Applications/Some App.app/Contents/MacOS/Some App
            garbage line
            """)

        #expect(rows.map(\.pid) == [600, 1, 999])
        #expect(rows[0].cpuSeconds == 1266 * 60 + 23.49)
        #expect(rows[2].command == "/Applications/Some App.app/Contents/MacOS/Some App")
    }

    @Test(arguments: [
        ("0:00.02", 0.02), ("12:01.50", 721.5), ("1266:23.49", 75983.49), ("01:02:03.00", 3723.0), ("1-00:00:01.00", 86401.0),
    ])
    func parsesPSCPUTime(text: String, seconds: Double) throws {
        let parsed = try #require(OtherUsersProcessReader.parseCPUTime(text))
        #expect(abs(parsed - seconds) < 1e-6)
    }

    /// Other users' processes (here WindowServer) arrive from background `ps` runs.
    @Test func readsOtherUsersProcessesInTheBackground() async throws {
        let reader = OtherUsersProcessReader(interval: 0)
        reader.refreshIfDue()  // baseline run
        try await waitForRun(of: reader)
        reader.refreshIfDue()  // second run yields rates
        try await waitForRun(of: reader)

        let windowServer = try #require(reader.latest().first { $0.name == "WindowServer" })
        #expect(windowServer.cpu >= 0)
        #expect(windowServer.path?.hasSuffix("/WindowServer") == true)
        #expect(reader.latest().allSatisfy { $0.pid != getpid() })
    }

    private func waitForRun(of reader: OtherUsersProcessReader) async throws {
        for _ in 0..<50 where !reader.isIdle {
            try await Task.sleep(for: .milliseconds(100))
        }
        try await Task.sleep(for: .milliseconds(200))
    }
}
