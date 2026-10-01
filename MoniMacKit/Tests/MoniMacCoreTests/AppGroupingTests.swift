import Testing
@testable import MoniMacCore

struct AppGroupingTests {
    let chrome = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
    let renderer = "/Applications/Google Chrome.app/Contents/Frameworks/Google Chrome Framework.framework/Versions/131/Helpers/Google Chrome Helper (Renderer).app/Contents/MacOS/Google Chrome Helper (Renderer)"
    let safari = "/Applications/Safari.app/Contents/MacOS/Safari"
    let webContent = "/System/Library/Frameworks/WebKit.framework/Versions/A/XPCServices/com.apple.WebKit.WebContent.xpc/Contents/MacOS/com.apple.WebKit.WebContent"
    let windowServer = "/System/Library/PrivateFrameworks/SkyLight.framework/Resources/WindowServer"

    private func process(
        _ pid: Int32, _ path: String?, cpu: Double, responsible: Int32? = nil, regular: Bool = false, otherUser: Bool = false
    ) -> ProcessSample {
        ProcessSample(pid: pid, responsiblePID: responsible, name: path.map { String($0.split(separator: "/").last!) } ?? "proc\(pid)",
                      path: path, cpu: cpu, isRegularApp: regular, isOtherUser: otherUser)
    }

    @Test func helpersRollUpUnderTheirResponsibleApp() {
        let apps = AppGrouping.apps(from: [
            process(10, safari, cpu: 0.1, regular: true),
            process(11, webContent, cpu: 0.4, responsible: 10),
            process(12, webContent, cpu: 0.2, responsible: 10),
        ])

        #expect(apps.count == 1)
        #expect(apps[0].name == "Safari")
        #expect(apps[0].bundlePath == "/Applications/Safari.app")
        #expect(apps[0].processCount == 3)
        #expect(abs(apps[0].cpu - 0.7) < 1e-9)
    }

    @Test func nestedHelperAppsCountTowardTheOutermostAppWithoutResponsibility() {
        let apps = AppGrouping.apps(from: [
            process(20, chrome, cpu: 0.2, regular: true),
            process(21, renderer, cpu: 0.5),
        ])

        #expect(apps.map(\.name) == ["Google Chrome"])
        #expect(apps[0].processCount == 2)
    }

    @Test func processWithoutResponsibilityOrBundleIsItsOwnEntry() {
        let apps = AppGrouping.apps(from: [process(30, webContent, cpu: 0.3), process(31, windowServer, cpu: 0.2)])

        #expect(apps.map(\.name) == ["com.apple.WebKit.WebContent", "WindowServer"])
        #expect(apps.map(\.bundlePath) == [nil, nil])
        #expect(apps[1].id == windowServer)
    }

    @Test func sortsBusiestFirst() {
        let apps = AppGrouping.apps(from: [
            process(1, safari, cpu: 0.1), process(2, chrome, cpu: 0.9), process(3, windowServer, cpu: 0.5),
        ])

        #expect(apps.map(\.name) == ["Google Chrome", "WindowServer", "Safari"])
    }

    @Test func onlyARunningRegularAppCanBeQuit() {
        let apps = AppGrouping.apps(from: [
            process(20, chrome, cpu: 0.9, regular: true),
            process(21, renderer, cpu: 0.5, responsible: 20),
            process(40, windowServer, cpu: 0.8),
        ])

        let byName = Dictionary(uniqueKeysWithValues: apps.map { ($0.name, $0) })
        #expect(byName["Google Chrome"]?.quitPID == 20)
        #expect(byName["WindowServer"]?.canQuit == false)
    }

    @Test func sumsPerProcessResourcesAndKeepsMissingOnesNil() {
        var main = process(20, chrome, cpu: 0.2, regular: true)
        main.resources = ResourceUse(memory: 300, power: 1.5)
        var helper = process(21, renderer, cpu: 0.5, responsible: 20)
        helper.resources = ResourceUse(memory: 700, diskWritePerSecond: 10)

        let app = AppGrouping.apps(from: [main, helper])[0]

        #expect(app.resources == ResourceUse(memory: 1000, diskWritePerSecond: 10, power: 1.5))
    }

    @Test func busiestAppNamesTheOwnerOfTheBusiestProcess() {
        let processes = [
            process(20, chrome, cpu: 0.2, regular: true),
            process(21, webContent, cpu: 0.9, responsible: 10),
            process(10, safari, cpu: 0.1, regular: true),
        ]

        #expect(AppGrouping.busiestApp(in: processes, by: \.cpu) == "Safari")
        #expect(AppGrouping.busiestApp(in: processes, by: \.resources.gpu) == nil)
    }

    @Test(arguments: [
        ("/Applications/Xcode.app/Contents/MacOS/Xcode", "/Applications/Xcode.app"),
        ("/usr/bin/swift-frontend", nil),
        (nil, nil),
    ] as [(String?, String?)])
    func findsTheOutermostAppBundle(path: String?, bundle: String?) {
        #expect(AppGrouping.outermostAppBundle(in: path) == bundle)
    }

    // MARK: Kind

    private func kinds(_ processes: [ProcessSample]) -> [String: AppKind] {
        Dictionary(uniqueKeysWithValues: AppGrouping.apps(from: processes).map { ($0.name, $0.kind) })
    }

    @Test func aGroupWithADockAppIsAnApp() {
        let kinds = kinds([
            process(10, safari, cpu: 0, regular: true),
            process(11, webContent, cpu: 0, responsible: 10),
            // Finder ships with macOS but is a regular app.
            process(12, "/System/Library/CoreServices/Finder.app/Contents/MacOS/Finder", cpu: 0, regular: true),
        ])

        #expect(kinds == ["Safari": .app, "Finder": .app])
    }

    @Test func aRegularAppWithARootHelperIsStillAnApp() {
        let kinds = kinds([
            process(20, "/Applications/Docker.app/Contents/MacOS/Docker Desktop.app/Contents/MacOS/Docker Desktop",
                    cpu: 0, regular: true),
            process(21, "/Applications/Docker.app/Contents/Library/LaunchServices/com.docker.vmnetd", cpu: 0, otherUser: true),
        ])

        #expect(kinds == ["Docker": .app])
    }

    @Test func ownBackgroundSoftwareOutsideMacOSIsAnAgent() {
        let kinds = kinds([
            process(30, "/Applications/Rectangle.app/Contents/MacOS/Rectangle", cpu: 0),
            process(31, "/opt/homebrew/bin/postgres", cpu: 0),
            process(32, "/usr/local/bin/node", cpu: 0),
            process(33, nil, cpu: 0),
        ])

        #expect(kinds == ["Rectangle": .agent, "postgres": .agent, "node": .agent, "proc33": .agent])
    }

    @Test func otherUsersProcessesAndOwnMacOSProcessesAreSystem() {
        let kinds = kinds([
            process(40, windowServer, cpu: 0, otherUser: true),
            process(41, nil, cpu: 0, otherUser: true),
            process(42, "/Applications/Some Daemon.app/Contents/MacOS/daemon", cpu: 0, otherUser: true),
            process(43, "/System/Library/CoreServices/ControlCenter.app/Contents/MacOS/ControlCenter", cpu: 0),
            process(44, "/usr/libexec/trustd", cpu: 0),
            process(45, "/sbin/launchd", cpu: 0),
        ])

        #expect(kinds == [
            "WindowServer": .system, "proc41": .system, "Some Daemon": .system, "ControlCenter": .system,
            "trustd": .system, "launchd": .system,
        ])
    }
}
