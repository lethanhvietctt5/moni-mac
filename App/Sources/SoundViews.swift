import AppKit
import MoniMacCore
import SwiftUI

// Sound (ticket 17). The window tab renders `SoundDetail`; it holds no logic.

/// The main window's Sound tab.
struct SoundWindowTab: View {
    let monitor: Monitor

    var body: some View {
        SoundWindowContent(detail: monitor.soundDetail, monitor: monitor)
    }
}

/// The tab's sections in default order; the user can rearrange them.
private enum SoundSection: String, WindowSection {
    case output, apps, duck, muteNew

    var width: SectionWidth {
        switch self {
        case .output, .apps: .full
        case .duck, .muteNew: .half
        }
    }
}

private struct SoundWindowContent: View {
    let detail: SoundDetail
    let monitor: Monitor

    var body: some View {
        ReorderableSections(columnSpacing: 16) { (section: SoundSection) in
            switch section {
            case .output:
                if let output = detail.output {
                    OutputCard(output: output, devices: detail.devices, monitor: monitor)
                }
            case .apps: apps
            case .duck:
                OptionCard(title: SoundDetail.duckTitle, description: SoundDetail.duckDescription,
                           isOn: Binding(get: { detail.duck }, set: monitor.setSoundDuckDuringCalls),
                           enabled: detail.duckEnabled)
            case .muteNew:
                OptionCard(title: SoundDetail.muteNewTitle, description: SoundDetail.muteNewDescription,
                           isOn: Binding(get: { detail.muteNewApps }, set: monitor.setSoundMuteNewApps),
                           enabled: detail.muteNewEnabled)
            }
        }
    }

    private var apps: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(SoundDetail.appsTitle)
                    .font(.system(size: 13, weight: .bold)).foregroundStyle(Palette.textPrimary)
                Spacer()
                Button(SoundDetail.resetTitle, action: monitor.resetSoundApps)
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(detail.canReset ? Palette.accent : Palette.textTertiary)
                    .disabled(!detail.canReset)
            }
            .padding(.bottom, 6)
            if let notice = detail.notice {
                NoticeView(notice: notice, monitor: monitor).padding(.bottom, 10)
            }
            if let message = detail.message {
                Text(message)
                    .font(.system(size: 12)).foregroundStyle(Palette.textSecondary)
                    .frame(maxWidth: .infinity, minHeight: 60)
            }
            if !detail.rows.isEmpty {
                VStack(spacing: 0) {
                    ForEach(Array(detail.rows.enumerated()), id: \.element.id) { index, row in
                        SoundAppRow(row: row, enabled: detail.controlsEnabled, monitor: monitor)
                            .overlay(alignment: .bottom) {
                                if index < detail.rows.count - 1 {
                                    Rectangle().fill(Palette.separator).frame(height: 1)
                                }
                            }
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Palette.separator, lineWidth: 1))
            }
        }
    }
}

// MARK: Output

private struct OutputCard: View {
    let output: SoundDetail.Output
    let devices: [SoundDetail.DeviceChoice]
    let monitor: Monitor

    var body: some View {
        HStack(spacing: 24) {
            Image(systemName: output.kind.symbol)
                .font(.system(size: 24))
                .foregroundStyle(.white)
                .frame(width: 52, height: 52)
                .background(RoundedRectangle(cornerRadius: 14).fill(Palette.accent))
            VStack(alignment: .leading, spacing: 4) {
                Menu {
                    ForEach(devices) { device in
                        Button {
                            monitor.setOutputDevice(uid: device.uid)
                        } label: {
                            if device.isCurrent {
                                Label(device.name, systemImage: "checkmark")
                            } else {
                                Text(device.name)
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Text(output.name)
                            .font(.system(size: 17, weight: .bold))
                            .foregroundStyle(Palette.textPrimary)
                            .lineLimit(1)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Palette.textSecondary)
                    }
                }
                .menuStyle(.button)
                .buttonStyle(.plain)
                .fixedSize()
                .help("Switch the output device")
                Text(output.detail).font(.system(size: 12)).foregroundStyle(Palette.textSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if let volume = output.volume {
                HStack(spacing: 10) {
                    Image(systemName: "speaker.wave.1.fill").font(.system(size: 13)).foregroundStyle(Palette.textSecondary)
                    LiveSlider(value: volume, tint: Palette.accent, onChange: monitor.setSystemVolume)
                        .frame(width: 200)
                    Image(systemName: "speaker.wave.3.fill").font(.system(size: 13)).foregroundStyle(Palette.textSecondary)
                    Text(output.volumeText)
                        .font(.system(size: 13, weight: .bold).monospacedDigit())
                        .foregroundStyle(Palette.textPrimary)
                        .frame(width: 40, alignment: .trailing)
                }
            }
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 20)
        .background(RoundedRectangle(cornerRadius: 14).fill(Palette.surface))
    }
}

// MARK: Per-App Volume

private struct SoundAppRow: View {
    let row: SoundDetail.Row
    let enabled: Bool
    let monitor: Monitor

    var body: some View {
        HStack(spacing: 16) {
            Image(nsImage: AppIcons.icon(for: row.path))
                .resizable()
                .frame(width: 32, height: 32)
            Text(row.name)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Palette.textPrimary)
                .lineLimit(1)
                .frame(width: 150, alignment: .leading)
            StateBadge(state: row.state, text: row.stateText)
            Spacer(minLength: 0)
            LiveSlider(value: row.volume, tint: row.isMuted ? Palette.textTertiary : Palette.accent) { volume in
                monitor.setSoundAppVolume(volume, for: row.id)
            }
            .frame(width: 240)
            .disabled(!enabled)
            Text(row.volumeText)
                .font(.system(size: 13, weight: .semibold).monospacedDigit())
                .foregroundStyle(Palette.textPrimary)
                .frame(width: 40, alignment: .trailing)
            Button {
                monitor.toggleSoundAppMute(row.id)
            } label: {
                Image(systemName: row.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(row.isMuted ? SoundColors.danger : Palette.textSecondary)
                    .frame(width: 28, height: 28)
                    .background(RoundedRectangle(cornerRadius: 7)
                        .fill(row.isMuted ? SoundColors.danger.opacity(0.1) : Palette.track))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!enabled)
            .help(row.isMuted ? "Unmute \(row.name)" : "Mute \(row.name)")
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .help(row.help ?? "")
    }
}

private struct StateBadge: View {
    let state: SoundAppState
    let text: String

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: symbol).font(.system(size: 10, weight: .semibold))
            Text(text).font(.system(size: 11, weight: .semibold))
        }
        .foregroundStyle(color)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Capsule().fill(state == .silent ? Palette.track : color.opacity(0.12)))
    }

    private var symbol: String {
        switch state {
        case .playing: "waveform"
        case .silent: "speaker.fill"
        case .muted: "speaker.slash.fill"
        }
    }

    private var color: Color {
        switch state {
        case .playing: Palette.success
        case .silent: Palette.textSecondary
        case .muted: SoundColors.danger
        }
    }
}

/// The permission explanation before first use, or what to do when per-app volume isn't working.
private struct NoticeView: View {
    let notice: SoundDetail.Notice
    let monitor: Monitor

    private var isProblem: Bool {
        if case .problem = notice { true } else { false }
    }

    var body: some View {
        switch notice {
        case .explain(let text), .checking(let text), .problem(let text):
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: isProblem ? "exclamationmark.triangle.fill" : "info.circle")
                    .foregroundStyle(isProblem ? SoundColors.warning : Palette.textSecondary)
                Text(text).foregroundStyle(Palette.textSecondary).fixedSize(horizontal: false, vertical: true)
            }
            .font(.system(size: 11))
        case .notWorking(let title, let text):
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 14)).foregroundStyle(SoundColors.warning)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.system(size: 12, weight: .semibold)).foregroundStyle(Palette.textPrimary)
                    Text(text).font(.system(size: 11)).foregroundStyle(Palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 14) {
                        Button("Open Privacy Settings…", action: monitor.openSoundPrivacySettings)
                        Button("Try Again", action: monitor.retrySoundAccess)
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Palette.accent)
                    .padding(.top, 2)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 10).fill(SoundColors.warning.opacity(0.1)))
        }
    }
}

// MARK: Options

private struct OptionCard: View {
    let title: String
    let description: String
    let isOn: Binding<Bool>
    let enabled: Bool

    var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13, weight: .semibold)).foregroundStyle(Palette.textPrimary)
                Text(description).font(.system(size: 11)).foregroundStyle(Palette.textSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Toggle("", isOn: isOn)
                .toggleStyle(.switch)
                .controlSize(.small)
                .labelsHidden()
                .tint(Palette.success)
                .disabled(!enabled)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .background(RoundedRectangle(cornerRadius: 12).fill(Palette.surface))
    }
}

// MARK: Shared pieces

/// A slider that follows its value, except while dragged: then it shows the drag, since the value read
/// back from the system arrives only on the next refresh.
private struct LiveSlider: View {
    let value: Double
    let tint: Color
    let onChange: (Double) -> Void
    @State private var draft: Double?

    var body: some View {
        Slider(value: Binding(get: { draft ?? value }, set: { newValue in
            draft = newValue
            onChange(newValue)
        }), in: 0...1) { editing in
            if !editing { draft = nil }
        }
        .controlSize(.small)
        .tint(tint)
    }
}

private extension SoundDevice.Kind {
    var symbol: String {
        switch self {
        case .builtIn: "speaker.wave.2.fill"
        case .bluetooth: "headphones"
        case .usb: "hifispeaker.fill"
        case .display: "display"
        case .airPlay: "airplayaudio"
        case .virtual: "waveform"
        case .other: "speaker.wave.2.fill"
        }
    }
}

/// The design's warning and danger tokens, which `Palette` doesn't have.
private enum SoundColors {
    static let warning = color(light: 0xFF9F0A, dark: 0xFFB340)
    static let danger = color(light: 0xFF3B30, dark: 0xFF453A)

    private static func color(light: UInt32, dark: UInt32) -> Color {
        func nsColor(_ rgb: UInt32) -> NSColor {
            NSColor(srgbRed: CGFloat((rgb >> 16) & 0xFF) / 255, green: CGFloat((rgb >> 8) & 0xFF) / 255,
                    blue: CGFloat(rgb & 0xFF) / 255, alpha: 1)
        }
        return Color(nsColor: NSColor(name: nil) { appearance in
            nsColor(appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light)
        })
    }
}
