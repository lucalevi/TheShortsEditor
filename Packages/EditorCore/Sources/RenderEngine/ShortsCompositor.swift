@preconcurrency import AVFoundation
import CoreImage
import EditorCore
import ImageIO
import Synchronization

/// One picture drawn in a stretch of the timeline: the main clip, or an overlay on top of it.
nonisolated struct CompositorLayer: Sendable {
    enum Source: Sendable {
        /// Frames of a composition track.
        case track(CMPersistentTrackID)
        /// A still picture file.
        case image(URL)
        /// One picture of a video (a freeze frame, or a clip held at the edge of a transition).
        case frame(FrameStills.Still)
        /// Nothing to draw (missing media): the layer shows black (main) or nothing (overlay).
        case none
    }

    let source: Source
    /// The clip's settings: framing, placement, motion, background.
    let clip: Clip
    /// Where the clip starts on the timeline, to find the source time of each frame.
    let timelineStart: CMTime
    /// The size and orientation of the source picture (for a track, as stored in the file).
    let naturalSize: CGSize
    let preferredTransform: CGAffineTransform
    /// The main clip fills the canvas behind it (blurred or black); overlays don't.
    let isMain: Bool
    /// Where on the canvas it is drawn (canvas pixels, origin top left): the whole canvas, or half
    /// of it in a split screen. The picture is framed inside it and cut to it.
    let region: CGRect
    /// How to steady a shaky video (Stabilize), once its file has been measured.
    var steadying: Steadying? = nil

    func with(region: CGRect) -> CompositorLayer {
        CompositorLayer(source: source, clip: clip, timelineStart: timelineStart, naturalSize: naturalSize,
                        preferredTransform: preferredTransform, isMain: isMain, region: region, steadying: steadying)
    }
}

/// A transition under way: the main clip of the instruction is changing into, or from, `other`.
nonisolated struct TransitionDrawing: Sendable {
    let kind: TransitionKind
    /// When the whole transition plays, for how far through it a frame is.
    let range: CMTimeRange
    /// The clip that isn't the main one of this stretch.
    let other: CompositorLayer
    /// True before the cut (the other clip is the one coming in), false after it.
    let otherIsIncoming: Bool
}

/// What the compositor needs for one stretch of the timeline where the same clips are on screen.
nonisolated final class ShortsInstruction: NSObject, AVVideoCompositionInstructionProtocol, @unchecked Sendable {
    let timeRange: CMTimeRange
    let enablePostProcessing = false
    /// Captions and motion change from frame to frame, so every frame is drawn.
    let containsTweening = true
    let requiredSourceTrackIDs: [NSValue]?
    let passthroughTrackID = kCMPersistentTrackID_Invalid

    /// Bottom first: the main clip, then the overlays in order.
    let layers: [CompositorLayer]
    let captions: CaptionTrack
    let titles: TitleTrack
    let transition: TransitionDrawing?
    /// The filter over the whole Short, drawn over the clips (not the titles and captions).
    let look: FilterChoice?

    init(timeRange: CMTimeRange, layers: [CompositorLayer], captions: CaptionTrack, titles: TitleTrack, transition: TransitionDrawing? = nil,
         look: FilterChoice? = nil) {
        self.timeRange = timeRange
        self.layers = layers
        self.captions = captions
        self.titles = titles
        self.transition = transition
        self.look = look
        let trackIDs = (layers + (transition.map { [$0.other] } ?? [])).compactMap { layer -> CMPersistentTrackID? in
            if case .track(let id) = layer.source { id } else { nil }
        }
        requiredSourceTrackIDs = trackIDs.isEmpty ? nil : trackIDs.map { NSNumber(value: $0) }
    }
}

/// While a picture is being dragged in the viewer, the placement it would have, drawn straight
/// away without rebuilding the composition. Cleared when the drag ends and the edit is made.
public nonisolated enum LivePreview {
    private static let placements = Mutex<[Clip.ID: Placement]>([:])

    public static func set(_ placement: Placement?, for clipID: Clip.ID) {
        placements.withLock { $0[clipID] = placement }
    }

    public static func clearAll() {
        placements.withLock { $0.removeAll() }
        looks.withLock { $0.removeAll() }
        shortLook.withLock { $0 = nil }
    }

    static func placement(for clipID: Clip.ID) -> Placement? {
        placements.withLock { $0[clipID] }
    }

    // Colour sliders being dragged: the look they would give, shown at once.
    private static let looks = Mutex<[Clip.ID: ClipLook]>([:])
    private static let shortLook = Mutex<FilterChoice??>(nil)
    private static let original = Mutex(false)

    public static func setLook(_ look: ClipLook?, for clipID: Clip.ID) {
        looks.withLock { $0[clipID] = look }
    }

    static func look(for clipID: Clip.ID) -> ClipLook? {
        looks.withLock { $0[clipID] }
    }

    /// The whole Short's filter while its strength slider is dragged (`.some(nil)`: no filter).
    public static func setShortLook(_ choice: FilterChoice??) {
        shortLook.withLock { $0 = choice }
    }

    static var shortLookOverride: FilterChoice?? { shortLook.withLock { $0 } }

    /// Before/after: while true, every picture is drawn without its look (colour and filters).
    public static var showsOriginal: Bool {
        get { original.withLock { $0 } }
        set { original.withLock { $0 = newValue } }
    }
}

/// Draws every frame of a Short: the main clip's picture placed on the 9:16 canvas (over a
/// blurred copy of itself, or black, where it doesn't reach), the overlays, then the titles,
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
        let time = request.compositionTime
        let canvas = CGRect(origin: .zero, size: Project.canvasSize)
        var image = CIImage(color: .black).cropped(to: canvas)

        var layers = instruction.layers[...]
        if let transition = instruction.transition, let main = layers.first, main.isMain {
            // Both clips drawn whole, then mixed; B-roll, titles and captions go on top as usual.
            let black = CIImage(color: .black).cropped(to: canvas)
            let mainImage = draw(main, at: time, request: request, over: black)
            let otherImage = draw(transition.other, at: time, request: request, over: black)
            let region = main.region
            let ciRegion = CGRect(x: region.minX, y: canvas.height - region.maxY, width: region.width, height: region.height)
            // Counted from the middle of each frame, so the first and last frames are equally far in.
            let into = (time - transition.range.start).seconds + 0.5 / Double(Project.frameRate)
            let progress = min(max(into / max(transition.range.duration.seconds, 0.001), 0), 1)
            let mixed = TransitionMixer.mix(transition.kind, from: transition.otherIsIncoming ? mainImage : otherImage,
                                            to: transition.otherIsIncoming ? otherImage : mainImage, progress: progress, in: ciRegion)
            image = mixed.cropped(to: ciRegion).composited(over: image)
            layers = layers.dropFirst()
        }
        for layer in layers {
            image = draw(layer, at: time, request: request, over: image)
        }
        if !LivePreview.showsOriginal, let look = LivePreview.shortLookOverride ?? instruction.look {
            image = LookRenderer.apply(look, to: image.cropped(to: canvas))
        }

        for state in instruction.titles.states(at: time) {
            guard state.opacity > 0, let title = titleImage(state) else { continue }
            let over = title.composited(over: image)
            // Fading: blend between the frame without and with the title.
            image = state.opacity < 1
                ? image.applyingFilter("CIDissolveTransition", parameters: ["inputTargetImage": over, "inputTime": state.opacity])
                : over
        }
        if let caption = captionImage(for: instruction.captions, at: time) {
            image = caption.composited(over: image)
        }

        context.render(image.cropped(to: canvas), to: output, bounds: canvas, colorSpace: nil)
        request.finish(withComposedVideoFrame: output)
    }

    /// Draws one layer over `image`: its picture framed and placed in its region (over a blurred
    /// copy of itself or black for a main clip), see-through as far as its opacity and fades say.
    private func draw(_ layer: CompositorLayer, at time: CMTime, request: AVAsynchronousVideoCompositionRequest, over image: CIImage) -> CIImage {
        let canvas = CGRect(origin: .zero, size: Project.canvasSize)
        let region = layer.region
        // Core Image's origin is at the bottom left.
        let ciRegion = CGRect(x: region.minX, y: canvas.height - region.maxY, width: region.width, height: region.height)
        guard var source = sourceImage(for: layer, request: request) else {
            return layer.isMain ? CIImage(color: .black).cropped(to: ciRegion).composited(over: image) : image
        }
        if !LivePreview.showsOriginal {
            source = LookRenderer.apply(LivePreview.look(for: layer.clip.id) ?? layer.clip.look, to: source)
        }
        var image = image
        let offset = time - layer.timelineStart
        let sourceTime = layer.clip.sourceTime(atOffset: offset)
        let placement = LivePreview.placement(for: layer.clip.id) ?? layer.clip.placement(atSourceTime: sourceTime)
        // Steadied (moved against the shake and zoomed in a little), then framed to the region's
        // size, then moved, resized and turned around its middle, then put in place.
        let steady = layer.steadying?.transform(atSourceTime: sourceTime, naturalSize: layer.naturalSize) ?? .identity
        let transform = steady
            .concatenating(layer.clip.framing.transform(naturalSize: layer.naturalSize, preferredTransform: layer.preferredTransform, canvas: region.size))
            .concatenating(placement.transform(in: region))
        let height = source.extent.height
        if layer.isMain {
            let covers = layer.clip.framing.placedFrame(of: Self.displaySize(layer), placement: placement, region: region).covers(region)
            let behind = layer.clip.background == .blur && !covers
                ? Self.blurredBackground(source, layer: layer, sourceHeight: height)
                : CIImage(color: .black)
            image = behind.cropped(to: ciRegion).composited(over: image)
        }
        // Cut to the region (the canvas, or half of it) so a big picture doesn't spill over.
        var placed = source.transformed(by: Self.flipped(transform, sourceHeight: height)).cropped(to: ciRegion)
        let opacity = placement.opacity * (layer.isMain ? 1 : layer.clip.pictureFade(atOffset: offset))
        if opacity <= 0 { return image }
        if opacity < 1 {
            placed = placed.applyingFilter("CIColorMatrix", parameters: ["inputAVector": CIVector(x: 0, y: 0, z: 0, w: opacity)])
        }
        return placed.composited(over: image)
    }

    private func sourceImage(for layer: CompositorLayer, request: AVAsynchronousVideoCompositionRequest) -> CIImage? {
        switch layer.source {
        case .track(let id):
            return request.sourceFrame(byTrackID: id).map { CIImage(cvPixelBuffer: $0) }
        case .image(let url):
            return StillImages.image(at: url).map { CIImage(cgImage: $0) }
        case .frame(let still):
            return CIImage(cvPixelBuffer: still.buffer)
        case .none:
            return nil
        }
    }

    /// The upright size of the layer's picture.
    private static func displaySize(_ layer: CompositorLayer) -> CGSize {
        let rect = CGRect(origin: .zero, size: layer.naturalSize).applying(layer.preferredTransform)
        return CGSize(width: abs(rect.width), height: abs(rect.height))
    }

    /// The same picture filling the canvas, enlarged a little and blurred, behind a picture that
    /// doesn't cover it. Blurred at a quarter of the size, which is much quicker and looks the same.
    private static func blurredBackground(_ source: CIImage, layer: CompositorLayer, sourceHeight: CGFloat) -> CIImage {
        let canvas = CGRect(origin: .zero, size: Project.canvasSize)
        let fill = Framing.fill.transform(naturalSize: layer.naturalSize, preferredTransform: layer.preferredTransform, canvas: layer.region.size)
            .concatenating(Placement(scale: 1.1).transform(in: layer.region))
        let small = CGAffineTransform(scaleX: 0.25, y: 0.25)
        return source
            .transformed(by: flipped(fill, sourceHeight: sourceHeight).concatenating(small))
            .clampedToExtent()
            .applyingGaussianBlur(sigma: 14)
            .applyingFilter("CIColorControls", parameters: [kCIInputBrightnessKey: -0.08, kCIInputSaturationKey: 1.1])
            .transformed(by: small.inverted())
            .cropped(to: canvas)
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
        var hasher = Hasher()
        hasher.combine(track.settings)
        hasher.combine(state.drawing)
        let key = "caption|\(hasher.finalize())"
        let cgImage = cachedImage(key) { CaptionRenderer.image(state.drawing, settings: track.settings) }
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

    private func titleImage(_ state: TitleTrack.State) -> CIImage? {
        let title = state.title, scale = state.scale
        let key = "title|\(title.look.hashValue)|\(title.text)|\(state.visibleCharacters ?? -1)"
        guard let placement = TitleRenderer.placement(of: title),
              let cgImage = cachedImage(key, make: { TitleRenderer.image(text: title.text, look: title.look, visibleCharacters: state.visibleCharacters) })
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
            y: canvas.height - placement.image.maxY - state.yOffset
        ))
    }

    func cancelAllPendingVideoCompositionRequests() {}
}

/// Still pictures, decoded once at a size good enough for a 1080×1920 Short (and turned the
/// right way up), then kept while they are used.
public nonisolated enum StillImages {
    /// Long side in pixels: enough to zoom in a little on a full-screen picture.
    static let maxPixelSize = 2600
    private static let cache = Mutex<[URL: CGImage]>([:])

    /// The picture at `url`, or nil when it can't be read.
    public static func image(at url: URL) -> CGImage? {
        if let cached = cache.withLock({ $0[url] }) { return cached }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                  kCGImageSourceCreateThumbnailFromImageAlways: true,
                  kCGImageSourceCreateThumbnailWithTransform: true,
                  kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
                  kCGImageSourceShouldCacheImmediately: true,
              ] as CFDictionary)
        else { return nil }
        cache.withLock { cache in
            if cache.count > 40 { cache.removeAll() }
            cache[url] = image
        }
        return image
    }

    /// The upright size of the picture at `url`, in pixels, without decoding it.
    public static func size(at url: URL) -> CGSize? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              CGImageSourceGetCount(source) > 0,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0
        else { return nil }
        // EXIF orientations 5–8 are turned a quarter, so width and height swap.
        let orientation = properties[kCGImagePropertyOrientation] as? Int ?? 1
        return orientation >= 5 ? CGSize(width: height, height: width) : CGSize(width: width, height: height)
    }

    /// Forgets a picture, e.g. after its file was relinked.
    public static func forget(_ url: URL) {
        cache.withLock { _ = $0.removeValue(forKey: url) }
    }
}
