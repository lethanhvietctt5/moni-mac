import Darwin
import Foundation
import MoniMacCore

/// Reads memory for each snapshot: one `host_statistics64` call and three sysctls, all cheap.
///
/// The breakdown matches Activity Monitor's Memory tab, from `HOST_VM_INFO64` page counts:
/// - App Memory = internal (anonymous) pages − purgeable pages
/// - Wired = wired pages
/// - Compressed = pages the compressor occupies (`compressor_page_count`); before compression they
///   held `total_uncompressed_pages_in_compressor` pages
/// - Cached Files = external (file-backed) pages + purgeable pages
/// - Used = App + Wired + Compressed; Free is what's left of `hw.memsize`
///
/// Pressure: the level comes from `kern.memorystatus_vm_pressure_level` (1 normal, 2 warning,
/// 4 critical) and the percentage is 100 − `kern.memorystatus_level` (the kernel's free percentage,
/// which `memory_pressure` prints). Swap comes from `vm.swapusage`.
@MainActor
final class MemoryReader {
    private let host = mach_host_self()
    private let total = UInt64(max(sysctlInt("hw.memsize") ?? 0, 0))
    private let pageSize = UInt64(max(sysctlInt("hw.pagesize") ?? 0, 0))

    func sample() -> Reading<MemoryReading> {
        guard total > 0, pageSize > 0 else { return .unavailable(.failed("hw.memsize or hw.pagesize unreadable")) }
        guard let vm = readVMStatistics() else { return .unavailable(.failed("host_statistics64(HOST_VM_INFO64) failed")) }
        let pages = { (count: UInt64) in count * self.pageSize }
        let purgeable = UInt64(vm.purgeable_count)
        let internalPages = UInt64(vm.internal_page_count)
        return .value(MemoryReading(
            total: total,
            app: pages(internalPages > purgeable ? internalPages - purgeable : 0),
            wired: pages(UInt64(vm.wire_count)),
            compressed: pages(UInt64(vm.compressor_page_count)),
            compressedOriginal: pages(vm.total_uncompressed_pages_in_compressor),
            cached: pages(UInt64(vm.external_page_count) + purgeable),
            pressureLevel: readPressureLevel(),
            pressure: sysctlInt("kern.memorystatus_level").map { 1 - Double(min(max($0, 0), 100)) / 100 },
            swap: readSwap()
        ))
    }

    private func readVMStatistics() -> vm_statistics64? {
        var info = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(host, HOST_VM_INFO64, $0, &count)
            }
        }
        return result == KERN_SUCCESS ? info : nil
    }

    private func readPressureLevel() -> MemoryPressureLevel? {
        switch sysctlInt("kern.memorystatus_vm_pressure_level") {
        case 1: .normal
        case 2: .warning
        case 4: .critical
        default: nil
        }
    }

    private func readSwap() -> MemoryReading.Swap? {
        var usage = xsw_usage()
        var size = MemoryLayout<xsw_usage>.size
        guard sysctlbyname("vm.swapusage", &usage, &size, nil, 0) == 0 else { return nil }
        return MemoryReading.Swap(used: usage.xsu_used, total: usage.xsu_total)
    }
}
