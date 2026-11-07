import CoreGraphics

public extension Framing {
    /// The transform that places a video track's frames on the canvas.
    ///
    /// `preferredTransform` is the track's own orientation (e.g. a 90° rotation for footage shot
    /// in portrait on an iPhone). It is applied first, then the upright picture is scaled to fill
    /// or fit the canvas and centred.
    func transform(naturalSize: CGSize, preferredTransform: CGAffineTransform, canvas: CGSize = Project.canvasSize) -> CGAffineTransform {
        let oriented = CGRect(origin: .zero, size: naturalSize).applying(preferredTransform)
        guard oriented.width > 0, oriented.height > 0 else { return preferredTransform }
        let scaleX = canvas.width / oriented.width
        let scaleY = canvas.height / oriented.height
        let scale = self == .fill ? max(scaleX, scaleY) : min(scaleX, scaleY)
        let offsetX = (canvas.width - oriented.width * scale) / 2
        let offsetY = (canvas.height - oriented.height * scale) / 2
        return preferredTransform
            .concatenating(CGAffineTransform(translationX: -oriented.minX, y: -oriented.minY))
            .concatenating(CGAffineTransform(scaleX: scale, y: scale))
            .concatenating(CGAffineTransform(translationX: offsetX, y: offsetY))
    }
}

/// Areas of a Short covered by YouTube's own interface (title, channel name, buttons).
/// Text and faces placed there get hidden.
///
/// The figures are approximate: guides disagree and no official overlay was found (see
/// research/shorts-editor-research.md §2). Values are in canvas pixels (1080×1920).
public enum SafeZone {
    public static let top: CGFloat = 200
    public static let bottom: CGFloat = 480
    /// The column of like/comment/share buttons on the right…
    public static let right: CGFloat = 140
    /// …which starts this far from the top.
    public static let rightColumnTop: CGFloat = 860

    /// The covered regions, in canvas coordinates with the origin at the top left.
    public static var coveredRects: [CGRect] {
        let canvas = Project.canvasSize
        return [
            CGRect(x: 0, y: 0, width: canvas.width, height: top),
            CGRect(x: 0, y: canvas.height - bottom, width: canvas.width, height: bottom),
            CGRect(x: canvas.width - right, y: rightColumnTop, width: right, height: canvas.height - bottom - rightColumnTop),
        ]
    }
}
