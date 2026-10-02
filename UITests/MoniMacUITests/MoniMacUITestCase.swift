import AppKit
import XCTest

/// Shared plumbing for the UI tests. Every test launches MoniMac through `launchMoniMac`, which:
/// - always passes `--mute-notifications`, so no permission prompt or banner appears;
/// - snapshots MoniMac's settings and restores them exactly once MoniMac has quit, even on failure.
///
/// Screenshots come only from `XCUIElement.screenshot()` on MoniMac's own windows or popover, never the
/// whole screen, which would record the user's other apps.
class MoniMacUITestCase: XCTestCase {
    static let bundleID = "io.github.lethanhvietctt5.MoniMac"
    static let dummyBundleID = "io.github.lethanhvietctt5.MoniMacUITestDummy"
    static let dummyName = "MoniMacUITestDummy"

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// Launches MoniMac with `arguments` (dev flags such as `--show-popover`) and registers its teardown:
    /// quit MoniMac, then put its settings back as they were.
    @MainActor
    @discardableResult
    func launchMoniMac(_ arguments: [String] = []) -> XCUIApplication {
        let settings = MoniMacSettings.snapshot()
        let app = XCUIApplication()
        app.launchArguments = ["--mute-notifications"] + arguments
        addTeardownBlock { @MainActor in
            if app.state != .notRunning {
                app.terminate()
                _ = app.wait(for: .notRunning, timeout: 10)
            }
            MoniMacSettings.restore(settings)
        }
        app.launch()
        return app
    }

    /// The popover, opened by `--show-popover` 3 s after launch.
    @MainActor
    func popover(of app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) -> XCUIElement {
        let popover = app.popovers.firstMatch
        XCTAssertTrue(popover.waitForExistence(timeout: 15), "The popover didn't open", file: file, line: line)
        return popover
    }

    /// The main window: the window with the sidebar, as opposed to the share card or a quit panel.
    @MainActor
    func mainWindow(of app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) -> XCUIElement {
        let window = app.windows.containing(.any, identifier: "window.title").firstMatch
        XCTAssertTrue(window.waitForExistence(timeout: 15), "The main window didn't open", file: file, line: line)
        return window
    }

    /// The toolbar title, e.g. "CPU": the tab the main window shows.
    @MainActor
    func windowTitle(_ window: XCUIElement) -> String {
        let title = window.staticTexts["window.title"]
        return title.exists ? title.label : ""
    }

    /// Attaches a screenshot of one of MoniMac's own elements (a window, the popover, a sheet).
    @MainActor
    func attachScreenshot(of element: XCUIElement, named name: String) {
        guard element.exists else { return }
        let attachment = XCTAttachment(screenshot: element.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// Waits until `condition` holds, polling every 0.25 s.
    @MainActor
    func waitUntil(timeout: TimeInterval, _ condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.25))
        }
        return condition()
    }

    /// Whether the segment with this identifier is the selected one.
    @MainActor
    func isSelected(_ element: XCUIElement) -> Bool {
        element.exists && element.isSelected
    }

    // MARK: The throwaway app

    /// Launches MoniMacUITestDummy, a throwaway regular app built next to the test runner, so quit tests
    /// never touch the user's apps. It's launched through LaunchServices (so macOS sees it as its own app,
    /// not a child of the runner) and without activating, so it doesn't close MoniMac's popover.
    /// It's force-quit in teardown if a test left it running.
    @MainActor
    func launchDummy(spinning: Bool) throws -> NSRunningApplication {
        let url = Bundle(for: MoniMacUITestCase.self).bundleURL // …/MoniMacUITests-Runner.app/Contents/PlugIns/X.xctest
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "\(Self.dummyName).app")
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw XCTSkip("\(Self.dummyName).app isn't built next to the runner at \(url.path)")
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        configuration.createsNewApplicationInstance = true
        configuration.arguments = spinning ? ["--spin"] : []
        let launched = XCTestExpectation(description: "dummy launched")
        nonisolated(unsafe) var result: NSRunningApplication?
        NSWorkspace.shared.openApplication(at: url, configuration: configuration) { app, _ in
            result = app
            launched.fulfill()
        }
        wait(for: [launched], timeout: 20)
        let dummy = try XCTUnwrap(result, "The throwaway app didn't launch")
        addTeardownBlock { @MainActor in
            if !dummy.isTerminated { dummy.forceTerminate() }
        }
        return dummy
    }
}

/// MoniMac's settings domain, read and written as the user (the runner isn't sandboxed).
enum MoniMacSettings {
    private static var domain: CFString { MoniMacUITestCase.bundleID as CFString }

    private static var keys: [String] {
        CFPreferencesCopyKeyList(domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost) as? [String] ?? []
    }

    static func snapshot() -> [String: Any] {
        CFPreferencesAppSynchronize(domain)
        return CFPreferencesCopyMultiple(keys as CFArray, domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
            as? [String: Any] ?? [:]
    }

    /// Puts every key back as it was and removes keys the test added (e.g. status item positions).
    static func restore(_ snapshot: [String: Any]) {
        CFPreferencesAppSynchronize(domain)
        let added = keys.filter { snapshot[$0] == nil }
        CFPreferencesSetMultiple(snapshot as CFDictionary, added as CFArray, domain, kCFPreferencesCurrentUser,
                                 kCFPreferencesAnyHost)
        CFPreferencesAppSynchronize(domain)
    }

    static func value(_ key: String) -> Any? {
        CFPreferencesAppSynchronize(domain)
        return CFPreferencesCopyAppValue(key as CFString, domain)
    }
}
