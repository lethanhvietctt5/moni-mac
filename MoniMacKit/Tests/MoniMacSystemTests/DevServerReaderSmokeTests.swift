import Darwin
import Foundation
import Testing
import MoniMacCore
@testable import MoniMacSystem

/// The real dev-server reader against this Mac. It starts its own throwaway server in a temp
/// project folder and stops only that process.
@Suite(.serialized)
struct DevServerReaderSmokeTests {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("monimac-tests-\(UUID().uuidString)")

    /// Never reads protected folders, so the test can't raise a privacy prompt.
    private func scanner() -> DevServerScanner {
        DevServerScanner(resolver: ProjectRootResolver(allowProtected: { false }), docker: DockerReader(locate: { nil }))
    }

    /// A project with a git branch and a package.json, and `python3 -m http.server` serving it.
    private func startServer() throws -> (Process, port: UInt16, root: String) {
        let project = folder.appendingPathComponent("smoke-site")
        try FileManager.default.createDirectory(at: project.appendingPathComponent(".git"), withIntermediateDirectories: true)
        try "ref: refs/heads/smoke-branch\n".write(to: project.appendingPathComponent(".git/HEAD"), atomically: true, encoding: .utf8)
        try "{}".write(to: project.appendingPathComponent("package.json"), atomically: true, encoding: .utf8)
        let port = try freePort()
        let server = Process()
        server.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        server.arguments = ["python3", "-m", "http.server", "\(port)", "--bind", "127.0.0.1"]
        server.currentDirectoryURL = project
        server.standardOutput = FileHandle.nullDevice
        server.standardError = FileHandle.nullDevice
        try server.run()
        // The kernel reports the resolved path (/private/var/… for /var/…).
        let root = try #require(realpath(project.path, nil).map { path in defer { free(path) }; return String(cString: path) })
        return (server, port, root)
    }

    private func freePort() throws -> UInt16 {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        defer { close(fd) }
        var address = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET)
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        try withUnsafeMutablePointer(to: &address) { pointer in
            try pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                guard bind(fd, $0, length) == 0, getsockname(fd, $0, &length) == 0 else { throw POSIXError(.EADDRINUSE) }
            }
        }
        return UInt16(bigEndian: address.sin_port)
    }

    private func connect(to port: UInt16) -> Int32 {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        var address = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET)
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        address.sin_port = port.bigEndian
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        _ = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
        }
        return fd
    }

    /// Polls until the server process listens (python takes a moment to start).
    private func waitForServer(_ scanner: DevServerScanner, pid: Int32) -> DevProcess? {
        for _ in 0..<50 {
            if let found = scanner.scan().processes.first(where: { $0.pid == pid && !$0.listeningPorts.isEmpty }) {
                return found
            }
            usleep(100_000)
        }
        return nil
    }

    @Test func findsAServerInAProjectWithItsBranchPortAndConnections() throws {
        let (server, port, root) = try startServer()
        defer {
            server.terminate()
            server.waitUntilExit()
            try? FileManager.default.removeItem(at: folder)
        }
        let scanner = scanner()

        let found = try #require(waitForServer(scanner, pid: server.processIdentifier))
        #expect(found.project == ProjectRoot(path: root, branch: "smoke-branch"))
        #expect(found.listeningPorts == [port])
        #expect(found.arguments.suffix(5) == ["-m", "http.server", "\(port)", "--bind", "127.0.0.1"])
        #expect(found.memory ?? 0 > 0)
        #expect(found.connections.isEmpty)
        let servers = ProjectCatalog.servers(in: DevServerReading(sampledAt: Date(), processes: [found]))
        #expect(servers.map(\.command) == ["http.server \(port) --bind 127.0.0.1"])
        #expect(servers.map(\.kind) == [ServerKind("Static Server", .python)])

        // An inbound connection shows up on the server's side.
        let client = connect(to: port)
        defer { close(client) }
        var connections: Set<String> = []
        for _ in 0..<20 where connections.isEmpty {
            connections = scanner.scan().processes.first { $0.pid == server.processIdentifier }?.connections ?? []
            usleep(50_000)
        }
        #expect(connections.count == 1)
        #expect(connections.first?.hasPrefix("\(port) 127.0.0.1:") == true)
    }

    @Test func appsStartedOutsideAProjectAreNotCandidates() {
        let home = NSHomeDirectory()
        let processes = scanner().scan().processes
        // ControlCenter's AirPlay ports, Raycast, Discord, and the like run from "/" or app bundles.
        #expect(processes.allSatisfy { $0.project?.path != "/" && $0.project?.path != home })
        // Only servers and watchers get a project: looking one up touches the folder.
        #expect(processes.allSatisfy { $0.project == nil || !$0.listeningPorts.isEmpty
            || ProjectCatalog.isWatcher(arguments: $0.arguments) })
        #expect(!processes.contains { $0.name == "ControlCenter" || $0.name == "rapportd" })
    }

    @Test func readsInTheBackgroundAndKeepsTheLatest() async throws {
        let reader = DevServerReader(scanner: scanner(), interval: 60, firstDelay: 0)
        #expect(reader.latest() == .unavailable(.warmingUp))
        reader.refreshIfDue()
        for _ in 0..<100 where reader.latest().value == nil {
            try await Task.sleep(for: .milliseconds(50))
        }
        #expect(reader.latest().value != nil)
    }
}

/// Parsing and folder rules behind the reader, without touching real projects or Docker.
struct DevServerParsingTests {
    @Test func parsesProcArgs2() {
        var buffer: [UInt8] = []
        withUnsafeBytes(of: Int32(3)) { buffer.append(contentsOf: $0) }
        buffer += Array("/opt/homebrew/bin/node".utf8) + [0, 0, 0, 0]
        buffer += Array("node".utf8) + [0] + Array("/w/node_modules/.bin/vite".utf8) + [0] + Array("--host".utf8) + [0]
        buffer += Array("PATH=/usr/bin".utf8) + [0]

        #expect(DevProcessInfo.parseArguments(buffer[...]) == ["node", "/w/node_modules/.bin/vite", "--host"])
    }

    @Test func readsTheBranchFromHEAD() {
        #expect(ProjectRootResolver.branch(head: "ref: refs/heads/feat/auth\n") == "feat/auth")
        #expect(ProjectRootResolver.branch(head: "4f1c2a9d0e\n") == nil)
    }

    @Test func protectedFoldersFallBackToTheWorkingDirectoryWithoutReadingThem() {
        let resolver = ProjectRootResolver(home: "/Users/me", allowProtected: { false })
        #expect(resolver.project(for: "/Users/me/Documents/acme/web") == ProjectRoot(path: "/Users/me/Documents/acme/web"))
        #expect(resolver.project(for: "/Volumes/Work/site") == ProjectRoot(path: "/Volumes/Work/site"))
        #expect(resolver.project(for: "/Users/me") == nil)
        #expect(resolver.project(for: "/") == nil)
        #expect(ProjectFolderAccess.isProtected("/Users/me/Desktop", home: "/Users/me"))
        #expect(!ProjectFolderAccess.isProtected("/Users/me/Developer/x", home: "/Users/me"))
        #expect(!ProjectFolderAccess.isProtected("/Users/me/Documentsy", home: "/Users/me"))
    }

    @Test func findsTheNearestManifestAndTheEnclosingRepository() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("monimac-tests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        let web = folder.appendingPathComponent("mono/packages/web")
        try FileManager.default.createDirectory(at: web.appendingPathComponent("src"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: folder.appendingPathComponent("mono/.git"), withIntermediateDirectories: true)
        try "ref: refs/heads/main\n".write(to: folder.appendingPathComponent("mono/.git/HEAD"), atomically: true, encoding: .utf8)
        try "{}".write(to: web.appendingPathComponent("package.json"), atomically: true, encoding: .utf8)
        let resolver = ProjectRootResolver(home: folder.path, allowProtected: { false })

        #expect(resolver.project(for: web.appendingPathComponent("src").path) == ProjectRoot(path: web.path, branch: "main"))
        #expect(resolver.project(for: folder.appendingPathComponent("mono").path)
            == ProjectRoot(path: folder.appendingPathComponent("mono").path, branch: "main"))
        // A folder without markers is its own project; the home folder never is.
        try FileManager.default.createDirectory(at: folder.appendingPathComponent("loose"), withIntermediateDirectories: true)
        #expect(resolver.project(for: folder.appendingPathComponent("loose").path)
            == ProjectRoot(path: folder.appendingPathComponent("loose").path))
        #expect(resolver.project(for: folder.path) == nil)
    }

    @Test func parsesHTTPResponsesAndDockerDates() throws {
        let response = try DockerClient.parse(Data("HTTP/1.0 200 OK\r\nContent-Type: application/json\r\n\r\n[]".utf8))
        #expect(response.status == 200)
        #expect(response.body == Data("[]".utf8))
        #expect(DockerReader.parseDate("2026-09-27T10:11:12.123456789Z") == Date(timeIntervalSince1970: 1_790_503_872))
    }

    @Test func dockerMissingOrStoppedIsNotAnError() {
        #expect(DockerReader(locate: { nil }).read { _ in nil } == .notInstalled)
        let missing = FileManager.default.temporaryDirectory.appendingPathComponent("monimac-tests-\(UUID().uuidString).sock")
        #expect(DockerReader(locate: { DockerClient(socketPath: missing.path) }).read { _ in nil } == .notRunning)
    }
}
