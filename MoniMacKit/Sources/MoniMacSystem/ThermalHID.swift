import Foundation
import MoniMacCore

/// Temperatures from the IOHID event system: the SoC die, NAND, and battery gauge sensors.
///
/// A fallback for Macs whose SMC reports no temperatures MoniMac can name. A full pass over the
/// ~50 services costs ~40 ms, so callers read it rarely. The calls are private IOKit symbols,
/// resolved at runtime; when any is missing, `init` fails.
final class ThermalHID {
    private typealias Create = @convention(c) (CFAllocator?) -> Unmanaged<AnyObject>?
    private typealias SetMatching = @convention(c) (AnyObject, CFDictionary) -> Int32
    private typealias CopyServices = @convention(c) (AnyObject) -> Unmanaged<CFArray>?
    private typealias CopyProperty = @convention(c) (AnyObject, CFString) -> Unmanaged<AnyObject>?
    private typealias CopyEvent = @convention(c) (AnyObject, Int64, Int32, Int64) -> Unmanaged<AnyObject>?
    private typealias FloatValue = @convention(c) (AnyObject, Int32) -> Double

    private static let temperatureEvent: Int64 = 15  // kIOHIDEventTypeTemperature
    private static let temperatureField = Int32(temperatureEvent << 16)

    private let copyEvent: CopyEvent
    private let floatValue: FloatValue
    private let client: AnyObject
    private let services: [(name: String, service: AnyObject)]

    init?() {
        func symbol<T>(_ name: String, as type: T.Type) -> T? {
            dlsym(UnsafeMutableRawPointer(bitPattern: -2), name).map { unsafeBitCast($0, to: type) }
        }
        guard let create = symbol("IOHIDEventSystemClientCreate", as: Create.self),
              let setMatching = symbol("IOHIDEventSystemClientSetMatching", as: SetMatching.self),
              let copyServices = symbol("IOHIDEventSystemClientCopyServices", as: CopyServices.self),
              let copyProperty = symbol("IOHIDServiceClientCopyProperty", as: CopyProperty.self),
              let copyEvent = symbol("IOHIDServiceClientCopyEvent", as: CopyEvent.self),
              let floatValue = symbol("IOHIDEventGetFloatValue", as: FloatValue.self),
              let client = create(kCFAllocatorDefault)?.takeRetainedValue()
        else { return nil }
        // Apple vendor usage page, temperature sensor usage.
        _ = setMatching(client, ["PrimaryUsagePage": 0xff00, "PrimaryUsage": 5] as CFDictionary)
        let services = (copyServices(client)?.takeRetainedValue() as? [AnyObject]) ?? []
        self.client = client
        self.copyEvent = copyEvent
        self.floatValue = floatValue
        self.services = services.compactMap { service in
            guard let name = copyProperty(service, "Product" as CFString)?.takeRetainedValue() as? String else { return nil }
            return (name, service)
        }
    }

    /// Reads every sensor once.
    func read() -> [ThermalSensor] {
        services.compactMap { name, service in
            guard let event = copyEvent(service, Self.temperatureEvent, 0, 0)?.takeRetainedValue() else { return nil }
            return ThermalSensor(name: name, celsius: floatValue(event, Self.temperatureField))
        }
    }
}
