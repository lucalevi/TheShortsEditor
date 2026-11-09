@preconcurrency import AVFoundation
import CoreImage
import EditorCore
import Synchronization

/// What the compositor needs for one clip's stretch of the timeline.
nonisolated final class ShortsInstruction: NSObject, AVVideoCompositionInstructionProtocol, @unchecked Sendable {
    let timeRange: CMTimeRange
    let enablePostProcessing = false
    /// Captions change from frame to frame, so every frame is drawn.
    let containsTweening = true
    let requiredSourceTrackIDs: [NSValue]?
    let passthroughTrackID = kCMPersistentTrackID_Invalid

    let trackID: CMPersistentTrackID
    /// Places the source picture on the canvas, with the origin at the top left (as for a layer
    /// instruction): see `Framing.transform`.
    let transform: CGAffineTransform
    let captions: CaptionTrack
    let titles: TitleTrack

    init(timeRange: CMTimeRange, trackID: CMPersistentTrackID, transform: CGAffineTransform, captions: CaptionTrack, titles: TitleTrack) {
        self.timeRange = timeRange
        self.trackID = trackID
        self.transform = transform
        self.captions = captions
        self.titles = titles
        requiredSourceTrackIDs = [NSNumber(value: trackID)]
    }
}

/// Draws every frame of a Short: the clip's picture placed on the 9:16 canvas, then the titles,
/// then the captions on top.
///
/// Preview, thumbnails and export all go through this one compositor, so what is seen while
/// editing is exactly what gets exported.
nonisolated final class ShortsCompositor: NSObject, AVVideoCompositing, Sendable {
    private static let pixelFormat: [String: any Sendable] = [
        kCVPixelBufferPixelFormatTypeKey as String: [kCVPixelFormatType_32BGRA],
        kCVPixelBufferIOSurfacePropertiesKey as String: [String: any Sendable](),
    ]

    let sourcePixelBufferAttributes: [String: any Sendable]? = ShortsCompositor.pixelFormat
    let requiredPixelBufferAttributesForRenderContext: [String: any Sendable] = ShortsCompositor.pixelFormat

    // No colour conversion: video values pass through untouched, like the built-in compositor.
    private let context = CIContext(options: [.workingColorSpace: NSNull(), .outputColorSpace: NSNull(), .cacheIntermediates: false])
    private let overlayImages = Mutex<[String: CGImage]>([:])

    func renderContextChanged(_ newRenderContext: AVVideoCompositionRenderContext) {}

    func startRequest(_ request: AVAsynchronousVideoCompositionRequest) {
        guard let instruction = request.videoCompositionInstruction as? ShortsInstruction,
              let output = request.renderContext.newPixelBuffer()
        else {
            request.finish(with: NSError(domain: "ShortsCompositor", code: 1))
            return
        }
        let canvas = CGRect(origin: .zero, size: Project.canvasSize)
        var image = CIImage(color: .black).cropped(to: canvas)

        if let source = request.sourceFrame(byTrackID: instruction.trackID) {
            let height = CGFloat(CVPixelBufferGetHeight(source))
            image = CIImage(cvPixelBuffer: source)
                .transformed(by: Self.flipped(instruction.transform, sourceHeight: height))
                .composited(over: image)
        }
        for state in instruction.titles.states(at: request.compositionTime) {
            guard state.opacity > 0, let title = titleImage(state.title, scale: state.scale) else { continue }
            let over = title.composited(over: image)
            // Fading: blend between the frame without and with the title.
            image = state.opacity < 1
                ? image.applyingFilter("CIDissolveTransition", parameters: ["inputTargetImage": over, "inputTime": state.opacity])
                : over
        }
        if let caption = captionImage(for: instruction.captions, at: request.compositionTime) {
            image = caption.composited(over: image)
        }

        context.render(image.cropped(to: canvas), to: output, bounds: canvas, colorSpace: nil)
        request.finish(withComposedVideoFrame: output)
    }

    /// Converts a top-left-origin transform to Core Image, whose origin is at the bottom left of
    /// both the source picture and the canvas.
    static func flipped(_ transform: CGAffineTransform, sourceHeight: CGFloat) -> CGAffineTransform {
        let canvasHeight = Project.canvasSize.height
        return CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: sourceHeight)
            .concatenating(transform)
            .concatenating(CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: canvasHeight))
    }

    private func captionImage(for track: CaptionTrack, at time: CMTime) -> CIImage? {
        guard let state = track.state(at: time) else { return nil }
        let key = "\(track.style.rawValue)|\(state.page.id)|\(state.page.text)|\(state.word)"
        let cgImage = cachedImage(key) {
            CaptionRenderer.image(words: state.page.words.map(\.text), currentWord: state.word, style: track.style)
        }
        guard let cgImage else { return nil }

        let size = CGSize(width: cgImage.width, height: cgImage.height)
        let top = track.top(forHeight: size.height)
        let canvas = Project.canvasSize
        var image = CIImage(cgImage: cgImage)
        if CaptionRenderer.animates(track.style), state.entrance < 1 {
            // A quick pop: grow from 80% to full size around the caption's centre.
            let scale = 0.8 + 0.2 * (1 - pow(1 - state.entrance, 3))
            image = image.transformed(by: CGAffineTransform(translationX: -size.width / 2, y: -size.height / 2)
                .concatenating(CGAffineTransform(scaleX: scale, y: scale))
                .concatenating(CGAffineTransform(translationX: size.width / 2, y: size.height / 2)))
        }
        return image.transformed(by: CGAffineTransform(
            translationX: (canvas.width - size.width) / 2,
            y: canvas.height - top - size.height
        ))
    }

    private func cachedImage(_ key: String, make: () -> CGImage?) -> CGImage? {
        if let cached = overlayImages.withLock({ $0[key] }) { return cached }
        let made = make()
        if let made {
            overlayImages.withLock { cache in
                if cache.count > 64 { cache.removeAll() }
                cache[key] = made
            }
        }
        return made
    }

    private func titleImage(_ title: TextOverlay, scale: Double) -> CIImage? {
        guard let placement = TitleRenderer.placement(of: title),
              let cgImage = cachedImage("title|\(title.style.rawValue)|\(title.text)", make: { TitleRenderer.image(text: title.text, style: title.style) })
        else { return nil }
        let size = CGSize(width: cgImage.width, height: cgImage.height)
        var image = CIImage(cgImage: cgImage)
        if scale != 1 {
            image = image.transformed(by: CGAffineTransform(translationX: -size.width / 2, y: -size.height / 2)
                .concatenating(CGAffineTransform(scaleX: scale, y: scale))
                .concatenating(CGAffineTransform(translationX: size.width / 2, y: size.height / 2)))
        }
        let canvas = Project.canvasSize
        return image.transformed(by: CGAffineTransform(
            translationX: placement.image.minX,
            y: canvas.height - placement.image.maxY
        ))
    }

    func cancelAllPendingVideoCompositionRequests() {}
}
