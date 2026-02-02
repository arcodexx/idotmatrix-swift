import SwiftUI
import AppKit
import DynamicColor
import ColorPickerRing

// MARK: - Models & Storage (Embedded for Scope Safety)

struct PixelArtModel: Codable, Identifiable {
    var id: UUID = UUID()
    var name: String
    var createdAt: Date = Date()
    var colorsInfo: [String]

    var gridColors: [Color] {
        colorsInfo.map { Color(hex: $0) }
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

enum ToolMode: String, CaseIterable {
    case pen = "pencil"
    case eraser = "eraser"
    case eyedropper = "eyedropper"

    var icon: String {
        switch self {
        case .pen: return "pencil"
        case .eraser: return "eraser.fill"
        case .eyedropper: return "eyedropper"
        }
    }
}

struct PixelArtEditorView: View {
    @ObservedObject var viewModel: ViewModel = ViewModel.shared
    @State private var gridColors: [Color] = Array(repeating: .black, count: 1024)

    // PRIMARY STATE: DynamicColor (0-255 scale)
    @State private var selectedDynamicColor: DynamicColor = DynamicColor(r: 255, g: 0, b: 0, a: 255)
    @State private var currentTool: ToolMode = .pen

    // NEW STATE PROPERTIES
    @State private var showingSaveAlert = false
    @State private var artName = ""
    @State private var showingGallery = false

    // Binding for System Picker
    var systemColorBinding: Binding<Color> {
        Binding(
            get: { Color(selectedDynamicColor) },
            set: { newColor in updateSelectedColor(from: newColor) }
        )
    }

    var selectedColor: Color {
        Color(
            red: Double(selectedDynamicColor.redComponent),
            green: Double(selectedDynamicColor.greenComponent),
            blue: Double(selectedDynamicColor.blueComponent)
        )
        .opacity(Double(selectedDynamicColor.alphaComponent))
    }

    func updateSelectedColor(from color: Color) {
        if let nsColor = NSColor(color).usingColorSpace(.deviceRGB) {
            selectedDynamicColor = DynamicColor(
                r: Double(nsColor.redComponent * 255.0),
                g: Double(nsColor.greenComponent * 255.0),
                b: Double(nsColor.blueComponent * 255.0),
                a: Double(nsColor.alphaComponent * 255.0)
            )
            return
        }
        // Fallback
        if let cgColor = color.cgColor, let components = cgColor.components {
            let count = cgColor.numberOfComponents
            if count >= 3 {
                selectedDynamicColor = DynamicColor(
                    r: Double(components[0] * 255.0),
                    g: Double(components[1] * 255.0),
                    b: Double(components[2] * 255.0),
                    a: Double(cgColor.alpha * 255.0)
                )
            }
        }
    }

    var body: some View {
        VStack {
            // Header
            HStack {
                Text("Pixel Art Editor")
                    .font(.headline)
                    .bold()

                Spacer()

                // Actions
                HStack(spacing: 12) {
                    Button(action: importImage) {
                        Label("Import", systemImage: "square.and.arrow.down")
                    }
                    .help("Import Image")

                    Button(action: { showingGallery = true }) {
                        Label("My Arts", systemImage: "photo.on.rectangle")
                    }
                    .help("View Saved Arts")

                    Button(action: { showingSaveAlert = true }) {
                        Label("Save", systemImage: "square.and.arrow.up")
                    }
                    .help("Save to My Arts")

                    Button("Send") {
                        Task { await sendPixelArt() }
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding()
            .sheet(isPresented: $showingGallery) {
                GalleryView(isPresented: $showingGallery) { loadedColors in
                    gridColors = loadedColors
                }
                .frame(width: 500, height: 600)
            }
            .alert("Save Pixel Art", isPresented: $showingSaveAlert) {
                TextField("Art Name", text: $artName)
                Button("Save") {
                    let art = PixelArtModel(name: artName.isEmpty ? "Untitled" : artName, gridColors: gridColors)
                    PixelArtStorage.shared.save(art)
                    artName = ""
                }
                Button("Cancel", role: .cancel) { }
            }

            // Drawing Area
            GeometryReader { geometry in
                let width = geometry.size.width
                let height = geometry.size.height
                let size = min(width, height)
                let cellSize = size / 32.0

                ZStack {
                    Canvas { context, size in
                        for i in 0..<1024 {
                            let rect = CGRect(
                                x: CGFloat(i % 32) * cellSize,
                                y: CGFloat(i / 32) * cellSize,
                                width: cellSize,
                                height: cellSize
                            )
                            context.fill(Path(rect), with: .color(gridColors[i]))
                            context.stroke(Path(rect), with: .color(.gray.opacity(0.3)), lineWidth: 0.5)
                        }
                    }
                }
                .frame(width: size, height: size)
                .background(Color.black)
                .border(Color.gray, width: 1)
                .onHover { isHovering in
                    if isHovering {
                        switch currentTool {
                        case .pen: NSCursor.crosshair.push()
                        case .eraser: NSCursor.openHand.push()
                        case .eyedropper: NSCursor.operationNotAllowed.push()
                        }
                    } else { NSCursor.pop() }
                }
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            let location = value.location
                            let col = Int(location.x / cellSize)
                            let row = Int(location.y / cellSize)
                            if col >= 0 && col < 32 && row >= 0 && row < 32 {
                                let index = row * 32 + col
                                handleTap(at: index)
                            }
                        }
                )
            }
            .aspectRatio(1, contentMode: .fit)
            .padding(.horizontal)

            // Tools
            ToolsView(currentTool: $currentTool, selectedDynamicColor: $selectedDynamicColor, systemColorBinding: systemColorBinding, selectedColor: selectedColor, gridColors: $gridColors)
        }
        .frame(minWidth: 720, minHeight: 750)
        .background(Color(nsColor: .windowBackgroundColor))
        .contentShape(Rectangle())
        .onTapGesture { }
    }

    private func handleTap(at index: Int) {
        switch currentTool {
        case .pen: gridColors[index] = selectedColor
        case .eraser: gridColors[index] = .black
        case .eyedropper:
            let pickedColor = gridColors[index]
            updateSelectedColor(from: pickedColor)
            currentTool = .pen
        }
    }

    private func importImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.begin { response in
            if response == .OK, let url = panel.url {
                processImportedImage(url: url)
            }
        }
    }

    private func processImportedImage(url: URL) {
        guard let image = NSImage(contentsOf: url) else { return }

        // 1. Get CGImage from NSImage
        var rect = NSRect(origin: .zero, size: image.size)
        guard let cgImage = image.cgImage(forProposedRect: &rect, context: nil, hints: nil) else { return }

        // 2. Create 32x32 Bitmap Context
        let width = 32
        let height = 32
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bytesPerRow = 32 * 4

        // Raw pixel buffer (RGBA)
        var rawData = [UInt8](repeating: 0, count: width * height * 4)

        guard let context = CGContext(
            data: &rawData,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return }

        // 3. Fill Black Background
        context.setFillColor(NSColor.black.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height)))

        // 4. Calculate Aspect Fit Rect
        let srcWidth = CGFloat(cgImage.width)
        let srcHeight = CGFloat(cgImage.height)
        let destWidth = CGFloat(width)
        let destHeight = CGFloat(height)

        // Avoid division by zero
        if srcWidth == 0 || srcHeight == 0 { return }

        let scale = min(destWidth / srcWidth, destHeight / srcHeight)
        let scaledWidth = srcWidth * scale
        let scaledHeight = srcHeight * scale

        // Center
        let x = (destWidth - scaledWidth) / 2.0
        let y = (destHeight - scaledHeight) / 2.0

        let drawingRect = CGRect(x: x, y: y, width: scaledWidth, height: scaledHeight)

        // 5. Draw Image into context
        // Draw directly (Removing Manual Flip as user reported it causes inversion)
        context.draw(cgImage, in: drawingRect)

        // 6. Extract Colors from Context Result
        guard let resizedCGImage = context.makeImage() else { return }
        let bitmap = NSBitmapImageRep(cgImage: resizedCGImage)

        var newColors: [Color] = []

        for y in 0..<height {
            for x in 0..<width {
                if let nsColor = bitmap.colorAt(x: x, y: y) {
                    // Check alpha component to treat transparent pixels as black
                    if nsColor.alphaComponent < 0.1 {
                        newColors.append(.black)
                    } else {
                        newColors.append(Color(nsColor: nsColor))
                    }
                } else {
                    newColors.append(.black) // Fallback if colorAt fails
                }
            }
        }

        if newColors.count == 1024 {
            DispatchQueue.main.async {
               self.gridColors = newColors
            }
        }
    }

    @MainActor
    func sendPixelArt() async {
        let width = 32
        let height = 32
        guard let bitmapRep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ) else { return }

        NSGraphicsContext.saveGraphicsState()
        guard let context = NSGraphicsContext(bitmapImageRep: bitmapRep) else {
             NSGraphicsContext.restoreGraphicsState(); return
        }
        NSGraphicsContext.current = context
        context.cgContext.setShouldAntialias(false)
        NSColor.black.setFill()
        NSRect(x: 0, y: 0, width: width, height: height).fill()

        for (index, color) in gridColors.enumerated() {
            let x = index % 32
            let row = index / 32
            let y = 31 - row
            NSColor(color).setFill()
            NSRect(x: x, y: y, width: 1, height: 1).fill()
        }
        NSGraphicsContext.restoreGraphicsState()

        if let pngData = bitmapRep.representation(using: .png, properties: [:]) {
            await viewModel.sendPhoto(pngData)
        }
    }
}

struct ToolsView: View {
    @Binding var currentTool: ToolMode
    @Binding var selectedDynamicColor: DynamicColor
    var systemColorBinding: Binding<Color>
    var selectedColor: Color
    @Binding var gridColors: [Color]

    var body: some View {
            HStack(spacing: 20) {
                Picker("Tool", selection: $currentTool) {
                    ForEach(ToolMode.allCases, id: \.self) { tool in
                        Image(systemName: tool.icon).tag(tool)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 150)
                Divider().frame(height: 40)
                HStack(spacing: 15) {
                    ColorPickerRing(color: $selectedDynamicColor, strokeWidth: 20)
                        .frame(width: 60, height: 60)
                        .onChange(of: selectedDynamicColor) {
                             if currentTool != .pen { currentTool = .pen }
                        }
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Hex / System")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                        HStack {
                            ColorPicker("", selection: systemColorBinding)
                                .labelsHidden()
                                .frame(width: 30, height: 30)
                            HexColorInputField(dynamicColor: $selectedDynamicColor, currentTool: $currentTool)
                                .frame(width: 80)
                        }
                    }
                }
                Divider().frame(height: 40)
                HStack(spacing: 10) {
                    Button(action: { gridColors = Array(repeating: .black, count: 1024) }) {
                        Label("Clear", systemImage: "trash").labelStyle(.iconOnly)
                    }
                    .buttonStyle(.plain)
                    .help("Clear Grid")
                    Button(action: { gridColors = Array(repeating: selectedColor, count: 1024) }) {
                        Label("Fill", systemImage: "paintpalette.fill").labelStyle(.iconOnly)
                    }
                    .buttonStyle(.plain)
                    .help("Fill Grid")
                }
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color(nsColor: .controlBackgroundColor)))
            .padding(.bottom)
    }
}

struct GalleryView: View {
    @Binding var isPresented: Bool
    var onLoad: ([Color]) -> Void
    @State private var arts: [PixelArtModel] = []
    let columns = [GridItem(.adaptive(minimum: 100))]
    var body: some View {
        VStack {
            HStack {
                Text("My Gallery").font(.title2).bold()
                Spacer()
                Button("Close") { isPresented = false }
            }
            .padding()
            ScrollView {
                LazyVGrid(columns: columns, spacing: 20) {
                    ForEach(arts) { art in
                        VStack {
                            Canvas { context, size in
                                let cellSize = size.width / 32.0
                                let colors = art.gridColors
                                for i in 0..<1024 {
                                    let color = i < colors.count ? colors[i] : .black
                                    let rect = CGRect(x: CGFloat(i % 32) * cellSize, y: CGFloat(i / 32) * cellSize, width: cellSize, height: cellSize)
                                    context.fill(Path(rect), with: .color(color))
                                }
                            }
                            .frame(width: 100, height: 100)
                            .cornerRadius(8)
                            .onTapGesture { onLoad(art.gridColors); isPresented = false }
                            Text(art.name).lineLimit(1).font(.caption)
                            Button(role: .destructive) { delete(art) } label: {
                                Image(systemName: "trash").foregroundStyle(.red)
                            }.buttonStyle(.plain)
                        }
                        .padding(8)
                        .background(RoundedRectangle(cornerRadius: 10).fill(Color.gray.opacity(0.1)))
                    }
                }
                .padding()
            }
        }
        .onAppear { arts = PixelArtStorage.shared.loadAll() }
    }
    func delete(_ art: PixelArtModel) {
        PixelArtStorage.shared.delete(art)
        arts = PixelArtStorage.shared.loadAll()
    }
}

struct HexColorInputField: View {
    @Binding var dynamicColor: DynamicColor
    @Binding var currentTool: ToolMode
    @State private var hexString: String = ""
    var body: some View {
        TextField("#Hex", text: $hexString)
            .textFieldStyle(.roundedBorder)
            .font(.system(size: 11, design: .monospaced))
            .onAppear { updateHexString() }
            .onChange(of: dynamicColor) { updateHexString() }
            .onSubmit { updateColorFromHex() }
            .onChange(of: hexString) { if hexString.count >= 6 { updateColorFromHex() } }
    }
    private func updateHexString() {
        let r = Int(dynamicColor.redComponent * 255.0)
        let g = Int(dynamicColor.greenComponent * 255.0)
        let b = Int(dynamicColor.blueComponent * 255.0)
        let newHex = String(format: "%02X%02X%02X", r, g, b)
        if newHex != hexString.replacingOccurrences(of: "#", with: "") { hexString = newHex }
    }
    private func updateColorFromHex() {
        let cleanHex = hexString.replacingOccurrences(of: "#", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard cleanHex.count == 6 else { return }
        let scanner = Scanner(string: cleanHex)
        var hexNumber: UInt64 = 0
        if scanner.scanHexInt64(&hexNumber) {
            let r = Double((hexNumber & 0xFF0000) >> 16)
            let g = Double((hexNumber & 0x00FF00) >> 8)
            let b = Double(hexNumber & 0x0000FF)
            let currentR = dynamicColor.redComponent * 255.0
            let currentG = dynamicColor.greenComponent * 255.0
            let currentB = dynamicColor.blueComponent * 255.0
            if abs(currentR - r) > 0.5 || abs(currentG - g) > 0.5 || abs(currentB - b) > 0.5 {
                dynamicColor = DynamicColor(r: r, g: g, b: b, a: 255.0)
                if currentTool != .pen { currentTool = .pen }
            }
        }
    }
}

class PixelArtWindowManager: NSObject, NSWindowDelegate {
    static let shared = PixelArtWindowManager()
    private var window: NSWindow?
    func open() {
        if let window = window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let newWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 750),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered, defer: false
        )
        newWindow.title = "Pixel Art Editor"
        newWindow.isReleasedWhenClosed = false
        newWindow.center()
        newWindow.contentView = NSHostingView(rootView: PixelArtEditorView())
        newWindow.delegate = self
        newWindow.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.window = newWindow
    }
    func windowWillClose(_ notification: Notification) { self.window = nil }
}
