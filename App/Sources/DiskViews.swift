import MoniMacCore
import SwiftUI

/// The popover's Disk tab. Renders `DiskPanel`; holds no logic.
struct DiskPopoverTab: View {
    let monitor: Monitor
    /// The tab's chart range, kept by the popover so it survives switching tabs.
    @Binding var range: TimeRange

    var body: some View {
        // Built once per render: building it queries history.
        DiskPopoverContent(panel: monitor.diskPanel(range: range), range: $range)
    }
}

/// The main window's Disk tab. Renders `DiskDetail`; holds no logic.
struct DiskWindowTab: View {
    let monitor: Monitor
    /// The tab's chart range, kept by the window so it survives switching tabs.
    @Binding var range: TimeRange

    var body: some View {
        DiskWindowContent(detail: monitor.diskDetail(range: range), range: $range)
    }
}

private struct DiskPopoverContent: View {
    let panel: DiskPanel
    @Binding var range: TimeRange

    var body: some View {
        VStack(spacing: 12) {
            hero
            VolumeUsageBar(usedShare: panel.usedShare, height: 6)
            DiskBars(bars: panel.history, cornerRadius: 1.5, spacing: 2)
                .frame(height: 56)
                .padding([.top, .horizontal], 8)
                .background(RoundedRectangle(cornerRadius: 8).fill(Palette.surface))
                .help("Read (solid) and write (light), up to \(panel.scale)")
            rates
            writtenToday
            storage
            writers
        }
    }

    private var hero: some View {
        // The volume line is long, so the picker sits beside it and the big number gets its own row.
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(panel.volumeLine)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Palette.textSecondary)
                    .lineLimit(1)
                Spacer()
                SegmentedPicker(options: DiskPanel.ranges, selection: $range, label: \.shortLabel, horizontalPadding: 8)
                    .fixedSize()
            }
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(panel.free)
                    .font(.system(size: 34, weight: .bold).monospacedDigit())
                    .foregroundStyle(Palette.textPrimary)
                    .fixedSize()
                Text(panel.freeCaption).font(.system(size: 12, weight: .medium)).foregroundStyle(Palette.textSecondary)
                Spacer()
            }
        }
    }

    private var rates: some View {
        HStack(spacing: 0) {
            stat(panel.read, dot: Palette.disk)
            stat(panel.write, dot: Palette.diskWrite)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 8).fill(Palette.surface))
    }

    private func stat(_ stat: DiskDetail.Stat, dot: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Circle().fill(dot).frame(width: 8, height: 8)
                Text(stat.label).font(.system(size: 12)).foregroundStyle(Palette.textSecondary)
                Text(stat.value).font(.system(size: 14, weight: .semibold).monospacedDigit())
                    .foregroundStyle(Palette.textPrimary)
            }
            Text(stat.detail).font(.system(size: 10)).foregroundStyle(Palette.textTertiary).padding(.leading, 14)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .help(ifPresent: stat.help)
    }

    private var writtenToday: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(panel.writtenToday.label).font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Palette.textPrimary)
                Text(panel.writtenToday.detail).font(.system(size: 11)).foregroundStyle(Palette.textSecondary)
                    .lineLimit(1).truncationMode(.tail)
            }
            .help(ifPresent: panel.writtenToday.help)
            Spacer()
            Text(panel.writtenToday.value).font(.system(size: 14, weight: .semibold).monospacedDigit())
                .foregroundStyle(Palette.textPrimary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 8).fill(Palette.surface))
    }

    private var storage: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Storage").font(.system(size: 13, weight: .bold)).foregroundStyle(Palette.textPrimary)
            StorageBar(storage: panel.storage, height: 8, cornerRadius: 3)
            if let storage = panel.storage {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), alignment: .leading), count: 3),
                          alignment: .leading, spacing: 6) {
                    ForEach(storage.segments, id: \.category) { segment in
                        HStack(spacing: 5) {
                            RoundedRectangle(cornerRadius: 2).fill(segment.category.color).frame(width: 8, height: 8)
                            Text(segment.category.rawValue).foregroundStyle(Palette.textSecondary)
                            Text(segment.value).fontWeight(.semibold).foregroundStyle(Palette.textPrimary)
                                .monospacedDigit()
                        }
                        .font(.system(size: 11))
                        .lineLimit(1)
                        .help(segment.hint)
                    }
                }
            } else if let status = panel.storageStatus {
                Text(status).font(.system(size: 11)).foregroundStyle(Palette.textSecondary)
            }
            if let age = panel.storageAge {
                Text(age).font(.system(size: 10)).foregroundStyle(Palette.textTertiary)
            }
        }
    }

    private var writers: some View {
        VStack(spacing: 2) {
            HStack {
                Text("Disk Writes Today").font(.system(size: 13, weight: .bold)).foregroundStyle(Palette.textPrimary)
                Spacer()
            }
            .padding(.bottom, 6)
            if panel.writesToday.isEmpty { NoWritesYet() }
            ForEach(panel.writesToday) { app in
                DiskWriterRow(app: app).padding(.vertical, 6)
            }
        }
    }
}

/// The tab's sections in default order; the user can rearrange them.
private enum DiskSection: String, WindowSection {
    case summary, breakdown, history, writers

    var width: SectionWidth {
        self == .history || self == .writers ? .half : .full
    }
}

private struct DiskWindowContent: View {
    let detail: DiskDetail
    @Binding var range: TimeRange

    var body: some View {
        ReorderableSections { (section: DiskSection) in
            switch section {
            case .summary: summary
            case .breakdown: breakdown
            case .history: history
            case .writers: writers
            }
        }
    }

    private var summary: some View {
        HStack(alignment: .top, spacing: 24) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(detail.free)
                        .font(.system(size: 40, weight: .bold).monospacedDigit())
                        .foregroundStyle(Palette.textPrimary)
                    Text(detail.freeCaption).font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Palette.textSecondary)
                }
                VolumeUsageBar(usedShare: detail.usedShare, height: 8)
            }
            .frame(width: 260, alignment: .leading)
            stat(detail.read, dot: Palette.disk)
            stat(detail.write, dot: Palette.diskWrite)
            stat(detail.writtenToday, dot: nil)
        }
    }

    private func stat(_ stat: DiskDetail.Stat, dot: Color?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                if let dot { Circle().fill(dot).frame(width: 8, height: 8) }
                Text(stat.label).font(.system(size: 11, weight: .medium)).foregroundStyle(Palette.textSecondary)
            }
            Text(stat.value).font(.system(size: 20, weight: .semibold).monospacedDigit())
                .foregroundStyle(Palette.textPrimary)
            Text(stat.detail).font(.system(size: 11)).foregroundStyle(Palette.textTertiary)
                .lineLimit(1).minimumScaleFactor(0.75)
        }
        .padding(.leading, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .leading) {
            Rectangle().fill(Palette.separator).frame(width: 1)
        }
        .help(ifPresent: stat.help)
    }

    private var breakdown: some View {
        VStack(alignment: .leading, spacing: 12) {
            StorageBar(storage: detail.storage, height: 14, cornerRadius: 5)
            if let storage = detail.storage {
                HStack(alignment: .top, spacing: 16) {
                    ForEach(storage.segments, id: \.category) { segment in
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 6) {
                                RoundedRectangle(cornerRadius: 3).fill(segment.category.color).frame(width: 10, height: 10)
                                Text(segment.category.rawValue).font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(Palette.textSecondary)
                            }
                            Text(segment.value).font(.system(size: 15, weight: .semibold).monospacedDigit())
                                .foregroundStyle(Palette.textPrimary)
                            Text(segment.hint).font(.system(size: 10)).foregroundStyle(Palette.textTertiary)
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            } else if let status = detail.storageStatus {
                Text(status).font(.system(size: 12)).foregroundStyle(Palette.textSecondary)
            }
            if let age = detail.storageAge {
                Text(age).font(.system(size: 11)).foregroundStyle(Palette.textTertiary)
            }
        }
    }

    private var history: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Read & Write").font(.system(size: 13, weight: .bold)).foregroundStyle(Palette.textPrimary)
                Spacer()
                SegmentedPicker(options: DiskDetail.ranges, selection: $range, label: \.shortLabel, horizontalPadding: 10)
                    .fixedSize()
            }
            VStack(spacing: 6) {
                HStack(spacing: 8) {
                    VStack(alignment: .trailing) {
                        ForEach(Array(detail.yAxis.enumerated()), id: \.offset) { index, label in
                            if index > 0 { Spacer() }
                            Text(label)
                        }
                    }
                    .font(.system(size: 10))
                    .foregroundStyle(Palette.textTertiary)
                    .lineLimit(1)
                    .frame(width: 52, alignment: .trailing)
                    DiskBars(bars: detail.history, cornerRadius: 2, spacing: 2)
                        .overlay(alignment: .top) { Rectangle().fill(Palette.separator).frame(height: 1) }
                        .overlay(alignment: .bottom) { Rectangle().fill(Palette.separator).frame(height: 1) }
                }
                .frame(height: 250)
                HStack {
                    ForEach(Array(detail.xAxis.enumerated()), id: \.offset) { index, label in
                        if index > 0 { Spacer() }
                        Text(label)
                    }
                }
                .font(.system(size: 10))
                .foregroundStyle(Palette.textTertiary)
                .padding(.leading, 60)
            }
            HStack(spacing: 16) {
                legend("Read", Palette.disk)
                legend("Write", Palette.diskWrite)
            }
            .padding(.leading, 60)
        }
        .frame(maxWidth: .infinity)
    }

    private func legend(_ label: String, _ color: Color) -> some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 3).fill(color).frame(width: 10, height: 10)
            Text(label).font(.system(size: 11, weight: .medium)).foregroundStyle(Palette.textSecondary)
        }
    }

    private var writers: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Disk Writes Today").font(.system(size: 13, weight: .bold)).foregroundStyle(Palette.textPrimary)
                Spacer()
                ShowAllButton(column: .disk)
            }
            .padding(.bottom, 6)
            if detail.writesToday.isEmpty { NoWritesYet().padding(.horizontal, 12) }
            ForEach(detail.writesToday) { app in
                DiskWriterRow(app: app)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
            }
        }
        .frame(maxWidth: .infinity)
    }
}
