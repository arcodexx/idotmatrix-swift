//
//  Text.swift
//  idotmatrix-swift
//
//  Created by Avi Wadhwa on 2024-12-01.
//

import Foundation
import AppKit
import CoreGraphics
import zlib

// Text
extension ViewModel {
    @MainActor
    func sendText(_ text: String) {
        currentlyDisplayingImage = .notImage
        guard !text.isEmpty else { return }

        // 1. Generate Bitmaps
        let bitmaps = generateBitmaps(for: text)
        let numChars = UInt16(bitmaps.count)

        let allBitmapsData = bitmaps.reduce(into: Data()) { result, data in
            result.append(data)
        }

        // 2. Build Metadata
        // 0-1: Num Chars
        // 2: 0, 3: 1
        // 4: Text Mode (1 = marquee)
        // 5: Speed (95)
        // 6: Color Mode (1 = RGB)
        // 7-9: RGB
        // 10: Bg Mode (0)
        // 11-13: BgRGB (0,0,0)

        var metadata = Data()
        withUnsafeBytes(of: numChars.littleEndian) { metadata.append(contentsOf: $0) }
        metadata.append(contentsOf: [0, 1] as [UInt8])
        metadata.append(0) // Text Mode (0 = Replace, 1 = Marquee) - Trying 0 for instant feedback
        metadata.append(95) // Speed
        metadata.append(1) // Color Mode
        metadata.append(UInt8(color.redComponent * 255))
        metadata.append(UInt8(color.greenComponent * 255))
        metadata.append(UInt8(color.blueComponent * 255))
        metadata.append(0) // Bg Mode
        metadata.append(contentsOf: [0, 0, 0] as [UInt8]) // BgRGB

        print("Metadata Count: \(metadata.count)")
        print("Metadata Hex: \(metadata.map { String(format: "%02x", $0) }.joined())")

        // 3. Build Packet
        let packet = metadata + allBitmapsData
        print("Bitmaps Length: \(allBitmapsData.count)")
        print("Total Packet Length: \(packet.count)")

        // 4. Build Header
        // 0-1: Total Len (Packet + 16)
        // 2: 3 (Command)
        // 3-4: 0, 0
        // 5-8: Packet Len
        // 9-12: CRC32
        // 13-16: 0,0,12
        // Total header size = 16 bytes.

        var header = Data(count: 16)
        let totalLen = UInt16(packet.count + 16)

        // Set Header Values
        header.replaceSubrange(0..<2, with: withUnsafeBytes(of: totalLen.littleEndian) { Data($0) })
        header[2] = 3

        let packetLen = UInt32(packet.count)
        header.replaceSubrange(5..<9, with: withUnsafeBytes(of: packetLen.littleEndian) { Data($0) })

        // CRC
        // zlib.crc32 signature: (uLong, UnsafePointer<Bytef>?, uInt) -> uLong
        let crc = packet.withUnsafeBytes { buffer in
            return zlib.crc32(0, buffer.bindMemory(to: Bytef.self).baseAddress, uInt(packet.count))
        }
        let crc32 = UInt32(crc) // Cast to 32-bit to ensure 4 bytes
        header.replaceSubrange(9..<13, with: withUnsafeBytes(of: crc32.littleEndian) { Data($0) })

        header[15] = 12


        // 5. Send
        let finalData = header + packet

        Task {
            await sendDataChunked(data: finalData)
        }
    }

    // Chunking with Task.sleep
    func sendDataChunked(data: Data) async {
        let chunkSize = 20 // Safe MTU for BLE without response
        var offset = 0
        while offset < data.count {
            let length = min(chunkSize, data.count - offset)
            let chunk = data.subdata(in: offset..<offset+length)
            sendData(data: chunk)
            offset += length
            // Delay is crucial for withoutResponse
            try? await Task.sleep(nanoseconds: 50_000_000) // 50ms
        }
    }

    func generateBitmaps(for text: String) -> [Data] {
        #if os(macOS)
        let font = NSFont.systemFont(ofSize: 20) // 16x32 canvas, 20pt might fit well
        let width = 16
        let height = 32
        let separator = Data([0x05, 0xff, 0xff, 0xff])

        var bitmaps: [Data] = []

        for char in text {
            // Create Context
            let colorSpace = CGColorSpaceCreateDeviceGray()
            guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width, space: colorSpace, bitmapInfo: CGImageAlphaInfo.none.rawValue) else { continue }

            // Draw
            context.setFillColor(gray: 0.0, alpha: 1.0) // Black background
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))

            let charStr = String(char) as NSString
            let attributes: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: NSColor.white
            ]

            let size = charStr.size(withAttributes: attributes)
            let x = (CGFloat(width) - size.width) / 2
            let y = (CGFloat(height) - size.height) / 2

            NSGraphicsContext.saveGraphicsState()
            let nsContext = NSGraphicsContext(cgContext: context, flipped: false)
            NSGraphicsContext.current = nsContext

            charStr.draw(at: CGPoint(x: x, y: y), withAttributes: attributes)

            NSGraphicsContext.restoreGraphicsState()

            // Extract Bits
            guard let pixelData = context.data else { continue }

            var charBitmap = Data()

            for y in 0..<height {
                for colByte in 0..<2 { // 16 width / 8 = 2 bytes
                    var byte: UInt8 = 0
                    for bit in 0..<8 {
                        let x = colByte * 8 + bit
                        // Get Pixel value.
                        // Context is 8-bit gray. 0=Black, 255=White.
                        // We want 1 for White (Text), 0 for Black.
                        // Row offset = y * width.

                        // CGContext with .none is top-left origin usually?
                        // Actually NSGraphicsContext with flipped: false is Bottom-Left.
                        // Python used top-left.
                        // If I draw at x,y with normal coordinates, I get upright text.
                        // If I read pixels linearly, I just need to match the display order.
                        // Assuming display is standard raster scan (top-left to bottom-right).
                        // If my context is bottom-left, I need to read rows in reverse Y order.

                        let rawIndex = y * width + x
                        let pixelValue = pixelData.load(fromByteOffset: rawIndex, as: UInt8.self)

                        // pixelValue is 0 (black) or 255 (white).
                        // If it's something else due to antialiasing, >127 is safe threshold.

                        if pixelValue > 127 {
                            byte |= (1 << bit)
                        }
                    }
                    charBitmap.append(byte)
                }
            }
            // Append Separator + Bitmap
            var entry = Data()
            entry.append(separator)
            entry.append(charBitmap)
            bitmaps.append(entry)
        }

        return bitmaps
        #else
        return []
        #endif
    }
}
