import AppKit
import MoniMacCore
import MoniMacSystem
import SwiftUI

/// The main window's Projects tab. Renders `ProjectDetail`; holds no logic.
struct ProjectsWindowTab: View {
    let monitor: Monitor

    var body: some View {
        ProjectsContent(detail: monitor.projectDetail, monitor: monitor)
            // Finding project roots inside Documents and the like asks macOS for access; ask here,
            // where the prompt makes sense, rather than at a random moment after launch.
            .onAppear(perform: ProjectFolderAccess.allow)
    }
}

private enum Columns {
    static let port: CGFloat = 90
    static let uptime: CGFloat = 90
    static let memory: CGFloat = 90
    static let activity: CGFloat = 130
    static let action: CGFloat = 28
}

private struct ProjectsContent: View {
    let detail: ProjectDetail
    let monitor: Monitor

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let banner = detail.banner {
                IdleBanner(banner: banner, monitor: monitor)
            }
            if let empty = detail.emptyMessage {
                VStack(spacing: 6) {
                    Image(systemName: "folder").font(.system(size: 22)).foregroundStyle(Palette.textTertiary)
                    Text(empty).font(.system(size: 13, weight: .semibold)).foregroundStyle(Palette.textSecondary)
                    Text("Servers and watchers started from a project folder, and Docker containers, appear here.")
                        .font(.system(size: 11)).foregroundStyle(Palette.textTertiary)
                }
                .frame(maxWidth: .infinity, minHeight: 200)
            } else {
                columnHeader
                ForEach(detail.projects) { project in
                    ProjectCard(project: project, monitor: monitor)
                }
            }
            if let note = detail.dockerNote {
                Text(note).font(.system(size: 11)).foregroundStyle(Palette.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
        }
    }

    private var columnHeader: some View {
        HStack(spacing: 12) {
            header("Server").frame(maxWidth: .infinity, alignment: .leading)
            header("Port").frame(width: Columns.port, alignment: .leading)
            header("Uptime").frame(width: Columns.uptime, alignment: .leading)
            header("Memory").frame(width: Columns.memory, alignment: .leading)
            header("Activity").frame(width: Columns.activity, alignment: .leading)
            Color.clear.frame(width: Columns.action, height: 1)
        }
        .padding(.horizontal, 16)
    }

    private func header(_ title: String) -> some View {
        Text(title).font(.system(size: 11, weight: .semibold)).foregroundStyle(Palette.textTertiary)
    }
}

private struct IdleBanner: View {
    let banner: ProjectDetail.Banner
    let monitor: Monitor

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "sparkles")
                .font(.system(size: 15))
                .foregroundStyle(ProjectsPalette.warning)
                .frame(width: 32, height: 32)
                .background(RoundedRectangle(cornerRadius: 8).fill(ProjectsPalette.warning.opacity(0.15)))
            VStack(alignment: .leading, spacing: 2) {
                Text(banner.title).font(.system(size: 13, weight: .bold)).foregroundStyle(Palette.textPrimary)
                Text(banner.message).font(.system(size: 11)).foregroundStyle(Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button("Ignore") { monitor.ignoreIdleServers() }
                .buttonStyle(BannerButtonStyle(fill: Palette.surfaceRaised, text: Palette.textPrimary, bordered: true))
            Button("Stop Idle Servers") { monitor.stopIdleServers() }
                .buttonStyle(BannerButtonStyle(fill: ProjectsPalette.warning, text: .white, bordered: false))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(RoundedRectangle(cornerRadius: 12).fill(ProjectsPalette.warning.opacity(0.08)))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(ProjectsPalette.warning.opacity(0.35), lineWidth: 1))
    }
}

private struct BannerButtonStyle: ButtonStyle {
    let fill: Color
    let text: Color
    let bordered: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(text)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 6).fill(fill))
            .overlay {
                if bordered { RoundedRectangle(cornerRadius: 6).stroke(Palette.separator, lineWidth: 1) }
            }
            .opacity(configuration.isPressed ? 0.7 : 1)
            .contentShape(Rectangle())
    }
}

private struct ProjectCard: View {
    let project: ProjectDetail.Project
    let monitor: Monitor

    var body: some View {
        VStack(spacing: 0) {
            header
            ForEach(Array(project.servers.enumerated()), id: \.element.id) { index, server in
                ServerRow(server: server, monitor: monitor)
                if index < project.servers.count - 1 {
                    Rectangle().fill(Palette.separator).frame(height: 1)
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Palette.separator, lineWidth: 1))
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: project.path == nil ? "shippingbox" : "folder")
                .font(.system(size: 14))
                .foregroundStyle(project.isForgotten ? ProjectsPalette.warning : Palette.accent)
                .frame(width: 16)
            Text(project.name).font(.system(size: 13, weight: .bold)).foregroundStyle(Palette.textPrimary)
                .lineLimit(1)
            if let path = project.path {
                Text(path).font(.system(size: 11)).foregroundStyle(Palette.textTertiary)
                    .lineLimit(1).truncationMode(.middle)
            }
            HStack(spacing: 4) {
                Image(systemName: "arrow.triangle.branch").font(.system(size: 9))
                Text(project.summary).font(.system(size: 10, weight: .medium)).lineLimit(1)
            }
            .foregroundStyle(Palette.textSecondary)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(RoundedRectangle(cornerRadius: 5).fill(Palette.track))
            .fixedSize()
            Spacer(minLength: 8)
            Text(project.memory).font(.system(size: 12, weight: .semibold).monospacedDigit())
                .foregroundStyle(Palette.textPrimary)
            if project.path != nil {
                Button { monitor.revealProject(id: project.id) } label: {
                    Image(systemName: "folder.badge.gearshape").font(.system(size: 13))
                        .foregroundStyle(Palette.textSecondary)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Show in Finder")
            }
            Button { monitor.stopProject(id: project.id) } label: {
                Text("Stop All").font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(project.isForgotten ? ProjectsPalette.danger : Palette.accent)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Stop every server in \(project.name)")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Palette.surface)
        .overlay(alignment: .bottom) { Rectangle().fill(Palette.separator).frame(height: 1) }
    }
}

private struct ServerRow: View {
    let server: ProjectDetail.Server
    let monitor: Monitor

    private var forgotten: Bool { server.level == .forgotten }

    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: ProjectsPalette.symbol(server.kind.runtime))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 24, height: 24)
                    .background(RoundedRectangle(cornerRadius: 6).fill(ProjectsPalette.color(server.kind.runtime)))
                VStack(alignment: .leading, spacing: 1) {
                    Text(server.command)
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Palette.textPrimary)
                        .lineLimit(1).truncationMode(.middle)
                        .help(server.command)
                    Text(server.kind.name).font(.system(size: 10)).foregroundStyle(Palette.textSecondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            port.frame(width: Columns.port, alignment: .leading)
            Text(server.uptime).font(.system(size: 12).monospacedDigit()).foregroundStyle(Palette.textSecondary)
                .frame(width: Columns.uptime, alignment: .leading)
            Text(server.memory).font(.system(size: 12, weight: .semibold).monospacedDigit())
                .foregroundStyle(Palette.textPrimary)
                .frame(width: Columns.memory, alignment: .leading)
            HStack(spacing: 6) {
                Circle().fill(dotColor).frame(width: 7, height: 7)
                Text(server.activity).font(.system(size: 12, weight: forgotten ? .semibold : .regular))
                    .foregroundStyle(forgotten ? ProjectsPalette.warning : Palette.textSecondary)
                    .lineLimit(1)
            }
            .frame(width: Columns.activity, alignment: .leading)
            Button { monitor.stopServer(id: server.id) } label: {
                Image(systemName: "stop.fill").font(.system(size: 9))
                    .foregroundStyle(forgotten ? ProjectsPalette.danger : Palette.textSecondary)
                    .frame(width: Columns.action, height: 24)
                    .background(RoundedRectangle(cornerRadius: 6)
                        .fill(forgotten ? ProjectsPalette.danger.opacity(0.1) : Palette.track))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(server.level == .stopping)
            .help("Stop \(server.command)")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
    }

    @ViewBuilder
    private var port: some View {
        if let first = server.ports.first {
            Button { monitor.openServer(port: first) } label: {
                HStack(spacing: 4) {
                    Text(":\(String(first))").font(.system(size: 11, weight: .semibold, design: .monospaced))
                    Image(systemName: "arrow.up.right").font(.system(size: 8, weight: .bold))
                }
                .foregroundStyle(Palette.accent)
                .padding(.horizontal, 7)
                .padding(.vertical, 2)
                .background(RoundedRectangle(cornerRadius: 5).fill(Palette.accent.opacity(0.14)))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(server.portHelp ?? "")
        } else {
            Text(Format.placeholder).font(.system(size: 12)).foregroundStyle(Palette.textTertiary)
        }
    }

    private var dotColor: Color {
        switch server.level {
        case .active: Palette.success
        case .idle, .stopping: Palette.textTertiary
        case .forgotten: ProjectsPalette.warning
        }
    }
}

/// The design's warning and danger tokens and the runtime badge colors, which `Palette` doesn't have.
enum ProjectsPalette {
    static let warning = color(light: 0xFF9F0A, dark: 0xFFB340)
    static let danger = color(light: 0xFF3B30, dark: 0xFF453A)

    static func color(_ runtime: ServerRuntime) -> Color {
        switch runtime {
        case .node: Color(red: 0x5F / 255, green: 0xA0 / 255, blue: 0x4E / 255)
        case .python: Color(red: 0x37 / 255, green: 0x76 / 255, blue: 0xAB / 255)
        case .docker: Color(red: 0x24 / 255, green: 0x96 / 255, blue: 0xED / 255)
        case .ruby: Color(red: 0xCC / 255, green: 0x34 / 255, blue: 0x2D / 255)
        case .other: Color(red: 0x8E / 255, green: 0x8E / 255, blue: 0x93 / 255)
        }
    }

    static func symbol(_ runtime: ServerRuntime) -> String {
        switch runtime {
        case .node: "hexagon"
        case .python: "chevron.left.forwardslash.chevron.right"
        case .docker: "shippingbox"
        case .ruby: "diamond"
        case .other: "terminal"
        }
    }

    private static func color(light: UInt32, dark: UInt32) -> Color {
        func color(_ rgb: UInt32) -> NSColor {
            NSColor(srgbRed: CGFloat((rgb >> 16) & 0xFF) / 255, green: CGFloat((rgb >> 8) & 0xFF) / 255,
                    blue: CGFloat(rgb & 0xFF) / 255, alpha: 1)
        }
        return Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? color(dark) : color(light)
        })
    }
}
