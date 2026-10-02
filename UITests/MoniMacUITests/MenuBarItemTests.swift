import XCTest

/// Tickets 05, 07, 10: Memory, Network, and Temperature menu bar items can be shown next to CPU.
final class MenuBarItemTests: MoniMacUITestCase {
    /// The items are turned on for this launch only, through launch arguments (the argument domain), so
    /// the user's settings are never written.
    @MainActor
    func testMemoryNetworkAndTemperatureItemsCanBeShown() throws {
        let metrics = ["cpu", "memory", "network", "temperature"]
        let arguments = metrics.flatMap { ["-menuBar.\($0).enabled", "<true/>", "-menuBar.\($0).style", "value"] }
        let app = launchMoniMac(arguments)
        // Each item's text: CPU "12%", Memory "8.2 GB", Network "1.2 MB/s", Temperature "58°C".
        let formats = [
            "cpu": #"^\d+(\.\d+)?%$"#,
            "memory": #"^\d+(\.\d+)? (GB|MB|TB)$"#,
            "network": #"^\d+(\.\d+)? ([KMG]?B/s|[KMG]?bps)$"#,
            "temperature": #"^\d+°[CF]$"#,
        ]
        var titles: [String: String] = [:]
        XCTAssertTrue(waitUntil(timeout: 20) {
            titles = self.statusItemTitles(app)
            return formats.allSatisfy { metric, format in
                titles[metric].map { $0.range(of: format, options: .regularExpression) != nil } ?? false
            }
        }, "Status items read \(titles); all items: \(app.statusItems.allElementsBoundByIndex.map(\.debugDescription))")
        let attachment = XCTAttachment(string: titles.sorted { $0.key < $1.key }.map { "\($0): \($1)" }
            .joined(separator: "\n"))
        attachment.name = "Status item titles"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// MoniMac's status items by metric (the button's identifier), with their titles.
    @MainActor
    private func statusItemTitles(_ app: XCUIApplication) -> [String: String] {
        var titles: [String: String] = [:]
        for item in app.statusItems.allElementsBoundByIndex where !item.identifier.isEmpty {
            titles[item.identifier] = item.title.isEmpty ? (item.value as? String ?? item.label) : item.title
        }
        return titles
    }
}
