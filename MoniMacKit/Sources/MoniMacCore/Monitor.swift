import Observation

/// Drives sampling and exposes the feature state every surface renders.
@MainActor
@Observable
public final class Monitor {
    public private(set) var latest: Snapshot?

    @ObservationIgnored private let sampler: any SystemSampler

    public init(sampler: any SystemSampler) {
        self.sampler = sampler
    }

    public var menuBarItems: [MenuBarItem] {
        [.cpu(latest)]
    }

    /// Takes one sample. The refresh loop calls this; tests call it directly.
    public func tick() {
        latest = sampler.sample()
    }

    /// Samples immediately, then every `interval`, until the task is cancelled.
    public func run(every interval: Duration) async {
        while !Task.isCancelled {
            tick()
            try? await Task.sleep(for: interval)
        }
    }
}
