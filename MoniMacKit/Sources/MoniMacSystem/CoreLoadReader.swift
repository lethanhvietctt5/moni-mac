import Darwin
import MoniMacCore

/// Per-core busy share from the kernel's per-processor tick counters.
@MainActor
final class CoreLoadReader {
    private let host: host_t
    private let efficiencyCores: Int
    private var previous: [CPUTicks]?

    init(host: host_t, efficiencyCores: Int) {
        self.host = host
        self.efficiencyCores = efficiencyCores
    }

    func sample() -> Reading<[CoreUsage]> {
        guard let ticks = readTicks() else { return .unavailable(.failed("host_processor_info failed")) }
        defer { previous = ticks }
        guard let previous, previous.count == ticks.count else { return .unavailable(.warmingUp) }
        return .value(zip(previous, ticks).enumerated().map { index, pair in
            // On Apple silicon the efficiency cores are the lowest-numbered CPUs
            // (verified on an M4: background-QoS load lands on cpu0…5).
            CoreUsage(
                kind: index < efficiencyCores ? .efficiency : .performance,
                usage: CPUUsage(from: pair.0, to: pair.1)?.total ?? 0
            )
        })
    }

    private func readTicks() -> [CPUTicks]? {
        var cpuCount: natural_t = 0
        var info: processor_info_array_t?
        var infoCount: mach_msg_type_number_t = 0
        guard host_processor_info(host, PROCESSOR_CPU_LOAD_INFO, &cpuCount, &info, &infoCount) == KERN_SUCCESS,
              let info else { return nil }
        defer {
            vm_deallocate(mach_task_self_, vm_address_t(bitPattern: info),
                          vm_size_t(infoCount) * vm_size_t(MemoryLayout<integer_t>.stride))
        }
        let states = Int(CPU_STATE_MAX)
        return (0..<Int(cpuCount)).map { cpu in
            func ticks(_ state: Int32) -> UInt32 { UInt32(bitPattern: info[cpu * states + Int(state)]) }
            return CPUTicks(
                user: ticks(CPU_STATE_USER), system: ticks(CPU_STATE_SYSTEM),
                idle: ticks(CPU_STATE_IDLE), nice: ticks(CPU_STATE_NICE)
            )
        }
    }
}
