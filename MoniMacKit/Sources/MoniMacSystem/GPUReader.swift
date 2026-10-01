import Foundation
import MoniMacCore

/// Reads gpu for each snapshot. Filled in by ticket 06.
@MainActor
final class GPUReader {
    func sample() -> Reading<GPUReading> {
        .unavailable(.unsupported)
    }

    /// Adds per-process gpu figures to the process list.
    func annotate(_ processes: Reading<[ProcessSample]>) -> Reading<[ProcessSample]> {
        processes
    }
}
