import Foundation
import MoniMacCore

/// Reads memory for each snapshot. Filled in by ticket 05.
@MainActor
final class MemoryReader {
    func sample() -> Reading<MemoryReading> {
        .unavailable(.unsupported)
    }
}
