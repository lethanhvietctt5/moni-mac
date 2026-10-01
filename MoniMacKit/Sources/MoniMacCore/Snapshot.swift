import Foundation

/// Everything SystemSampler read from the OS on one refresh tick. Immutable.
public struct Snapshot: Equatable, Sendable {
    public var timestamp: Date
    public var cpu: Reading<CPUUsage>

    public init(timestamp: Date, cpu: Reading<CPUUsage>) {
        self.timestamp = timestamp
        self.cpu = cpu
    }
}

/// A sampled value, or the reason it is missing. Missing data is never reported as zero.
public enum Reading<Value: Equatable & Sendable>: Equatable, Sendable {
    case value(Value)
    case unavailable(UnavailableReason)

    public var value: Value? {
        if case .value(let value) = self { value } else { nil }
    }
}

public enum UnavailableReason: Equatable, Sendable {
    /// The value needs two samples (e.g. a rate) and only one has been taken.
    case warmingUp
    /// This Mac doesn't have the hardware or the OS doesn't expose it.
    case unsupported
    /// The OS refused or the read failed.
    case failed(String)
}
