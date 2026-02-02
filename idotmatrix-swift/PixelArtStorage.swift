import Foundation
import SwiftUI

struct PixelArtModel: Codable, Identifiable {
    var id: UUID = UUID()
    var name: String
    var createdAt: Date = Date()
    // Store colors as Hex Strings for compact storage
    var colorsInfo: [String]

    // Helper to get Colors back
    var gridColors: [Color] {
        colorsInfo.map { hex in
            Color(hex: hex)
        }
    }

    init(name: String, gridColors: [Color]) {
        self.name = name
        self.colorsInfo = gridColors.map { $0.toHex() ?? "#000000" }
    }
}

class PixelArtStorage {
    static let shared = PixelArtStorage()
    private let folderName = "PixelArts"

    private var pixelArtsURL: URL? {
        guard let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return nil }
        return documents.appendingPathComponent(folderName)
    }

    init() {
        createFolderIfNeeded()
    }

    private func createFolderIfNeeded() {
        guard let url = pixelArtsURL else { return }
        if !FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }
    }

    func save(_ art: PixelArtModel) {
        guard let url = pixelArtsURL?.appendingPathComponent("\(art.id.uuidString).json") else { return }
        do {
            let data = try JSONEncoder().encode(art)
            try data.write(to: url)
            print("Saved art: \(art.name)")
        } catch {
            print("Error saving art: \(error)")
        }
    }

    func loadAll() -> [PixelArtModel] {
        guard let url = pixelArtsURL else { return [] }
        do {
            let fileURLs = try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)
            let arts = fileURLs.compactMap { fileURL -> PixelArtModel? in
                guard let data = try? Data(contentsOf: fileURL) else { return nil }
                return try? JSONDecoder().decode(PixelArtModel.self, from: data)
            }
            return arts.sorted(by: { $0.createdAt > $1.createdAt })
        } catch {
            print("Error loading arts: \(error)")
            return []
        }
    }

    func delete(_ art: PixelArtModel) {
        guard let url = pixelArtsURL?.appendingPathComponent("\(art.id.uuidString).json") else { return }
        try? FileManager.default.removeItem(at: url)
    }
}

// MARK: - Color Extensions for Hex Conversion
extension Color {
    func toHex() -> String? {
        guard let components = self.cgColor?.components, components.count >= 3 else { return "#000000" }

        let r = Float(components[0])
        let g = Float(components[1])
        let b = Float(components[2])

        return String(format: "#%02lX%02lX%02lX", lroundf(r * 255), lroundf(g * 255), lroundf(b * 255))
    }

    init(hex: String) {
        let cleanHex = hex.replacingOccurrences(of: "#", with: "")
        let scanner = Scanner(string: cleanHex)
        var hexNumber: UInt64 = 0

        if scanner.scanHexInt64(&hexNumber) {
            let r = Double((hexNumber & 0xFF0000) >> 16) / 255.0
            let g = Double((hexNumber & 0x00FF00) >> 8) / 255.0
            let b = Double(hexNumber & 0x0000FF) / 255.0

            self.init(red: r, green: g, blue: b)
            return
        }
        self.init(.black)
    }
}
