import AppKit
import MoniMacCore
import SwiftUI
import UniformTypeIdentifiers

/// The share card preview: a small window with a Light/Dark choice, Copy, and Save….
/// The summary is computed once when the window opens, so the preview doesn't re-render every tick.
@MainActor
final class ShareCardWindowController: NSObject, NSWindowDelegate {
    static let shared = ShareCardWindowController()

    private var window: NSWindow?

    func show(monitor: Monitor) {
        let summary = monitor.weeklySummary()
        let icon = ShareCardRenderer.icon(forApp: summary.figures.busiestApp, in: monitor.apps)
        let window = window ?? makeWindow()
        self.window = window
        window.contentView = NSHostingView(rootView: ShareCardPreview(summary: summary, busiestIcon: icon) {
            [weak window] in window
        })
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 768, height: 500),
            styleMask: [.titled, .closable], backing: .buffered, defer: false
        )
        window.title = "Share Your Week"
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        return window
    }

    func windowWillClose(_ notification: Notification) {
        window?.contentView = nil
        window = nil
    }

    /// Development aid: renders the card to a PNG at `path` without showing anything.
    static func export(monitor: Monitor, to path: String, dark: Bool) -> Bool {
        let summary = monitor.weeklySummary()
        let icon = ShareCardRenderer.icon(forApp: summary.figures.busiestApp, in: monitor.apps)
        guard let image = ShareCardRenderer.image(summary, dark: dark, busiestIcon: icon),
              let png = ShareCardRenderer.png(image) else { return false }
        return (try? png.write(to: URL(fileURLWithPath: path))) != nil
    }
}

private struct ShareCardPreview: View {
    let summary: WeeklySummary
    let busiestIcon: NSImage?
    let window: () -> NSWindow?

    @State private var dark: Bool
    @State private var images: [Bool: CGImage] = [:]
    @State private var copied = false

    init(summary: WeeklySummary, busiestIcon: NSImage?, window: @escaping () -> NSWindow?) {
        self.summary = summary
        self.busiestIcon = busiestIcon
        self.window = window
        _dark = State(initialValue: NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua)
    }

    private var image: CGImage? {
        images[dark] ?? ShareCardRenderer.image(summary, dark: dark, busiestIcon: busiestIcon)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Group {
                if let image {
                    Image(decorative: image, scale: 1).resizable().interpolation(.high)
                } else {
                    Rectangle().fill(Palette.surface)
                }
            }
            .aspectRatio(ShareCardView.size.width / ShareCardView.size.height, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Palette.separator, lineWidth: 1))

            HStack(spacing: 12) {
                SegmentedPicker(options: [false, true], selection: $dark, label: { $0 ? "Dark" : "Light" },
                                horizontalPadding: 14)
                    .frame(width: 150)
                Text("1200 × 630 PNG · made on this Mac, nothing is uploaded")
                    .font(.system(size: 11)).foregroundStyle(Palette.textSecondary)
                Spacer()
                if copied {
                    Text("Copied").font(.system(size: 11, weight: .medium)).foregroundStyle(Palette.textSecondary)
                }
                Button("Copy", action: copy)
                Button("Save…", action: save).keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 768)
        .background(Palette.windowBackground)
        .onAppear(perform: renderVariants)
        .onChange(of: dark) { copied = false }
    }

    private func renderVariants() {
        for variant in [false, true] where images[variant] == nil {
            images[variant] = ShareCardRenderer.image(summary, dark: variant, busiestIcon: busiestIcon)
        }
    }

    private func copy() {
        guard let image, let png = ShareCardRenderer.png(image) else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.declareTypes([.png, .tiff], owner: nil)
        pasteboard.setData(png, forType: .png)
        if let tiff = NSBitmapImageRep(cgImage: image).tiffRepresentation { pasteboard.setData(tiff, forType: .tiff) }
        copied = true
    }

    private func save() {
        guard let image, let png = ShareCardRenderer.png(image) else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = "MoniMac Week.png"
        let write = { (response: NSApplication.ModalResponse) in
            guard response == .OK, let url = panel.url else { return }
            do {
                try png.write(to: url)
            } catch {
                NSAlert(error: error).runModal()
            }
        }
        if let window = window() {
            panel.beginSheetModal(for: window, completionHandler: write)
        } else {
            write(panel.runModal())
        }
    }
}
