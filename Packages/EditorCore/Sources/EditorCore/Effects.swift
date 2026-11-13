import CoreMedia
import Foundation

// Effects (Stage J): a short, curated set made by the app, attached to a clip so they follow it
// (iMovie's way, not a separate effects track). Each plays over the whole clip, or only over its
// first or last moments, at a strength. They are drawn by `EffectRenderer` with Core Image.

/// What an effect does to the picture.
public enum EffectKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case shake, flash, zoomPulse, glitch, rgbSplit, vhs, filmGrain, lightLeak, blur, vignettePulse, mirror, colorPop

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .shake: "Shake"
        case .flash: "Flash"
        case .zoomPulse: "Zoom Pulse"
        case .glitch: "Glitch"
        case .rgbSplit: "Colour Split"
        case .vhs: "Old Tape"
        case .filmGrain: "Film Grain"
        case .lightLeak: "Light Leak"
        case .blur: "Blur"
        case .vignettePulse: "Dark Edges"
        case .mirror: "Mirror"
        case .colorPop: "Colour Pop"
        }
    }

    public var hint: String {
        switch self {
        case .shake: "The picture shakes, like an impact or a bass drop"
        case .flash: "A white flash: on a cut, a reveal, a beat"
        case .zoomPulse: "Quick zooms in time, like a heartbeat or a beat"
        case .glitch: "Digital breaks and jumps"
        case .rgbSplit: "Red and blue drift apart around the edges"
        case .vhs: "A worn video tape: soft colours, lines, wobble"
        case .filmGrain: "The grain and warmth of film"
        case .lightLeak: "Warm light drifting across the picture"
        case .blur: "Out of focus; at the start it sharpens, at the end it blurs away"
        case .vignettePulse: "Dark edges that breathe, for tension"
        case .mirror: "The left half mirrored onto the right"
        case .colorPop: "Black and white, except the strongest colours"
        }
    }

    public var systemImage: String {
        switch self {
        case .shake: "waveform.path"
        case .flash: "sun.max.fill"
        case .zoomPulse: "plus.magnifyingglass"
        case .glitch: "square.split.diagonal.2x2"
        case .rgbSplit: "circle.lefthalf.striped.horizontal"
        case .vhs: "film"
        case .filmGrain: "circle.dotted"
        case .lightLeak: "light.max"
        case .blur: "drop"
        case .vignettePulse: "circle.dashed"
        case .mirror: "rectangle.split.2x1"
        case .colorPop: "paintpalette"
        }
    }

    /// Where it plays when first added: flashes and blurs at the start, the rest all through.
    public var defaultPart: EffectPart {
        switch self {
        case .flash, .blur: .start
        default: .wholeClip
        }
    }

    public var defaultLength: CMTime {
        switch self {
        case .flash: CMTime(value: 2, timescale: 5)
        default: CMTime(value: 4, timescale: 5)
        }
    }
}

/// Which part of its clip an effect plays over.
public enum EffectPart: String, Codable, CaseIterable, Identifiable, Sendable {
    case wholeClip, start, end

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .wholeClip: "Whole clip"
        case .start: "At the start"
        case .end: "At the end"
        }
    }
}

/// An effect on a clip.
public struct ClipEffect: Codable, Equatable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var kind: EffectKind
    /// 0…1.
    public var strength: Double
    public var part: EffectPart
    /// How long it plays at the start or end (ignored for the whole clip).
    public var length: CMTime

    public init(id: UUID = UUID(), _ kind: EffectKind, strength: Double = ClipEffect.defaultStrength, part: EffectPart? = nil, length: CMTime? = nil) {
        self.id = id
        self.kind = kind
        self.strength = strength
        self.part = part ?? kind.defaultPart
        self.length = length ?? kind.defaultLength
    }

    public static let defaultStrength = 0.6
    public static let lengthRange: ClosedRange<Double> = 0.2...3

    private enum CodingKeys: String, CodingKey { case id, kind, strength, part, length }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        kind = try c.decode(EffectKind.self, forKey: .kind)
        strength = try c.decode(Double.self, forKey: .strength)
        part = try c.decode(EffectPart.self, forKey: .part)
        length = try c.decodeTime(forKey: .length)
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(kind, forKey: .kind)
        try c.encode(strength, forKey: .strength)
        try c.encode(part, forKey: .part)
        try c.encode(time: length, forKey: .length)
    }
}

/// An effect at one moment: how far into it (seconds) and through it (0…1).
public struct EffectMoment: Equatable, Sendable {
    public var effect: ClipEffect
    public var seconds: Double
    public var progress: Double
    /// The frame number on the timeline, for effects that change at random from frame to frame.
    public var frame: Int

    public init(effect: ClipEffect, seconds: Double, progress: Double, frame: Int) {
        self.effect = effect
        self.seconds = seconds
        self.progress = progress
        self.frame = frame
    }
}

public extension Clip {
    /// The effects playing `offset` into the clip (which starts at `clipStart` on the timeline).
    func activeEffects(atOffset offset: CMTime, clipStart: CMTime = .zero) -> [EffectMoment] {
        guard !effects.isEmpty, offset >= .zero, offset < duration else { return [] }
        let t = offset.seconds + 0.5 / Double(Project.frameRate)
        let frame = (clipStart + offset).convertScale(Project.frameRate, method: .roundTowardNegativeInfinity).value
        return effects.compactMap { effect in
            let length = min(effect.length.seconds, duration.seconds)
            switch effect.part {
            case .wholeClip:
                return EffectMoment(effect: effect, seconds: t, progress: min(t / max(duration.seconds, 0.001), 1), frame: Int(frame))
            case .start:
                guard t < length else { return nil }
                return EffectMoment(effect: effect, seconds: t, progress: t / length, frame: Int(frame))
            case .end:
                let from = duration.seconds - length
                guard t >= from else { return nil }
                return EffectMoment(effect: effect, seconds: t - from, progress: min((t - from) / length, 1), frame: Int(frame))
            }
        }
    }
}

public extension Project {
    /// Adds an effect to clips (main or B-roll), at its usual place and strength. One of each
    /// kind per clip: adding a kind it already has does nothing.
    mutating func addEffect(_ kind: EffectKind, to ids: [Clip.ID]) {
        for id in ids where anyClip(id: id) != nil && sound(id: id) == nil {
            updateAnyClip(id) { clip in
                guard !clip.effects.contains(where: { $0.kind == kind }) else { return }
                clip.effects.append(ClipEffect(kind))
            }
        }
    }

    mutating func updateEffect(_ effectID: ClipEffect.ID, on clipID: Clip.ID, _ change: (inout ClipEffect) -> Void) {
        updateAnyClip(clipID) { clip in
            guard let index = clip.effects.firstIndex(where: { $0.id == effectID }) else { return }
            change(&clip.effects[index])
            clip.effects[index].strength = min(max(clip.effects[index].strength, 0), 1)
            let seconds = min(max(clip.effects[index].length.seconds, ClipEffect.lengthRange.lowerBound), ClipEffect.lengthRange.upperBound)
            clip.effects[index].length = CMTime(seconds: seconds, preferredTimescale: 600).snappedToFrame()
        }
    }

    mutating func removeEffect(_ effectID: ClipEffect.ID, from clipID: Clip.ID) {
        updateAnyClip(clipID) { $0.effects.removeAll { $0.id == effectID } }
    }
}
