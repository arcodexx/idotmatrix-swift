import SwiftUI

struct TimeSlotEditorSheet: View {
    @State var slot: TimeSlot
    var onSave: (TimeSlot) -> Void
    var onCancel: () -> Void
    var isNew: Bool = false

    @ObservedObject var assetManager = AssetManager.shared
    @State private var selectedAssetID: UUID?

    let columns = [
        GridItem(.adaptive(minimum: 100))
    ]

    var body: some View {
        VStack {
            Text(isNew ? "Add Time Slot" : "Edit Time Slot")
                .font(.headline)
                .padding(.top)

            Form {
                Section(header: Text("Time Interval")) {
                    DatePicker("Start", selection: Binding(get: {
                        slot.startTime
                    }, set: { newVal in
                        slot.startTime = snapTo30(newVal)
                        if slot.endTime <= slot.startTime {
                            slot.endTime = Calendar.current.date(byAdding: .minute, value: 30, to: slot.startTime)!
                        }
                    }), displayedComponents: .hourAndMinute)

                    DatePicker("End", selection: Binding(get: {
                        slot.endTime
                    }, set: { newVal in
                        var snapped = snapTo30(newVal)
                        if snapped <= slot.startTime {
                             snapped = Calendar.current.date(byAdding: .minute, value: 30, to: slot.startTime)!
                        }
                        slot.endTime = snapped
                    }), displayedComponents: .hourAndMinute)

                    Text("Duration: \(formatDuration(start: slot.startTime, end: slot.endTime))")
                        .foregroundColor(.gray)
                        .font(.caption)
                }
            }
            .padding(.horizontal)

            Divider()

            Text("Select Asset")
                .font(.subheadline)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal)

            ScrollView {
                if assetManager.assets.isEmpty {
                    Text("No assets available.")
                        .foregroundColor(.gray)
                        .padding()
                } else {
                    LazyVGrid(columns: columns, spacing: 15) {
                        ForEach(assetManager.assets) { asset in
                            VStack {
                                ZStack {
                                    Rectangle()
                                        .fill(Color.gray.opacity(0.1))
                                        .frame(height: 100)
                                        .cornerRadius(8)

                                    if asset.type == .gif {
                                        if let url = AssetManager.shared.getGifURL(for: asset) {
                                            GifView(url: url)
                                                .frame(height: 100)
                                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                        } else {
                                            Image(systemName: "photo.stack")
                                        }
                                    } else {
                                        if let colors = asset.gridColors {
                                            PixelArtPreviewCanvas(colors: colors)
                                                .frame(height: 100)
                                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                        } else {
                                            Image(systemName: "paintbrush.fill")
                                        }
                                    }

                                    // Selection Overlay
                                    if slot.assetID == asset.id {
                                        ZStack {
                                            Color.black.opacity(0.3)
                                            Image(systemName: "checkmark.circle.fill")
                                                .foregroundColor(.white)
                                                .font(.largeTitle)
                                        }
                                        .cornerRadius(8)
                                    }
                                }
                                .onTapGesture {
                                    slot.assetID = asset.id
                                    selectedAssetID = asset.id
                                }

                                Text(asset.name)
                                    .font(.caption)
                                    .lineLimit(1)
                            }
                        }
                    }
                    .padding()
                }
            }

            HStack {
                Button("Cancel") {
                    onCancel()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Save") {
                    onSave(slot)
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
            .padding()
        }
        .frame(width: 500, height: 600)
        .onAppear {
            selectedAssetID = slot.assetID
        }
    }

    func snapTo30(_ date: Date) -> Date {
        let calendar = Calendar.current
        var components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        guard let minute = components.minute else { return date }

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
