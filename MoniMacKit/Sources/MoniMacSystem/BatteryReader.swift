import Foundation
import IOKit
import IOKit.ps
import MoniMacCore

/// Reads the internal battery for each snapshot.
///
/// Charge, charging state, and time remaining come from the public power-sources API (IOPS).
/// Power, health, cycles, and temperature come from the `AppleSmartBattery` registry entry. Recent
/// macOS versions moved some keys (temperature, capacities) into its `BatteryData` dictionary or onto
/// the `AppleSmartBatteryPack` child, so each is looked up in those places in turn.
@MainActor
final class BatteryReader {
    /// Capacity, cycles, temperature, and adapter rating change slowly; reading them every tick
    /// would copy large registry dictionaries for nothing.
    private static let detailsInterval: TimeInterval = 30

    private let battery = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
    private let pack = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBatteryPack"))
    private var details: Details?

    /// The slowly changing part of a reading.
    private struct Details {
        var readAt: Date
        var isPluggedIn: Bool
        var adapterWatts: Double?
        var designCapacity: Int?
        var maxCapacity: Int?
        var cycleCount: Int?
        var ratedCycles: Int?
        var temperature: Double?
    }

    deinit {
        IOObjectRelease(battery)
        IOObjectRelease(pack)
    }

    func sample() -> Reading<BatteryReading> {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue() else {
            return .unavailable(.failed("IOPSCopyPowerSourcesInfo returned nothing"))
        }
        let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] ?? []
        let internalBattery = sources.lazy
            .compactMap { IOPSGetPowerSourceDescription(info, $0)?.takeUnretainedValue() as? [String: Any] }
            .first { $0[kIOPSTypeKey] as? String == kIOPSInternalBatteryType && $0[kIOPSIsPresentKey] as? Bool == true }
        guard let source = internalBattery else { return .unavailable(.unsupported) }

        let current = source[kIOPSCurrentCapacityKey] as? Double ?? 0
        let max = source[kIOPSMaxCapacityKey] as? Double ?? 0
        guard max > 0 else { return .unavailable(.failed("The battery reported no capacity")) }
        let isPluggedIn = source[kIOPSPowerSourceStateKey] as? String == kIOPSACPowerValue
        let isCharging = source[kIOPSIsChargingKey] as? Bool ?? false
        let details = currentDetails(isPluggedIn: isPluggedIn)

        return .value(BatteryReading(
            charge: min(current / max, 1),
            isPluggedIn: isPluggedIn,
            isCharging: isCharging,
            isFullyCharged: source[kIOPSIsChargedKey] as? Bool ?? false,
            timeRemaining: timeRemaining(source, isPluggedIn: isPluggedIn, isCharging: isCharging),
            adapterWatts: details.adapterWatts,
            batteryPower: batteryPower(),
            systemPower: systemPower(),
            designCapacity: details.designCapacity,
            maxCapacity: details.maxCapacity,
            cycleCount: details.cycleCount,
            ratedCycles: details.ratedCycles,
            temperature: details.temperature
        ))
    }

    /// Minutes to full while charging, to empty on battery. macOS reports -1 while it's estimating.
    private func timeRemaining(_ source: [String: Any], isPluggedIn: Bool, isCharging: Bool) -> BatteryReading.TimeRemaining? {
        let key: String
        if isCharging {
            key = kIOPSTimeToFullChargeKey
        } else if !isPluggedIn {
            key = kIOPSTimeToEmptyKey
        } else {
            return nil
        }
        guard let minutes = source[key] as? Int, minutes >= 0 else { return .calculating }
        return .minutes(minutes)
    }

    /// Volts × amps through the battery: positive while charging, negative while discharging.
    private func batteryPower() -> Double? {
        guard let millivolts = int(battery, "Voltage"), let amperage = int(battery, "Amperage") else { return nil }
        // Older firmware publishes the signed current as an unsigned 32- or 64-bit number.
        let milliamps = Int(Int32(truncatingIfNeeded: amperage))
        return Double(millivolts) / 1000 * Double(milliamps) / 1000
    }

    /// The whole Mac's draw from the power controller's telemetry, in watts.
    private func systemPower() -> Double? {
        guard battery != 0, let telemetry = property(battery, "PowerTelemetryData") as? [String: Any] else { return nil }
        // SystemLoad is the system's total draw; SystemPowerIn is adapter input, absent on battery.
        for key in ["SystemLoad", "SystemPowerIn"] {
            if let milliwatts = (telemetry[key] as? NSNumber)?.int64Value, milliwatts > 0 {
                return Double(milliwatts) / 1000
            }
        }
        return nil
    }

    /// Cached details, reread every `detailsInterval` and whenever the adapter is plugged or unplugged.
    private func currentDetails(isPluggedIn: Bool) -> Details {
        if let details, details.isPluggedIn == isPluggedIn,
           Date().timeIntervalSince(details.readAt) < Self.detailsInterval {
            return details
        }
        let batteryData = property(battery, "BatteryData") as? [String: Any] ?? [:]
        var packData: [String: Any]?
        /// Top level first, then the battery's BatteryData, then the pack's (read only if needed).
        func lookup(_ key: String) -> Int? {
            if let value = int(battery, key) ?? (batteryData[key] as? NSNumber).map({ Int($0.int64Value) }) {
                return value
            }
            if packData == nil { packData = property(pack, "BatteryData") as? [String: Any] ?? [:] }
            return (packData?[key] as? NSNumber).map { Int($0.int64Value) }
        }
        let adapter = isPluggedIn ? IOPSCopyExternalPowerAdapterDetails()?.takeRetainedValue() as? [String: Any] : nil
        let details = Details(
            readAt: Date(),
            isPluggedIn: isPluggedIn,
            adapterWatts: (adapter?[kIOPSPowerAdapterWattsKey] as? NSNumber)?.doubleValue,
            designCapacity: lookup("DesignCapacity"),
            // Nominal capacity is what macOS bases "Maximum Capacity" on; the raw figure is a fallback.
            maxCapacity: lookup("NominalChargeCapacity") ?? lookup("AppleRawMaxCapacity"),
            cycleCount: lookup("CycleCount"),
            ratedCycles: int(battery, "DesignCycleCount9C") ?? 1000,
            // Reported in hundredths of a degree Celsius.
            temperature: lookup("Temperature").map { Double($0) / 100 }
        )
        self.details = details
        return details
    }

    private func property(_ entry: io_registry_entry_t, _ key: String) -> Any? {
        guard entry != 0 else { return nil }
        return IORegistryEntryCreateCFProperty(entry, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
    }

    private func int(_ entry: io_registry_entry_t, _ key: String) -> Int? {
        (property(entry, key) as? NSNumber).map { Int($0.int64Value) }
    }
}
