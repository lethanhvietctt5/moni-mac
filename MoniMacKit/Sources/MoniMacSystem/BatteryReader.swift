import Foundation
import MoniMacCore

/// Reads battery for each snapshot. Filled in by ticket 09.
@MainActor
final class BatteryReader {
    func sample() -> Reading<BatteryReading> {
        .unavailable(.unsupported)
    }
}
