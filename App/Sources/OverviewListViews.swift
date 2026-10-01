import AppKit
import MoniMacCore
import SwiftUI

/// Opens Overview → List sorted by a column, e.g. from a "Top Apps by …" section's "Show All".
struct ShowInListAction {
    let handler: @MainActor (OverviewListColumn) -> Void

    @MainActor
    func callAsFunction(_ column: OverviewListColumn) {
        handler(column)
    }
}

extension EnvironmentValues {
    @Entry var showInList = ShowInListAction { _ in }
}

/// A "Show All" link that opens the Overview List sorted by `column`.
struct ShowAllButton: View {
    var title = "Show All"
    let column: OverviewListColumn
    @Environment(\.showInList) private var showInList

    var body: some View {
        Button(title) { showInList(column) }
            .buttonStyle(.plain)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(Palette.accent)
            .help("Show every app, sorted by \(column.title)")
    }
}

/// The main window's Overview tab in the List view. Renders `OverviewList`; holds no logic.
struct OverviewListTab: View {
    let monitor: Monitor
    @Binding var query: OverviewListQuery

    var body: some View {
        OverviewListContent(list: monitor.overviewList(query), query: $query)
    }
}

extension OverviewListColumn {
    /// The column's width in the table; App takes the rest.
    var width: CGFloat? {
        switch self {
        case .app: nil
        case .processes: 56
        case .cpu: 72
        case .memory: 84
        case .gpu: 64
        case .network: 88
        case .disk: 84
        case .power: 72
        }
    }

    var color: Color? {
        switch self {
        case .app, .processes: nil
        case .cpu: Palette.cpu
        case .memory: Palette.memory
        case .gpu: Palette.gpu
        case .network: Palette.network
        case .disk: Palette.disk
        case .power: Palette.success
        }
    }
}

private struct OverviewListContent: View {
    let list: OverviewList
    @Binding var query: OverviewListQuery

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            filterBar
            table
            footer
        }
    }

    private var filterBar: some View {
        HStack {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").font(.system(size: 11)).foregroundStyle(Palette.textTertiary)
                TextField("Search apps and processes", text: $query.search)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                if !query.search.isEmpty {
                    Button { query.search = "" } label: {
                        Image(systemName: "xmark.circle.fill").font(.system(size: 11))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Palette.textTertiary)
                    .help("Clear search")
                }
            }
            .padding(.horizontal, 10)
            .frame(width: 260, height: 28)
            .background(RoundedRectangle(cornerRadius: 7).fill(Palette.surface))
            .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Palette.separator))
            Spacer()
            HStack(spacing: 16) {
                Menu {
                    Picker("Sort by", selection: $query.sort) {
                        ForEach(OverviewListColumn.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.inline)
                } label: {
                    Text(list.sortLabel).font(.system(size: 11)).foregroundStyle(Palette.textSecondary)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.visible)
                .fixedSize()
                Toggle(isOn: $query.grouped) {
                    Text("Group processes by app").font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Palette.textPrimary)
                }
                .toggleStyle(.switch)
                .controlSize(.mini)
            }
        }
    }

    private var table: some View {
        VStack(spacing: 0) {
            header
            Rectangle().fill(Palette.separator).frame(height: 1)
            if let message = list.emptyMessage {
                Text(message).font(.system(size: 12)).foregroundStyle(Palette.textSecondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(list.rows.enumerated()), id: \.element.id) { index, row in
                            OverviewListRow(row: row, sort: query.sort, striped: index % 2 == 1) {
                                query.toggle(row.appID)
                            }
                        }
                    }
                }
            }
        }
        .frame(maxHeight: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Palette.separator))
    }

    private var header: some View {
        HStack(spacing: 0) {
            ForEach(OverviewListColumn.allCases, id: \.self) { column in
                let sorted = column == query.sort
                Button { query.sort = column } label: {
                    HStack(spacing: 5) {
                        if let color = column.color { Circle().fill(color).frame(width: 6, height: 6) }
                        Text(column.title)
                            .foregroundStyle(sorted ? Palette.accent : Palette.textSecondary)
                        if sorted {
                            Image(systemName: column.sortsAscending ? "chevron.up" : "chevron.down")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundStyle(Palette.accent)
                        }
                    }
                    .frame(maxWidth: column.width == nil ? .infinity : nil,
                           alignment: column == .app ? .leading : .trailing)
                    .frame(width: column.width, alignment: .trailing)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(column.sortLabel)
            }
        }
        .font(.system(size: 11, weight: .semibold))
        .padding(.horizontal, 14)
        .frame(height: 30)
        .background(Palette.surface)
    }

    private var footer: some View {
        HStack {
            Text(list.footer)
            Spacer()
            HStack(spacing: 16) {
                ForEach(list.totals) { total in
                    HStack(spacing: 5) {
                        if let color = total.column.color { Circle().fill(color).frame(width: 6, height: 6) }
                        Text(total.text).fontWeight(.medium).monospacedDigit()
                    }
                }
            }
        }
        .font(.system(size: 11))
        .foregroundStyle(Palette.textSecondary)
        .padding(.horizontal, 4)
    }
}

/// One row: an app group with its disclosure, a helper line under an open group, or a process.
private struct OverviewListRow: View {
    let row: OverviewList.Row
    let sort: OverviewListColumn
    let striped: Bool
    let toggle: () -> Void
    @Environment(\.requestQuit) private var requestQuit
    @State private var hovering = false

    private var isHelper: Bool { row.kind == .helper }

    var body: some View {
        HStack(spacing: 0) {
            appCell.frame(maxWidth: .infinity, alignment: .leading)
            ForEach(OverviewListColumn.figures, id: \.self) { column in
                let value = row.values[column]
                Text(value ?? Format.placeholder)
                    .font(.system(size: isHelper ? 11 : 12, weight: column == sort && !isHelper ? .semibold : .regular)
                        .monospacedDigit())
                    .foregroundStyle(value == nil ? Palette.textTertiary
                        : isHelper ? Palette.textSecondary : Palette.textPrimary)
                    .lineLimit(1)
                    .frame(width: column.width, alignment: .trailing)
            }
        }
        .padding(.horizontal, 14)
        .frame(height: isHelper ? 26 : 32)
        .background(background)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture { if row.isExpandable { toggle() } }
        .contextMenu {
            if row.canQuit {
                Button("Quit \(row.appName)…") { requestQuit(row.appID) }
            }
        }
    }

    private var background: Color {
        if hovering { return Palette.accent.opacity(0.10) }
        if isHelper { return Palette.surface }
        return striped ? Palette.surface : .clear
    }

    @ViewBuilder
    private var appCell: some View {
        if isHelper {
            HStack(spacing: 8) {
                Image(systemName: "arrow.turn.down.right").font(.system(size: 10)).foregroundStyle(Palette.textTertiary)
                Text(row.name).font(.system(size: 11)).foregroundStyle(Palette.textSecondary).lineLimit(1)
            }
            .padding(.leading, 46)
        } else {
            HStack(spacing: 8) {
                if row.kind == .app {
                    Image(systemName: row.isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Palette.textTertiary)
                        .frame(width: 12)
                        .opacity(row.isExpandable ? 1 : 0)
                }
                Image(nsImage: AppIcons.icon(for: row.bundlePath)).resizable().frame(width: 20, height: 20)
                Text(row.name).font(.system(size: 12, weight: .medium)).foregroundStyle(Palette.textPrimary)
                    .lineLimit(1)
                if row.canQuit && hovering {
                    Button { requestQuit(row.appID) } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(Palette.textSecondary)
                            .frame(width: 18, height: 18)
                            .background(Circle().fill(Palette.track))
                    }
                    .buttonStyle(.plain)
                    .help("Quit \(row.appName)…")
                }
            }
        }
    }
}
