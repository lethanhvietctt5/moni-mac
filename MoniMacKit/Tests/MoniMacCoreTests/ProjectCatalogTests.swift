import Foundation
import Testing
@testable import MoniMacCore

struct ProjectCatalogTests {
    let start = Date(timeIntervalSince1970: 1_790_000_000)
    let web = ProjectRoot(path: "/Users/me/Developer/acme-web", branch: "main")
    let api = ProjectRoot(path: "/Users/me/Developer/api-gateway", branch: "feat/auth")

    private func process(
        _ pid: Int32, _ arguments: [String], in project: ProjectRoot, parent: Int32 = 1, ports: [UInt16] = []
    ) -> DevProcess {
        DevProcess(pid: pid, parentPID: parent, startedAt: start, name: (arguments[0] as NSString).lastPathComponent,
                   arguments: arguments, project: project, listeningPorts: ports)
    }

    @Test func groupsServersByProjectRootAndComposeFolder() {
        let reading = DevServerReading(sampledAt: start, processes: [
            process(10, ["node", "/w/node_modules/.bin/next", "dev"], in: web, ports: [3000]),
            process(11, ["node", "/w/node_modules/.bin/storybook", "dev", "-p", "6006"], in: web, ports: [6006]),
            process(20, ["/usr/bin/python3", "/a/.venv/bin/uvicorn", "app:main", "--reload"], in: api, ports: [8000]),
        ], docker: .running([
            DockerContainer(id: "abc123", name: "api-gateway-postgres-1", image: "postgres:16", ports: [5432], project: api),
            DockerContainer(id: "def456", name: "scratch", image: "redis:7-alpine", ports: [6379]),
        ]))

        let servers = ProjectCatalog.servers(in: reading)

        #expect(Dictionary(grouping: servers, by: \.projectID).mapValues { $0.map(\.command) } == [
            web.path: ["next dev", "storybook dev -p 6006"],
            api.path: ["uvicorn app:main --reload", "postgres:16"],
            ProjectCatalog.containersProjectID: ["redis:7-alpine"],
        ])
        #expect(servers.first { $0.command == "postgres:16" }?.target == .container(id: "abc123"))
        #expect(servers.first { $0.command == "next dev" }?.target == .process(pid: 10, startedAt: start))
    }

    @Test func processesThatNeitherListenNorWatchAreNotServers() {
        let reading = DevServerReading(sampledAt: start, processes: [
            process(1, ["-zsh"], in: web),
            process(2, ["node", "/usr/local/bin/npm", "run", "dev"], in: web),
            process(3, ["vim", "src/app.tsx"], in: web),
        ])

        #expect(ProjectCatalog.servers(in: reading).isEmpty)
    }

    @Test func watcherWrappersCollapseToTheToolDoingTheWork() {
        // npm run watch → sh -c "tailwindcss --watch" → node …/tailwindcss --watch
        let reading = DevServerReading(sampledAt: start, processes: [
            process(30, ["node", "/usr/local/bin/npm", "run", "watch"], in: web),
            process(31, ["sh", "-c", "tailwindcss -i in.css -o out.css --watch"], in: web, parent: 30),
            process(32, ["node", "/w/node_modules/.bin/tailwindcss", "-i", "in.css", "-o", "out.css", "--watch"],
                    in: web, parent: 31),
            // nodemon restarts a server that listens: the server is what's shown.
            process(40, ["node", "/w/node_modules/.bin/nodemon", "server.js"], in: api),
            process(41, ["node", "server.js"], in: api, parent: 40, ports: [4000]),
        ])

        let servers = ProjectCatalog.servers(in: reading)

        #expect(servers.map(\.command) == ["tailwindcss -i in.css -o out.css --watch", "server.js"])
        #expect(servers.map(\.kind.name) == ["Watcher", "Node.js"])
    }

    @Test func detectsServerTypesFromCommandLineAndPort() {
        func kind(_ arguments: [String], ports: [UInt16] = [3000]) -> String {
            ProjectCatalog.kind(arguments: arguments, name: arguments[0], ports: ports).name
        }

        #expect(kind(["node", "/w/node_modules/next/dist/bin/next", "dev"]) == "Next.js")
        #expect(kind(["next-server (v14.2.3)"]) == "Next.js")
        #expect(kind(["node", "/w/node_modules/.bin/storybook", "dev", "-p", "6006"]) == "Storybook")
        #expect(kind(["node", "/w/node_modules/.bin/vite"], ports: [5173]) == "Vite")
        #expect(kind(["/usr/bin/python3", "/a/.venv/bin/uvicorn", "app:main"], ports: [8000]) == "FastAPI")
        #expect(kind(["python3", "manage.py", "runserver"], ports: [8000]) == "Django")
        #expect(kind(["node", "/w/node_modules/.bin/json-server", "db.json"], ports: [4000]) == "Mock API")
        #expect(kind(["bundle", "exec", "rails", "server"]) == "Rails")
        #expect(kind(["python3", "-m", "http.server", "8765"], ports: [8765]) == "Static Server")
        #expect(kind(["node", "/w/node_modules/.bin/tailwindcss", "--watch"], ports: []) == "Watcher")
        // A wrapper that doesn't name the tool falls back to the tool's usual port, then to the runtime.
        #expect(kind(["node", "scripts/start.js"], ports: [6006]) == "Storybook")
        #expect(kind(["node", "server.js"], ports: [4000]) == "Node.js")
        #expect(kind(["python3", "app.py"], ports: [5050]) == "Python")
        #expect(kind(["/w/bin/api"], ports: [9090]) == "Server")
    }

    @Test func runtimesPickTheIcon() {
        #expect(ProjectCatalog.kind(arguments: ["node", "x/vite"], name: "node", ports: [5173]).runtime == .node)
        #expect(ProjectCatalog.kind(arguments: ["python3", "x/uvicorn"], name: "python3", ports: [8000]).runtime == .python)
        #expect(ProjectCatalog.kind(arguments: ["/w/bin/api"], name: "api", ports: [9090]).runtime == .other)
    }

    @Test func commandsReadAsTyped() {
        func command(_ arguments: [String]) -> String { ProjectCatalog.command(arguments: arguments, name: "x") }

        #expect(command(["node", "/w/node_modules/.bin/vite"]) == "vite")
        #expect(command(["/opt/homebrew/bin/node", "--inspect", "/w/node_modules/next/dist/bin/next", "dev"]) == "next dev")
        #expect(command(["python3", "-m", "http.server", "8765"]) == "http.server 8765")
        #expect(command(["/opt/homebrew/…/Python.app/Contents/MacOS/Python", "-m", "http.server"]) == "http.server")
        #expect(command(["sh", "-c", "vite --port 5173 "]) == "vite --port 5173")
        #expect(command(["node", "/w/node_modules/.bin/json-server", "/Users/me/w/db.json"]) == "json-server db.json")
        #expect(command(["/w/target/debug/api", "--port", "9090"]) == "api --port 9090")
        #expect(ProjectCatalog.command(arguments: [], name: "postgres") == "postgres")
    }

    @Test func detectsWatchers() {
        #expect(ProjectCatalog.isWatcher(arguments: ["node", "x/tailwindcss", "--watch"]))
        #expect(ProjectCatalog.isWatcher(arguments: ["node", "x/tsc", "-w"]))
        #expect(ProjectCatalog.isWatcher(arguments: ["node", "x/jest", "--watchAll"]))
        #expect(ProjectCatalog.isWatcher(arguments: ["cargo", "watch", "-x", "run"]))
        #expect(ProjectCatalog.isWatcher(arguments: ["node", "x/nodemon", "server.js"]))
        // `-w` means workers here, not watch.
        #expect(!ProjectCatalog.isWatcher(arguments: ["gunicorn", "-w", "4", "app:app"]))
        #expect(!ProjectCatalog.isWatcher(arguments: ["node", "x/npm", "run", "dev"]))
    }
}
