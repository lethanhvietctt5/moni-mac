import Foundation
import MoniMacCore

/// Reads network for each snapshot. Filled in by ticket 07.
@MainActor
final class NetworkReader {
    func sample() -> Reading<NetworkReading> {
        .unavailable(.unsupported)
    }

    /// Adds per-process network figures to the process list.
    func annotate(_ processes: Reading<[ProcessSample]>) -> Reading<[ProcessSample]> {
        processes
    }
}
