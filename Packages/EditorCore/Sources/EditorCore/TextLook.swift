import Foundation

/// A colour with transparency, stored as plain numbers (0…1).
public struct RGBA: Codable, Equatable, Hashable, Sendable {
    public var red: Double
    public var green: Double
    public var blue: Double
    public var alpha: Double

    public init(_ red: Double, _ green: Double, _ blue: Double, _ alpha: Double = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    public static let white = RGBA(1, 1, 1)
    public static let black = RGBA(0, 0, 0)
    public static let yellow = RGBA(1, 0.86, 0.1)
    public static let green = RGBA(0.16, 0.78, 0.36)

    /// The colours offered with one click: the ones Shorts use most.
    public static let palette: [RGBA] = [
        .white, .black, .yellow, RGBA(1, 0.42, 0.1), RGBA(0.95, 0.18, 0.25), RGBA(1, 0.4, 0.75),
        RGBA(0.62, 0.36, 1), RGBA(0.2, 0.55, 1), RGBA(0.2, 0.85, 0.95), .green, RGBA(0.65, 1, 0.3),
    ]
}

/// Everything about how a piece of text looks. Each title style is a ready-made `TextLook`;
/// changing any part of it makes the title your own.
public struct TextLook: Codable, Equatable, Hashable, Sendable {
    /// A font family installed on the Mac (or imported into the app), or nil for the system font.
    public var fontFamily: String?
    /// How heavy the letters are: -1 thin … 1 black. With a font family, above 0.3 picks its bold face.
    public var weight: Double
    /// Letter size in pixels on the 1080 × 1920 canvas.
    public var size: Double
    public var textColor: RGBA
    /// An outline around the letters, or nil for none.
    public var outlineColor: RGBA?
    /// Outline thickness as a percentage of the letter size.
    public var outlineWidth: Double
    /// A box behind the text, or nil for none.
    public var boxColor: RGBA?
    /// One box per line (like a marker) instead of one around everything.
    public var boxPerLine: Bool
    public var shadow: Bool
    public var uppercase: Bool
    /// A soft coloured light around the letters (neon), or nil for none.
    public var glowColor: RGBA? = nil
    /// A solid copy of the letters behind them, moved down and right, or nil for none.
    public var popShadowColor: RGBA? = nil
    /// Extra room between letters, as a percentage of the letter size.
    public var letterSpacing: Double = 0

    public init(
        fontFamily: String? = nil, weight: Double = 0.6, size: Double = 90, textColor: RGBA = .white,
        outlineColor: RGBA? = nil, outlineWidth: Double = 20, boxColor: RGBA? = nil, boxPerLine: Bool = false,
        shadow: Bool = false, uppercase: Bool = false, glowColor: RGBA? = nil, popShadowColor: RGBA? = nil, letterSpacing: Double = 0
    ) {
        self.glowColor = glowColor
        self.popShadowColor = popShadowColor
        self.letterSpacing = letterSpacing
        self.fontFamily = fontFamily
        self.weight = weight
        self.size = size
        self.textColor = textColor
        self.outlineColor = outlineColor
        self.outlineWidth = outlineWidth
        self.boxColor = boxColor
        self.boxPerLine = boxPerLine
        self.shadow = shadow
        self.uppercase = uppercase
    }

    public static let sizeRange: ClosedRange<Double> = 40...220
    public var isBold: Bool { weight > 0.3 }

    private enum CodingKeys: String, CodingKey {
        case fontFamily, weight, size, textColor, outlineColor, outlineWidth, boxColor, boxPerLine, shadow, uppercase
        case glowColor, popShadowColor, letterSpacing
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        fontFamily = try c.decodeIfPresent(String.self, forKey: .fontFamily)
        weight = try c.decode(Double.self, forKey: .weight)
        size = try c.decode(Double.self, forKey: .size)
        textColor = try c.decode(RGBA.self, forKey: .textColor)
        outlineColor = try c.decodeIfPresent(RGBA.self, forKey: .outlineColor)
        outlineWidth = try c.decode(Double.self, forKey: .outlineWidth)
        boxColor = try c.decodeIfPresent(RGBA.self, forKey: .boxColor)
        boxPerLine = try c.decode(Bool.self, forKey: .boxPerLine)
        shadow = try c.decode(Bool.self, forKey: .shadow)
        uppercase = try c.decode(Bool.self, forKey: .uppercase)
        glowColor = try c.decodeIfPresent(RGBA.self, forKey: .glowColor)
        popShadowColor = try c.decodeIfPresent(RGBA.self, forKey: .popShadowColor)
        letterSpacing = try c.decodeIfPresent(Double.self, forKey: .letterSpacing) ?? 0
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(fontFamily, forKey: .fontFamily)
        try c.encode(weight, forKey: .weight)
        try c.encode(size, forKey: .size)
        try c.encode(textColor, forKey: .textColor)
        try c.encodeIfPresent(outlineColor, forKey: .outlineColor)
        try c.encode(outlineWidth, forKey: .outlineWidth)
        try c.encodeIfPresent(boxColor, forKey: .boxColor)
        try c.encode(boxPerLine, forKey: .boxPerLine)
        try c.encode(shadow, forKey: .shadow)
        try c.encode(uppercase, forKey: .uppercase)
        try c.encodeIfPresent(glowColor, forKey: .glowColor)
        try c.encodeIfPresent(popShadowColor, forKey: .popShadowColor)
        if letterSpacing != 0 { try c.encode(letterSpacing, forKey: .letterSpacing) }
    }
}

public extension TitleStyle {
    /// The look each style starts from.
    var look: TextLook {
        switch self {
        case .bold: TextLook(weight: 0.62, size: 96, outlineColor: .black, outlineWidth: 24)
        case .label: TextLook(weight: 0.56, size: 76, textColor: .black, boxColor: .white, boxPerLine: true)
        case .marker: TextLook(weight: 0.56, size: 76, textColor: .black, boxColor: .yellow, boxPerLine: true)
        case .dark: TextLook(weight: 0.4, size: 70, boxColor: RGBA(0, 0, 0, 0.75))
        case .simple: TextLook(weight: 0.5, size: 84, shadow: true)
        case .neon: TextLook(weight: 0.5, size: 92, textColor: RGBA(1, 0.92, 0.98), glowColor: RGBA(1, 0.2, 0.8))
        case .hollow: TextLook(weight: 0.8, size: 104, textColor: RGBA(1, 1, 1, 0), outlineColor: .white, outlineWidth: 6, uppercase: true)
        case .popShadow: TextLook(weight: 0.75, size: 100, popShadowColor: RGBA(0.95, 0.18, 0.25), letterSpacing: 2)
        case .comic: TextLook(weight: 0.8, size: 100, textColor: .yellow, outlineColor: .black, outlineWidth: 26, shadow: true, uppercase: true)
        case .pill: TextLook(weight: 0.62, size: 72, boxColor: RGBA(0.95, 0.18, 0.25))
        case .typewriter:
            TextLook(fontFamily: "American Typewriter", weight: 0.2, size: 66, textColor: .black, boxColor: RGBA(0.98, 0.96, 0.88), boxPerLine: true)
        case .cinema: TextLook(fontFamily: "Futura", weight: 0, size: 62, shadow: true, uppercase: true, letterSpacing: 30)
        case .handwritten: TextLook(fontFamily: "Marker Felt", weight: 0.62, size: 100, shadow: true)
        }
    }
}

/// A look the user saved to use again on other titles and Shorts (their "brand kit").
public struct SavedTextStyle: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var look: TextLook
    public var entrance: TitleEntrance
    public var exit: ClipAnimation? = nil
    public var loop: TitleLoop? = nil

    public init(id: UUID = UUID(), name: String, look: TextLook, entrance: TitleEntrance, exit: ClipAnimation? = nil, loop: TitleLoop? = nil) {
        self.exit = exit
        self.loop = loop
        self.id = id
        self.name = name
        self.look = look
        self.entrance = entrance
    }
}
