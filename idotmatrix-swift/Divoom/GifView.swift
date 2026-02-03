import SwiftUI


struct GifView: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> NSImageView {
        let imageView = NSImageView()
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.animates = true
        imageView.setContentHuggingPriority(.defaultLow, for: .horizontal)
        imageView.setContentHuggingPriority(.defaultLow, for: .vertical)
        return imageView
    }

    func updateNSView(_ nsView: NSImageView, context: Context) {
        if let image = NSImage(contentsOf: url) {
            nsView.image = image
            nsView.animates = true
        }
    }
}
