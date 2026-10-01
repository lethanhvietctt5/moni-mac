import Foundation

/// The confirmation shown before quitting an app: what it's using and which processes go with it.
public struct QuitSheet: Equatable, Sendable {
    /// How many of the app's processes are listed; the rest are counted in `more`.
    public static let processLimit = 5

    public struct Process: Equatable, Sendable, Identifiable {
        public var id: Int32
        public var name: String
        public var pid: String
        /// e.g. "22.4%".
        public var cpu: String
        /// e.g. "812 MB", or a dash when unreadable.
        public var memory: String
    }

    public var appID: AppUsage.ID
    public var appName: String
    public var bundlePath: String?
    /// e.g. "Quit Google Chrome and its 23 processes?"
    public var title: String
    /// e.g. "Google Chrome is using 86% CPU and 6.8 GB of memory. Quitting asks the app to close normally
    /// so you can save your work."
    public var message: String
    /// The busiest processes first, at most `processLimit`.
    public var processes: [Process]
    /// e.g. "and 18 more helper processes"; nil when every process is listed.
    public var more: String?
    /// e.g. "Total  86% · 6.8 GB".
    public var total: String
    /// e.g. "Reopen Google Chrome windows next time".
    public var reopenLabel: String
}

/// What the user chose in the quit sheet.
public enum QuitChoice: Equatable, Sendable {
    /// Ask the app to quit normally; `reopenWindows` asks it to restore its windows next launch.
    case quit(reopenWindows: Bool)
    /// End it at once, without saving.
    case forceQuit
    case cancel
}

extension QuitSheet {
    static func make(app: AppUsage, members: [ProcessSample], logicalCores: Int, mode: CPUMode) -> QuitSheet {
        let cores = max(logicalCores, 1)
        func cpu(_ coresBusy: Double, decimals: Int) -> String {
            Format.cpu(coresBusy / Double(cores), mode: mode, logicalCores: cores, decimals: decimals)
        }
        let count = app.processCount
        let memory = app.resources.memory.map(Format.memorySize)
        // Whole percents, except below 10% where "0%" would hide a working app.
        let shown = mode == .system ? app.cpu / Double(cores) : app.cpu
        let appCPU = cpu(app.cpu, decimals: shown < 0.095 ? 1 : 0)
        let usage = "\(app.name) is using \(appCPU) CPU"
            + (memory.map { " and \($0) of memory" } ?? "") + "."
        // Busiest first; stable for equal CPU.
        let listed = members.enumerated()
            .sorted { $0.element.cpu != $1.element.cpu ? $0.element.cpu > $1.element.cpu : $0.offset < $1.offset }
            .prefix(processLimit)
            .map(\.element)
        let remaining = count - listed.count
        return QuitSheet(
            appID: app.id,
            appName: app.name,
            bundlePath: app.bundlePath,
            title: "Quit \(app.name)" + (count > 1 ? " and its \(Format.count(count)) processes?" : "?"),
            message: usage + " Quitting asks the app to close normally so you can save your work.",
            processes: listed.map { process in
                Process(id: process.pid, name: process.name, pid: String(process.pid),
                        cpu: cpu(process.cpu, decimals: 1),
                        memory: process.resources.memory.map(Format.memorySize) ?? Format.placeholder)
            },
            more: remaining > 0
                ? "and \(Format.count(remaining)) more helper \(remaining == 1 ? "process" : "processes")" : nil,
            total: "Total  \(appCPU)" + (memory.map { " · \($0)" } ?? ""),
            reopenLabel: "Reopen \(app.name) windows next time"
        )
    }
}

extension Monitor {
    /// The quit sheet for an app group, or nil when it isn't a running regular app (or has quit).
    public func quitSheet(for id: AppUsage.ID) -> QuitSheet? {
        guard let latest, let app = apps.first(where: { $0.id == id }), app.canQuit else { return nil }
        let processes = latest.processes.value ?? []
        return QuitSheet.make(app: app, members: OverviewList.membership(processes)[id] ?? [],
                              logicalCores: latest.system.logicalCores, mode: preferences.cpuMode)
    }

    /// Carries out the quit sheet's choice for an app group. Always the group's app process (its
    /// `quitPID`), never a helper; nothing happens for groups that can't be quit or on Cancel.
    public func resolveQuit(appID: AppUsage.ID, choice: QuitChoice) {
        guard choice != .cancel, let pid = apps.first(where: { $0.id == appID })?.quitPID else { return }
        switch choice {
        case .quit(let reopenWindows): actions.quitApp(pid: pid, reopenWindows: reopenWindows)
        case .forceQuit: actions.forceQuitApp(pid: pid)
        case .cancel: break
        }
    }
}
