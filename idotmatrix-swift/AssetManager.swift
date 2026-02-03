import Foundation
import SwiftUI

enum AssetType: String, Codable {
    case pixelArt
    case gif
}

struct AssetModel: Codable, Identifiable {
    var id: UUID = UUID()
    var name: String
    var type: AssetType
    var createdAt: Date = Date()

    // For Pixel Art
    var colorsInfo: [String]?

    // For GIF (we store relative path or filename)
    var gifFilename: String?

    // Helper for Pixel Art Colors
    var gridColors: [Color]? {
        colorsInfo?.map { Color(hex: $0) }
    }
}

class AssetManager: ObservableObject {
    static let shared = AssetManager()
    private let folderName = "MyAssets"

    @Published var assets: [AssetModel] = []

    private var assetsFolderURL: URL? {
        guard let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return nil }
        return documents.appendingPathComponent(folderName)
    }

    init() {
        createFolderIfNeeded()
        loadAssets()
    }

    private func createFolderIfNeeded() {
        guard let url = assetsFolderURL else { return }
        if !FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }
    }

    func loadAssets() {
        assets = loadAll()
    }

    private func loadAll() -> [AssetModel] {
        guard let url = assetsFolderURL else { return [] }
        do {
            // We look for JSON files
            let fileURLs = try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)
            let loadedAssets = fileURLs.filter { $0.pathExtension == "json" }.compactMap { fileURL -> AssetModel? in
                guard let data = try? Data(contentsOf: fileURL) else { return nil }
                return try? JSONDecoder().decode(AssetModel.self, from: data)
            }
            return loadedAssets.sorted(by: { $0.createdAt > $1.createdAt })
        } catch {
            print("Error loading assets: \(error)")
            return []
        }
    }

    // Save GIF
    func saveGif(name: String, data: Data) {
        guard let folder = assetsFolderURL else { return }
        let id = UUID()
        let gifFilename = "\(id.uuidString).gif"
        let gifURL = folder.appendingPathComponent(gifFilename)

        do {
            try data.write(to: gifURL)

            let asset = AssetModel(id: id, name: name, type: .gif, gifFilename: gifFilename)
            saveMetadata(asset)
            loadAssets()
        } catch {
            print("Failed to save GIF: \(error)")
        }
    }

    // Save Pixel Art (Adapter for existing logic)
    func savePixelArt(name: String, colors: [Color]) {
        let hexColors = colors.map { $0.toHex() ?? "#000000" }
        let asset = AssetModel(id: UUID(), name: name, type: .pixelArt, colorsInfo: hexColors)
        saveMetadata(asset)
        loadAssets()
    }

    private func saveMetadata(_ asset: AssetModel) {
        guard let folder = assetsFolderURL else { return }
        let jsonURL = folder.appendingPathComponent("\(asset.id.uuidString).json")
        do {
            let data = try JSONEncoder().encode(asset)
            try data.write(to: jsonURL)
        } catch {
            print("Failed to save asset metadata: \(error)")
        }
    }

    func delete(_ asset: AssetModel) {
        guard let folder = assetsFolderURL else { return }
        let jsonURL = folder.appendingPathComponent("\(asset.id.uuidString).json")
        try? FileManager.default.removeItem(at: jsonURL)

        if let gifFilename = asset.gifFilename {
            let gifURL = folder.appendingPathComponent(gifFilename)
            try? FileManager.default.removeItem(at: gifURL)
        }
        loadAssets()
    }

    func getGifURL(for asset: AssetModel) -> URL? {
        guard let filename = asset.gifFilename, let folder = assetsFolderURL else { return nil }
        return folder.appendingPathComponent(filename)
    }
}
