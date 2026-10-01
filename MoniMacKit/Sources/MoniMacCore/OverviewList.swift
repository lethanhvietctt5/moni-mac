import Foundation

/// A column of the Overview List, in the design's order. Every column sorts.
public enum OverviewListColumn: String, CaseIterable, Sendable {
    case app, processes, cpu, memory, gpu, network, disk, power

    public var title: String {
        switch self {
        case .app: "App"
        case .processes: "Procs"
        case .cpu: "CPU"
        case .memory: "Memory"
        case .gpu: "GPU"
        case .network: "Network"
        case .disk: "Disk"
        case .power: "Power"
        }
    }

    /// The "Sorted by …" control's label, e.g. "Sorted by CPU".
    public var sortLabel: String {
        "Sorted by \(self == .processes ? "Processes" : title)"
    }

    /// The columns that hold a figure, i.e. all but App.
    public static let figures: [OverviewListColumn] = allCases.filter { $0 != .app }
}

/// What the user picked in the List view: sort, search, grouping, and which groups are open.
/// The window keeps it, so it survives switching tabs.
public struct OverviewListQuery: Equatable, Sendable {
    public var sort: OverviewListColumn
    public var search: String
    public var grouped: Bool
    /// Ids of the app groups whose helpers are shown.
    public var expanded: Set<AppUsage.ID>

    public init(sort: OverviewListColumn = .cpu, search: String = "", grouped: Bool = true,
                expanded: Set<AppUsage.ID> = []) {
        self.sort = sort
        self.search = search
        self.grouped = grouped
        self.expanded = expanded
    }
}

/// Everything the Overview List view shows: the table rows, the footer, and system totals.
///
/// **Rows.** Grouped, there is one row per app group, including bare daemons such as WindowServer, so
/// any process can be found. An expanded group lists its processes collapsed by name, e.g.
/// "Google Chrome Helper (Renderer) ×14". Ungrouped, there is one row per process.
///
/// **Footer.** "Apps" are counted as the Overview Processes tile and its "Show All N Apps" link count
/// them: groups with an `.app` bundle. Daemon rows are covered by "processes grouped", the processes
/// in the rows shown. So "Show All 61 Apps" lands on "Showing 61 of 61 apps".
public struct OverviewList: Equatable, Sendable {
    public struct Row: Equatable, Sendable, Identifiable {
        public enum Kind: Equatable, Sendable {
            /// An app group (grouped view).
            case app
            /// Processes of an expanded group that share a name.
            case helper
            /// One process (ungrouped view).
            case process
        }

        public var id: String
        public var kind: Kind
        /// The group this row belongs to; quitting any row quits that app.
        public var appID: AppUsage.ID
        /// The group's name, e.g. "Google Chrome" on its helpers' rows.
        public var appName: String
        /// e.g. "Google Chrome", "Google Chrome Helper (Renderer) ×14", "mds_stores".
        public var name: String
        /// For the icon: the group's bundle, or nil for a bare executable.
        public var bundlePath: String?
        /// Formatted figures by column; a missing column couldn't be read and shows as a dash.
        public var values: [OverviewListColumn: String]
        /// Whether the row has helpers to show, and whether they're shown.
        public var isExpandable: Bool
        public var isExpanded: Bool
        /// Whether its app is a running regular app, the only kind offered to quit.
        public var canQuit: Bool
    }

    /// Group rows with their shown helpers right after them, or process rows.
    public var rows: [Row]
    /// e.g. "Sorted by CPU".
    public var sortLabel: String
    /// e.g. "Showing 14 of 61 apps · 1,048 processes grouped", "Showing 40 of 1,048 processes".
    public var footer: String
    /// System totals for the footer: CPU, Memory, GPU, Network, Power.
    public var totals: [Total]
    /// Shown instead of rows: while the process list warms up, or when nothing matches the search.
    public var emptyMessage: String?

    public struct Total: Equatable, Sendable, Identifiable {
        public var column: OverviewListColumn
        /// e.g. "CPU 32%", "Network 4.2 MB/s", "Power —".
        public var text: String

        public var id: OverviewListColumn { column }
    }
}

extension OverviewList {
    /// One sortable thing: an app group, a set of same-named helpers, or a process.
    fileprivate struct Entry {
        var name: String
        var count: Int
        /// In cores.
        var cpu: Double
        var resources: ResourceUse
        /// Position in the input (busiest CPU first), the tie-break.
        var order: Int
    }

    static func make(
        snapshot: Snapshot?, apps: [AppUsage], query: OverviewListQuery, preferences: Preferences
    ) -> OverviewList {
        let processes = snapshot?.processes.value ?? []
        let cores = max(snapshot?.system.logicalCores ?? 1, 1)
        let format = Formatter(cores: cores, mode: preferences.cpuMode, units: preferences.networkUnits)
        let members = membership(processes)
        let needle = query.search.trimmingCharacters(in: .whitespaces)
        func matches(_ name: String) -> Bool { needle.isEmpty || name.localizedCaseInsensitiveContains(needle) }

        let rows: [Row]
        let footer: String
        if query.grouped {
            var shown: [(app: AppUsage, helpers: [ProcessSample], openedBySearch: Bool)] = []
            for app in apps {
                let all = members[app.id] ?? []
                if matches(app.name) {
                    shown.append((app, all, false))
                } else {
                    let hits = all.filter { matches($0.name) }
                    if !hits.isEmpty { shown.append((app, hits, true)) }
                }
            }
            let entries = shown.enumerated().map { index, item in
                Entry(name: item.app.name, count: item.app.processCount, cpu: item.app.cpu,
                      resources: item.app.resources, order: index)
            }
            rows = sorted(entries, by: query.sort).flatMap { entry -> [Row] in
                let (app, helpers, openedBySearch) = shown[entry.order]
                let expanded = openedBySearch || query.expanded.contains(app.id)
                let row = Row(id: app.id, kind: .app, appID: app.id, appName: app.name, name: app.name, bundlePath: app.bundlePath,
                              values: format.values(entry), isExpandable: app.processCount > 1,
                              isExpanded: expanded && app.processCount > 1, canQuit: app.canQuit)
                guard row.isExpanded else { return [row] }
                return [row] + helperRows(helpers, of: app, sort: query.sort, format: format)
            }
            let bundled = OverviewTiles.bundled(apps)
            let shownBundled = shown.filter { $0.app.bundlePath != nil }.count
            let grouped = shown.map(\.app.processCount).reduce(0, +)
            footer = "Showing \(Format.count(shownBundled)) of \(Format.count(bundled.count)) "
                + "\(bundled.count == 1 ? "app" : "apps") · \(Format.count(grouped)) "
                + "\(grouped == 1 ? "process" : "processes") grouped"
        } else {
            let byPID = Dictionary(processes.map { ($0.pid, $0) }, uniquingKeysWith: { first, _ in first })
            let appsByID = Dictionary(apps.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            // Processes arrive in pid order; rank them by CPU first, so ties keep the busiest on top.
            let shown = processes.compactMap { process -> (process: ProcessSample, app: AppUsage?)? in
                let owner = AppGrouping.owner(of: process, byPID: byPID)
                guard matches(process.name) || matches(owner.name) else { return nil }
                return (process, appsByID[owner.id])
            }
            .enumerated().sorted { $0.element.process.cpu != $1.element.process.cpu
                ? $0.element.process.cpu > $1.element.process.cpu : $0.offset < $1.offset }
            .map(\.element)
            let entries = shown.enumerated().map { index, item in
                Entry(name: item.process.name, count: 1, cpu: item.process.cpu, resources: item.process.resources,
                      order: index)
            }
            rows = sorted(entries, by: query.sort).map { entry in
                let (process, app) = shown[entry.order]
                return Row(id: "pid:\(process.pid)", kind: .process, appID: app?.id ?? process.name,
                           appName: app?.name ?? process.name,
                           name: process.name, bundlePath: app?.bundlePath, values: format.values(entry),
                           isExpandable: false, isExpanded: false, canQuit: app?.canQuit ?? false)
            }
            footer = "Showing \(Format.count(rows.count)) of \(Format.count(processes.count)) "
                + (processes.count == 1 ? "process" : "processes")
        }

        let emptyMessage: String? = if processes.isEmpty {
            "Waiting for the process list…"
        } else if rows.isEmpty {
            "No apps or processes match “\(needle)”"
        } else {
            nil
        }
        return OverviewList(rows: rows, sortLabel: query.sort.sortLabel, footer: footer,
                            totals: totals(snapshot, format: format), emptyMessage: emptyMessage)
    }

    /// Each group's processes, in input order. Built once per list, not per row.
    static func membership(_ processes: [ProcessSample]) -> [AppUsage.ID: [ProcessSample]] {
        let byPID = Dictionary(processes.map { ($0.pid, $0) }, uniquingKeysWith: { first, _ in first })
        return Dictionary(grouping: processes) { AppGrouping.owner(of: $0, byPID: byPID).id }
    }

    /// An expanded group's processes, collapsed by name: "Google Chrome Helper (Renderer) ×14".
    private static func helperRows(
        _ processes: [ProcessSample], of app: AppUsage, sort: OverviewListColumn, format: Formatter
    ) -> [Row] {
        var names: [String] = []
        var byName: [String: Entry] = [:]
        for process in processes {
            if var entry = byName[process.name] {
                entry.count += 1
                entry.cpu += process.cpu
                entry.resources = entry.resources + process.resources
                byName[process.name] = entry
            } else {
                byName[process.name] = Entry(name: process.name, count: 1, cpu: process.cpu,
                                             resources: process.resources, order: names.count)
                names.append(process.name)
            }
        }
        // Rank by CPU first, so equal figures keep the busier helper on top, as app rows do.
        let ranked = sorted(names.compactMap { byName[$0] }, by: .cpu).enumerated().map { rank, entry in
            var entry = entry
            entry.order = rank
            return entry
        }
        return sorted(ranked, by: sort).map { entry in
            Row(id: "\(app.id)\u{0}\(entry.name)", kind: .helper, appID: app.id, appName: app.name,
                name: entry.count > 1 ? "\(entry.name) ×\(entry.count)" : entry.name, bundlePath: nil,
                values: format.values(entry), isExpandable: false, isExpanded: false, canQuit: app.canQuit)
        }
    }

    private static func sorted(_ entries: [Entry], by column: OverviewListColumn) -> [Entry] {
        entries.sorted(by: column)
    }

    private static func totals(_ snapshot: Snapshot?, format: Formatter) -> [Total] {
        let dash = Format.placeholder
        let cpu = snapshot?.cpu.value.map { format.cpu($0.total * Double(format.cores), decimals: 0) }
        let memory = snapshot?.memory.value.map { Format.memorySize($0.used) }
        let gpu = snapshot?.gpu.value.map { Format.percent($0.utilization) }
        let network = snapshot?.network.value.map { format.rate($0.downloadPerSecond + $0.uploadPerSecond) }
        let power = snapshot?.battery.value?.systemPower.map(BatteryDetail.watts)
        return [(OverviewListColumn.cpu, cpu), (.memory, memory), (.gpu, gpu), (.network, network), (.power, power)]
            .map { Total(column: $0, text: "\($0.title) \($1 ?? dash)") }
    }

    /// Formats an entry's figures in the user's CPU mode and network units.
    private struct Formatter {
        var cores: Int
        var mode: CPUMode
        var units: NetworkUnits

        /// `coresBusy` is in cores, as processes report CPU.
        func cpu(_ coresBusy: Double, decimals: Int = 1) -> String {
            Format.cpu(coresBusy / Double(cores), mode: mode, logicalCores: cores, decimals: decimals)
        }

        func rate(_ bytesPerSecond: Double) -> String {
            NetworkFormat.rate(bytesPerSecond, units: units).text
        }

        func values(_ entry: Entry) -> [OverviewListColumn: String] {
            let resources = entry.resources
            var values: [OverviewListColumn: String] = [
                .processes: Format.count(entry.count),
                .cpu: cpu(entry.cpu),
            ]
            values[.memory] = resources.memory.map(Format.memorySize)
            values[.gpu] = resources.gpu.map(GPUFormat.appShare)
            values[.network] = resources.network.map(rate)
            values[.disk] = diskRate(resources).map(DiskFormat.rate)
            values[.power] = resources.power.map(BatteryDetail.watts)
            return values
        }
    }

    fileprivate static func diskRate(_ resources: ResourceUse) -> Double? {
        switch (resources.diskReadPerSecond, resources.diskWritePerSecond) {
        case (nil, nil): nil
        case let (read, write): (read ?? 0) + (write ?? 0)
        }
    }
}

private extension Array where Element == OverviewList.Entry {
    /// Figures highest first with unreadable ones last; App by name; ties keep input order.
    func sorted(by column: OverviewListColumn) -> [Element] {
        func key(_ entry: Element) -> Double? {
            switch column {
            case .app: nil
            case .processes: Double(entry.count)
            case .cpu: entry.cpu
            case .memory: entry.resources.memory.map(Double.init)
            case .gpu: entry.resources.gpu
            case .network: entry.resources.network
            case .disk: OverviewList.diskRate(entry.resources)
            case .power: entry.resources.power
            }
        }
        return sorted { lhs, rhs in
            if column == .app {
                let order = lhs.name.localizedStandardCompare(rhs.name)
                return order != .orderedSame ? order == .orderedAscending : lhs.order < rhs.order
            }
            switch (key(lhs), key(rhs)) {
            case let (a?, b?) where a != b: return a > b
            case (_?, nil): return true
            case (nil, _?): return false
            default: return lhs.order < rhs.order
            }
        }
    }
}

extension Monitor {
    /// The main window's Overview tab, List view.
    public func overviewList(_ query: OverviewListQuery) -> OverviewList {
        OverviewList.make(snapshot: latest, apps: apps, query: query, preferences: preferences)
    }
}
