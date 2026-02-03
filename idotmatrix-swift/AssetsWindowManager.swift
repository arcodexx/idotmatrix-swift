import SwiftUI
import AppKit

class AssetsWindowManager: NSObject, NSWindowDelegate {
    static let shared = AssetsWindowManager()
    private var window: NSWindow?

    func open() {
        if let window = window {
            window.makeKeyAndOrderFront(nil)
            return
        }

        // Create new window
        let newWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1000, height: 600),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        newWindow.title = "My Assets"
        newWindow.center()
        newWindow.isReleasedWhenClosed = false
        newWindow.contentView = NSHostingView(rootView: AssetsView())
        newWindow.delegate = self

        newWindow.makeKeyAndOrderFront(nil)
        self.window = newWindow
    }

    func windowWillClose(_ notification: Notification) {
        self.window = nil
    }
}
