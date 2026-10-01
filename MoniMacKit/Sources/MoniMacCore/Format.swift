/// Compact display strings shared by every surface.
public enum Format {
    /// Shown wherever a value is unavailable.
    public static let placeholder = "—"

    /// A 0...1 fraction as a whole percentage, e.g. `0.317` → `"32%"`.
    public static func percent(_ fraction: Double) -> String {
        let clamped = min(max(fraction, 0), 1)
        return "\(Int((clamped * 100).rounded()))%"
    }
}
