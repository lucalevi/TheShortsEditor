import CoreGraphics
import Foundation

// Cut-outs (Stage K): taking away part of a clip's picture so what is under it shows. The
// background can be removed (a copy of the file with the person or subject alone, made once by
// Vision, see `CutoutCache`), a coloured screen keyed out, and a shape (mask) kept. B-roll can
// also be mixed into the clips under it (blend modes). All of it is drawn by the compositor.

/// What Remove Background keeps.
public enum CutoutSubject: String, Codable, CaseIterable, Identifiable, Sendable {
    /// People, found with Vision's person segmentation (quick, made for video).
    case people
    /// Whatever stands out in front: a pet, a product, a person (Vision's subject lifting).
    case subject

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .people: "People"
        case .subject: "Main subject"
        }
    }

    public var hint: String {
        switch self {
        case .people: "Keeps the people and takes away everything else"
        case .subject: "Keeps whatever stands out in front: a person, a pet, an object"
        }
    }
}

/// Keying out a coloured screen (green screen): pixels near `color` become see-through.
public struct ColorKey: Codable, Equatable, Hashable, Sendable {
    /// The screen's colour, as it looks in the clip.
    public var color: RGBA
    /// How far from the colour still goes (0…1).
    public var strength: Double
    /// How gradually the edge goes from gone to kept (0…1).
    public var softness: Double
    /// How much of the screen's colour is taken off what is kept (the glow it casts on hair and edges), 0…1.
    public var spill: Double

    public init(color: RGBA = ColorKey.green, strength: Double = 0.45, softness: Double = 0.3, spill: Double = 0.5) {
        self.color = color
        self.strength = strength
        self.softness = softness
        self.spill = spill
    }

    /// A typical green screen, and blue screen, as cameras see them.
    public static let green = RGBA(0.2, 0.75, 0.3)
    public static let blue = RGBA(0.15, 0.3, 0.85)

    /// A pixel's colour without its brightness (a point near 0, 0 is grey).
    static func chroma(_ r: Double, _ g: Double, _ b: Double) -> (cb: Double, cr: Double) {
        (-0.168_736 * r - 0.331_264 * g + 0.5 * b, 0.5 * r - 0.418_688 * g - 0.081_312 * b)
    }

    /// Where the edge starts (fully gone below it) and ends (fully kept above it), as a distance
    /// between colours without their brightness.
    var edge: (inner: Double, outer: Double) {
        let inner = 0.03 + 0.3 * strength.clamped(0, 1)
        return (inner, inner + 0.01 + 0.25 * softness.clamped(0, 1))
    }

    /// The colour and see-through-ness (alpha 0…1, not premultiplied) a pixel has once keyed.
    public func keyed(_ r: Double, _ g: Double, _ b: Double) -> (red: Double, green: Double, blue: Double, alpha: Double) {
        let key = Self.chroma(color.red, color.green, color.blue)
        let pixel = Self.chroma(r, g, b)
        let distance = hypot(pixel.cb - key.cb, pixel.cr - key.cr)
        let (inner, outer) = edge
        let t = ((distance - inner) / (outer - inner)).clamped(0, 1)
        let alpha = t * t * (3 - 2 * t)
        guard spill > 0 else { return (r, g, b, alpha) }
        // The part of the pixel's colour that leans towards the screen's is taken off, more the
        // closer it is to the edge; the brightness stays.
        let length = hypot(key.cb, key.cr)
        guard length > 0.000_1 else { return (r, g, b, alpha) }
        let along = (pixel.cb * key.cb + pixel.cr * key.cr) / length
        guard along > 0 else { return (r, g, b, alpha) }
        let removed = along * spill.clamped(0, 1) * (1 - 0.5 * alpha)
        let cb = pixel.cb - removed * key.cb / length, cr = pixel.cr - removed * key.cr / length
        let y = 0.299 * r + 0.587 * g + 0.114 * b
        return ((y + 1.402 * cr).clamped(0, 1), (y - 0.344_136 * cb - 0.714_136 * cr).clamped(0, 1), (y + 1.772 * cb).clamped(0, 1), alpha)
    }

    /// The screen's colour in a picture: the most common strong colour, averaged. `pixels` are
    /// (r, g, b) 0…1. Nil when nothing is colourful enough to be a screen.
    public static func screenColor(in pixels: [(Double, Double, Double)]) -> RGBA? {
        // Hues in 12 bins; only strong, not too dark colours count.
        var bins = [(count: Int, r: Double, g: Double, b: Double)](repeating: (0, 0, 0, 0), count: 12)
        for (r, g, b) in pixels {
            let high = max(r, g, b), low = min(r, g, b)
            guard high > 0.15, high - low > 0.18 else { continue }
            let hue = RGBA.hue(r, g, b)
            let index = min(Int(hue * 12), 11)
            bins[index].count += 1
            bins[index].r += r
            bins[index].g += g
            bins[index].b += b
        }
        guard let best = bins.max(by: { $0.count < $1.count }), best.count >= max(pixels.count / 20, 1) else { return nil }
        let n = Double(best.count)
        return RGBA(best.r / n, best.g / n, best.b / n)
    }
}

/// A shape that keeps part of a clip's picture (or hides it, inverted). It is placed on the
/// picture itself, so it moves with it.
public struct ClipMask: Codable, Equatable, Hashable, Sendable {
    public enum Shape: String, Codable, CaseIterable, Identifiable, Sendable {
        /// Keeps one side of a line (above it, before turning).
        case line
        /// Keeps a band between two parallel lines.
        case band
        case circle
        case rectangle
        case heart
        case star

        public var id: String { rawValue }

        public var displayName: String {
            switch self {
            case .line: "Line"
            case .band: "Band"
            case .circle: "Circle"
            case .rectangle: "Rectangle"
            case .heart: "Heart"
            case .star: "Star"
            }
        }

        public var systemImage: String {
            switch self {
            case .line: "line.diagonal"
            case .band: "rectangle.split.1x2"
            case .circle: "circle"
            case .rectangle: "rectangle"
            case .heart: "heart"
            case .star: "star"
            }
        }

        /// Whether it has a size of its own (a line only has a place and an angle).
        public var hasSize: Bool { self != .line }
        /// Whether it can be stretched wider or taller.
        public var stretches: Bool { self == .circle || self == .rectangle }
    }

    public var shape: Shape
    /// Its middle, as fractions of the picture (0, 0 top left).
    public var centerX: Double
    public var centerY: Double
    /// Its size, as a fraction of the picture's shorter side (a band's thickness).
    public var size: Double
    /// Width over height, 0.25…4 (circle and rectangle).
    public var stretch: Double
    /// Degrees, clockwise.
    public var rotation: Double
    /// How soft its edge is, 0…1.
    public var feather: Double
    /// How round a rectangle's corners are, 0…1.
    public var roundness: Double
    /// Hides the shape instead of keeping it.
    public var inverted: Bool

    public init(
        shape: Shape, centerX: Double = 0.5, centerY: Double = 0.5, size: Double? = nil, stretch: Double = 1,
        rotation: Double = 0, feather: Double = 0.1, roundness: Double = 0.2, inverted: Bool = false
    ) {
        self.shape = shape
        self.centerX = centerX
        self.centerY = centerY
        self.size = size ?? (shape == .band ? 0.4 : 0.7)
        self.stretch = stretch
        self.rotation = rotation
        self.feather = feather
        self.roundness = roundness
        self.inverted = inverted
    }

    public static let stretchRange: ClosedRange<Double> = 0.25...4
    public static let sizeRange: ClosedRange<Double> = 0.05...2

    /// Width and height of the shape, in pixels of a picture of `pictureSize`.
    public func shapeSize(in pictureSize: CGSize) -> CGSize {
        let side = min(pictureSize.width, pictureSize.height) * size
        guard shape.stretches else { return CGSize(width: side, height: side) }
        let s = stretch.clamped(Self.stretchRange.lowerBound, Self.stretchRange.upperBound)
        return CGSize(width: side * s.squareRoot(), height: side / s.squareRoot())
    }

    /// Width of the soft edge, in pixels of a picture of `pictureSize`.
    public func featherWidth(in pictureSize: CGSize) -> Double {
        feather.clamped(0, 1) * 0.25 * min(pictureSize.width, pictureSize.height)
    }

    /// How much of the picture shows at `point` (pixels of a picture of `pictureSize`, origin top
    /// left), 0…1. The renderer draws the same shapes with Core Image; this is the reference.
    public func visibility(at point: CGPoint, in pictureSize: CGSize) -> Double {
        // Into the shape's own frame: its middle at 0, 0, not turned.
        let dx = point.x - centerX * pictureSize.width, dy = point.y - centerY * pictureSize.height
        let angle = -rotation * .pi / 180
        let x = dx * cos(angle) - dy * sin(angle), y = dx * sin(angle) + dy * cos(angle)
        let soft = max(featherWidth(in: pictureSize), 0.5)
        // Signed distance to the edge: negative inside.
        let distance: Double
        let box = shapeSize(in: pictureSize)
        switch shape {
        case .line:
            distance = y
        case .band:
            distance = abs(y) - box.height / 2
        case .circle, .heart, .star:
            // Hearts and stars are drawn as their own shapes; here they count as a circle.
            let a = box.width / 2, b = box.height / 2
            let r = hypot(x / a, y / b)
            distance = (r - 1) * min(a, b)
        case .rectangle:
            let corner = roundness.clamped(0, 1) * min(box.width, box.height) / 2
            let qx = abs(x) - box.width / 2 + corner, qy = abs(y) - box.height / 2 + corner
            distance = hypot(max(qx, 0), max(qy, 0)) + min(max(qx, qy), 0) - corner
        }
        let t = (0.5 - distance / soft).clamped(0, 1)
        let inside = t * t * (3 - 2 * t)
        return inverted ? 1 - inside : inside
    }
}

/// How B-roll is mixed into the picture under it.
public enum BlendMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case normal, multiply, screen, overlay, softLight, hardLight, add, difference, darken, lighten, colorBurn, colorDodge

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .normal: "Normal"
        case .multiply: "Darken"
        case .screen: "Lighten"
        case .overlay: "Overlay"
        case .softLight: "Soft Light"
        case .hardLight: "Hard Light"
        case .add: "Add"
        case .difference: "Difference"
        case .darken: "Darker Only"
        case .lighten: "Lighter Only"
        case .colorBurn: "Burn"
        case .colorDodge: "Dodge"
        }
    }

    public var hint: String {
        switch self {
        case .normal: "Covers what is under it"
        case .multiply: "Darkens what is under it; white parts disappear"
        case .screen: "Lightens what is under it; black parts disappear (fire, light leaks, sparks)"
        case .overlay: "More contrast: darks darken, lights lighten"
        case .softLight: "A gentle wash of its colours and light"
        case .hardLight: "A strong wash of its colours and light"
        case .add: "Adds its light: bright and glowing"
        case .difference: "Colours turn inside out where it is bright"
        case .darken: "Keeps whichever is darker"
        case .lighten: "Keeps whichever is lighter"
        case .colorBurn: "Deep, saturated darks"
        case .colorDodge: "Bright, burnt-out lights"
        }
    }
}

/// Everything that takes part of a clip's picture away, or mixes it in.
public struct ClipCutout: Codable, Equatable, Hashable, Sendable {
    /// Remove Background: what is kept, or nil.
    public var removeBackground: CutoutSubject?
    /// A coloured screen keyed out.
    public var key: ColorKey?
    public var mask: ClipMask?
    /// How it is mixed into what is under it (B-roll only).
    public var blend: BlendMode

    public init(removeBackground: CutoutSubject? = nil, key: ColorKey? = nil, mask: ClipMask? = nil, blend: BlendMode = .normal) {
        self.removeBackground = removeBackground
        self.key = key
        self.mask = mask
        self.blend = blend
    }

    public var isEmpty: Bool { removeBackground == nil && key == nil && mask == nil && blend == .normal }
    /// Whether some of the picture may be see-through.
    public var isSeeThrough: Bool { removeBackground != nil || key != nil || mask != nil }

    private enum CodingKeys: String, CodingKey { case removeBackground, key, mask, blend }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        removeBackground = try c.decodeIfPresent(CutoutSubject.self, forKey: .removeBackground)
        key = try c.decodeIfPresent(ColorKey.self, forKey: .key)
        mask = try c.decodeIfPresent(ClipMask.self, forKey: .mask)
        blend = (try c.decodeIfPresent(BlendMode.self, forKey: .blend)) ?? .normal
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(removeBackground, forKey: .removeBackground)
        try c.encodeIfPresent(key, forKey: .key)
        try c.encodeIfPresent(mask, forKey: .mask)
        if blend != .normal { try c.encode(blend, forKey: .blend) }
    }
}

public extension RGBA {
    /// The hue of a colour, 0…1 (red 0, green ⅓, blue ⅔).
    static func hue(_ r: Double, _ g: Double, _ b: Double) -> Double {
        let high = max(r, g, b), low = min(r, g, b), range = high - low
        guard range > 0 else { return 0 }
        var hue: Double
        if high == r { hue = (g - b) / range } else if high == g { hue = 2 + (b - r) / range } else { hue = 4 + (r - g) / range }
        hue /= 6
        return hue < 0 ? hue + 1 : hue
    }
}

public extension Project {
    /// Changes the cut-out settings of clip `id` (main clip, B-roll or not).
    mutating func updateCutout(of id: Clip.ID, _ change: (inout ClipCutout) -> Void) {
        updateAnyClip(id) { change(&$0.cutout) }
    }

    /// Whether any clip removes its background (so the app makes the cut-out copies).
    var removesBackgrounds: Bool {
        (timeline.clips + overlays.map(\.clip)).contains { $0.cutout.removeBackground != nil }
    }
}
