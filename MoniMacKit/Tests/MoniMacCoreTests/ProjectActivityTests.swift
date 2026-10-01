import Foundation
import Testing
@testable import MoniMacCore

/// Replays dev-server readings: each sample is a fresh background read stamped with the clock.
/// Tests change `processes` and `docker` between ticks to script CPU and connection histories.
final class DevServerSampler: SystemSampler {
    let clock: TestClock
    var processes: [DevProcess] = []
    var docker: DockerStatus = .notInstalled

    init(clock: TestClock) {
        self.clock = clock
    }

    func sample() -> Snapshot {
        Snapshot(timestamp: clock.now, cpu: .cpu(user: 0.1, system: 0.1),
                 devServers: .value(DevServerReading(sampledAt: clock.now, processes: processes, docker: docker)))
    }
}

@MainActor
struct ProjectActivityTests {
    let clock = TestClock()
    let defaults = UserDefaults(suiteName: "monimac-tests-\(UUID().uuidString)")!
    let actions = RecordingActions()
    let utc = TimeZone(identifier: "UTC")!
    let web = ProjectRoot(path: "/Users/me/Developer/acme-web", branch: "main")
    let landing = ProjectRoot(path: "/Users/me/Developer/old-landing", branch: "main")
    let started: Date

    let mb: UInt64 = 1_048_576

    init() {
        started = clock.now.addingTimeInterval(-3600)
    }

    private func monitor(_ sampler: DevServerSampler) throws -> Monitor {
        Monitor(sampler: sampler, history: try MetricsHistory(.inMemory), preferences: Preferences(defaults: defaults),
                actions: actions, startedAt: clock.now)
    }

    private func vite(cpu: TimeInterval = 10, connections: Set<String> = []) -> DevProcess {
        DevProcess(pid: 501, startedAt: started, name: "node", arguments: ["node", "/l/node_modules/.bin/vite"],
                   project: landing, listeningPorts: [5173], connections: connections, cpuTime: cpu, memory: 862 * mb)
    }

    private func jsonServer(cpu: TimeInterval = 4) -> DevProcess {
        DevProcess(pid: 502, startedAt: started, name: "node", arguments: ["node", "/l/node_modules/.bin/json-server", "db.json"],
                   project: landing, listeningPorts: [4000], cpuTime: cpu, memory: 214 * mb)
    }

    private func next(cpu: TimeInterval = 50, connections: Set<String> = []) -> DevProcess {
        DevProcess(pid: 601, startedAt: started, name: "node", arguments: ["node", "/w/node_modules/.bin/next", "dev"],
                   project: web, listeningPorts: [3000], connections: connections, cpuTime: cpu, memory: 742 * mb)
    }

    private func watcher(cpu: TimeInterval = 2) -> DevProcess {
        DevProcess(pid: 602, startedAt: started, name: "node", arguments: ["node", "/w/node_modules/.bin/tailwindcss", "--watch"],
                   project: web, cpuTime: cpu, memory: 96 * mb)
    }

    private func detail(_ monitor: Monitor) -> ProjectDetail {
        ProjectDetail.make(
            servers: monitor.projectActivity.servers, docker: monitor.projectActivity.docker,
            lastActive: monitor.projectActivity.lastActive, ignored: monitor.projectActivity.ignoredProjects,
            stopping: Set(monitor.projectActivity.stopRequests.keys), now: monitor.latest!.timestamp,
            home: "/Users/me", timeZone: utc
        )
    }

    private func activity(_ monitor: Monitor, _ command: String) -> String? {
        detail(monitor).projects.flatMap(\.servers).first { $0.command == command }?.activity
    }

    /// Advances the clock and takes one reading.
    private func tick(_ monitor: Monitor, after seconds: TimeInterval) {
        clock.advance(by: seconds)
        monitor.tick()
    }

    // MARK: Idle definition

    @Test func idleNeedsNoNewConnectionsAndCPUUnderTheFloor() throws {
        let sampler = DevServerSampler(clock: clock)
        sampler.processes = [vite()]
        let monitor = try monitor(sampler)
        monitor.tick()
        #expect(activity(monitor, "vite") == "Active · now")

        // Quiet: CPU flat, no connections.
        tick(monitor, after: 12)
        tick(monitor, after: 6 * 60)
        #expect(activity(monitor, "vite") == "Idle 6 min")

        // A new inbound connection makes it active.
        sampler.processes = [vite(connections: ["5173 127.0.0.1:52001"])]
        tick(monitor, after: 12)
        #expect(activity(monitor, "vite") == "Active · now")

        // The same connection still open (e.g. an HMR websocket) is not a new one.
        tick(monitor, after: 12)
        tick(monitor, after: 3 * 60)
        #expect(activity(monitor, "vite") == "Active · 3 min")
        tick(monitor, after: 2 * 60)
        #expect(activity(monitor, "vite") == "Idle 5 min")

        // CPU over the floor (3% of a core) makes it active without any connection: 0.5 s over 12 s is 4%.
        sampler.processes = [vite(cpu: 10.5, connections: ["5173 127.0.0.1:52001"])]
        tick(monitor, after: 12)
        #expect(activity(monitor, "vite") == "Active · now")

        // CPU just under the floor doesn't: 0.3 s over 12 s is 2.5%.
        sampler.processes = [vite(cpu: 10.8, connections: ["5173 127.0.0.1:52001"])]
        tick(monitor, after: 12)
        tick(monitor, after: 3600)
        #expect(activity(monitor, "vite") == "Idle 1 h")
    }

    @Test func watchersAreIdleByCPUAlone() throws {
        let sampler = DevServerSampler(clock: clock)
        sampler.processes = [watcher(cpu: 2)]
        let monitor = try monitor(sampler)
        monitor.tick()
        tick(monitor, after: 30 * 60)
        #expect(activity(monitor, "tailwindcss --watch") == "Idle 30 min")

        sampler.processes = [watcher(cpu: 3)]
        tick(monitor, after: 12)
        #expect(activity(monitor, "tailwindcss --watch") == "Active · now")
    }

    @Test func aReadingRepeatedBetweenBackgroundReadsCountsOnce() throws {
        let sampler = DevServerSampler(clock: clock)
        sampler.processes = [vite()]
        let monitor = try monitor(sampler)
        monitor.tick()
        tick(monitor, after: 12)
        let activity = ProjectActivity(preferences: Preferences(defaults: defaults))
        let reading = monitor.latest!.devServers
        activity.observe(reading, now: clock.now)
        let first = activity.lastActive
        // The same reading on the next ticks changes nothing, even with time moving on.
        activity.observe(reading, now: clock.now.addingTimeInterval(2))
        activity.observe(reading, now: clock.now.addingTimeInterval(4))
        #expect(activity.lastActive == first)
    }

    @Test func idleLabelsCountMinutesHoursAndDays() {
        #expect(ProjectDetail.activity(idleFor: 20) == "Active · now")
        #expect(ProjectDetail.activity(idleFor: 2 * 60) == "Active · 2 min")
        #expect(ProjectDetail.activity(idleFor: 26 * 60) == "Idle 26 min")
        #expect(ProjectDetail.activity(idleFor: 3 * 3600 + 59) == "Idle 3 h")
        #expect(ProjectDetail.activity(idleFor: 86400) == "Idle 1 day")
        #expect(ProjectDetail.activity(idleFor: 4 * 86400 + 3600) == "Idle 4 days")
    }

    // MARK: Banner and Ignore

    /// old-landing goes quiet on Sep 27 while acme-web stays busy.
    private func forgottenLanding() throws -> (DevServerSampler, Monitor) {
        let sampler = DevServerSampler(clock: clock)
        sampler.processes = [vite(), jsonServer(), next()]
        let monitor = try monitor(sampler)
        monitor.tick()
        tick(monitor, after: 2 * 86400 + 3600)
        // acme-web's next dev keeps working (10 s of CPU in 12 s).
        sampler.processes = [vite(), jsonServer(), next(cpu: 60)]
        tick(monitor, after: 12)
        return (sampler, monitor)
    }

    @Test func serversIdleForTwoDaysRaiseTheBanner() throws {
        let (_, monitor) = try forgottenLanding()
        let detail = detail(monitor)

        #expect(detail.banner == ProjectDetail.Banner(
            title: "2 servers have been idle for days",
            message: "old-landing has had no requests since Sep 21 and is holding 1.1 GB of memory and ports 5173, 4000.",
            projectIDs: [landing.path],
            serverIDs: ["501-\(Int(started.timeIntervalSince1970))", "502-\(Int(started.timeIntervalSince1970))"]
        ))
        let landingCard = try #require(detail.projects.first { $0.name == "old-landing" })
        #expect(landingCard.isForgotten)
        #expect(landingCard.servers.map(\.level) == [.forgotten, .forgotten])
        #expect(landingCard.servers.map(\.activity) == ["Idle 2 days", "Idle 2 days"])
        #expect(detail.projects.map(\.name) == ["acme-web", "old-landing"])
        #expect(!detail.projects[0].isForgotten)
    }

    @Test func noBannerUnderTwoDays() throws {
        let sampler = DevServerSampler(clock: clock)
        sampler.processes = [vite()]
        let monitor = try monitor(sampler)
        monitor.tick()
        tick(monitor, after: 2 * 86400 - 60)
        #expect(detail(monitor).banner == nil)
        #expect(detail(monitor).projects[0].servers[0].level == .idle)
        tick(monitor, after: 60)
        #expect(detail(monitor).banner != nil)
    }

    @Test func ignoreHidesTheBannerUntilTheProjectIsActiveAgain() throws {
        let (sampler, monitor) = try forgottenLanding()
        monitor.ignoreIdleServers()
        #expect(detail(monitor).banner == nil)

        // Still ignored while it stays idle, including after a relaunch.
        tick(monitor, after: 86400)
        #expect(detail(monitor).banner == nil)
        let relaunched = try self.monitor(sampler)
        relaunched.tick()
        #expect(detail(relaunched).banner == nil)
        // The rows stay highlighted; only the banner is hidden.
        #expect(detail(relaunched).projects.first { $0.name == "old-landing" }?.isForgotten == true)

        // A request makes the project active, which ends the Ignore…
        sampler.processes = [vite(connections: ["5173 127.0.0.1:52001"]), jsonServer(), next(cpu: 60)]
        tick(relaunched, after: 12)
        #expect(relaunched.projectActivity.ignoredProjects.isEmpty)
        // …so going quiet for two more days brings the banner back.
        tick(relaunched, after: 2 * 86400)
        #expect(detail(relaunched).banner?.projectIDs.contains(landing.path) == true)
    }

    @Test func idleTimesSurviveRelaunch() throws {
        let (sampler, monitor) = try forgottenLanding()
        #expect(activity(monitor, "vite") == "Idle 2 days")

        sampler.processes = [vite(), jsonServer()]
        tick(monitor, after: 2 * 86400)
        let relaunched = try self.monitor(sampler)
        relaunched.tick()
        #expect(activity(relaunched, "vite") == "Idle 4 days")
        #expect(detail(relaunched).banner?.message.contains("since Sep 21") == true)
    }

    @Test func aRestartedServerIsANewServer() throws {
        let (sampler, monitor) = try forgottenLanding()
        var restarted = vite()
        restarted.pid = 777
        restarted.startedAt = clock.now
        sampler.processes = [restarted, jsonServer(), next(cpu: 60)]
        tick(monitor, after: 12)
        #expect(activity(monitor, "vite") == "Active · now")
        #expect(detail(monitor).banner?.title == "1 server has been idle for days")
        #expect(detail(monitor).banner?.message
            == "old-landing has had no requests since Sep 21 and is holding 214 MB of memory and port 4000.")
    }

    // MARK: Actions

    @Test func stopIdleServersStopsWhatTheBannerNames() throws {
        let (_, monitor) = try forgottenLanding()
        monitor.stopIdleServers()

        #expect(actions.recorded == [
            .stopProcess(pid: 501, startedAt: started), .stopProcess(pid: 502, startedAt: started),
        ])
        // They show as stopping, and the banner goes until the next reading confirms.
        #expect(detail(monitor).banner == nil)
        #expect(detail(monitor).projects.first { $0.name == "old-landing" }?.servers.map(\.activity)
            == ["Stopping…", "Stopping…"])
        // Asking again doesn't signal twice.
        monitor.stopProject(id: landing.path)
        #expect(actions.recorded.count == 2)
    }

    @Test func stopAndStopAllAndContainers() throws {
        let sampler = DevServerSampler(clock: clock)
        sampler.processes = [next(), watcher()]
        sampler.docker = .running([
            DockerContainer(id: "c0ffee", image: "postgres:16", startedAt: started, ports: [5432],
                            project: web),
        ])
        let monitor = try monitor(sampler)
        monitor.tick()
        let rows = detail(monitor).projects[0].servers
        #expect(rows.map(\.command) == ["next dev", "tailwindcss --watch", "postgres:16"])

        monitor.stopServer(id: rows[1].id)
        #expect(actions.recorded == [.stopProcess(pid: 602, startedAt: started)])

        monitor.stopProject(id: web.path)
        #expect(actions.recorded == [
            .stopProcess(pid: 602, startedAt: started),
            .stopProcess(pid: 601, startedAt: started),
            .stopContainer(id: "c0ffee"),
        ])
    }

    @Test func aStopThatDoesNotTakeEffectStopsShowingAsStopping() throws {
        let sampler = DevServerSampler(clock: clock)
        sampler.processes = [next()]
        let monitor = try monitor(sampler)
        monitor.tick()
        monitor.stopProject(id: web.path)
        #expect(activity(monitor, "next dev") == "Stopping…")
        tick(monitor, after: 31)
        #expect(activity(monitor, "next dev") != "Stopping…")
    }

    @Test func openPortAndRevealFolder() throws {
        let sampler = DevServerSampler(clock: clock)
        sampler.processes = [next()]
        let monitor = try monitor(sampler)
        monitor.tick()

        monitor.openServer(port: 3000)
        monitor.revealProject(id: web.path)

        #expect(actions.recorded == [
            .openURL(URL(string: "http://localhost:3000")!), .revealInFinder(path: web.path),
        ])
    }

    // MARK: Cards and subtitle

    @Test func cardsMatchTheDesign() throws {
        let sampler = DevServerSampler(clock: clock)
        sampler.processes = [next(), watcher()]
        let monitor = try monitor(sampler)
        monitor.tick()
        tick(monitor, after: 12 * 60)

        let card = try #require(detail(monitor).projects.first)
        #expect(card.name == "acme-web")
        #expect(card.path == "~/Developer/acme-web")
        #expect(card.summary == "main · 2 servers")
        #expect(card.memory == "838 MB")
        #expect(card.servers.map(\.kind.name) == ["Next.js", "Watcher"])
        #expect(card.servers.map(\.ports) == [[3000], []])
        #expect(card.servers.map(\.uptime) == ["1h 12m", "1h 12m"])
        #expect(card.servers.map(\.memory) == ["742 MB", "96 MB"])
        #expect(card.servers.map(\.level) == [.idle, .idle])
    }

    @Test func subtitleSummarizesServersProjectsAndMemory() throws {
        let sampler = DevServerSampler(clock: clock)
        sampler.processes = [vite(), jsonServer(), next(), watcher()]
        sampler.docker = .running([
            DockerContainer(id: "c0ffee", image: "postgres:16", ports: [5432], memory: 264 * mb),
        ])
        let monitor = try monitor(sampler)
        #expect(monitor.projectsSubtitle == nil)
        monitor.tick()
        #expect(monitor.projectsSubtitle == "5 dev servers across 3 projects · 2.1 GB")

        sampler.processes = [watcher()]
        sampler.docker = .notRunning
        tick(monitor, after: 12)
        #expect(monitor.projectsSubtitle == "1 dev server in 1 project · 96 MB")
        #expect(detail(monitor).dockerNote == "Docker isn't running.")

        sampler.processes = []
        tick(monitor, after: 12)
        #expect(monitor.projectsSubtitle == "No dev servers running")
        #expect(detail(monitor).emptyMessage == "No dev servers running")
    }

    @Test func aFailedDockerReadKeepsContainersAndTheirIdleTime() throws {
        let sampler = DevServerSampler(clock: clock)
        let postgres = DockerContainer(id: "c0ffee", image: "postgres:16", ports: [5432], project: web, cpuTime: 3)
        sampler.docker = .running([postgres])
        let monitor = try monitor(sampler)
        monitor.tick()
        tick(monitor, after: 3 * 3600)
        #expect(activity(monitor, "postgres:16") == "Idle 3 h")

        sampler.docker = .failed("HTTP 500")
        tick(monitor, after: 12)
        #expect(activity(monitor, "postgres:16") == "Idle 3 h")

        // Back again, it's the same container, still idle: not a new, active one.
        sampler.docker = .running([postgres])
        tick(monitor, after: 12)
        #expect(activity(monitor, "postgres:16") == "Idle 3 h")
    }

    @Test func portChipsOpenTheFirstPortAndNameTheRest() throws {
        let sampler = DevServerSampler(clock: clock)
        var server = next()
        server.listeningPorts = [3000, 3001]
        sampler.processes = [server, watcher()]
        let monitor = try monitor(sampler)
        monitor.tick()

        let rows = detail(monitor).projects[0].servers
        #expect(rows.map(\.portHelp) == ["Open http://localhost:3000 · also listening on 3001", nil])
    }

    @Test func containersOutsideComposeAreGroupedLast() throws {
        let sampler = DevServerSampler(clock: clock)
        sampler.processes = [next()]
        sampler.docker = .running([DockerContainer(id: "beef", image: "redis:7-alpine", ports: [6379])])
        let monitor = try monitor(sampler)
        monitor.tick()

        let projects = detail(monitor).projects
        #expect(projects.map(\.name) == ["acme-web", "Containers"])
        #expect(projects[1].path == nil)
        #expect(projects[1].servers.map(\.kind) == [ServerKind("Docker", .docker)])
    }
}
