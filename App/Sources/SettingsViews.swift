import MoniMacCore
import SwiftUI

/// The main window's Settings tab. Renders `SettingsPanel`; every change goes through a Monitor intent.
struct SettingsWindowTab: View {
    let monitor: Monitor

    /// The app's marketing version, e.g. "1.4.2".
    static let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
    /// The toolbar subtitle, e.g. "MoniMac 1.4.2".
    static var subtitle: String { SettingsPanel.about(version: version) }

    var body: some View {
        SettingsContent(panel: monitor.settingsPanel(version: Self.version), monitor: monitor)
            // Login items can also change in System Settings.
            .onAppear(perform: monitor.refreshLaunchAtLogin)
    }
}

private struct SettingsContent: View {
    let panel: SettingsPanel
    let monitor: Monitor

    var body: some View {
        HStack(alignment: .top, spacing: 24) {
            VStack(alignment: .leading, spacing: 18) {
                general
                units
                notifications
            }
            .frame(maxWidth: .infinity)
            VStack(alignment: .leading, spacing: 18) {
                menuBarItems
                windowTabs
                dataAndAbout
            }
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: Left column

    private var general: some View {
        SettingsGroup(title: "General") {
            SettingsRow(label: "Launch at login", description: panel.launchAtLoginNote) {
                if panel.launchAtLoginNote != nil {
                    Button("Open…", action: monitor.openLoginItemsSettings).controlSize(.small)
                }
                SettingsSwitch(isOn: panel.launchesAtLogin, set: monitor.setLaunchAtLogin)
            }
            SettingsRow(label: "Refresh interval") {
                choice(RefreshInterval.allCases, \.title, Binding(get: { panel.refreshInterval }, set: monitor.setRefreshInterval))
            }
            SettingsRow(label: "Show icon in Dock", isLast: true) {
                SettingsSwitch(isOn: panel.showsDockIcon, set: monitor.setShowsDockIcon)
            }
        }
    }

    private var units: some View {
        SettingsGroup(title: "Units") {
            SettingsRow(label: "Temperature") {
                choice(TemperatureUnit.allCases, \.symbol, Binding(get: { panel.temperatureUnit }, set: monitor.setTemperatureUnit))
            }
            SettingsRow(label: "Network speed") {
                choice(NetworkUnits.allCases, \.title, Binding(get: { panel.networkUnits }, set: monitor.setNetworkUnits))
            }
            SettingsRow(label: "CPU usage", description: panel.cpuModeNote, isLast: true) {
                choice(CPUMode.allCases, \.title, Binding(get: { panel.cpuMode }, set: monitor.setCPUMode))
            }
        }
    }

    /// One row per alert rule. CPU and memory pick a threshold or Off from one menu; disk and network have a
    /// switch beside their threshold, as the design draws them.
    private var notifications: some View {
        SettingsGroup(title: "Notifications") {
            ForEach(Array(panel.alertRules.enumerated()), id: \.element.id) { index, row in
                SettingsRow(label: row.label, description: row.description,
                            isLast: index == panel.alertRules.count - 1) {
                    ThresholdPopup(row: row, monitor: monitor)
                    if row.hasSwitch {
                        SettingsSwitch(isOn: row.isEnabled) { monitor.setAlertEnabled($0, for: row.rule) }
                    }
                }
            }
        }
    }

    // MARK: Right column

    private var menuBarItems: some View {
        VStack(alignment: .leading, spacing: 8) {
            SettingsGroup(title: "Menu Bar Items") {
                ForEach(Array(panel.menuBarRows.enumerated()), id: \.element.id) { index, row in
                    MenuBarItemRow(row: row, monitor: monitor, isLast: index == panel.menuBarRows.count - 1)
                }
            }
            HStack(spacing: 6) {
                Image(systemName: "command").font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Palette.textTertiary)
                Text("⌘-drag items in the menu bar to reorder them")
                    .font(.system(size: 11)).foregroundStyle(Palette.textSecondary)
            }
            .padding(.horizontal, 4)
        }
    }

    private var windowTabs: some View {
        SettingsGroup(title: "Window Tabs") {
            VStack(alignment: .leading, spacing: 8) {
                ChipFlow(spacing: 6) {
                    ForEach(panel.windowTabs) { chip in
                        TabChip(chip: chip) { monitor.setTabShown(!chip.isShown, chip.tab) }
                    }
                }
                Text("Drag tabs in the sidebar to change their order. Sections inside each tab can be rearranged too.")
                    .font(.system(size: 11)).foregroundStyle(Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var dataAndAbout: some View {
        SettingsGroup(title: "Data & About") {
            SettingsRow(label: "Keep history", description: "Per-app CPU, memory, network and disk") {
                Picker("Keep history", selection: Binding(get: { panel.keepHistory }, set: monitor.setKeepHistory)) {
                    ForEach(HistoryRetention.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .fixedSize()
            }
            SettingsRow(label: panel.about, description: "Free and open source", isLast: true) {
                Button("Source", action: monitor.openSourceCode).buttonStyle(.link).font(.system(size: 12))
                Button("Release Notes", action: monitor.openReleaseNotes).buttonStyle(.link).font(.system(size: 12))
                // Update checks arrive with ticket 20.
                Button("Check for Updates…") {}
                    .controlSize(.small)
                    .disabled(true)
                    .help("Coming soon")
            }
        }
    }

    private func choice<Value: Hashable>(
        _ options: [Value], _ label: @escaping (Value) -> String, _ selection: Binding<Value>
    ) -> some View {
        SegmentedPicker(options: options, selection: selection, label: label, horizontalPadding: 9)
            .fixedSize()
    }
}

// MARK: Components

/// A titled box of rows, as the design draws every Settings section.
private struct SettingsGroup<Content: View>: View {
    let title: String
    var note: String?
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(title).font(.system(size: 12, weight: .bold)).foregroundStyle(Palette.textSecondary)
                if let note {
                    Text(note).font(.system(size: 11)).foregroundStyle(Palette.textTertiary)
                }
            }
            VStack(spacing: 0, content: content)
                .background(RoundedRectangle(cornerRadius: 10).fill(Palette.surface))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Palette.separator, lineWidth: 1))
        }
    }
}

private struct SettingsRow<Control: View>: View {
    let label: String
    var description: String?
    var isLast = false
    @ViewBuilder let control: () -> Control

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(label).font(.system(size: 13, weight: .medium)).foregroundStyle(Palette.textPrimary)
                if let description {
                    Text(description).font(.system(size: 11)).foregroundStyle(Palette.textSecondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            control()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .rowSeparator(isLast: isLast)
    }
}

extension View {
    /// The line between rows of a Settings box; the last row has none.
    fileprivate func rowSeparator(isLast: Bool) -> some View {
        overlay(alignment: .bottom) {
            if !isLast { Rectangle().fill(Palette.separator).frame(height: 1) }
        }
    }
}

/// A small switch. With no `set` it's shown disabled.
private struct SettingsSwitch: View {
    let isOn: Bool
    let set: ((Bool) -> Void)?

    var body: some View {
        Toggle("", isOn: Binding(get: { isOn }, set: { set?($0) }))
            .toggleStyle(.switch)
            .controlSize(.small)
            .labelsHidden()
            .tint(Palette.success)
            .disabled(set == nil)
    }
}

/// An alert rule's threshold menu, e.g. "80% ⌃". Rules without a switch also turn off here.
private struct ThresholdPopup: View {
    let row: AlertRuleRow
    let monitor: Monitor

    var body: some View {
        Menu {
            ForEach(row.options) { option in
                Button {
                    monitor.setAlertThreshold(option.value, for: row.rule)
                } label: {
                    if option.isSelected { Label(option.title, systemImage: "checkmark") } else { Text(option.title) }
                }
            }
            if !row.hasSwitch {
                Divider()
                Button {
                    monitor.setAlertEnabled(false, for: row.rule)
                } label: {
                    if row.isEnabled { Text("Off") } else { Label("Off", systemImage: "checkmark") }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Text(row.menuTitle)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Palette.textPrimary)
                Image(systemName: "chevron.up.chevron.down").font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Palette.textSecondary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(RoundedRectangle(cornerRadius: 6).fill(Palette.surfaceRaised))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Palette.separator, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .disabled(row.hasSwitch && !row.isEnabled)
        .opacity(row.hasSwitch && !row.isEnabled ? 0.5 : 1)
    }
}

private struct MenuBarItemRow: View {
    let row: SettingsPanel.MenuBarRow
    let monitor: Monitor
    let isLast: Bool

    var body: some View {
        HStack(spacing: 10) {
            // The menu bar's own order is set by ⌘-dragging the items; this list keeps a fixed order.
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Palette.textTertiary)
                .help("⌘-drag the item in the menu bar to move it")
            Button {
                monitor.setMenuBarItemEnabled(!row.isEnabled, for: row.metric)
            } label: {
                Checkbox(isOn: row.isEnabled)
            }
            .buttonStyle(.plain)
            .disabled(!row.canToggle)
            .help(row.canToggle ? "" : "MoniMac keeps at least one menu bar item")
            Image(systemName: row.metric.symbolName)
                .font(.system(size: 12))
                .frame(width: 16)
                .foregroundStyle(row.isEnabled ? row.metric.color : Palette.textTertiary)
            Text(row.metric.title)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(row.isEnabled ? Palette.textPrimary : Palette.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            SegmentedPicker(options: MenuBarStyle.allCases,
                            selection: Binding(get: { row.style }, set: { monitor.setMenuBarStyle($0, for: row.metric) }),
                            label: \.title, horizontalPadding: 9)
                .fixedSize()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .rowSeparator(isLast: isLast)
    }
}

private struct Checkbox: View {
    let isOn: Bool
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        RoundedRectangle(cornerRadius: 4)
            .fill(isOn ? Palette.accent : Palette.surfaceRaised)
            .overlay {
                if isOn {
                    Image(systemName: "checkmark").font(.system(size: 9, weight: .bold)).foregroundStyle(.white)
                } else {
                    RoundedRectangle(cornerRadius: 4).stroke(Palette.textTertiary, lineWidth: 1)
                }
            }
            .frame(width: 16, height: 16)
            .opacity(isEnabled ? 1 : 0.5)
    }
}

/// ✓ when the tab is shown, + when it's hidden. Tabs that can't be hidden don't respond.
private struct TabChip: View {
    let chip: WindowTabChip
    let toggle: () -> Void

    var body: some View {
        Button(action: toggle) {
            HStack(spacing: 4) {
                Image(systemName: chip.isShown ? "checkmark" : "plus").font(.system(size: 9, weight: .bold))
                Text(chip.title).font(.system(size: 11, weight: .semibold))
            }
            .foregroundStyle(chip.isShown ? Palette.accent : Palette.textSecondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Capsule().fill(chip.isShown ? Palette.accent.opacity(0.14) : Palette.surfaceRaised))
            .overlay {
                if !chip.isShown { Capsule().stroke(Palette.separator, lineWidth: 1) }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(!chip.canToggle)
        .help(chip.canToggle ? (chip.isShown ? "Hide \(chip.title)" : "Show \(chip.title)") : "Always shown")
    }
}

/// Lays chips out left to right, wrapping onto new lines.
private struct ChipFlow: Layout {
    let spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = rows(subviews, width: proposal.width ?? .infinity)
        let height = rows.map(\.height).reduce(0, +) + spacing * CGFloat(max(rows.count - 1, 0))
        return CGSize(width: proposal.width ?? rows.map(\.width).max() ?? 0, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in rows(subviews, width: bounds.width) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private func rows(_ subviews: Subviews, width: CGFloat) -> [(indices: [Int], width: CGFloat, height: CGFloat)] {
        var rows: [(indices: [Int], width: CGFloat, height: CGFloat)] = []
        for (index, subview) in subviews.enumerated() {
            let size = subview.sizeThatFits(.unspecified)
            if let last = rows.indices.last, rows[last].width + spacing + size.width <= width {
                rows[last].indices.append(index)
                rows[last].width += spacing + size.width
                rows[last].height = max(rows[last].height, size.height)
            } else {
                rows.append(([index], size.width, size.height))
            }
        }
        return rows
    }
}
