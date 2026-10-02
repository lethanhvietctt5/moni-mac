import Darwin
import Foundation
import MoniMacCore

/// The real SystemSampler. Composes one reader per data source.
@MainActor
public final class HostSampler: SystemSampler {
    private let host = mach_host_self()
    private let system = SystemInfoReader.read()
    private var previousTicks: CPUTicks?
    private var lastCPU: CPUUsage?
    private let cores: CoreLoadReader
    private let processes = ProcessReader()
    private let memory = MemoryReader()
    private let gpu = GPUReader()
    private let network = NetworkReader()
    private let disk: DiskReader
    private let battery = BatteryReader()
    private let thermal = ThermalReader()
    private let devServers = DevServerReader()
    private let bluetooth = BluetoothReader()
    /// What needs Bluetooth read, asked on every tick; the app answers from the window and the settings.
    /// Until it's set, nothing does, and Bluetooth is never read.
    public var bluetoothDemand: @MainActor () -> BluetoothDemand = { .none }
    /// The latest process list with GPU and network figures added. Annotation runs only when the
    /// process list is refreshed, so readers see the same cadence and can compute their own rates.
    private var annotatedProcesses: Reading<[ProcessSample]> = .unavailable(.warmingUp)

    /// `storageScanCache` keeps the storage scan across launches; the app passes `.standard`.
    public init(storageScanCache: StorageScanCache? = nil) {
        cores = CoreLoadReader(host: host, efficiencyCores: system.efficiencyCores)
        disk = DiskReader(storageScanCache: storageScanCache)
    }

    public func sample() -> Snapshot {
        Snapshot(
            timestamp: Date(),
            system: system,
            cpu: sampleCPU(),
            cores: cores.sample(),
            loadAverage: sampleLoadAverage(),
            taskCounts: sampleTaskCounts(),
            processes: sampleProcesses(),
            memory: memory.sample(),
            gpu: gpu.sample(),
            network: network.sample(),
            disk: disk.sample(),
            battery: battery.sample(),
            thermal: thermal.sample(),
            devServers: sampleDevServers(),
            bluetooth: sampleBluetooth()
        )
    }

    private func sampleProcesses() -> Reading<[ProcessSample]> {
        let (list, refreshed) = processes.sample()
        if refreshed {
            annotatedProcesses = network.annotate(gpu.annotate(list))
        }
        return annotatedProcesses
    }

    private func sampleDevServers() -> Reading<DevServerReading> {
        devServers.refreshIfDue()
        return devServers.latest()
    }

    private func sampleBluetooth() -> Reading<BluetoothReading> {
        bluetooth.refreshIfDue(demand: bluetoothDemand())
        return bluetooth.latest()
    }

    private func sampleCPU() -> Reading<CPUUsage> {
        guard let ticks = readCPUTicks() else {
            return .unavailable(.failed("host_statistics(HOST_CPU_LOAD_INFO) failed"))
        }
        guard let previousTicks else {
            previousTicks = ticks
            return .unavailable(.warmingUp)
        }
        // The kernel can publish tick counters lazily; if none elapsed, keep the baseline and
        // repeat the last value rather than flashing a placeholder.
        guard let usage = CPUUsage(from: previousTicks, to: ticks) else {
            return lastCPU.map(Reading.value) ?? .unavailable(.warmingUp)
        }
        self.previousTicks = ticks
        lastCPU = usage
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

    /// System-wide counts, including processes MoniMac can't inspect individually.
    private func sampleTaskCounts() -> Reading<TaskCounts> {
        var processorSet = processor_set_name_t()
        guard processor_set_default(host, &processorSet) == KERN_SUCCESS else {
            return .unavailable(.failed("processor_set_default failed"))
        }
        defer { mach_port_deallocate(mach_task_self_, processorSet) }
        var info = processor_set_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<processor_set_load_info>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                processor_set_statistics(processorSet, PROCESSOR_SET_LOAD_INFO, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return .unavailable(.failed("processor_set_statistics failed")) }
        return .value(TaskCounts(processes: Int(info.task_count), threads: Int(info.thread_count)))
    }

    private func sampleLoadAverage() -> Reading<LoadAverage> {
        var loads = [Double](repeating: 0, count: 3)
        guard getloadavg(&loads, 3) == 3 else { return .unavailable(.failed("getloadavg failed")) }
        return .value(LoadAverage(one: loads[0], five: loads[1], fifteen: loads[2]))
    }
}
