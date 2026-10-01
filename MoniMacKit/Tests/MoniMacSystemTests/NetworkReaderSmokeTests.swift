import Foundation
import Testing
import MoniMacCore
@testable import MoniMacSystem

/// Runs against the real Mac. Checks fields are present and in range, not exact values.
@MainActor
struct NetworkReaderSmokeTests {
    @Test func secondSampleReportsRatesAndTheActiveInterface() async throws {
        let reader = NetworkReader()
        #expect(reader.sample() == .unavailable(.warmingUp))
        try await Task.sleep(for: .seconds(1))

        let network = try #require(reader.sample().value)

        #expect(network.downloadPerSecond >= 0 && network.uploadPerSecond >= 0)
        #expect(network.received >= 0 && network.sent >= 0)
        // Rates are amounts over roughly the one-second gap.
        #expect(network.received <= network.downloadPerSecond * 2)
        // This Mac is online while tests run; the interface has a user-facing name.
        let interface = try #require(network.interface)
        #expect(!interface.name.isEmpty)
        #expect(interface.linkRate.map { $0 >= 1_000_000 } ?? true)
    }

    @Test func nettopReportsPerProcessRates() async throws {
        let reader = NetworkProcessReader(interval: 0)
        for _ in 0..<2 {
            reader.refreshIfDue()
            for _ in 0..<50 where !reader.isIdle { try await Task.sleep(for: .milliseconds(100)) }
        }

        let rates = try #require(reader.latest())
        #expect(!rates.isEmpty)
        #expect(rates.values.allSatisfy { $0 >= 0 })
    }

    @Test func parsesNettopRowsFromTheRight() {
        let output = """
            ,bytes_in,bytes_out,
            mDNSResponder.679,94737586,37610006,
            Google Chrome H.4273,209018937,11134309,
            2.1.286.17426,984581,71753647,
            odd,name.12,5,6,
            garbage
            """

        #expect(NetworkProcessReader.parse(output) == [
            679: 94_737_586 + 37_610_006, 4273: 209_018_937 + 11_134_309, 17426: 984_581 + 71_753_647, 12: 11,
        ])
    }

    @Test func ratesAreDeltasAndNeverNegative() {
        let rates = NetworkProcessReader.rates(from: [1: 1000, 2: 5000], to: [1: 9000, 2: 100, 3: 700], seconds: 4)

        #expect(rates == [1: 2000, 2: 0])
    }

    @Test(arguments: [
        (7, 2, "Wi-Fi 7"), (6, 3, "Wi-Fi 6E"), (6, 2, "Wi-Fi 6"), (5, 2, "Wi-Fi 5"), (4, 1, "Wi-Fi 4"), (3, 1, "Wi-Fi"),
    ])
    func namesTheWiFiGeneration(phyMode: Int, band: Int, name: String) {
        #expect(NetworkReader.wifiName(phyMode: phyMode, band: band) == name)
    }
}
