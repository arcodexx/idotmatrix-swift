import SwiftUI
import AppKit

class SchedulerWindowManager: NSObject, NSWindowDelegate {
    static let shared = SchedulerWindowManager()
    private var window: NSWindow?

    func open() {
        if let window = window {
            window.makeKeyAndOrderFront(nil)
            return
        }

        // Create new window
        let newWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        newWindow.title = "Scheduler"
        newWindow.center()
        newWindow.isReleasedWhenClosed = false
        newWindow.contentView = NSHostingView(rootView: SchedulerView())
        newWindow.delegate = self

        newWindow.makeKeyAndOrderFront(nil)
        self.window = newWindow
    }

    func windowWillClose(_ notification: Notification) {
        self.window = nil
    }
}
