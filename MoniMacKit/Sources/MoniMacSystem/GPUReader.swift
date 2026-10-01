import Foundation
import MoniMacCore

/// Reads gpu for each snapshot. Filled in by ticket 06.
@MainActor
final class GPUReader {
    func sample() -> Reading<GPUReading> {
        .unavailable(.unsupported)
    }

    /// Adds per-process gpu figures (`ResourceUse.gpu`) to the process list.
    /// Called only when the process list is refreshed (every few seconds), never with a stale list.
    func annotate(_ processes: Reading<[ProcessSample]>) -> Reading<[ProcessSample]> {
        processes
    }
}
