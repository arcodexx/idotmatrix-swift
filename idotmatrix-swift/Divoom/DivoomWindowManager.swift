import SwiftUI
import AppKit

class DivoomWindowManager: NSObject, NSWindowDelegate {
    static let shared = DivoomWindowManager()
    private var window: NSWindow?

    func open() {
        if let window = window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let newWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered, defer: false
        )
        newWindow.title = "Divoom Library"
        newWindow.isReleasedWhenClosed = false
        newWindow.center()
        newWindow.contentView = NSHostingView(rootView: DivoomLibraryView())
        newWindow.delegate = self
        newWindow.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.window = newWindow
    }

    func windowWillClose(_ notification: Notification) {
        self.window = nil
    }
}
