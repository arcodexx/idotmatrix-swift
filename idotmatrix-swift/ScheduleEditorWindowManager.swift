import SwiftUI
import AppKit

class ScheduleEditorWindowManager: NSObject, NSWindowDelegate {
    static let shared = ScheduleEditorWindowManager()
    private var editors: [UUID: NSWindow] = [:] // Map schedule ID to window
    private var newScheduleWindow: NSWindow? // For creating a new schedule

    func open(scheduleID: UUID?) {
        // If ID provided, edit existing
        if let id = scheduleID {
            if let existingWindow = editors[id] {
                existingWindow.makeKeyAndOrderFront(nil)
                return
            }

            // Create window for specific schedule
            // We pass the ID to the view, which will look it up in ScheduleManager
            let window = makeWindow(title: "Edit Schedule", view: AnyView(ScheduleEditorView(scheduleID: id)))
            editors[id] = window
            window.makeKeyAndOrderFront(nil)
        } else {
             // Create New Schedule
             if let window = newScheduleWindow {
                 window.makeKeyAndOrderFront(nil)
                 return
             }
             // For new schedule, we might want to create it first then open editor?
             // Or have a "New Schedule" view.
             // Let's create a temporary schedule or just add it immediately and open editor?
             // User said "open add... to new window".
             // Let's create a default one and open editor.

             let newName = "New Schedule \(ScheduleManager.shared.schedules.count + 1)"
             ScheduleManager.shared.addSchedule(name: newName)
             // Get the last added
             if let newSchedule = ScheduleManager.shared.schedules.last {
                  open(scheduleID: newSchedule.id)
             }
        }
    }

    // Helper to close specific editor
    func close(scheduleID: UUID) {
        if let window = editors[scheduleID] {
            window.close()
            editors.removeValue(forKey: scheduleID)
        }
    }

    private func makeWindow(title: String, view: AnyView) -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 500),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = title
        window.center()
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: view)
        window.delegate = self
        return window
    }

    func windowWillClose(_ notification: Notification) {
        guard let closedWindow = notification.object as? NSWindow else { return }

        // Find and remove from dictionary
        for (id, window) in editors {
            if window == closedWindow {
                editors.removeValue(forKey: id)
                break
            }
        }
        if closedWindow == newScheduleWindow {
            newScheduleWindow = nil
        }
    }
}
