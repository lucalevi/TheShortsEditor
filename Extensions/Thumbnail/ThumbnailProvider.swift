import AppKit
import EditorCore
import QuickLookThumbnailing

/// Finder's thumbnail of a saved Short (`.shortsproject`, F27): a vertical card with its name,
/// length and number of clips, read from the summary at the top of the file without building the
/// project. (The poster picture lives in the app's own folder, which Finder can't reach.)
final class ThumbnailProvider: QLThumbnailProvider {
    override func provideThumbnail(for request: QLFileThumbnailRequest, _ handler: @escaping (QLThumbnailReply?, Error?) -> Void) {
        let listing: ProjectFile.Listing
        do {
            listing = try ProjectFile.readListing(Data(contentsOf: request.fileURL))
        } catch {
            handler(nil, error)
            return
        }
        let name = listing.name ?? request.fileURL.deletingPathExtension().lastPathComponent
        let length = TimeFormat.string(listing.summary.duration)
        let clips = listing.summary.clipCount
        // 9:16, fitted into the size Finder asks for.
        let height = request.maximumSize.height, width = min(request.maximumSize.width, height * 9 / 16)
        let size = CGSize(width: width, height: width * 16 / 9)
        let reply = QLThumbnailReply(contextSize: size) { context in
            Self.draw(in: context, size: size, name: name, details: "\(length) · \(clips) \(clips == 1 ? "clip" : "clips")")
            return true
        }
        handler(reply, nil)
    }

    private static func draw(in context: CGContext, size: CGSize, name: String, details: String) {
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let bounds = CGRect(origin: .zero, size: size)
        let card = CGPath(roundedRect: bounds, cornerWidth: size.width * 0.08, cornerHeight: size.width * 0.08, transform: nil)
        context.addPath(card)
        context.clip()
        let colours = [CGColor(srgbRed: 94 / 255, green: 92 / 255, blue: 230 / 255, alpha: 1), CGColor(srgbRed: 1, green: 55 / 255, blue: 140 / 255, alpha: 1)]
        let gradient = CGGradient(colorsSpace: space, colors: colours as CFArray, locations: [0, 1])!
        context.drawLinearGradient(gradient, start: CGPoint(x: 0, y: size.height), end: CGPoint(x: size.width, y: 0), options: [])

        // A play sign in the middle.
        let side = size.width * 0.28, middle = CGPoint(x: size.width / 2 + side * 0.08, y: size.height * 0.58)
        context.move(to: CGPoint(x: middle.x - side * 0.45, y: middle.y + side * 0.55))
        context.addLine(to: CGPoint(x: middle.x + side * 0.55, y: middle.y))
        context.addLine(to: CGPoint(x: middle.x - side * 0.45, y: middle.y - side * 0.55))
        context.closePath()
        context.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.95))
        context.fillPath()

        // The name and the details at the bottom, on a dark band.
        let band = CGRect(x: 0, y: 0, width: size.width, height: size.height * 0.26)
        context.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.45))
        context.fill(band)
        let graphics = NSGraphicsContext(cgContext: context, flipped: false)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = graphics
        let inset = size.width * 0.07
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        let title = NSAttributedString(
            string: name,
            attributes: [.font: NSFont.systemFont(ofSize: size.width * 0.085, weight: .bold), .foregroundColor: NSColor.white, .paragraphStyle: paragraph])
        title.draw(in: CGRect(x: inset, y: band.height * 0.42, width: size.width - 2 * inset, height: band.height * 0.45))
        let subtitle = NSAttributedString(
            string: details,
            attributes: [.font: NSFont.systemFont(ofSize: size.width * 0.062, weight: .medium), .foregroundColor: NSColor.white.withAlphaComponent(0.85)])
        subtitle.draw(in: CGRect(x: inset, y: band.height * 0.12, width: size.width - 2 * inset, height: band.height * 0.3))
        NSGraphicsContext.restoreGraphicsState()
    }
}
