import SwiftUI

struct AssetsView: View {
    @ObservedObject var assetManager = AssetManager.shared
    @ObservedObject var viewModel = ViewModel.shared

    let columns = [
        GridItem(.adaptive(minimum: 160))
    ]

    var body: some View {
        VStack {
            Text("My Assets")
                .font(.title)
                .bold()
                .padding()

            ScrollView {
                if assetManager.assets.isEmpty {
                    Text("No assets saved yet.")
                        .foregroundStyle(.gray)
                        .padding()
                } else {
                    LazyVGrid(columns: columns, spacing: 20) {
                        ForEach(assetManager.assets) { asset in
                            AssetItemView(asset: asset, viewModel: viewModel)
                        }
                    }
                    .padding()
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            assetManager.loadAssets()
        }
    }
}

struct AssetItemView: View {
    let asset: AssetModel
    @ObservedObject var viewModel: ViewModel
    @State private var hover = false
    @State private var showingDeleteAlert = false

    var body: some View {
        VStack {
            ZStack {
                Rectangle()
                    .fill(Color.gray.opacity(0.1))
                    .frame(height: 160)
                    .cornerRadius(8)

                if asset.type == .gif {
                     if let url = AssetManager.shared.getGifURL(for: asset) {
                         GifView(url: url)
                             .frame(height: 160)
                             .clipShape(RoundedRectangle(cornerRadius: 8))
                     } else {
                         Image(systemName: "photo.stack")
                     }
                } else {
                    // Pixel Art Preview
                    if let colors = asset.gridColors {
                        PixelArtPreviewCanvas(colors: colors)
                            .frame(height: 160)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    } else {
                        Image(systemName: "paintbrush.fill")
                    }
                }

                // Overlay Controls
                if hover {
                    ZStack {
                        Color.black.opacity(0.6)
                        VStack(spacing: 10) {
                            Button("Send") {
                                sendAsset()
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)

                            Button("Delete") {
                                showingDeleteAlert = true
                            }
                            .buttonStyle(.bordered)
                            .tint(.red)
                            .controlSize(.small)

                            if asset.type == .pixelArt {
                                Button("Edit") {
                                    // TODO: Open in Editor
                                    openInEditor()
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }
                        }
                    }
                    .cornerRadius(8)
                }
            }
            .onHover { isHovering in
                hover = isHovering
            }

            Text(asset.name)
                .font(.caption)
                .lineLimit(1)
        }
        .frame(minWidth: 0, maxWidth: .infinity)
        .alert("Delete Asset", isPresented: $showingDeleteAlert) {
            Button("Delete", role: .destructive) {
                AssetManager.shared.delete(asset)
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Are you sure you want to delete '\(asset.name)'? This action cannot be undone.")
        }
    }

    func sendAsset() {
        Task {
            if asset.type == .gif {
                if let url = AssetManager.shared.getGifURL(for: asset),
                   let data = try? Data(contentsOf: url) {
                    await viewModel.sendGif(data)
                }
            } else if asset.type == .pixelArt, let colors = asset.gridColors {
                // Determine width from count (assuming square)
                let size = Int(sqrt(Double(colors.count)))
                // TODO: Send Pixel Art logic (not implemented in ViewModel easily yet?)
                // Actually ViewModel has sendData, maybe we need a dedicated function?
                // Or just open in Editor and let user tap Send.
            }
        }
    }

    func openInEditor() {
        // We need a notification or mechanism to tell PixelArtWindow to load this.
        // For now, let's just use NotificationCenter
        NotificationCenter.default.post(name: Notification.Name("LoadPixelArt"), object: asset)
        PixelArtWindowManager.shared.open()
    }
}

struct PixelArtPreviewCanvas: View {
    let colors: [Color]

    var body: some View {
        GeometryReader { geometry in
            let gridSize = Int(sqrt(Double(colors.count)))
            // Avoid division by zero
            let pixelSize = gridSize > 0 ? geometry.size.width / CGFloat(gridSize) : 0

            Canvas { context, canvasSize in
                for row in 0..<gridSize {
                    for col in 0..<gridSize {
                        let index = row * gridSize + col
                        if index < colors.count {
                             let rect = CGRect(x: CGFloat(col) * pixelSize, y: CGFloat(row) * pixelSize, width: pixelSize, height: pixelSize)
                             context.fill(Path(rect), with: .color(colors[index]))
                        }
                    }
                }
            }
        }
    }
}
