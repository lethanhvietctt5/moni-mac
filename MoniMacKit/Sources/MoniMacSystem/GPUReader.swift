import Foundation
import IOKit
import MoniMacCore

/// Reads GPU utilization and memory from the IOAccelerator service, and per-process GPU time
/// from its user clients. Everything here is readable without privileges on Apple silicon.
@MainActor
final class GPUReader {
    /// The GPU's accelerator service, matched once. Zero when the Mac has none.
    private let accelerator: io_service_t
    private let model: String
    private let coreCount: Int?
    private let unifiedMemory: UInt64?
    /// GPU time per pid (ns) at the previous `annotate` pass, and when that pass ran.
    private var previousGPUTime: [Int32: UInt64] = [:]
    private var previousWall: UInt64?

    init() {
        accelerator = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOAccelerator"))
        model = Self.string(accelerator, "model") ?? "GPU"
        coreCount = Self.property(accelerator, "gpu-core-count") as? Int
        unifiedMemory = sysctlInt("hw.memsize").map(UInt64.init)
    }

    deinit {
        if accelerator != 0 { IOObjectRelease(accelerator) }
    }

    func sample() -> Reading<GPUReading> {
        guard accelerator != 0 else { return .unavailable(.unsupported) }
        // Only this key is read: the full property table includes large IOReport legends.
        guard let stats = Self.property(accelerator, "PerformanceStatistics") as? [String: Any],
              let device = stats["Device Utilization %"] as? Int else {
            return .unavailable(.failed("PerformanceStatistics not readable"))
        }
        func share(_ key: String) -> Double? { (stats[key] as? Int).map { Double($0) / 100 } }
        return .value(GPUReading(
            model: model,
            coreCount: coreCount,
            utilization: Double(device) / 100,
            renderer: share("Renderer Utilization %"),
            tiler: share("Tiler Utilization %"),
            memoryInUse: (stats["In use system memory"] as? Int).flatMap { UInt64(exactly: $0) },
            unifiedMemory: unifiedMemory
        ))
    }

    /// Adds each process's share of GPU time since the previous pass (`ResourceUse.gpu`).
    /// Processes without GPU clients get zero. The first pass only takes a baseline; HostSampler's first
    /// process list is still warming up then, so no list is shown without GPU figures.
    func annotate(_ processes: Reading<[ProcessSample]>) -> Reading<[ProcessSample]> {
        guard accelerator != 0 else { return processes }
        let wall = DispatchTime.now().uptimeNanoseconds
        let current = readGPUTime()
        let previous = previousGPUTime
        let elapsed = previousWall.map { Double(wall - $0) }
        previousGPUTime = current
        previousWall = wall

        guard let elapsed, elapsed > 0, case .value(var list) = processes else { return processes }
        for index in list.indices {
            let pid = list[index].pid
            let now = current[pid] ?? 0
            // A client closing between passes lowers the sum; count that as no use, not negative use.
            let delta = now >= (previous[pid] ?? 0) ? now - (previous[pid] ?? 0) : 0
            list[index].resources.gpu = Double(delta) / elapsed
        }
        return .value(list)
    }

    /// Cumulative GPU time (ns) per pid, summed over the pid's accelerator user clients.
    private func readGPUTime() -> [Int32: UInt64] {
        var iterator: io_iterator_t = 0
        guard IORegistryEntryGetChildIterator(accelerator, kIOServicePlane, &iterator) == KERN_SUCCESS else { return [:] }
        defer { IOObjectRelease(iterator) }
        var times: [Int32: UInt64] = [:]
        while case let client = IOIteratorNext(iterator), client != 0 {
            defer { IOObjectRelease(client) }
            guard let usage = Self.property(client, "AppUsage") as? [[String: Any]], !usage.isEmpty,
                  let creator = Self.string(client, "IOUserClientCreator"),
                  let pid = Self.pid(fromCreator: creator) else { continue }
            let total = usage.reduce(UInt64(0)) { $0 &+ (($1["accumulatedGPUTime"] as? NSNumber)?.uint64Value ?? 0) }
            times[pid, default: 0] &+= total
        }
        return times
    }

    /// `"pid 600, WindowServer"` → 600.
    static func pid(fromCreator creator: String) -> Int32? {
        guard creator.hasPrefix("pid ") else { return nil }
        return Int32(creator.dropFirst(4).prefix { $0.isNumber })
    }

    private static func property(_ entry: io_registry_entry_t, _ key: String) -> Any? {
        IORegistryEntryCreateCFProperty(entry, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
    }

    private static func string(_ entry: io_registry_entry_t, _ key: String) -> String? {
        switch property(entry, key) {
        case let string as String: string
        // Some entries publish strings as null-terminated data.
        case let data as Data: String(decoding: data.prefix { $0 != 0 }, as: UTF8.self)
        default: nil
        }
    }
}
