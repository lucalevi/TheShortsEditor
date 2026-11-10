import Foundation

// How a clip looks: colour adjustments, a filter, and the maths behind Enhance, Match Color and
// picking white or skin in the viewer. Everything works on colours as stored in the video
// (0…1 per channel, not linear light), which is what the compositor draws with.

/// A colour, 0…1 per channel.
public struct RGB: Equatable, Hashable, Sendable, Codable {
    public var r: Double
    public var g: Double
    public var b: Double

    public init(_ r: Double, _ g: Double, _ b: Double) {
        self.r = r
        self.g = g
        self.b = b
    }

    public init(gray: Double) { self.init(gray, gray, gray) }

    /// Brightness as the eye sees it (Rec. 709 weights).
    public var luma: Double { 0.2126 * r + 0.7152 * g + 0.0722 * b }

    /// How colourful it is: 0 for grey, up to 1.
    public var saturation: Double {
        let high = max(r, g, b), low = min(r, g, b)
        return high <= 0.0001 ? 0 : (high - low) / high
    }

    public var clamped: RGB { RGB(r.clamped(0, 1), g.clamped(0, 1), b.clamped(0, 1)) }

    func map(_ f: (Double) -> Double) -> RGB { RGB(f(r), f(g), f(b)) }
    static func * (c: RGB, k: Double) -> RGB { RGB(c.r * k, c.g * k, c.b * k) }
    static func * (c: RGB, k: RGB) -> RGB { RGB(c.r * k.r, c.g * k.g, c.b * k.b) }
    static func + (a: RGB, b: RGB) -> RGB { RGB(a.r + b.r, a.g + b.g, a.b + b.b) }
    static func - (a: RGB, b: RGB) -> RGB { RGB(a.r - b.r, a.g - b.g, a.b - b.b) }

    /// `self` moved `amount` of the way to `other`.
    func mixed(with other: RGB, _ amount: Double) -> RGB { self + (other - self) * amount }

    /// More or less colourful around its own grey: 0 keeps it, −1 makes it grey, 1 doubles the colour.
    func saturated(_ amount: Double) -> RGB {
        guard amount != 0 else { return self }
        let y = luma
        return RGB(gray: y) + (self - RGB(gray: y)) * (1 + amount)
    }
}

extension Double {
    func clamped(_ low: Double, _ high: Double) -> Double { Swift.min(Swift.max(self, low), high) }
}

// MARK: - Colour adjustments

/// The colour sliders of a clip. Each one goes from −1 to 1, and 0 leaves the picture as it is.
public struct ColorAdjustments: Codable, Equatable, Hashable, Sendable {
    /// Brighter or darker overall.
    public var exposure: Double = 0
    /// More (positive) or less difference between light and dark.
    public var contrast: Double = 0
    /// Bright parts brighter (positive) or brought back (negative).
    public var highlights: Double = 0
    /// Dark parts lifted (positive) or deepened (negative).
    public var shadows: Double = 0
    /// More colourful (positive) or less, down to black and white at −1.
    public var saturation: Double = 0
    /// Warmer, more orange (positive) or cooler, more blue (negative). Picking white or skin sets it.
    public var warmth: Double = 0
    /// More magenta (positive) or more green (negative). Picking white or skin sets it.
    public var tint: Double = 0

    public static let range: ClosedRange<Double> = -1...1

    public init(exposure: Double = 0, contrast: Double = 0, highlights: Double = 0, shadows: Double = 0,
                saturation: Double = 0, warmth: Double = 0, tint: Double = 0) {
        self.exposure = exposure
        self.contrast = contrast
        self.highlights = highlights
        self.shadows = shadows
        self.saturation = saturation
        self.warmth = warmth
        self.tint = tint
    }

    public var isNeutral: Bool { self == ColorAdjustments() }

    /// Every value kept inside −1…1 and rounded to hundredths, so sliders and saved files agree.
    public var tidied: ColorAdjustments {
        func t(_ v: Double) -> Double { (v.clamped(-1, 1) * 100).rounded() / 100 }
        return ColorAdjustments(exposure: t(exposure), contrast: t(contrast), highlights: t(highlights), shadows: t(shadows),
                                saturation: t(saturation), warmth: t(warmth), tint: t(tint))
    }

    // How strong the sliders are at ±1.
    static let warmthStrength = 0.35
    static let tintStrength = 0.25
    static let exposureStops = 0.8

    /// What each channel is multiplied by for the warmth and tint, keeping the brightness of grey.
    public var channelGains: RGB {
        let raw = RGB(exp(Self.warmthStrength * warmth), exp(-Self.tintStrength * tint), exp(-Self.warmthStrength * warmth))
        return raw * (1 / raw.luma)
    }

    /// The colour `input` becomes.
    public func apply(_ input: RGB) -> RGB {
        if isNeutral { return input }
        var c = input * channelGains
        if exposure != 0 { c = c * pow(2, exposure * Self.exposureStops) }
        c = c.clamped.map(toneCurve)
        return c.saturated(saturation).clamped
    }

    /// Contrast, highlights and shadows as one curve on each channel (0 stays 0, 1 stays 1).
    func toneCurve(_ x: Double) -> Double {
        var y = x
        if contrast != 0 {
            // An S-curve through 0, ½ and 1; blending toward it (or away) never turns the curve back.
            let s = x - sin(2 * .pi * x) / (2 * .pi)
            y += 0.45 * contrast * (s - x)
        }
        // Bumps that peak at a third (shadows) and two thirds (highlights) of the way up. With
        // these strengths no mix of the three sliders makes the curve turn back.
        if shadows != 0 { y += 0.08 * shadows * 6.75 * x * (1 - x) * (1 - x) }
        if highlights != 0 { y += 0.08 * highlights * 6.75 * x * x * (1 - x) }
        return y.clamped(0, 1)
    }

    // MARK: Picking a colour in the viewer

    /// What a picked spot should become.
    public enum BalanceTarget: Sendable {
        /// Something white or grey: it becomes neutral.
        case white
        /// Someone's skin: it becomes a natural skin colour.
        case skin

        public var color: RGB {
            switch self {
            case .white: RGB(gray: 0.7)
            case .skin: RGB(0.85, 0.64, 0.52)
            }
        }
    }

    /// The same adjustments with the warmth and tint that turn `sample` (the spot as filmed) into
    /// the target's colour. Too dark or too bright a spot (nothing to read) changes nothing.
    public func balanced(_ sample: RGB, toward target: BalanceTarget) -> ColorAdjustments {
        guard min(sample.r, sample.g, sample.b) > 0.02, max(sample.r, sample.g, sample.b) < 0.995 else { return self }
        let wanted = target.color
        var result = self
        // Gains of e^(kw) on red and e^(−kw) on blue: their ratio has to change by wanted/sample.
        result.warmth = (log(wanted.r / wanted.b) - log(sample.r / sample.b)) / (2 * Self.warmthStrength)
        // Green against the middle of red and blue (which warmth leaves alone).
        let sampleGreen = log(sample.g / (sample.r * sample.b).squareRoot())
        let wantedGreen = log(wanted.g / (wanted.r * wanted.b).squareRoot())
        result.tint = (sampleGreen - wantedGreen) / Self.tintStrength
        return result.tidied
    }

    // MARK: Enhance and Match Color

    /// One click: a cast taken out, brightness and contrast set so the picture uses the whole
    /// range, and a little colour where it is dull. Gentle on pictures that are fine already.
    public static func auto(for stats: FrameStats) -> ColorAdjustments {
        var result = ColorAdjustments()
        // A colour cast: half of the way to grey on average (a sunset should stay a sunset).
        let mean = stats.mean
        if min(mean.r, mean.g, mean.b) > 0.03 {
            let neutral = ColorAdjustments().balanced(mean, toward: .white)
            result.warmth = neutral.warmth * 0.5
            result.tint = neutral.tint * 0.5
        }
        // Middle brightness toward 0.45.
        let median = stats.median
        if median > 0.01 {
            let stops = log2(0.45 / median) / exposureStops
            result.exposure = stops.clamped(-0.6, 0.6) * (abs(stops) < 0.08 ? 0 : 0.8)
        }
        // A flat picture gets more contrast; the brightest and darkest parts are brought in.
        let spread = stats.bright - stats.dark
        if spread < 0.75 { result.contrast = ((0.75 - spread) * 1.6).clamped(0, 0.5) }
        if stats.bright > 0.97 { result.highlights = -0.3 }
        if stats.dark < 0.03 { result.shadows = 0.25 }
        // Dull colours get a little more.
        if stats.saturation < 0.3 { result.saturation = ((0.3 - stats.saturation) * 1.2).clamped(0, 0.3) }
        return result.tidied
    }

    /// Adjustments that make `pixels` (a small copy of a picture) look like a picture with
    /// `reference`'s stats: the same colour on average, brightness, spread of light and dark, and
    /// colourfulness. The sliders affect each other, so the guess is measured and corrected a few times.
    public static func matching(_ pixels: [RGB], to reference: FrameStats) -> ColorAdjustments {
        var result = ColorAdjustments()
        guard var now = FrameStats(pixels: pixels) else { return result }
        for _ in 0..<6 {
            if min(now.mean.r, now.mean.g, now.mean.b) > 0.02, min(reference.mean.r, reference.mean.g, reference.mean.b) > 0.02 {
                let wanted = reference.mean
                result.warmth += (log(wanted.r / wanted.b) - log(now.mean.r / now.mean.b)) / (2 * warmthStrength)
                result.tint += (log(now.mean.g / (now.mean.r * now.mean.b).squareRoot())
                    - log(wanted.g / (wanted.r * wanted.b).squareRoot())) / tintStrength
            }
            if now.median > 0.01, reference.median > 0.01 {
                result.exposure += log2(reference.median / now.median) / exposureStops
            }
            let spread = max(now.bright - now.dark, 0.05), wantedSpread = max(reference.bright - reference.dark, 0.05)
            result.contrast += (wantedSpread / spread - 1) * 1.5
            if now.saturation > 0.01 { result.saturation += reference.saturation / now.saturation - 1 }
            result = result.tidied
            guard let measured = FrameStats(pixels: pixels.map(result.apply)) else { break }
            now = measured
        }
        return result
    }
}

/// What a picture is like, measured on a small copy of it: for Enhance and Match Color.
public struct FrameStats: Equatable, Sendable {
    /// The average colour.
    public var mean: RGB
    /// Brightness that 2% of the picture is darker than, half of it, and 98% of it.
    public var dark: Double
    public var median: Double
    public var bright: Double
    /// How colourful it is on average.
    public var saturation: Double

    public init(mean: RGB, dark: Double, median: Double, bright: Double, saturation: Double) {
        self.mean = mean
        self.dark = dark
        self.median = median
        self.bright = bright
        self.saturation = saturation
    }

    /// Measures `pixels` (any order). Nil when there are none.
    public init?(pixels: [RGB]) {
        guard !pixels.isEmpty else { return nil }
        var sum = RGB(gray: 0), saturation = 0.0
        var lumas: [Double] = []
        lumas.reserveCapacity(pixels.count)
        for p in pixels {
            sum = sum + p
            saturation += p.saturation
            lumas.append(p.luma)
        }
        lumas.sort()
        func percentile(_ p: Double) -> Double { lumas[min(lumas.count - 1, Int(Double(lumas.count - 1) * p))] }
        let n = Double(pixels.count)
        self.init(mean: sum * (1 / n), dark: percentile(0.02), median: percentile(0.5), bright: percentile(0.98), saturation: saturation / n)
    }
}

// MARK: - Filters

/// A ready-made look, chosen from a grid.
public enum LookFilter: String, Codable, CaseIterable, Identifiable, Sendable {
    case vivid, bright, warm, cool, tealOrange, film, fade, vintage, dreamy, moody, blackAndWhite, noir

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .vivid: "Vivid"
        case .bright: "Bright"
        case .warm: "Warm"
        case .cool: "Cool"
        case .tealOrange: "Teal & Orange"
        case .film: "Film"
        case .fade: "Faded"
        case .vintage: "Vintage"
        case .dreamy: "Dreamy"
        case .moody: "Moody"
        case .blackAndWhite: "Black & White"
        case .noir: "Noir"
        }
    }

    /// The colour `c` becomes with the whole filter.
    public func apply(_ c: RGB) -> RGB {
        switch self {
        case .vivid:
            // More colour where there is little, so skin doesn't go orange.
            let boost = 0.55 * (1 - c.saturation)
            return ColorAdjustments(contrast: 0.25).apply(c).saturated(boost).clamped
        case .bright:
            return ColorAdjustments(exposure: 0.2, highlights: -0.3, shadows: 0.45, saturation: 0.1).apply(c)
        case .warm:
            return ColorAdjustments(shadows: 0.1, saturation: 0.1, warmth: 0.45, tint: 0.05).apply(c)
        case .cool:
            return ColorAdjustments(contrast: 0.1, saturation: -0.05, warmth: -0.45, tint: -0.05).apply(c)
        case .tealOrange:
            let base = ColorAdjustments(contrast: 0.2, saturation: 0.15).apply(c)
            let y = base.luma
            return (base + RGB(-0.07, 0.02, 0.07) * (1 - y) + RGB(0.08, 0.01, -0.08) * y).clamped
        case .film:
            let base = ColorAdjustments(contrast: 0.2, saturation: -0.2, warmth: 0.12).apply(c)
            return base.map { 0.05 + 0.9 * $0 }
        case .fade:
            return c.saturated(-0.35).map { 0.12 + 0.84 * $0 }.clamped
        case .vintage:
            let y = c.luma
            let sepia = RGB(min(1, y * 1.07 + 0.04), y * 0.92 + 0.02, y * 0.72)
            return c.mixed(with: sepia, 0.55).map { 0.07 + 0.88 * $0 }.clamped
        case .dreamy:
            return ColorAdjustments(exposure: 0.12, contrast: -0.35, saturation: -0.1, warmth: 0.08, tint: 0.08).apply(c)
        case .moody:
            return ColorAdjustments(exposure: -0.15, contrast: 0.3, highlights: -0.2, saturation: -0.35, warmth: -0.15).apply(c)
        case .blackAndWhite:
            return ColorAdjustments(contrast: 0.15).apply(RGB(gray: c.luma))
        case .noir:
            return ColorAdjustments(contrast: 0.7, shadows: -0.4).apply(RGB(gray: c.luma))
        }
    }

    /// How much the corners darken with the whole filter (0: not at all).
    public var vignette: Double {
        switch self {
        case .vintage: 0.55
        case .moody, .noir: 0.45
        case .film: 0.25
        default: 0
        }
    }

    /// How much bright parts glow softly with the whole filter (0: not at all).
    public var glow: Double {
        self == .dreamy ? 0.6 : 0
    }
}

/// A filter and how strongly it is used (0…1).
public struct FilterChoice: Codable, Equatable, Hashable, Sendable {
    public var filter: LookFilter
    public var strength: Double

    public init(_ filter: LookFilter, strength: Double = 1) {
        self.filter = filter
        self.strength = strength.clamped(0, 1)
    }

    public func apply(_ c: RGB) -> RGB {
        strength >= 1 ? filter.apply(c) : c.mixed(with: filter.apply(c), strength)
    }

    public var vignette: Double { filter.vignette * strength }
    public var glow: Double { filter.glow * strength }
}

/// Everything about a clip's colour: the sliders first, then the filter on top.
public struct ClipLook: Codable, Equatable, Hashable, Sendable {
    public var color: ColorAdjustments
    public var filter: FilterChoice?

    public init(color: ColorAdjustments = ColorAdjustments(), filter: FilterChoice? = nil) {
        self.color = color
        self.filter = filter
    }

    public var isNeutral: Bool { color.isNeutral && (filter == nil || filter!.strength == 0) }

    public func apply(_ c: RGB) -> RGB {
        let adjusted = color.apply(c)
        return filter?.apply(adjusted) ?? adjusted
    }

    public var vignette: Double { filter?.vignette ?? 0 }
    public var glow: Double { filter?.glow ?? 0 }
}

// MARK: - On the project

public extension Project {
    /// Every clip on the timeline (main and over the others) whose picture can be coloured.
    var colorableClipIDs: [Clip.ID] {
        (timeline.clips + overlays.map(\.clip)).filter { asset(id: $0.assetID)?.hasVideo == true }.map(\.id)
    }

    /// Changes the look of clip `id`.
    mutating func updateLook(of id: Clip.ID, _ change: (inout ClipLook) -> Void) {
        updateAnyClip(id) { change(&$0.look) }
    }

    /// Gives every main clip and every clip over them the same filter (nil removes them all).
    mutating func setFilterOnEveryClip(_ choice: FilterChoice?) {
        for id in colorableClipIDs { updateLook(of: id) { $0.filter = choice } }
    }
}
