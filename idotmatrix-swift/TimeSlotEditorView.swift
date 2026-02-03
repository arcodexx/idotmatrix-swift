import SwiftUI

struct TimeSlotEditorView: View {
    @Binding var slot: TimeSlot
    @StateObject var assetManager = AssetManager.shared

    // We need to ensure start/end times are restricted to 30 min intervals.
    // We might use a custom picker or just process the DatePicker updates.

    var body: some View {
        Form {
            Section(header: Text("Time Interval")) {
                // Custom Time Pickers
                // Using DatePicker but we will snap values?
                // Or use Stepper for Hour/Minute?

                // Let's use two pickers: Start Time and Duration? Or Start and End?
                // Providing 30 min steps in DatePicker in SwiftUI is tricky (minuteInterval).
                // macOS DatePicker supports it maybe?

                DatePicker("Start Time", selection: Binding(get: {
                    slot.startTime
                }, set: { newVal in
                    slot.startTime = snapTo30(newVal)
                    // Ensure end time is at least 30 mins after start
                    if slot.endTime <= slot.startTime {
                        slot.endTime = Calendar.current.date(byAdding: .minute, value: 30, to: slot.startTime)!
                    }
                    ScheduleManager.shared.saveSchedules()
                }), displayedComponents: .hourAndMinute)

                DatePicker("End Time", selection: Binding(get: {
                    slot.endTime
                }, set: { newVal in
                    // Ensure end > start
                    var snapped = snapTo30(newVal)
                    if snapped <= slot.startTime {
                         snapped = Calendar.current.date(byAdding: .minute, value: 30, to: slot.startTime)!
                    }
                    slot.endTime = snapped
                    ScheduleManager.shared.saveSchedules()
                }), displayedComponents: .hourAndMinute)

                Text("Duration: \(formatDuration(start: slot.startTime, end: slot.endTime))")
                    .foregroundColor(.gray)
            }

            Section(header: Text("Select Asset")) {
                if assetManager.assets.isEmpty {
                    Text("No assets found. Please add assets in 'My Assets'.")
                } else {
                    // Simple List or Grid
                    // Reusing a simple list for now, ideally visual grid
                    List {
                        ForEach(assetManager.assets) { asset in
                            HStack {
                                Text(asset.name)
                                Spacer()
                                if asset.type == .gif {
                                    Image(systemName: "photo.stack")
                                } else {
                                    Image(systemName: "paintbrush.fill")
                                }

                                if slot.assetID == asset.id {
                                    Image(systemName: "checkmark")
                                        .foregroundColor(.blue)
                                }
                            }
                            .contentShape(Rectangle())
                            .onTapGesture {
                                slot.assetID = asset.id
                                ScheduleManager.shared.saveSchedules()
                            }
                        }
                    }
                    .frame(height: 200)
                }
            }
        }
        .padding()
        .navigationTitle("Edit Slot")
    }

    func snapTo30(_ date: Date) -> Date {
        let calendar = Calendar.current
        var components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)

        guard let minute = components.minute else { return date }

        // Round to nearest 30
        // Or floor? "options to set ... can be either the hour or hour and 30"
        // Usually floor or nearest. Let's do nearest for UX, or strict specific intervals given user requirement.
        // User said: "options to set ... can be either the hour or hour and 30 mins"
        // This implies 00 or 30.

        let newMinute = minute < 15 ? 0 : (minute < 45 ? 30 : 0)
        let addHour = (minute >= 45) ? 1 : 0

        components.minute = newMinute
        if addHour == 1 {
            components.hour = (components.hour ?? 0) + 1
        }
        components.second = 0

        return calendar.date(from: components) ?? date
    }

    func formatDuration(start: Date, end: Date) -> String {
        let diff = end.timeIntervalSince(start)
        let hours = Int(diff) / 3600
        let minutes = (Int(diff) % 3600) / 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(minutes)m"
        }
    }
}
