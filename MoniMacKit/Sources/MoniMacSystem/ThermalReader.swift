import Foundation
import MoniMacCore

/// Reads thermal for each snapshot. Filled in by ticket 10.
@MainActor
final class ThermalReader {
    func sample() -> Reading<ThermalReading> {
        .unavailable(.unsupported)
    }
}
