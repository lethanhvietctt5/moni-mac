import Foundation
import IOKit
import MoniMacCore

/// NVMe SMART health through the NVMeSMARTLib plug-in that macOS attaches to NVMe drives. It's
/// readable without privileges, including Apple silicon's built-in SSD. Read-only.
enum DiskHealthReader {
    // UUIDs from IOKit's NVMeSMARTLibExternal.h and IOCFPlugIn.h, which aren't imported into Swift.
    // Computed: CFUUID isn't Sendable, so it can't be a stored static.
    private static var smartUserClientType: CFUUID { uuid("AA0FA6F9-C2D6-457F-B10B-59A13253292F") }
    private static var smartInterface: CFUUID { uuid("CCD1DB19-FD9A-4DAF-BF95-12454B230AB6") }
    private static var plugInInterface: CFUUID { uuid("C244E858-109C-11D4-91D4-0050E4C6426F") }

    private static func uuid(_ string: String) -> CFUUID {
        CFUUIDCreateFromString(nil, string as CFString)
    }

    /// `IONVMeSMARTInterface` starts with IUnknown's four pointers, then two UInt16 version
    /// fields (padded to 8 bytes), then `SMARTReadData`.
    private static let releaseOffset = 24
    private static let readDataOffset = 40
    private typealias Release = @convention(c) (UnsafeMutableRawPointer) -> UInt32
    private typealias ReadData = @convention(c) (UnsafeMutableRawPointer, UnsafeMutableRawPointer) -> IOReturn

    /// `device` is the registry entry ID of the startup drive's NVMe device, or nil if it isn't NVMe.
    static func read(device: UInt64?) -> Reading<SSDHealth> {
        guard let device else { return .unavailable(.unsupported) }
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IORegistryEntryIDMatching(device))
        guard service != 0 else { return .unavailable(.failed("the drive is no longer attached")) }
        defer { IOObjectRelease(service) }

        var plugIn: UnsafeMutablePointer<UnsafeMutablePointer<IOCFPlugInInterface>?>?
        var score: Int32 = 0
        let created = IOCreatePlugInInterfaceForService(service, smartUserClientType, plugInInterface, &plugIn, &score)
        guard created == KERN_SUCCESS, let plugIn, let methods = plugIn.pointee?.pointee else {
            return .unavailable(.failed("the drive's SMART service didn't open (\(hex(created)))"))
        }
        defer { _ = IODestroyPlugInInterface(plugIn) }

        var interface: LPVOID?
        guard methods.QueryInterface(plugIn, CFUUIDGetUUIDBytes(smartInterface), &interface) == 0, let interface else {
            return .unavailable(.failed("the drive's SMART interface isn't available"))
        }
        let table = interface.assumingMemoryBound(to: UnsafeMutableRawPointer.self).pointee
        defer { _ = table.load(fromByteOffset: releaseOffset, as: Release.self)(interface) }

        // The NVMe SMART / Health Information log page.
        var page = [UInt8](repeating: 0, count: 512)
        let status = page.withUnsafeMutableBytes {
            table.load(fromByteOffset: readDataOffset, as: ReadData.self)(interface, $0.baseAddress!)
        }
        guard status == kIOReturnSuccess else { return .unavailable(.failed("reading SMART data failed (\(hex(status)))")) }
        return .value(parse(page))
    }

    /// Byte 5 is "percentage used"; bytes 48–63 count data units written, each 1,000 × 512 bytes.
    static func parse(_ page: [UInt8]) -> SSDHealth {
        let unitsWritten = (0..<8).reduce(UInt64(0)) { $0 | UInt64(page[48 + $1]) << (8 * UInt64($1)) }
        let (bytes, overflow) = unitsWritten.multipliedReportingOverflow(by: 512_000)
        return SSDHealth(percentageUsed: Int(page[5]), lifetimeBytesWritten: overflow ? .max : bytes)
    }

    private static func hex(_ code: Int32) -> String {
        "0x" + String(UInt32(bitPattern: code), radix: 16)
    }
}
