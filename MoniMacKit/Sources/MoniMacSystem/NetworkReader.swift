import Foundation
import MoniMacCore

/// Reads network for each snapshot. Filled in by ticket 07.
@MainActor
final class NetworkReader {
    func sample() -> Reading<NetworkReading> {
        .unavailable(.unsupported)
    }

    /// Adds per-process network figures (`ResourceUse.network`) to the process list.
    /// Called only when the process list is refreshed (every few seconds), never with a stale list.
    func annotate(_ processes: Reading<[ProcessSample]>) -> Reading<[ProcessSample]> {
        processes
    }
}
