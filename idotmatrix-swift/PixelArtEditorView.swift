import SwiftUI
import AppKit

struct PixelArtEditorView: View {
    @Binding var viewModel: ViewModel
    @State private var gridColors: [Color] = Array(repeating: .black, count: 1024)
    @State private var selectedColor: Color = .white

    var body: some View {
        VStack {
            // Header
            HStack {
                Button(action: {
                    viewModel.currentScreen = .home
                }, label: {
                    Image(systemName: "chevron.backward")
                })
                Text("Pixel Art Editor")
                    .bold()
                Image(systemName: "paintbrush.fill")
                    .font(.system(size: 24))
            }
            .padding(.bottom)

            // Drawing Area
            GeometryReader { geometry in
                let width = geometry.size.width
                let height = geometry.size.height
                let size = min(width, height)
                let cellSize = size / 32.0

                ZStack {
                    // Draw the grid
                    Canvas { context, size in
                        for i in 0..<1024 {
                            let x = (i % 32)
                            let y = (i / 32)
                            let rect = CGRect(x: CGFloat(x) * cellSize, y: CGFloat(y) * cellSize, width: cellSize, height: cellSize)
                            context.fill(Path(rect), with: .color(gridColors[i]))
                        }
                    }
                    // Overlay Grid Lines (Optional, maybe too heavy)

                }
                .frame(width: size, height: size)
                .background(Color.black)
                .border(Color.gray, width: 1)
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            let location = value.location
                            // Calculate index
                            let col = Int(location.x / cellSize)
                            let row = Int(location.y / cellSize)

                            if col >= 0 && col < 32 && row >= 0 && row < 32 {
                                let index = row * 32 + col
                                gridColors[index] = selectedColor
                            }
                        }
                )
            }
            .aspectRatio(1, contentMode: .fit)

            // Tools
            HStack(spacing: 20) {
                ColorPicker("Pick Color", selection: $selectedColor)
                    .labelsHidden()

                Button(action: {
                    gridColors = Array(repeating: .black, count: 1024)
                }) {
                    VStack {
                        Image(systemName: "trash")
                        Text("Clear")
                    }
                }

                Button(action: {
                    gridColors = Array(repeating: selectedColor, count: 1024)
                }) {
                    VStack {
                        Image(systemName: "paintpalette.fill")
                        Text("Fill")
                    }
                }

                Spacer()

                Button(action: {
                    Task {
                        await sendPixelArt()
                    }
                }) {
                    Text("Send to Device")
                        .bold()
                        .padding([.horizontal], 20)
                        .padding([.vertical], 10)
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
        }
        .padding()
    }

    @MainActor
    func sendPixelArt() async {
        // Convert [Color] to NSImage/Bitmap
        let size = CGSize(width: 32, height: 32)
        let img = NSImage(size: size)
        img.lockFocus()

        if let context = NSGraphicsContext.current?.cgContext {
             // Fill background black
            context.setFillColor(NSColor.black.cgColor)
            context.fill(CGRect(origin: .zero, size: size))

            for (index, color) in gridColors.enumerated() {
                let x = index % 32
                // Grid index 0 is top-left (row 0, col 0).
                // CGContext coords: (0,0) is usually bottom-left in NSImage unless flipped?
                // NSImage lockFocus usually sets a flipped coordinate system if specifically handled,
                // or standard bottom-up.
                // Standard NSImage is bottom-up. y=0 is bottom.
                // If our grid index 0 is "Row 0" (Top), then y needs inversion.
                // Row 0 -> y = 31. Row 31 -> y = 0.

                let row = index / 32
                let y = 31 - row

                let nsColor = NSColor(color)
                context.setFillColor(nsColor.cgColor)
                context.fill(CGRect(x: x, y: y, width: 1, height: 1))
            }
        }

        img.unlockFocus()

        // Convert to PNG Data
        guard let tiffData = img.tiffRepresentation,
              let bitmapRep = NSBitmapImageRep(data: tiffData),
              let pngData = bitmapRep.representation(using: .png, properties: [:]) else {
            print("Failed to generate PNG")
            return
        }

        // Use existing ViewModel logic to send photo
        await viewModel.sendPhoto(pngData)
    }
}
