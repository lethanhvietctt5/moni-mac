import Foundation
import MoniMacCore

/// Running containers, read from the Docker Engine API. Only talks to Docker when its socket exists.
///
/// Per refresh: one container list, plus a one-shot stats call per running container for memory
/// and cumulative CPU. Start times come from an inspect call, once per container.
final class DockerReader {
    private var startTimes: [String: Date] = [:]
    private let locate: () -> DockerClient?

    init(locate: @escaping () -> DockerClient? = DockerClient.locate) {
        self.locate = locate
    }

    /// Containers, each with the folder of its Compose project when it has one.
    func read(project: (String) -> ProjectRoot?) -> DockerStatus {
        guard let client = locate() else {
            startTimes = [:]
            return .notInstalled
        }
        let listed: [ListedContainer]
        do {
            listed = try JSONDecoder().decode([ListedContainer].self, from: client.get("/containers/json"))
        } catch DockerClient.Failure.notRunning {
            startTimes = [:]
            return .notRunning
        } catch {
            return .failed(String(describing: error))
        }
        startTimes = startTimes.filter { id, _ in listed.contains { $0.Id == id } }
        let containers = listed.map { container in
            let stats = try? JSONDecoder().decode(Stats.self, from: client.get("/containers/\(container.Id)/stats?stream=false&one-shot=true"))
            return DockerContainer(
                id: container.Id,
                image: container.Image,
                startedAt: startTime(of: container.Id, client: client),
                ports: Array(Set((container.Ports ?? []).compactMap(\.PublicPort))).sorted(),
                project: container.Labels?["com.docker.compose.project.working_dir"].flatMap(project),
                cpuTime: stats?.cpu_stats?.cpu_usage?.total_usage.map { Double($0) / 1_000_000_000 },
                memory: stats?.memoryInUse
            )
        }
        return .running(containers)
    }

    private func startTime(of id: String, client: DockerClient) -> Date? {
        if let known = startTimes[id] { return known }
        guard let data = try? client.get("/containers/\(id)/json"),
              let inspected = try? JSONDecoder().decode(Inspected.self, from: data),
              let date = Self.parseDate(inspected.State.StartedAt) else { return nil }
        startTimes[id] = date
        return date
    }

    /// Docker's RFC 3339 times carry nanoseconds, which ISO8601DateFormatter can't parse; drop them.
    static func parseDate(_ text: String) -> Date? {
        var trimmed = text
        if let dot = text.firstIndex(of: "."),
           let zone = text[dot...].firstIndex(where: { $0 == "Z" || $0 == "+" || $0 == "-" }) {
            trimmed = String(text[..<dot] + text[zone...])
        }
        return ISO8601DateFormatter().date(from: trimmed)
    }

    // The API's field names.
    struct ListedContainer: Decodable {
        struct Port: Decodable {
            var PublicPort: UInt16?
        }

        var Id: String
        var Image: String
        var Ports: [Port]?
        var Labels: [String: String]?
    }

    struct Inspected: Decodable {
        struct State: Decodable {
            var StartedAt: String
        }

        var State: State
    }

    struct Stats: Decodable {
        struct CPU: Decodable {
            struct Usage: Decodable {
                var total_usage: UInt64?
            }

            var cpu_usage: Usage?
        }

        struct Memory: Decodable {
            var usage: UInt64?
            var stats: [String: UInt64]?
        }

        var cpu_stats: CPU?
        var memory_stats: Memory?

        /// As `docker stats` shows it: usage minus the inactive page cache.
        var memoryInUse: UInt64? {
            guard let usage = memory_stats?.usage else { return nil }
            let cache = memory_stats?.stats?["inactive_file"] ?? memory_stats?.stats?["total_inactive_file"] ?? 0
            return usage > cache ? usage - cache : usage
        }
    }
}
