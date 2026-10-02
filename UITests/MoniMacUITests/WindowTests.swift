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
            XCTAssertTrue(staticText(group, in: window).exists, "The sidebar has no \(group) group")
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
        var seen: [String] = []
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
            XCTAssertTrue(waitUntil(timeout: 5) {
                self.text(of: peak).range(of: peakPattern, options: .regularExpression) != nil
            }, "\(format.range) peak label reads \"\(text(of: peak))\"")
            seen.append("\(format.range): \(text(of: peak)) · axis \(xAxis(window).joined(separator: ", "))")
        }
        XCTAssertNotEqual(axes["12H"], axes["24H"], "12H and 24H show the same axis")
        attach(seen.joined(separator: "\n"), named: "CPU history per range")
    }

    @MainActor
    private func xAxis(_ window: XCUIElement) -> [String] {
        window.staticTexts.matching(identifier: "cpu.history.xAxis").allElementsBoundByIndex.map { text(of: $0) }
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
        // If the user hid GPU, show it first (settings are restored after the test).
        if chip.label == "Show GPU" { chip.click() }
        XCTAssertTrue(waitUntil(timeout: 5) { chip.label == "Hide GPU" }, "The chip reads \"\(chip.label)\"")
        XCTAssertTrue(window.buttons["sidebar.gpu"].exists)

        chip.click()
        XCTAssertTrue(waitUntil(timeout: 5) { !window.buttons["sidebar.gpu"].exists }, "GPU is still in the sidebar")
        XCTAssertTrue(waitUntil(timeout: 5) { chip.label == "Show GPU" }, "The chip reads \"\(chip.label)\"")
        XCTAssertTrue((PreferenceDomain.isolated.value("layout.tabs.hidden") as? [String] ?? []).contains("gpu"))

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

        XCTAssertTrue(flip(toggle) { policy() == flipped }, "The Dock icon setting didn't take effect")
        XCTAssertTrue(flip(toggle) { policy() == initial }, "Turning it back didn't take effect")
    }

    /// Clicks a switch and waits for `done`. A click can be lost (the switch's value doesn't change), so a
    /// lost click is retried once; a click that changed the switch is never repeated.
    @MainActor
    private func flip(_ toggle: XCUIElement, until done: () -> Bool) -> Bool {
        for _ in 0..<2 {
            let before = toggle.value as? Int
            // The small switch can report "not hittable" while it is plainly visible, so click its center.
            toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).click()
            if waitUntil(timeout: 5, done) { return true }
            if toggle.value as? Int != before { return false }
        }
        return false
    }

    /// 09: hovering Power Draw, the "Watts (est.)" header, and an app's watts each shows a tooltip over
    /// MoniMac's window. The throwaway app keeps a core busy so at least one app shows watts.
    ///
    /// What it can't check: the tooltip's text ("Estimated …"). macOS exposes the tooltip to XCUITest as a
    /// help tag with a frame, but with no title, label, value, or children, and reading it from pixels needs
    /// a screenshot, which needs the screen capture the scheme turns off (see `MoniMacUITestCase`).
    /// `BatteryDetailTests` cover the text.
    @MainActor
    func testPowerFiguresShowTooltipsOnHover() throws {
        _ = try launchDummy()
        // A slower refresh: a tooltip that hasn't shown yet doesn't survive the re-render a refresh causes.
        let app = launchMoniMac(["--show-window", "--tab", "battery"], settings: ["general.refreshInterval": 5])
        let window = mainWindow(of: app)
        let powerDraw = staticText("Power Draw", in: window)
        XCTAssertTrue(powerDraw.waitForExistence(timeout: 10), "No Power Draw on the Battery tab")
        let header = staticText("Watts (est.)", in: window)
        XCTAssertTrue(header.waitForExistence(timeout: 10), "No Watts (est.) header")
        let watts = window.staticTexts.matching(identifier: "battery.energy.watts").firstMatch
        XCTAssertTrue(watts.waitForExistence(timeout: 30), "No app shows watts")
        var seen: [String] = []
        for (name, element) in [("Power Draw", powerDraw), ("Watts (est.)", header), ("App watts", watts)] {
            let tip = tooltipFrame(hovering: element, in: window, app: app)
            seen.append("\(name) at \(element.frame): tooltip at \(tip.map { "\($0)" } ?? "none")")
        }
        attach(seen.joined(separator: "\n"), named: "Tooltip frames")
    }

    /// Hovers `element` and returns the frame of the tooltip that appears next to it. A tooltip that hasn't
    /// shown yet doesn't survive a refresh, so the pointer moves off and back on, up to eight times.
    @MainActor
    private func tooltipFrame(hovering element: XCUIElement, in window: XCUIElement, app: XCUIApplication) -> CGRect? {
        // macOS puts a tooltip just below the pointer, which rests in the element's middle (near the
        // window's edge it can extend past the window).
        let target = element.frame
        let nearby = { () -> CGRect? in
            app.helpTags.allElementsBoundByIndex.map { $0.frame }.first {
                abs($0.minY - target.midY) < 60 && abs($0.minX - target.midX) < 300
            }
        }
        for _ in 0..<8 {
            // The empty sidebar between the tabs and Settings, where nothing has a tooltip.
            window.coordinate(withNormalizedOffset: CGVector(dx: 0.08, dy: 0.8)).hover()
            _ = waitUntil(timeout: 3) { nearby() == nil }
            // macOS shows tooltips only in the active app, and the throwaway app can take activation.
            app.activate()
            element.hover()
            var frame: CGRect?
            if waitUntil(timeout: 7, { frame = nearby(); return frame != nil }) { return frame }
        }
        XCTFail("No tooltip appeared next to \(target)")
        return nil
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
        light.click()
        XCTAssertTrue(waitUntil(timeout: 5) { self.isSelected(light) && !dark.isSelected })
    }

    /// 19: Save… writes a 1200×630 PNG where the save panel says.
    @MainActor
    func testShareCardSaveWrites1200x630PNG() throws {
        let directory = try outputDirectory()
        // The card shows the user's week, so it isn't left on disk.
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
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
        addTeardownBlock { @MainActor in
            saved.restore(to: pasteboard)
            XCTAssertTrue(saved.matches(pasteboard), "The pasteboard wasn't restored exactly")
        }

        let app = launchMoniMac(["--show-window"])
        let preview = try openShareCard(app)
        let before = pasteboard.changeCount
        preview.buttons["shareCard.copy"].click()
        XCTAssertTrue(waitUntil(timeout: 5) { pasteboard.changeCount != before }, "Copy didn't change the pasteboard")
        XCTAssertTrue(staticText("Copied", in: preview).waitForExistence(timeout: 5))
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
        // Opening renders both cards from a week of history first, which can take a while.
        XCTAssertTrue(preview.waitForExistence(timeout: 30), "The share card preview didn't open")
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

    /// Whether the pasteboard holds exactly these items, types, and bytes again.
    func matches(_ pasteboard: NSPasteboard) -> Bool {
        let current = (pasteboard.pasteboardItems ?? []).map { item in
            item.types.compactMap { type in item.data(forType: type).map { (type, $0) } }
        }
        let asDictionary = { (types: [(NSPasteboard.PasteboardType, Data)]) in
            Dictionary(types, uniquingKeysWith: { first, _ in first })
        }
        return current.count == items.count
            && zip(current, items).allSatisfy { asDictionary($0) == asDictionary($1) }
    }
}
