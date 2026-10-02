import AppKit

// A throwaway regular app for MoniMac's UI tests: they quit it through the quit sheet, so a test never
// quits one of the user's apps. It keeps one core busy so it ranks first in the popover's Top Apps.
// (Launch arguments from the sandboxed test runner don't arrive, so this is the default.)

nonisolated(unsafe) var spins: UInt64 = 0

if !CommandLine.arguments.contains("--idle") {
    Thread.detachNewThread {
        while true {
            spins &+= 1
            if spins == 0 { print("wrapped") }
        }
    }
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    app.setActivationPolicy(.regular)
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 360, height: 120),
                          styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
    window.title = "MoniMac UI Test Dummy"
    window.center()
    window.orderFront(nil)
    app.run()
}
