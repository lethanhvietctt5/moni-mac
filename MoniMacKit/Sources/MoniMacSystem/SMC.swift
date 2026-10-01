import Foundation
import IOKit

/// A read-only client for the System Management Controller (the AppleSMC user client).
///
/// MoniMac never writes to the SMC: `Command` has no write case, so no code path can send one.
final class SMC {
    /// The SMC commands MoniMac sends, all reads. The SMC's write command (6) is deliberately absent.
    private enum Command: UInt8 {
        case readKey = 5
        case keyAtIndex = 8
        case keyInfo = 9
    }

    struct KeyInfo: Equatable {
        var size: UInt32
        /// e.g. "flt ", "sp78", "fpe2".
        var type: String
    }

    /// AppleSMC's struct-method selector for all of the commands above.
    private static let selector: UInt32 = 2
    /// `SMCKeyData_t` is 80 bytes. Fields are written at their C offsets rather than through a
    /// mirrored Swift struct, whose layout Swift doesn't guarantee.
    private enum Offset {
        static let key = 0
        static let dataSize = 28
        static let dataType = 32
        static let result = 40
        static let command = 42
        static let index = 44
        static let bytes = 48
        static let length = 80
    }

    private let connection: io_connect_t
    private var infoCache: [String: KeyInfo] = [:]

    /// Nil when AppleSMC can't be opened.
    init?() {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        var connection: io_connect_t = 0
        guard IOServiceOpen(service, mach_task_self_, 0, &connection) == kIOReturnSuccess else { return nil }
        self.connection = connection
    }

    deinit {
        IOServiceClose(connection)
    }

    /// How many keys the SMC has.
    func keyCount() -> Int? {
        read("#KEY").flatMap { Self.decode($0, type: "ui32") }.map { Int($0) }
    }

    /// The key at an index, 0..<keyCount.
    func key(at index: Int) -> String? {
        call(.keyAtIndex, key: 0, index: UInt32(index)).map { Self.name(Self.load(UInt32.self, $0, at: Offset.key)) }
    }

    /// A key's size and type, cached: they never change.
    func info(_ key: String) -> KeyInfo? {
        if let cached = infoCache[key] { return cached }
        guard let output = call(.keyInfo, key: Self.code(key)) else { return nil }
        let info = KeyInfo(size: Self.load(UInt32.self, output, at: Offset.dataSize),
                           type: Self.name(Self.load(UInt32.self, output, at: Offset.dataType)))
        infoCache[key] = info
        return info
    }

    /// A key's raw bytes, or nil if the key doesn't exist.
    func read(_ key: String) -> [UInt8]? {
        guard let info = info(key), info.size <= 32,
              let output = call(.readKey, key: Self.code(key), size: info.size) else { return nil }
        return Array(output[Offset.bytes..<Offset.bytes + Int(info.size)])
    }

    /// A numeric key's value, or nil if it doesn't exist or isn't numeric.
    func number(_ key: String) -> Double? {
        guard let info = info(key), let bytes = read(key) else { return nil }
        return Self.decode(bytes, type: info.type)
    }

    /// Decodes the SMC's numeric types. Apple silicon reports `flt` (little-endian Float32); older
    /// types are big-endian fixed point (`fpe2` for fans, `sp78` for temperatures) or integers.
    static func decode(_ bytes: [UInt8], type: String) -> Double? {
        func bigEndian(_ count: Int) -> UInt32? {
            bytes.count >= count ? bigEndianValue(bytes.prefix(count)) : nil
        }
        switch type {
        case "flt ":
            guard bytes.count >= 4 else { return nil }
            return Double(Float32(bitPattern: bigEndianValue(bytes.prefix(4).reversed())))
        case "fpe2": return bigEndian(2).map { Double($0) / 4 }
        case "sp78": return bigEndian(2).map { Double(Int16(truncatingIfNeeded: $0)) / 256 }
        case "ui8 ": return bigEndian(1).map(Double.init)
        case "ui16": return bigEndian(2).map(Double.init)
        case "ui32": return bigEndian(4).map(Double.init)
        default: return nil
        }
    }

    private func call(_ command: Command, key: UInt32, size: UInt32 = 0, index: UInt32 = 0) -> [UInt8]? {
        var input = [UInt8](repeating: 0, count: Offset.length)
        Self.store(key, in: &input, at: Offset.key)
        Self.store(size, in: &input, at: Offset.dataSize)
        input[Offset.command] = command.rawValue
        Self.store(index, in: &input, at: Offset.index)
        var output = [UInt8](repeating: 0, count: Offset.length)
        var outputSize = Offset.length
        let status = IOConnectCallStructMethod(connection, Self.selector, input, Offset.length, &output, &outputSize)
        guard status == kIOReturnSuccess, output[Offset.result] == 0 else { return nil }
        return output
    }

    /// A four-character key as the SMC's 32-bit code, e.g. "Tp01".
    private static func code(_ key: String) -> UInt32 {
        bigEndianValue(key.utf8.prefix(4))
    }

    /// Bytes read as one big-endian unsigned integer (at most 4 bytes).
    private static func bigEndianValue(_ bytes: some Sequence<UInt8>) -> UInt32 {
        bytes.reduce(UInt32(0)) { $0 << 8 | UInt32($1) }
    }

    private static func name(_ code: UInt32) -> String {
        String(decoding: [24, 16, 8, 0].map { UInt8(truncatingIfNeeded: code >> $0) }, as: UTF8.self)
    }

    private static func store(_ value: UInt32, in buffer: inout [UInt8], at offset: Int) {
        withUnsafeBytes(of: value) { buffer.replaceSubrange(offset..<offset + 4, with: $0) }
    }

    private static func load<T: FixedWidthInteger>(_: T.Type, _ buffer: [UInt8], at offset: Int) -> T {
        buffer[offset..<offset + MemoryLayout<T>.size].withUnsafeBytes { $0.loadUnaligned(as: T.self) }
    }
}
