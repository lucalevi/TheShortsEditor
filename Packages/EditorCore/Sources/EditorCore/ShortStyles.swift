import CoreMedia
import Foundation

// Stage F (one-click Shorts): styles, like iMovie's themes. A style is a bundle of title look,
// caption look, transition, motion, filter and music mood for the whole Short, switchable any time.

// MARK: - Music moods

/// The kinds of background music the app makes itself (see `RenderEngine/MusicLibrary.swift`):
/// no recordings to license, so they are safe to upload anywhere.
public enum MusicMood: String, Codable, CaseIterable, Identifiable, Sendable {
    case upbeat, chill, dramatic, playful, calm, focus

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .upbeat: "Upbeat"
        case .chill: "Chill"
        case .dramatic: "Dramatic"
        case .playful: "Playful"
        case .calm: "Calm"
        case .focus: "Focus"
        }
    }

    public var hint: String {
        switch self {
        case .upbeat: "Bright and driving, for energy"
        case .chill: "Laid-back beat, for vlogs"
        case .dramatic: "Big and moody, for reveals"
        case .playful: "Bouncy, for fun and food"
        case .calm: "Soft, no drums"
        case .focus: "Light and steady, under talking"
        }
    }

    /// Beats a minute.
    public var tempo: Double {
        switch self {
        case .upbeat: 118
        case .chill: 84
        case .dramatic: 90
        case .playful: 128
        case .calm: 70
        case .focus: 100
        }
    }

    /// One bar (four beats), the unit the music is built in.
    public var barLength: CMTime { CMTime(seconds: 240 / tempo, preferredTimescale: 48_000) }

    /// How loud it plays under the Short. Busy music sits lower so the voice stays clear.
    public var volume: Double {
        switch self {
        case .upbeat, .playful: 0.4
        case .dramatic: 0.45
        case .chill, .focus: 0.45
        case .calm: 0.55
        }
    }
}

public extension BackgroundMusic {
    /// Music the app made for a style. It fits itself to the Short's end (`Project.fitMoodMusic()`).
    var isMoodMusic: Bool { mood != nil }
}

public extension Project {
    /// Starts the app-made music so its last moment lands on the end of a bar: the Short then ends
    /// on the beat and loops back cleanly instead of fading out. Done after every edit.
    mutating func fitMoodMusic() {
        guard var music, let mood = music.mood, duration > .zero else { return }
        let bar = mood.barLength.seconds
        let length = (duration - music.start).seconds
        guard length > 0 else { return }
        let remainder = length.truncatingRemainder(dividingBy: bar)
        let start = remainder < 0.001 ? 0 : bar - remainder
        music.sourceStart = CMTime(seconds: start, preferredTimescale: 48_000)
        music.fadesIn = false
        music.fadesOut = false
        if music != self.music { self.music = music }
    }
}

// MARK: - Styles

/// How a style moves the pictures.
public enum StyleMotion: String, Codable, Sendable {
    case none
    /// Zoom in on every other cut of the same recording, to hide jump cuts.
    case punchIns
    /// Every clip slowly zooms in.
    case slowZoom
    /// Clips slowly zoom in and out, one after the other.
    case drift
}

/// A ready-made look for the whole Short, like a theme in iMovie.
public enum ShortStyle: String, Codable, CaseIterable, Identifiable, Sendable {
    case clean, bold, pop, cinematic, explainer, vlog

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .clean: "Clean"
        case .bold: "Bold"
        case .pop: "Pop"
        case .cinematic: "Cinematic"
        case .explainer: "Explainer"
        case .vlog: "Vlog"
        }
    }

    public var hint: String {
        switch self {
        case .clean: "Simple text, plain cuts, calm music"
        case .bold: "Big captions, punch-ins, upbeat music"
        case .pop: "Colourful boxes, zooms, playful music"
        case .cinematic: "Film colour, slow zooms, dissolves"
        case .explainer: "Clear labels and subtitles, steady music"
        case .vlog: "One word at a time, swipes, chill beat"
        }
    }

    public var systemImage: String {
        switch self {
        case .clean: "circle"
        case .bold: "bolt.fill"
        case .pop: "sparkles"
        case .cinematic: "film"
        case .explainer: "list.bullet.rectangle"
        case .vlog: "camera.fill"
        }
    }

    /// The ready-made title style it is closest to.
    public var titleStyle: TitleStyle {
        switch self {
        case .clean: .simple
        case .bold: .bold
        case .pop: .marker
        case .cinematic: .simple
        case .explainer: .label
        case .vlog: .dark
        }
    }

    public var titleLook: TextLook {
        var look = titleStyle.look
        switch self {
        case .clean: break
        case .bold: look.uppercase = true
        case .pop:
            look.boxColor = RGBA(1, 0.4, 0.75)
            look.textColor = .white
            look.uppercase = true
        case .cinematic:
            look.weight = 0.2
            look.size = 72
            look.uppercase = true
        case .explainer: break
        case .vlog: look.boxColor = RGBA(0, 0, 0, 0.6)
        }
        return look
    }

    public var titleEntrance: TitleEntrance {
        switch self {
        case .clean: .fade
        case .bold: .pop
        case .pop: .zoom
        case .cinematic: .fade
        case .explainer: .slideUp
        case .vlog: .typewriter
        }
    }

    public var captionStyle: CaptionStyle {
        switch self {
        case .clean: .minimal
        case .bold: .bold
        case .pop: .highlight
        case .cinematic: .minimal
        case .explainer: .classic
        case .vlog: .oneWord
        }
    }

    /// The colour of the word being spoken and of key words (nil: the caption style's own).
    public var captionAccent: RGBA? {
        switch self {
        case .pop: RGBA(1, 0.4, 0.75)
        case .explainer: RGBA(0.2, 0.55, 1)
        case .vlog: .yellow
        default: nil
        }
    }

    /// The transition put on cuts between recordings (nil: plain cuts).
    public var transition: ClipTransition? {
        switch self {
        case .clean, .bold: nil
        case .pop: ClipTransition(kind: .zoom, duration: CMTime(value: 10, timescale: Project.frameRate))
        case .cinematic: ClipTransition(kind: .dissolve, duration: CMTime(value: 20, timescale: Project.frameRate))
        case .explainer: ClipTransition(kind: .slide, duration: CMTime(value: 12, timescale: Project.frameRate))
        case .vlog: ClipTransition(kind: .slideUp, duration: CMTime(value: 10, timescale: Project.frameRate))
        }
    }

    public var motion: StyleMotion {
        switch self {
        case .clean, .explainer: .none
        case .bold, .pop: .punchIns
        case .cinematic: .slowZoom
        case .vlog: .drift
        }
    }

    /// A filter over the whole Short.
    public var filter: FilterChoice? {
        switch self {
        case .cinematic: FilterChoice(.film, strength: 0.8)
        case .pop: FilterChoice(.vivid, strength: 0.6)
        case .vlog: FilterChoice(.warm, strength: 0.5)
        default: nil
        }
    }

    public var music: MusicMood {
        switch self {
        case .clean: .calm
        case .bold: .upbeat
        case .pop: .playful
        case .cinematic: .dramatic
        case .explainer: .focus
        case .vlog: .chill
        }
    }

    /// Whether key words are coloured in the captions.
    public var highlightsKeywords: Bool { self == .bold || self == .pop || self == .explainer }
    /// Whether emoji are shown with the captions.
    public var showsEmoji: Bool { self == .pop || self == .vlog }
}

extension TextOverlay {
    /// Gives the title a style's look and entrance, keeping its font (a brand font is usually
    /// wanted whatever the style).
    mutating func takeLook(of style: ShortStyle) {
        let font = look.fontFamily
        self.style = style.titleStyle
        look = style.titleLook
        look.fontFamily = font
        entrance = style.titleEntrance
    }
}

public extension Project {
    /// Gives the whole Short a style, or takes it away (nil). Every title and the captions take
    /// its look; every cut to another recording gets its transition (other cuts become plain); clips without motion of their own get its motion;
    /// the whole Short gets its filter unless another filter was chosen; and `music` (the style's
    /// music file, made by the app) replaces any app-made music. The user's own song stays.
    mutating func applyStyle(_ newStyle: ShortStyle?, music musicAsset: MediaAsset? = nil) {
        let old = style
        style = newStyle

        if let newStyle {
            for index in titles.indices where titles[index].sticker == nil { titles[index].takeLook(of: newStyle) }
            captions.style = newStyle.captionStyle
            captions.accentColor = newStyle.captionAccent
            captions.textColor = nil
            captions.showsKeywords = newStyle.highlightsKeywords
            captions.showsEmoji = newStyle.showsEmoji
            setStyleTransitions(newStyle.transition)
        } else if let old {
            // Take away only what the style put there.
            for index in timeline.clips.indices where timeline.clips[index].transitionOut?.kind == old.transition?.kind {
                timeline.clips[index].transitionOut = nil
            }
        }

        applyStyleMotion(newStyle?.motion ?? .none)

        if look == nil || look == old?.filter { look = newStyle?.filter }

        let oldMusic = self.music
        if let musicAsset, newStyle != nil, self.music == nil || self.music?.isMoodMusic == true {
            self.music = nil
            addStyleMusic(musicAsset)
        } else if newStyle == nil, self.music?.isMoodMusic == true {
            self.music = nil
        }
        // App-made music no longer used leaves Media too, so switching styles doesn't pile it up.
        if let oldMusic, oldMusic.isMoodMusic, self.music?.assetID != oldMusic.assetID, usageCount(of: oldMusic.assetID) == 0 {
            assets.removeAll { $0.id == oldMusic.assetID }
        }
        fitMoodMusic()
    }

    /// Uses `asset` (the style's music file) as the music, when the Short has a style and no music yet.
    mutating func addStyleMusic(_ asset: MediaAsset) {
        guard let style, music == nil else { return }
        let id = addAsset(asset)
        music = BackgroundMusic(assetID: id, volume: style.music.volume, mood: style.music)
        fitMoodMusic()
    }

    /// Clips whose style-given placement or motion was changed by hand in this edit become the
    /// user's own, so a later style leaves them alone. Called after every edit but a style's.
    mutating func claimHandMadeMotion(from old: Project) {
        let before = Dictionary(old.timeline.clips.map { ($0.id, $0) }) { a, _ in a }
        for index in timeline.clips.indices where timeline.clips[index].styledMotion {
            guard let was = before[timeline.clips[index].id], was.styledMotion else { continue }
            if was.placement != timeline.clips[index].placement || was.keyframes != timeline.clips[index].keyframes {
                timeline.clips[index].styledMotion = false
            }
        }
    }

    /// Puts `transition` on every cut to another recording (a change of place or subject) and
    /// leaves cuts inside one recording plain: there, punch-ins hide the jump instead.
    mutating func setStyleTransitions(_ transition: ClipTransition?) {
        for index in timeline.clips.indices {
            let isSceneChange = index + 1 < timeline.clips.count && timeline.clips[index + 1].assetID != timeline.clips[index].assetID
            timeline.clips[index].transitionOut = isSceneChange ? transition : nil
        }
    }

    /// Clears the motion an earlier style gave, then gives `motion` to every clip whose picture
    /// hasn't been moved or animated by hand.
    mutating func applyStyleMotion(_ motion: StyleMotion) {
        for index in timeline.clips.indices where timeline.clips[index].styledMotion {
            timeline.clips[index].placement = .identity
            timeline.clips[index].keyframes = []
            timeline.clips[index].styledMotion = false
        }
        func isFree(_ clip: Clip) -> Bool { !clip.hasMotion && clip.placement == .identity }
        switch motion {
        case .none:
            break
        case .punchIns:
            var previousAsset: MediaAsset.ID?
            var zoomed = false
            for index in timeline.clips.indices {
                let clip = timeline.clips[index]
                zoomed = previousAsset == clip.assetID ? !zoomed : false
                previousAsset = clip.assetID
                guard zoomed, isFree(clip) else { continue }
                timeline.clips[index].placement.scale = Placement.punchInScale
                timeline.clips[index].styledMotion = true
            }
        case .slowZoom, .drift:
            var zoomIn = true
            for index in timeline.clips.indices {
                let clip = timeline.clips[index]
                guard isFree(clip) else { continue }
                let preset: MotionPreset = motion == .slowZoom || zoomIn ? .slowZoomIn : .slowZoomOut
                zoomIn.toggle()
                // A freeze frame shows one picture: its motion is drawn over its length on screen.
                guard !clip.isFrozen else { continue }
                timeline.clips[index].applyMotion(preset, playheadSource: clip.sourceStart)
                timeline.clips[index].styledMotion = timeline.clips[index].hasMotion || timeline.clips[index].placement != .identity
            }
        }
    }
}
