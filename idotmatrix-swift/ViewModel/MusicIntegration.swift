
import Foundation
import CoreImage
#if os(macOS)
import AppKit
import ImageIO
#endif

extension ViewModel {
    @objc func handleColorUpdate(notification: Notification) {
        if let jsonString = notification.object as? String,
           let jsonData = jsonString.data(using: .utf8),
           let colorData = try? JSONSerialization.jsonObject(with: jsonData, options: []) as? [String: CGFloat],
           let red = colorData["red"],
           let green = colorData["green"],
           let blue = colorData["blue"] {
            // Update color properties based on logic
            self.color = .init(
                r: red > green ? min(red * (blue > red ? 1.8 : 2.5), 255) : min(red * 1.2, 255), // Boost red only if it’s higher than green
                g: green > red ? min(green * (blue > green ? 1.7 : 2.3), 255) : min(green * 1.2, 255), // Boost green only if it’s higher than red
                b: (red > blue || green > blue) ? min(blue * 0.25, 128) : min(blue * 0.8, 200) // Cap blue to prevent it from overpowering
            )
            setClock()
        } else {
            print("Failed to decode color data")
        }
    }

    @objc func handleSpotifyUpdate(notification: Notification) {
        #if os(macOS)
        updateSpotifyAlbumArt()
        #endif
    }

    func updateSpotifyAlbumArt() {
        #if os(macOS)
        if !isSpotifyEnabled { return }

        // Cancel the previous task to prevent race conditions/corruption
        currentSpotifyTask?.cancel()

        currentSpotifyTask = Task {
            // Check for cancellation at start
            if Task.isCancelled { return }

            // Handle Pause State
            if let playerState = spotifyScript?.playerState, playerState == .paused, switchToClockOnPause {
                print("Spotify paused, switching to clock")
                currentArtworkUrlString = "" // Reset tracker so resume triggers update
                await MainActor.run {
                    self.setClock()
                }
                return
            }

            guard let track = spotifyScript?.currentTrack,
                  let artworkUrlString = track.artworkUrl,
                  let trackID = track.id?(),
                  let trackName = track.name else {
                return
            }

            let uniqueId = trackID

            if uniqueId != "" && currentArtworkUrlString != uniqueId {
                currentArtworkUrlString = uniqueId

                if let artworkUrl = URL(string: artworkUrlString), let data = try? await URLSession.shared.data(from: artworkUrl) {

                    if Task.isCancelled { return }

                    let ciImage = CIImage(data: data.0)

                    // Generate GIF with scrolling text
                    if showSongTitle, let gifData = generateMarqueeGif(from: ciImage, text: trackName) {
                        if Task.isCancelled { return }

                        // Clear buffer with blank GIF to prevent artifacts
                        // Use 0 delay for blank gif for instant flush
                        if let blankGif = getBlankGif() {
                             await sendGif(blankGif, delay: 0)
                             // Robust delay to ensure device processes the clear
                             try? await Task.sleep(nanoseconds: 250_000_000) // 0.25s
                        }

                        if Task.isCancelled { return }
                        // Use 0.04s delay for reliability (0.03s was borderline)
                        await sendGif(gifData, delay: 40_000_000)
                    } else {
                        // Fallback to static image if GIF generation skipped or fails, OR if showSongTitle is false
                        let filter = CIFilter(name: "CIColorControls")!
                        filter.setValue(ciImage, forKey: kCIInputImageKey)
                        filter.setValue(1.8, forKey: kCIInputSaturationKey)
                        let context = CIContext()
                        guard let outputImage = filter.outputImage, let image = context.pngRepresentation(of: outputImage, format: .RGBAh, colorSpace: CGColorSpace(name: CGColorSpace.dcip3)!) else { return }

                        if Task.isCancelled { return }
                        await photoButtonClicked(data: image)
                    }
                }
            }
        }
        #endif
    }

    #if os(macOS)
    func generateMarqueeGif(from inputImage: CIImage?, text: String) -> Data? {
        guard let inputImage = inputImage else { return nil }
        let width = 32
        let height = 32

        // Resize and adjust saturation
        let filter = CIFilter(name: "CIColorControls")!
        filter.setValue(inputImage, forKey: kCIInputImageKey)
        filter.setValue(1.8, forKey: kCIInputSaturationKey)

        guard let filteredImage = filter.outputImage else { return nil }
        let context = CIContext()
        // Create CGImage to draw
        guard let cgImage = context.createCGImage(filteredImage, from: filteredImage.extent) else { return nil }

        // Determine Text Color based on bottom area brightness
        var textColor = NSColor.white

        // Crop to bottom 10 pixels (approx area of text)
        // Image origin in Core Image is bottom-left.
        let bottomRect = CGRect(x: 0, y: 0, width: filteredImage.extent.width, height: filteredImage.extent.height * 0.3)
        let vector = CIVector(x: bottomRect.origin.x, y: bottomRect.origin.y, z: bottomRect.size.width, w: bottomRect.size.height)

        if let areaAverageFilter = CIFilter(name: "CIAreaAverage") {
            areaAverageFilter.setValue(filteredImage, forKey: kCIInputImageKey)
            areaAverageFilter.setValue(vector, forKey: kCIInputExtentKey)

            if let outputImage = areaAverageFilter.outputImage {
                var bitmap = [UInt8](repeating: 0, count: 4)
                context.render(outputImage, toBitmap: &bitmap, rowBytes: 4, bounds: CGRect(x: 0, y: 0, width: 1, height: 1), format: .RGBA8, colorSpace: CGColorSpaceCreateDeviceRGB())

                let r = CGFloat(bitmap[0]) / 255.0
                let g = CGFloat(bitmap[1]) / 255.0
                let b = CGFloat(bitmap[2]) / 255.0

                // Calculate luminance
                let luminance = 0.299 * r + 0.587 * g + 0.114 * b

                if luminance > 0.6 { // Bright background
                    textColor = NSColor.black
                } else {
                    textColor = NSColor.white
                }
            }
        }

        // Setup Bitmap Context
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
        // Use noneSkipLast to ensure opaque alpha (RGBX), preventing transparency artifacts in simple GIF decoders
        guard let bitmapContext = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4, space: colorSpace, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }

        bitmapContext.setShouldAntialias(false) // Disable AA for crisp text on low-res 32x32 display

        // Text Attributes
        let font = NSFont.boldSystemFont(ofSize: 10)

        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: textColor,
        ]
        let attributedText = NSAttributedString(string: text, attributes: attributes)
        let textSize = attributedText.size()

        // Calculate Frames
        // Text starts at right edge (32) and scrolls to -textWidth
        // Total distance = 32 + textWidth
        let scrollStart = CGFloat(width)
        let scrollEnd = -textSize.width
        let distance = scrollStart - scrollEnd
        let speed: CGFloat = 1.0 // Pixels per frame
        let totalFrames = Int(distance / speed)

        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data as CFMutableData, kUTTypeGIF as CFString, totalFrames, nil) else { return nil }

        let frameProperties = [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 0.1]] // 0.1s delay = 10fps

        for i in 0..<totalFrames {
            // Clear
            bitmapContext.clear(CGRect(x: 0, y: 0, width: width, height: height))

            // Draw Background (resize to fill)
            bitmapContext.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

            // Draw Text at Bottom
            let xPos = scrollStart - (CGFloat(i) * speed)
            // Position at bottom. y=0 is bottom in standard Cartesian.
            let yPos: CGFloat = 0 // Fully at bottom

            NSGraphicsContext.saveGraphicsState()
            let nsContext = NSGraphicsContext(cgContext: bitmapContext, flipped: false) // Flipped false means (0,0) is bottom-left.
            NSGraphicsContext.current = nsContext

            attributedText.draw(at: CGPoint(x: xPos, y: yPos))

            NSGraphicsContext.restoreGraphicsState()

            if let frameImage = bitmapContext.makeImage() {
                CGImageDestinationAddImage(destination, frameImage, frameProperties as CFDictionary)
            }
        }

        if CGImageDestinationFinalize(destination) {
            return data as Data
        }
        return nil
    }

    // Cache the blank GIF to avoid regenerating it every time
    private static var _blankGifData: Data?

    func getBlankGif() -> Data? {
        if let data = Self._blankGifData {
            return data
        }

        let width = 32
        let height = 32
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
        guard let bitmapContext = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4, space: colorSpace, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }

        bitmapContext.setFillColor(NSColor.black.cgColor)
        bitmapContext.fill(CGRect(x: 0, y: 0, width: width, height: height))

        // 1 Frame
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data as CFMutableData, kUTTypeGIF as CFString, 1, nil) else { return nil }
        let frameProperties = [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 0.1]]

        if let frameImage = bitmapContext.makeImage() {
             CGImageDestinationAddImage(destination, frameImage, frameProperties as CFDictionary)
        }

        if CGImageDestinationFinalize(destination) {
            Self._blankGifData = data as Data
            return data as Data
        }
        return nil
    }
    #endif
}
