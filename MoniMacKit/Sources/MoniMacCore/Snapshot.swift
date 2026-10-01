import Foundation

/// Everything SystemSampler read from the OS on one refresh tick. Immutable.
public struct Snapshot: Equatable, Sendable {
    public var timestamp: Date
    public var system: SystemInfo
    public var cpu: Reading<CPUUsage>
    /// Per logical core, in the kernel's CPU order.
    public var cores: Reading<[CoreUsage]>
    public var loadAverage: Reading<LoadAverage>
    public var taskCounts: Reading<TaskCounts>
    public var processes: Reading<[ProcessSample]>
    // One field per metric; each metric's file defines its reading type.
    public var memory: Reading<MemoryReading>
    public var gpu: Reading<GPUReading>
    public var network: Reading<NetworkReading>
    public var disk: Reading<DiskReading>
    public var battery: Reading<BatteryReading>
    public var thermal: Reading<ThermalReading>

    public init(
        timestamp: Date,
        system: SystemInfo = .unknown,
        cpu: Reading<CPUUsage>,
        cores: Reading<[CoreUsage]> = .unavailable(.unsupported),
        loadAverage: Reading<LoadAverage> = .unavailable(.unsupported),
        taskCounts: Reading<TaskCounts> = .unavailable(.unsupported),
        processes: Reading<[ProcessSample]> = .unavailable(.unsupported),
        memory: Reading<MemoryReading> = .unavailable(.unsupported),
        gpu: Reading<GPUReading> = .unavailable(.unsupported),
        network: Reading<NetworkReading> = .unavailable(.unsupported),
        disk: Reading<DiskReading> = .unavailable(.unsupported),
        battery: Reading<BatteryReading> = .unavailable(.unsupported),
        thermal: Reading<ThermalReading> = .unavailable(.unsupported)
    ) {
        self.timestamp = timestamp
        self.system = system
        self.cpu = cpu
        self.cores = cores
        self.loadAverage = loadAverage
        self.taskCounts = taskCounts
        self.processes = processes
        self.memory = memory
        self.gpu = gpu
        self.network = network
        self.disk = disk
        self.battery = battery
        self.thermal = thermal
    }
}

/// A sampled value, or the reason it is missing. Missing data is never reported as zero.
public enum Reading<Value: Equatable & Sendable>: Equatable, Sendable {
    case value(Value)
    case unavailable(UnavailableReason)

    public var value: Value? {
        if case .value(let value) = self { value } else { nil }
    }
}

public enum UnavailableReason: Equatable, Sendable {
    /// The value needs two samples (e.g. a rate) and only one has been taken.
    case warmingUp
    /// This Mac doesn't have the hardware or the OS doesn't expose it.
    case unsupported
    /// The OS refused or the read failed.
    case failed(String)
}

/// Facts about the Mac that don't change while MoniMac runs.
public struct SystemInfo: Equatable, Sendable {
    /// e.g. "Apple M3 Pro".
    public var chipName: String
    public var performanceCores: Int
    public var efficiencyCores: Int
    public var bootTime: Date?

    public init(chipName: String, performanceCores: Int, efficiencyCores: Int, bootTime: Date?) {
        self.chipName = chipName
        self.performanceCores = performanceCores
        self.efficiencyCores = efficiencyCores
        self.bootTime = bootTime
    }

    public var logicalCores: Int { performanceCores + efficiencyCores }

    public static let unknown = SystemInfo(chipName: "Mac", performanceCores: 1, efficiencyCores: 0, bootTime: nil)
}

public enum CoreKind: Equatable, Sendable {
    case performance
    case efficiency
}

public struct CoreUsage: Equatable, Sendable {
    public var kind: CoreKind
    /// Busy share of this core, 0...1.
    public var usage: Double

    public init(kind: CoreKind, usage: Double) {
        self.kind = kind
        self.usage = usage
    }
}

/// Runnable threads averaged over 1, 5, and 15 minutes.
public struct LoadAverage: Equatable, Sendable {
    public var one: Double
    public var five: Double
    public var fifteen: Double

    public init(one: Double, five: Double, fifteen: Double) {
        self.one = one
        self.five = five
        self.fifteen = fifteen
    }
}

/// System-wide process and thread counts, including other users' processes.
public struct TaskCounts: Equatable, Sendable {
    public var processes: Int
    public var threads: Int

    public init(processes: Int, threads: Int) {
        self.processes = processes
        self.threads = threads
    }
}

/// One running process over the last sampling interval.
public struct ProcessSample: Equatable, Sendable {
    public var pid: Int32
    /// The process macOS holds responsible for this one (e.g. Chrome for its renderers), if known.
    public var responsiblePID: Int32?
    public var name: String
    /// Full executable path, if readable.
    public var path: String?
    /// CPU in cores: 1.0 means one core fully busy. Can exceed 1.
    public var cpu: Double
    /// Whether this is a running app with a Dock presence (the only kind MoniMac offers to quit).
    public var isRegularApp: Bool
    /// Physical memory footprint in bytes.
    public var memory: UInt64?
    /// Share of the GPU, 0...1.
    public var gpu: Double?
    /// Network traffic, bytes per second (in + out).
    public var network: Double?
    public var diskReadPerSecond: Double?
    public var diskWritePerSecond: Double?
    /// Estimated power draw in watts.
    public var power: Double?

    public init(
        pid: Int32, responsiblePID: Int32? = nil, name: String, path: String?, cpu: Double, isRegularApp: Bool = false,
        memory: UInt64? = nil, gpu: Double? = nil, network: Double? = nil,
        diskReadPerSecond: Double? = nil, diskWritePerSecond: Double? = nil, power: Double? = nil
    ) {
        self.pid = pid
        self.responsiblePID = responsiblePID
        self.name = name
        self.path = path
        self.cpu = cpu
        self.isRegularApp = isRegularApp
        self.memory = memory
        self.gpu = gpu
        self.network = network
        self.diskReadPerSecond = diskReadPerSecond
        self.diskWritePerSecond = diskWritePerSecond
        self.power = power
    }
}
