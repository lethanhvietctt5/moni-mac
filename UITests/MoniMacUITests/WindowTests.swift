import AppKit
import XCTest

/// The main window (tickets 04, 09, 12, 13, 19).
final class WindowTests: MoniMacUITestCase {
    /// 04: the sidebar shows the grouped tabs, and selecting a tab switches the content.
    @MainActor
    func testSidebarSwitchesTabs() throws {
        let app = launchMoniMac(["--show-window"])
        let window = mainWindow(of: app)
        for group in ["Monitor", "Devices", "Developer"] {
            XCTAssertTrue(window.staticTexts[group].exists, "The sidebar has no \(group) group")
        }
        let tabs = [("cpu", "CPU"), ("memory", "Memory"), ("gpu", "GPU"), ("network", "Network"), ("disk", "Disk"),
                    ("temperature", "Temperature & Fans"), ("projects", "Projects"), ("settings", "Settings"),
                    ("overview", "Overview")]
        for (id, title) in tabs {
            let item = window.buttons["sidebar.\(id)"]
            XCTAssertTrue(item.exists, "No \(title) tab in the sidebar")
            item.click()
            XCTAssertTrue(waitUntil(timeout: 5) { self.windowTitle(window) == title },
                          "The window shows \(windowTitle(window)), not \(title)")
            XCTAssertTrue(isSelected(item), "\(title) isn't highlighted in the sidebar")
        }
        window.buttons["sidebar.memory"].click()
        XCTAssertTrue(waitUntil(timeout: 5) { self.windowTitle(window) == "Memory" })
        attachScreenshot(of: window, named: "Memory tab after switching")
    }

    /// 04: the CPU history chart switches between 12H/24H/7D/30D, with axes and a peak label per range.
    @MainActor
    func testCPUHistoryRangesSwitchChartAndPeakLabel() throws {
        let app = launchMoniMac(["--show-window", "--tab", "cpu"])
        let window = mainWindow(of: app)
        XCTAssertEqual(windowTitle(window), "CPU")
        XCTAssertTrue(isSelected(window.buttons["cpu.history.range.24H"]), "24H is the default range")

        // Each range's axis labels and peak time have their own format (see `Format.time`).
        let hourMinute = #"\d{2}:\d{2}"#
        let formats: [(range: String, axis: String, peakTime: String)] = [
            ("12H", hourMinute, hourMinute),
            ("7D", #"(Mon|Tue|Wed|Thu|Fri|Sat|Sun)"#, #"(Mon|Tue|Wed|Thu|Fri|Sat|Sun) \#(hourMinute)"#),
            ("30D", #"\d{1,2} [A-Z][a-z]{2}"#, #"\d{1,2} [A-Z][a-z]{2}"#),
            ("24H", hourMinute, hourMinute),
        ]
        var axes: [String: [String]] = [:]
        for format in formats {
            let button = window.buttons["cpu.history.range.\(format.range)"]
            button.click()
            XCTAssertTrue(waitUntil(timeout: 5) { self.isSelected(button) }, "\(format.range) isn't selected")
            let axisPattern = "^\(format.axis)$"
            XCTAssertTrue(waitUntil(timeout: 5) {
                let labels = self.xAxis(window)
                return labels.count == 5 && labels.last == "Now"
                    && labels.dropLast().allSatisfy { $0.range(of: axisPattern, options: .regularExpression) != nil }
            }, "\(format.range) axis reads \(xAxis(window))")
            axes[format.range] = xAxis(window)
            for other in ["12H", "24H", "7D", "30D"] where other != format.range {
                XCTAssertFalse(window.buttons["cpu.history.range.\(other)"].isSelected)
            }
            let peak = window.staticTexts["cpu.history.peak"]
            XCTAssertTrue(peak.waitForExistence(timeout: 5), "No peak label for \(format.range)")
            let peakPattern = #"^Peak \d+(\.\d+)?% at "# + format.peakTime + "$"
            XCTAssertTrue(waitUntil(timeout: 5) { peak.label.range(of: peakPattern, options: .regularExpression) != nil },
                          "\(format.range) peak label reads \"\(peak.label)\"")
            attachScreenshot(of: window, named: "CPU history \(format.range)")
        }
        XCTAssertNotEqual(axes["12H"], axes["24H"], "12H and 24H show the same axis")
    }

    @MainActor
    private func xAxis(_ window: XCUIElement) -> [String] {
        window.staticTexts.matching(identifier: "cpu.history.xAxis").allElementsBoundByIndex.map { $0.label }
    }

    /// 12: "Show All" in a tab's Top Apps opens Overview › List sorted by that tab's metric.
    @MainActor
    func testShowAllOpensListSortedByThatMetric() throws {
        let app = launchMoniMac(["--show-window", "--tab", "cpu"])
        let window = mainWindow(of: app)
        let metrics = [("memory", "Memory"), ("gpu", "GPU"), ("network", "Network"), ("disk", "Disk"), ("cpu", "CPU")]
        for (id, title) in metrics {
            window.buttons["sidebar.\(id)"].click()
            XCTAssertTrue(waitUntil(timeout: 5) { self.windowTitle(window) == title })
            let showAll = window.buttons["showAll.\(id)"]
            XCTAssertTrue(showAll.waitForExistence(timeout: 10), "No Show All in the \(title) tab")
            showAll.click()
            XCTAssertTrue(waitUntil(timeout: 5) { self.windowTitle(window) == "Overview" },
                          "Show All in \(title) opened \(windowTitle(window))")
            XCTAssertTrue(window.textFields["Search apps and processes"].waitForExistence(timeout: 5),
                          "Show All in \(title) didn't open the List view")
            let header = window.buttons["overviewList.header.\(id)"]
            XCTAssertTrue(waitUntil(timeout: 5) { self.isSelected(header) },
                          "The List isn't sorted by \(title) after Show All in \(title)")
            for other in metrics.map(\.0) where other != id {
                XCTAssertFalse(window.buttons["overviewList.header.\(other)"].isSelected)
            }
            if id == "memory" { attachScreenshot(of: window, named: "List sorted by Memory") }
        }
    }

    /// 13: hiding a tab with its chip drops it from the sidebar, the chip shows +, and clicking it again
    /// brings the tab back.
    @MainActor
    func testTabChipHidesAndRestoresSidebarTab() throws {
        let app = launchMoniMac(["--show-window", "--tab", "settings"])
        let window = mainWindow(of: app)
        let chip = window.buttons["settings.tabChip.gpu"]
        XCTAssertTrue(chip.waitForExistence(timeout: 10))
        XCTAssertEqual(chip.label, "Hide GPU", "GPU should start shown")
        XCTAssertTrue(window.buttons["sidebar.gpu"].exists)

        chip.click()
        XCTAssertTrue(waitUntil(timeout: 5) { !window.buttons["sidebar.gpu"].exists }, "GPU is still in the sidebar")
        XCTAssertTrue(waitUntil(timeout: 5) { chip.label == "Show GPU" }, "The chip reads \"\(chip.label)\"")
        XCTAssertEqual(MoniMacSettings.value("layout.tabs.hidden") as? [String], ["gpu"])
        attachScreenshot(of: window, named: "GPU hidden")

        chip.click()
        XCTAssertTrue(waitUntil(timeout: 5) { window.buttons["sidebar.gpu"].exists }, "GPU didn't come back")
        XCTAssertTrue(waitUntil(timeout: 5) { chip.label == "Hide GPU" })
    }

    /// 13: the "Show icon in Dock" switch changes MoniMac's activation policy, and back.
    @MainActor
    func testShowIconInDockTakesEffect() throws {
        let app = launchMoniMac(["--show-window", "--tab", "settings"])
        let window = mainWindow(of: app)
        let toggle = window.descendants(matching: .any)["settings.showsDockIcon"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 10))
        let policy = { () -> NSApplication.ActivationPolicy? in
            // A fresh instance each time, so the policy isn't a cached value.
            NSRunningApplication.runningApplications(withBundleIdentifier: Self.bundleID).first
                .flatMap { NSRunningApplication(processIdentifier: $0.processIdentifier) }?.activationPolicy
        }
        let initial = try XCTUnwrap(policy())
        let flipped: NSApplication.ActivationPolicy = initial == .regular ? .accessory : .regular

        toggle.click()
        XCTAssertTrue(waitUntil(timeout: 5) { policy() == flipped }, "The Dock icon setting didn't take effect")
        toggle.click()
        XCTAssertTrue(waitUntil(timeout: 5) { policy() == initial }, "Turning it back didn't take effect")
    }

    /// 09: Power Draw and an app's watts show "estimate" tooltips on hover. The throwaway app keeps a core
    /// busy so at least one app shows watts.
    @MainActor
    func testPowerFiguresShowEstimateTooltips() throws {
        _ = try launchDummy(spinning: true)
        let app = launchMoniMac(["--show-window", "--tab", "battery"])
        let window = mainWindow(of: app)
        let powerDraw = window.staticTexts["Power Draw"]
        XCTAssertTrue(powerDraw.waitForExistence(timeout: 10), "No Power Draw on the Battery tab")
        let drawTip = tooltip(hovering: powerDraw, in: app)
        XCTAssertTrue(drawTip.contains("Estimated"), "Power Draw's tooltip reads \"\(drawTip)\"")

        let watts = window.staticTexts.matching(identifier: "battery.energy.watts").firstMatch
        XCTAssertTrue(watts.waitForExistence(timeout: 30), "No app shows watts")
        // Move off and back so the next tooltip is a fresh one.
        window.staticTexts["window.title"].hover()
        let appTip = tooltip(hovering: watts, in: app)
        XCTAssertTrue(appTip.contains("Estimated"), "An app's watts tooltip reads \"\(appTip)\"")
    }

    /// Hovers `element` and returns the tooltip macOS shows, or "" if none is reachable.
    @MainActor
    private func tooltip(hovering element: XCUIElement, in app: XCUIApplication) -> String {
        element.hover()
        let tag = app.descendants(matching: .helpTag).firstMatch
        guard tag.waitForExistence(timeout: 5) else {
            XCTContext.runActivity(named: "No help tag after hovering") { activity in
                let attachment = XCTAttachment(string: app.debugDescription)
                attachment.name = "Hierarchy"
                activity.add(attachment)
            }
            return ""
        }
        let text = [tag.label, tag.value as? String ?? "", tag.title].first { !$0.isEmpty } ?? ""
        return text
    }

    // MARK: Share card (19)

    /// 19: the toolbar's share button opens the preview with a Light/Dark choice.
    @MainActor
    func testShareButtonOpensPreviewWithLightDarkChoice() throws {
        let app = launchMoniMac(["--show-window"])
        let preview = try openShareCard(app)
        let light = preview.buttons["shareCard.appearance.Light"]
        let dark = preview.buttons["shareCard.appearance.Dark"]
        XCTAssertTrue(light.exists && dark.exists, "No Light/Dark choice")
        dark.click()
        XCTAssertTrue(waitUntil(timeout: 5) { self.isSelected(dark) && !light.isSelected })
        attachScreenshot(of: preview, named: "Share card dark")
        light.click()
        XCTAssertTrue(waitUntil(timeout: 5) { self.isSelected(light) && !dark.isSelected })
        attachScreenshot(of: preview, named: "Share card light")
    }

    /// 19: Save… writes a 1200×630 PNG where the save panel says.
    @MainActor
    func testShareCardSaveWrites1200x630PNG() throws {
        let directory = try outputDirectory()
        let app = launchMoniMac(["--show-window"])
        let preview = try openShareCard(app)
        preview.buttons["shareCard.save"].click()
        let panel = preview.sheets.firstMatch
        XCTAssertTrue(panel.waitForExistence(timeout: 10), "The save panel didn't open")
        // "/" in the name field opens Go to Folder; the name stays "MoniMac Week.png".
        panel.typeText("/")
        RunLoop.current.run(until: Date().addingTimeInterval(1))
        app.typeKey("a", modifierFlags: .command)
        app.typeText(directory.path + "\n")
        RunLoop.current.run(until: Date().addingTimeInterval(1))
        panel.buttons["Save"].click()

        let file = directory.appending(path: "MoniMac Week.png")
        XCTAssertTrue(waitUntil(timeout: 10) { FileManager.default.fileExists(atPath: file.path) },
                      "Nothing was saved at \(file.path)")
        let size = try pixelSize(of: Data(contentsOf: file))
        XCTAssertEqual(size.width, 1200)
        XCTAssertEqual(size.height, 630)
    }

    /// 19: Copy puts a 1200×630 image on the pasteboard. The pasteboard belongs to the user: its items are
    /// kept in memory, put back exactly afterwards, and never logged or attached.
    @MainActor
    func testShareCardCopyPuts1200x630ImageOnPasteboard() throws {
        let pasteboard = NSPasteboard.general
        // Reading another app's pasteboard data shows a system alert unless the runner may always paste.
        if #available(macOS 15.4, *), pasteboard.accessBehavior != .alwaysAllow {
            throw XCTSkip("""
                The test runner may not read the pasteboard without an alert (access: \
                \(pasteboard.accessBehavior.rawValue)). Allow MoniMacUITests-Runner in System Settings › \
                Privacy & Security › Paste from Other Apps to run this test.
                """)
        }
        let saved = PasteboardSnapshot(pasteboard)
        addTeardownBlock { @MainActor in saved.restore(to: pasteboard) }

        let app = launchMoniMac(["--show-window"])
        let preview = try openShareCard(app)
        let before = pasteboard.changeCount
        preview.buttons["shareCard.copy"].click()
        XCTAssertTrue(waitUntil(timeout: 5) { pasteboard.changeCount != before }, "Copy didn't change the pasteboard")
        XCTAssertTrue(preview.staticTexts["Copied"].waitForExistence(timeout: 5))
        let png = try XCTUnwrap(pasteboard.data(forType: .png), "No PNG on the pasteboard")
        let size = try pixelSize(of: png)
        XCTAssertEqual(size.width, 1200)
        XCTAssertEqual(size.height, 630)
    }

    @MainActor
    private func openShareCard(_ app: XCUIApplication) throws -> XCUIElement {
        let window = mainWindow(of: app)
        let share = window.buttons["toolbar.share"]
        XCTAssertEqual(share.label, "Share your week")
        share.click()
        let preview = app.windows["Share Your Week"]
        XCTAssertTrue(preview.waitForExistence(timeout: 10), "The share card preview didn't open")
        return preview
    }

    /// Where Save… writes: a fresh folder (so the panel never asks to replace a file) under
    /// `MONIMAC_UITEST_OUTPUT` (pass `TEST_RUNNER_MONIMAC_UITEST_OUTPUT` to xcodebuild) or `/private/tmp`.
    /// The sandboxed runner may write only under `/private/tmp` (see the entitlements).
    private func outputDirectory() throws -> URL {
        let base = URL(fileURLWithPath: ProcessInfo.processInfo.environment["MONIMAC_UITEST_OUTPUT"] ?? "/private/tmp")
        let directory = base.appending(path: "share-card-\(UUID().uuidString.prefix(8))")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.resolvingSymlinksInPath()
    }

    private func pixelSize(of data: Data) throws -> (width: Int, height: Int) {
        let image = try XCTUnwrap(NSBitmapImageRep(data: data), "Not an image")
        return (image.pixelsWide, image.pixelsHigh)
    }
}

/// Every item on a pasteboard with all its types' data, held in memory only.
struct PasteboardSnapshot {
    private let items: [[(NSPasteboard.PasteboardType, Data)]]

    init(_ pasteboard: NSPasteboard) {
        items = (pasteboard.pasteboardItems ?? []).map { item in
            item.types.compactMap { type in item.data(forType: type).map { (type, $0) } }
        }
    }

    func restore(to pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        let restored = items.map { types in
            let item = NSPasteboardItem()
            for (type, data) in types { item.setData(data, forType: type) }
            return item
        }
        if !restored.isEmpty { pasteboard.writeObjects(restored) }
    }
}
