import Darwin
import Foundation
import IOKit
import MoniMacCore

/// Reads facts about the Mac that don't change while MoniMac runs.
enum SystemInfoReader {
    static func read() -> SystemInfo {
        let logical = sysctlInt("hw.logicalcpu") ?? 1
        // Apple silicon reports one perflevel per core type: perflevel0 is Performance and
        // perflevel1 Efficiency. Macs without perflevels (Intel) count every core as performance.
        var performance = logical
        var efficiency = 0
        for level in 0..<2 {
            guard let name = sysctlString("hw.perflevel\(level).name"),
                  let count = sysctlInt("hw.perflevel\(level).logicalcpu") else { continue }
            if name == "Efficiency" { efficiency = count } else if level == 0 { performance = count }
        }
        if performance + efficiency != logical { performance = logical - efficiency }

        return SystemInfo(
            chipName: sysctlString("machdep.cpu.brand_string") ?? "Mac",
            performanceCores: performance,
            efficiencyCores: efficiency,
            bootTime: bootTime(),
            modelName: modelName()
        )
    }

    /// The marketing name, e.g. "MacBook Pro", from the device tree's `product-name`
    /// ("MacBook Pro (14-inch, Nov 2024)") without the parenthetical. Apple silicon only; no privileges needed.
    static func modelName() -> String? {
        let entry = IORegistryEntryFromPath(kIOMainPortDefault, "IODeviceTree:/product")
        guard entry != 0 else { return nil }
        defer { IOObjectRelease(entry) }
        guard let data = IORegistryEntryCreateCFProperty(entry, "product-name" as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue() as? Data else { return nil }
        return marketingName(String(nullTerminated: data.map { CChar(bitPattern: $0) }))
    }

    /// "MacBook Pro (14-inch, Nov 2024)" → "MacBook Pro"; nil when nothing is left.
    static func marketingName(_ productName: String) -> String? {
        let name = productName.split(separator: "(", maxSplits: 1).first.map(String.init) ?? ""
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func bootTime() -> Date? {
        var time = timeval()
        var size = MemoryLayout<timeval>.size
        guard sysctlbyname("kern.boottime", &time, &size, nil, 0) == 0 else { return nil }
        return Date(timeIntervalSince1970: Double(time.tv_sec) + Double(time.tv_usec) / 1_000_000)
    }
}

func sysctlInt(_ name: String) -> Int? {
    var value = 0
    var size = MemoryLayout<Int>.size
    guard sysctlbyname(name, &value, &size, nil, 0) == 0 else { return nil }
    // Some keys are 32-bit; sysctl fills only the low bytes.
    return size == MemoryLayout<Int32>.size ? Int(Int32(truncatingIfNeeded: value)) : value
}

func sysctlString(_ name: String) -> String? {
    var size = 0
    guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
    var buffer = [CChar](repeating: 0, count: size)
    guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { return nil }
    return String(nullTerminated: buffer)
}

extension String {
    /// Decodes a C string buffer as UTF-8, stopping at the first null.
    init(nullTerminated buffer: [CChar]) {
        self = String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }
}
