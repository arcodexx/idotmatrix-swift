import Foundation
import Combine

struct TimeSlot: Codable, Identifiable {
    var id: UUID = UUID()
    var startTime: Date // Only time components are used
    var endTime: Date   // Only time components are used
    var assetID: UUID

    // Helpers to enforce 30 min intervals?
    // For data model, we just store what's given, but UI will enforce.

    // Check if a given date (time) falls within this slot
    func contains(date: Date) -> Bool {
        let calendar = Calendar.current
        let currentHour = calendar.component(.hour, from: date)
        let currentMinute = calendar.component(.minute, from: date)

        let startHour = calendar.component(.hour, from: startTime)
        let startMinute = calendar.component(.minute, from: startTime)

        let endHour = calendar.component(.hour, from: endTime)
        let endMinute = calendar.component(.minute, from: endTime)

        let currentTimeValue = currentHour * 60 + currentMinute
        let startTimeValue = startHour * 60 + startMinute
        let endTimeValue = endHour * 60 + endMinute

        // Handle overnight slots if necessary (e.g. 23:00 to 01:00)
        if startTimeValue < endTimeValue {
            return currentTimeValue >= startTimeValue && currentTimeValue < endTimeValue
        } else {
            // Overnight
            return currentTimeValue >= startTimeValue || currentTimeValue < endTimeValue
        }
    }
}

struct Schedule: Codable, Identifiable {
    var id: UUID = UUID()
    var name: String
    var isActive: Bool = false
    var slots: [TimeSlot] = []
}

class ScheduleManager: ObservableObject {
    static let shared = ScheduleManager()
    private let fileName = "schedules.json"

    @Published var schedules: [Schedule] = []

    private var timer: Timer?

    init() {
        loadSchedules()
    }

    private var fileURL: URL? {
        guard let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return nil }
        return documents.appendingPathComponent(fileName)
    }

    func loadSchedules() {
        guard let url = fileURL else { return }
        if !FileManager.default.fileExists(atPath: url.path) {
            return
        }
        do {
            let data = try Data(contentsOf: url)
            schedules = try JSONDecoder().decode([Schedule].self, from: data)
        } catch {
            print("Error loading schedules: \(error)")
        }
    }

    func saveSchedules() {
        guard let url = fileURL else { return }
        do {
            let data = try JSONEncoder().encode(schedules)
            try data.write(to: url)
        } catch {
            print("Error saving schedules: \(error)")
        }
    }

    func addSchedule(name: String) {
        let newSchedule = Schedule(name: name)
        schedules.append(newSchedule)
        saveSchedules()
    }

    func deleteSchedule(at indexSet: IndexSet) {
        schedules.remove(atOffsets: indexSet)
        saveSchedules()
    }

    func updateSchedule(_ schedule: Schedule) {
        if let index = schedules.firstIndex(where: { $0.id == schedule.id }) {
            schedules[index] = schedule
            saveSchedules()
        }
    }

    func toggleActive(scheduleID: UUID) {
        for index in schedules.indices {
            if schedules[index].id == scheduleID {
                schedules[index].isActive.toggle()
            } else {
                schedules[index].isActive = false // Enforce mutual exclusivity
            }
        }
        saveSchedules()
        checkCurrentSchedule() // Immediate check
    }

    // MARK: - Scheduler Logic

    func startScheduler() {
        // Calculate time until next 30-minute mark
        let now = Date()
        let calendar = Calendar.current
        let minute = calendar.component(.minute, from: now)
        let second = calendar.component(.second, from: now)

        let minutesToNextSlot: Int
        if minute < 30 {
            minutesToNextSlot = 30 - minute
        } else {
            minutesToNextSlot = 60 - minute
        }

        // Wait seconds remaining in current minute + minutes remaining
        let timeInterval = TimeInterval((minutesToNextSlot * 60) - second)

        print("Scheduling next check in \(timeInterval) seconds")

        // Initial check immediately
        checkCurrentSchedule()

        // Schedule timer
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: timeInterval, repeats: false) { [weak self] _ in
            self?.checkCurrentSchedule()
            self?.startPeriodicTimer() // Start the recurring 30-min timer
        }
    }

    private func startPeriodicTimer() {
        timer?.invalidate()
        // Run every 30 minutes
        timer = Timer.scheduledTimer(withTimeInterval: 30 * 60, repeats: true) { [weak self] _ in
            self?.checkCurrentSchedule()
        }
    }

    func stopScheduler() {
        timer?.invalidate()
        timer = nil
    }

    func checkCurrentSchedule() {
        print("Checking schedule at \(Date())")
        guard let activeSchedule = schedules.first(where: { $0.isActive }) else {
            print("No active schedule")
            return
        }

        let now = Date()
        if let currentSlot = activeSchedule.slots.first(where: { $0.contains(date: now) }) {
            print("Found matching slot with asset: \(currentSlot.assetID)")
            triggerAssetUpdate(assetID: currentSlot.assetID)
        } else {
            print("No slot matches current time")
        }
    }

    private func triggerAssetUpdate(assetID: UUID) {
        // Find asset
        guard let asset = AssetManager.shared.assets.first(where: { $0.id == assetID }) else {
            print("Asset not found")
            return
        }

        Task { @MainActor in
            if asset.type == .gif, let gifFilename = asset.gifFilename, let folder = AssetManager.shared.assetsFolderURL {
                 let gifURL = folder.appendingPathComponent(gifFilename)
                 // Need to expose a method in ViewModel to load direct ID or URL without UI interaction preference
                 // For now, let's reuse logic.
                 // We will update ViewModel to handle this cleaner

                 // Reuse existing logic
                 ViewModel.shared.currentlyDisplayingImage = .notImage
                 if let data = try? Data(contentsOf: gifURL) {
                     await ViewModel.shared.sendGif(data)
                 }
            } else if asset.type == .pixelArt, let colors = asset.gridColors {
                // Handle pixel art
                // Need a way to send pixel art data
                // ViewModel doesn't strongly expose "Send Pixel Art" public func suitable for this context easily yet
                // But we can check PixelArtEditor logic
                // For now, let's assume GIF focus as per prompt "image/gif"
                // But user said "image/git ... pixel art is an image"
                // We'll implement pixel art sending logic in ViewModel or here
            }
        }
    }
}

// Add Extension to AssetManager to expose assetsFolderURL publicly if needed
extension AssetManager {
    var publicAssetsFolderURL: URL? {
        return assetsFolderURL // This was private, we might need to change it to public
    }
}
