/// Seam 1: the only way MoniMac reads OS state. Called once per refresh tick.
///
/// The real implementation lives in MoniMacSystem; tests use a scripted fake.
public protocol SystemSampler: AnyObject {
    func sample() -> Snapshot
}
