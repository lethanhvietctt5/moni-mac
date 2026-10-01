import Foundation
import Testing
import MoniMacCore
@testable import MoniMacSystem

/// Runs against the real Mac.
struct SystemInfoReaderSmokeTests {
    @Test func readsTheMarketingNameWithoutTheYear() throws {
        let name = try #require(SystemInfoReader.modelName(), "Apple silicon Macs report product-name")
        #expect(name.hasPrefix("Mac"))
        #expect(!name.contains("("))
    }

    @Test func marketingNameDropsTheParenthetical() {
        #expect(SystemInfoReader.marketingName("MacBook Pro (14-inch, Nov 2024)") == "MacBook Pro")
        #expect(SystemInfoReader.marketingName("Mac mini") == "Mac mini")
        #expect(SystemInfoReader.marketingName(" (2024)") == nil)
    }
}
