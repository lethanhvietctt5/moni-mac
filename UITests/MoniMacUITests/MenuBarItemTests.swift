import XCTest

/// Tickets 05, 07, 10: Memory, Network, and Temperature menu bar items can be shown next to CPU.
final class MenuBarItemTests: MoniMacUITestCase {
    /// The items are turned on for this launch only, through launch arguments (the argument domain), so
    /// the user's settings are never written.
    @MainActor
    func testMemoryNetworkAndTemperatureItemsCanBeShown() throws {
        let metrics = ["cpu", "memory", "network", "temperature"]
        // GPU is turned off, so its "%" can't be mistaken for CPU's.
        let arguments = metrics.flatMap { ["-menuBar.\($0).enabled", "<true/>", "-menuBar.\($0).style", "value"] }
            + ["-menuBar.gpu.enabled", "<false/>"]
        let app = launchMoniMac(arguments)
        // Each item's text: CPU "12%", Memory "8.2 GB", Network "1.2 MB/s", Temperature "58°C".
        let formats = [
            "cpu": #"^\d+(\.\d+)?%$"#,
            "memory": #"^\d+(\.\d+)? (GB|MB|TB)$"#,
            "network": #"^\d+(\.\d+)? ([KMG]?B/s|[KMG]?bps)$"#,
            "temperature": #"^\d+°[CF]$"#,
        ]
        // Status items expose their title but not the button's identifier, so each metric is told apart by
        // its format: exactly one of MoniMac's items must match each.
        var titles: [String] = []
        XCTAssertTrue(waitUntil(timeout: 20) {
            titles = app.statusItems.allElementsBoundByIndex.map { $0.title }
            return titles.count == formats.count && formats.values.allSatisfy { format in
                titles.filter { $0.range(of: format, options: .regularExpression) != nil }.count == 1
            }
        }, "MoniMac's status items read \(titles)")
        let attachment = XCTAttachment(string: formats.keys.sorted().map { metric in
            "\(metric): \(titles.first { $0.range(of: formats[metric]!, options: .regularExpression) != nil } ?? "-")"
        }.joined(separator: "\n"))
        attachment.name = "Status item titles"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
