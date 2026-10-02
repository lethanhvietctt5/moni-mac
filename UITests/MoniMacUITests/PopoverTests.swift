import AppKit
import XCTest

/// The popover (tickets 03, 04, 12). It's opened with `--show-popover`, because the status item may sit
/// under the notch where no click can reach it.
final class PopoverTests: MoniMacUITestCase {
    /// 03: the range buttons switch the CPU chart between 1m, 5m, 1H, and 24H.
    @MainActor
    func testRangeButtonsSwitchPopoverChart() throws {
        let app = launchMoniMac(["--show-popover", "--tab", "cpu"])
        let popover = popover(of: app)
        let chart = popover.descendants(matching: .any)["cpu.popover.chart"]
        XCTAssertTrue(chart.waitForExistence(timeout: 10))
        XCTAssertTrue(isSelected(popover.buttons["cpu.range.5m"]), "5m is the default range")
        XCTAssertEqual(chart.value as? String, "5m")

        for range in ["1m", "1H", "24H", "5m"] {
            popover.buttons["cpu.range.\(range)"].click()
            XCTAssertTrue(waitUntil(timeout: 5) { self.isSelected(popover.buttons["cpu.range.\(range)"]) },
                          "\(range) isn't selected after clicking it")
            XCTAssertTrue(waitUntil(timeout: 5) { chart.value as? String == range },
                          "The chart shows \(chart.value ?? "nothing"), not \(range)")
            for other in ["1m", "5m", "1H", "24H"] where other != range {
                XCTAssertFalse(popover.buttons["cpu.range.\(other)"].isSelected)
            }
            attachScreenshot(of: popover, named: "Popover CPU \(range)")
        }
    }

    /// 03: "Quit MoniMac" in the popover's footer quits MoniMac.
    @MainActor
    func testQuitMoniMacQuitsTheApp() throws {
        let app = launchMoniMac(["--show-popover"])
        popover(of: app).buttons["popover.quit"].click()
        XCTAssertTrue(app.wait(for: .notRunning, timeout: 10), "MoniMac is still running")
    }

    /// 03: the CPU tab's "Activity Monitor" link opens Activity Monitor. If Activity Monitor wasn't running
    /// before, the test quits it afterwards; if it was, it's left alone.
    @MainActor
    func testActivityMonitorLinkOpensActivityMonitor() throws {
        let activityMonitor = "com.apple.ActivityMonitor"
        let running = { NSRunningApplication.runningApplications(withBundleIdentifier: activityMonitor) }
        let wasRunning = !running().isEmpty
        addTeardownBlock { @MainActor in
            guard !wasRunning else { return }
            for app in running() { app.terminate() }
        }
        let app = launchMoniMac(["--show-popover", "--tab", "cpu"])
        let link = popover(of: app).buttons["cpu.activityMonitor"]
        XCTAssertTrue(link.waitForExistence(timeout: 10))
        link.click()
        XCTAssertTrue(waitUntil(timeout: 15) { !running().isEmpty },
                      "Activity Monitor didn't open")
        XCTAssertTrue(app.state != .notRunning, "MoniMac quit")
    }

    /// 04: the popover header's window button opens the main window.
    @MainActor
    func testOpenWindowButtonOpensMainWindow() throws {
        let app = launchMoniMac(["--show-popover"])
        let button = popover(of: app).buttons["popover.openWindow"]
        XCTAssertEqual(button.label, "Open MoniMac")
        button.click()
        let window = mainWindow(of: app)
        XCTAssertFalse(app.popovers.firstMatch.exists, "The popover stayed open")
        // The window opens on its current tab: Overview, the first tab, on a fresh launch.
        XCTAssertEqual(windowTitle(window), "Overview")
        attachScreenshot(of: window, named: "Window from the popover button")
    }

    /// 04 / 11: the popover Overview tab's "Open MoniMac" link opens the main window.
    @MainActor
    func testOverviewOpenMoniMacLinkOpensMainWindow() throws {
        let app = launchMoniMac(["--show-popover", "--tab", "overview"])
        let link = popover(of: app).buttons["overview.openWindow"]
        XCTAssertTrue(link.waitForExistence(timeout: 10))
        link.click()
        let window = mainWindow(of: app)
        XCTAssertEqual(windowTitle(window), "Overview")
    }

    /// 12: the popover × opens the quit sheet instead of quitting. Only Cancel is pressed, on the
    /// throwaway app's row, and the app keeps running.
    @MainActor
    func testPopoverQuitButtonOpensQuitSheetAndCancelKeepsAppRunning() throws {
        let dummy = try launchDummy(spinning: true)
        let app = launchMoniMac(["--show-popover", "--tab", "cpu"])
        let sheet = try openQuitSheetFromPopover(app)
        attachScreenshot(of: sheet, named: "Quit sheet from the popover")
        sheet.buttons["quitSheet.cancel"].click()
        XCTAssertTrue(waitUntil(timeout: 5) { !sheet.exists }, "The quit sheet stayed open")
        RunLoop.current.run(until: Date().addingTimeInterval(2))
        XCTAssertFalse(dummy.isTerminated, "Cancel quit the app")
    }

    /// 03: pressing × on an app and then the sheet's Quit quits that app (the throwaway app only).
    @MainActor
    func testPopoverQuitButtonThenQuitQuitsTheApp() throws {
        let dummy = try launchDummy(spinning: true)
        let app = launchMoniMac(["--show-popover", "--tab", "cpu"])
        let sheet = try openQuitSheetFromPopover(app)
        sheet.buttons["quitSheet.quit"].click()
        XCTAssertTrue(waitUntil(timeout: 15) { dummy.isTerminated }, "The app didn't quit")
        XCTAssertTrue(app.state != .notRunning, "MoniMac quit too")
    }

    /// Presses × on the throwaway app's row in the popover's Top Apps and returns the quit sheet, after
    /// checking it names the throwaway app. Any other sheet is cancelled and the test fails, so a test
    /// can never quit one of the user's apps.
    @MainActor
    private func openQuitSheetFromPopover(_ app: XCUIApplication) throws -> XCUIElement {
        let popover = popover(of: app)
        // The spinning app reaches Top Apps after two process samples (4 s apart).
        let quit = popover.buttons.matching(identifier: "cpu.topApps.quit")
            .matching(NSPredicate(format: "label == %@", "Quit \(Self.dummyName)")).firstMatch
        XCTAssertTrue(quit.waitForExistence(timeout: 30), "\(Self.dummyName) didn't reach Top Apps by CPU")
        attachScreenshot(of: popover, named: "Popover with the throwaway app")
        quit.click()
        let title = app.staticTexts["quitSheet.title"]
        XCTAssertTrue(title.waitForExistence(timeout: 10), "The quit sheet didn't open")
        let sheet = app.windows.containing(.staticText, identifier: "quitSheet.title").firstMatch
        guard title.label.contains(Self.dummyName) else {
            sheet.buttons["quitSheet.cancel"].click()
            XCTFail("The quit sheet is for \"\(title.label)\", not the throwaway app; cancelled")
            throw XCTSkip("Wrong quit sheet")
        }
        XCTAssertFalse(app.popovers.firstMatch.exists, "The popover stayed open behind the sheet")
        return sheet
    }
}
