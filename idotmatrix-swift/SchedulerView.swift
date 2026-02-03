import SwiftUI

struct SchedulerView: View {
    @ObservedObject var scheduleManager = ScheduleManager.shared

    var body: some View {
        VStack {
            HStack {
                Spacer()
                // "New Schedule" -> Opens Editor directly via WindowManager for a new schedule
                Button(action: {
                    ScheduleEditorWindowManager.shared.open(scheduleID: nil)
                }) {
                    Label("Add Schedule", systemImage: "plus")
                }
            }
            .padding(.bottom, 5)

            if scheduleManager.schedules.isEmpty {
                Text("No schedules created.\nClick + to add and open editor.")
                    .multilineTextAlignment(.center)
                    .foregroundColor(.gray)
                    .padding()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach($scheduleManager.schedules) { $schedule in
                            HStack {
                                Toggle(isOn: Binding(
                                    get: { schedule.isActive },
                                    set: { _ in scheduleManager.toggleActive(scheduleID: schedule.id) }
                                )) {
                                     Text("")
                                }
                                .toggleStyle(SwitchToggleStyle())
                                .labelsHidden()
                                .frame(width: 40)

                                VStack(alignment: .leading) {
                                    Text(schedule.name)
                                        .font(.headline)
                                    Text("\(schedule.slots.count) slots")
                                        .font(.caption)
                                        .foregroundColor(.gray)
                                }

                                Spacer()

                                // Edit Button - Opens separate window
                                Button(action: {
                                    ScheduleEditorWindowManager.shared.open(scheduleID: schedule.id)
                                }) {
                                    Image(systemName: "pencil.circle")
                                        .font(.title2)
                                        .foregroundColor(.blue)
                                }
                                .buttonStyle(PlainButtonStyle())
                                .padding(.horizontal, 5)

                                // Delete Button
                                Button(action: {
                                    if let index = scheduleManager.schedules.firstIndex(where: { $0.id == schedule.id }) {
                                        // Close editor if open
                                        ScheduleEditorWindowManager.shared.close(scheduleID: schedule.id)
                                        scheduleManager.deleteSchedule(at: IndexSet(integer: index))
                                    }
                                }) {
                                    Image(systemName: "trash")
                                        .foregroundColor(.red)
                                }
                                .buttonStyle(PlainButtonStyle())
                            }
                            .padding(.vertical, 8)
                            .padding(.horizontal, 10)
                            .background(Color.gray.opacity(0.1))
                            .cornerRadius(8)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                        }
                    }
                    .padding(.bottom, 10)
                }
            }
        }
        // Removed padding() to fit better in embed
    }
}
