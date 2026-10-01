import Foundation
import Testing
import MoniMacCore
@testable import MoniMacSystem

/// Runs against the real Mac's GPU. Checks fields are present and in range, not exact values.
@MainActor
struct GPUReaderSmokeTests {
    @Test func readsUtilizationMemoryAndModel() throws {
        let gpu = try #require(GPUReader().sample().value)

        #expect(gpu.model.hasPrefix("Apple"))
        #expect((gpu.coreCount ?? 0) > 0)
        for share in [gpu.utilization, gpu.renderer, gpu.tiler].compactMap({ $0 }) {
            #expect((0...1).contains(share))
        }
        let memory = try #require(gpu.memoryInUse)
        let unified = try #require(gpu.unifiedMemory)
        #expect(memory > 0 && memory < unified)
        #expect(gpu.subtitle.hasSuffix("-core GPU"))
    }

    @Test func perProcessSharesNeedABaselineThenStayInRange() async throws {
        let reader = GPUReader()
        let processes: Reading<[ProcessSample]> = .value([
            ProcessSample(pid: getpid(), name: "tests", path: nil, cpu: 0),
            ProcessSample(pid: 1, name: "launchd", path: "/sbin/launchd", cpu: 0),
        ])

        let first = reader.annotate(processes)
        #expect(first.value?.allSatisfy { $0.resources.gpu == nil } == true)

        try await Task.sleep(for: .seconds(1))
        let second = try #require(reader.annotate(processes).value)
        for process in second {
            let share = try #require(process.resources.gpu, "\(process.name) has no GPU figure")
            // Nanoseconds of GPU time over nanoseconds of wall time; a unit mistake shows up as >> 1.
            #expect((0...2).contains(share), "\(process.name) used \(share) of the GPU")
        }
    }

    @Test func parsesTheClientCreator() {
        #expect(GPUReader.pid(fromCreator: "pid 600, WindowServer") == 600)
        #expect(GPUReader.pid(fromCreator: "kernel") == nil)
    }

    @Test func hostSamplerAddsGPUToSnapshotsAndProcesses() async throws {
        let sampler = HostSampler()
        _ = sampler.sample()
        try await Task.sleep(for: .seconds(1))
        _ = sampler.sample()
        try await Task.sleep(for: .seconds(4.2))

        let snapshot = sampler.sample()
        #expect(snapshot.gpu.value != nil)
        let processes = try #require(snapshot.processes.value)
        #expect(processes.contains { $0.resources.gpu != nil })
    }
}
