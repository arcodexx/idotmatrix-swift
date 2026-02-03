import SwiftUI

struct ScheduleEditorView: View {
    let scheduleID: UUID
    @ObservedObject var scheduleManager = ScheduleManager.shared

    // Local state for slot editing
    @State private var showingSlotEditor = false
    @State private var selectedSlotID: UUID?

    // We bind to the specific schedule in the manager
    var scheduleBinding: Binding<Schedule>? {
        guard let index = scheduleManager.schedules.firstIndex(where: { $0.id == scheduleID }) else { return nil }
        return $scheduleManager.schedules[index]
    }

    var body: some View {
        if let schedule = scheduleBinding {
            VStack {
                Form {
                    Section(header: Text("Schedule Details")) {
                        TextField("Schedule Name", text: schedule.name)
                    }

                    Section(header: Text("Time Slots")) {
                        if schedule.wrappedValue.slots.isEmpty {
                            Text("No time slots. Click '+' below to add one.")
                                .foregroundColor(.gray)
                                .italic()
                        }

                        List {
                            ForEach(schedule.wrappedValue.slots) { slot in
                                HStack {
                                    VStack(alignment: .leading) {
                                        Text("\(formatTime(slot.startTime)) - \(formatTime(slot.endTime))")
                                            .font(.headline)
                                        Text(assetName(for: slot.assetID))
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                    Spacer()
                                    // Edit Slot
                                    Button(action: {
                                        selectedSlotID = slot.id
                                        showingSlotEditor = true
                                    }) {
                                        Image(systemName: "pencil")
                                    }
                                    .buttonStyle(.borderless)

                                    // Delete Slot
                                    Button(action: {
                                        deleteSlot(id: slot.id)
                                    }) {
                                        Image(systemName: "trash")
                                            .foregroundColor(.red)
                                    }
                                    .buttonStyle(.borderless)
                                }
                                .padding(.vertical, 4)
                            }
                        }
                        .frame(minHeight: 200)
                    }
                }
                .padding()

                HStack {
                    Button(action: {
                        selectedSlotID = nil // New slot
                        showingSlotEditor = true
                    }) {
                        Label("Add Time Slot", systemImage: "plus")
                    }
                    .padding()
                    Spacer()
                }

                Divider()

                HStack {
                    Spacer()
                    Button("Done") {
                        ScheduleEditorWindowManager.shared.close(scheduleID: scheduleID)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .padding()
                }
            }
            .sheet(isPresented: $showingSlotEditor) {
                // If selectedSlotID is nil, we are adding new.
                // If not nil, editing existing.
                // We need to pass a binding to the slot.
                if let selectedID = selectedSlotID, let slotIndex = schedule.wrappedValue.slots.firstIndex(where: { $0.id == selectedID }) {
                    TimeSlotEditorSheet(slot: schedule.wrappedValue.slots[slotIndex], onSave: { updatedSlot in
                        // It's a binding, so it might update directly?
                        // But TimeSlotEditorSheet will take a STATE copy and save back on 'Save'
                        // Let's implement TimeSlotEditorSheet to handle "Save/Cancel"
                        schedule.wrappedValue.slots[slotIndex] = updatedSlot
                        ScheduleManager.shared.saveSchedules()
                        showingSlotEditor = false
                    }, onCancel: {
                         showingSlotEditor = false
                    })
                } else {
                    // New Slot
                    TimeSlotEditorSheet(slot: createDefaultSlot(), onSave: { newSlot in
                        schedule.wrappedValue.slots.append(newSlot)
                        ScheduleManager.shared.saveSchedules()
                        showingSlotEditor = false
                    }, onCancel: {
                        showingSlotEditor = false
                    }, isNew: true)
                }
            }
            .onChange(of: schedule.wrappedValue.name) {
                 ScheduleManager.shared.saveSchedules()
            }
        } else {
            Text("Schedule not found or deleted.")
                .foregroundColor(.red)
        }
    }

    func deleteSlot(id: UUID) {
        guard let index = scheduleBinding?.wrappedValue.slots.firstIndex(where: { $0.id == id }) else { return }
        scheduleBinding?.wrappedValue.slots.remove(at: index)
        ScheduleManager.shared.saveSchedules()
    }

    func createDefaultSlot() -> TimeSlot {
        let now = Date()
        let calendar = Calendar.current
        let hour = calendar.component(.hour, from: now)
        var components = DateComponents()
        components.hour = hour
        components.minute = 0
        let start = calendar.date(from: components) ?? now
        let end = calendar.date(byAdding: .minute, value: 30, to: start) ?? now.addingTimeInterval(1800)
        let defaultAssetID = AssetManager.shared.assets.first?.id ?? UUID()
        return TimeSlot(startTime: start, endTime: end, assetID: defaultAssetID)
    }

    func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    func assetName(for id: UUID) -> String {
        return AssetManager.shared.assets.first(where: { $0.id == id })?.name ?? "Unknown"
    }
}
