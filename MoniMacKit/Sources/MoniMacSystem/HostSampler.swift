import Darwin
import Foundation
import MoniMacCore

/// The real SystemSampler, backed by Mach host statistics.
public final class HostSampler: SystemSampler {
    private let host = mach_host_self()
    private var previousTicks: CPUTicks?

    public init() {}

    public func sample() -> Snapshot {
        Snapshot(timestamp: Date(), cpu: sampleCPU())
    }

    private func sampleCPU() -> Reading<CPUUsage> {
        guard let ticks = readCPUTicks() else {
            return .unavailable(.failed("host_statistics(HOST_CPU_LOAD_INFO) failed"))
        }
        defer { previousTicks = ticks }
        guard let previousTicks, let usage = CPUUsage(from: previousTicks, to: ticks) else {
            return .unavailable(.warmingUp)
        }
        return .value(usage)
    }

    private func readCPUTicks() -> CPUTicks? {
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(
            MemoryLayout<host_cpu_load_info_data_t>.stride / MemoryLayout<integer_t>.stride
        )
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(host, HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        let ticks = info.cpu_ticks
        return CPUTicks(
            user: ticks.0,  // CPU_STATE_USER
            system: ticks.1,  // CPU_STATE_SYSTEM
            idle: ticks.2,  // CPU_STATE_IDLE
            nice: ticks.3  // CPU_STATE_NICE
        )
    }
}
