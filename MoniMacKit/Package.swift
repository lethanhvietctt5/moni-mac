// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MoniMacKit",
    platforms: [.macOS("14.2")],
    products: [
        .library(name: "MoniMacCore", targets: ["MoniMacCore"]),
        .library(name: "MoniMacSystem", targets: ["MoniMacSystem"]),
    ],
    targets: [
        // Pure logic: snapshots, the sampler seam, math, formatting, feature state. No OS reads.
        .target(name: "MoniMacCore"),
        // The real SystemSampler. The only target that reads OS state.
        .target(name: "MoniMacSystem", dependencies: ["MoniMacCore"]),
        .testTarget(name: "MoniMacCoreTests", dependencies: ["MoniMacCore"]),
        // Smoke tests against real hardware.
        .testTarget(name: "MoniMacSystemTests", dependencies: ["MoniMacSystem"]),
    ]
)
