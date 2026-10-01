import Foundation
import MoniMacCore

/// Reads disk for each snapshot. Filled in by ticket 08.
@MainActor
final class DiskReader {
    func sample() -> Reading<DiskReading> {
        .unavailable(.unsupported)
    }
}
