import AppKit

// A throwaway regular app for MoniMac's UI tests: they quit it through the quit sheet, so a test never
// quits one of the user's apps. It keeps one core busy so it ranks first in the popover's Top Apps and
// shows watts. (It always spins: launch arguments from the sandboxed test runner don't arrive.)

nonisolated(unsafe) var spins: UInt64 = 0

Thread.detachNewThread {
    while true {
        spins &+= 1
        // A visible side effect, so the compiler can't drop the loop.
        if spins == 0 { print("wrapped") }
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
