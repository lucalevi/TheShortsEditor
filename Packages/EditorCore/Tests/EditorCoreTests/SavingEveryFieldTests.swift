import CoreGraphics
import CoreMedia
import Foundation
import Testing
@testable import EditorCore

/// Every field of every saved type comes back after saving, even when nothing is at its default.
///
/// The model's coders are written by hand (35 keys for a clip), so a new field can be left out of
/// `encode` or `init(from:)` and silently not saved. Each value below sets every stored field to
/// something other than its default; `expectEveryFieldSet` checks that with `Mirror`, so a field
/// added later fails here until it is set below, and the round trip then proves it is saved.
struct SavingEveryFieldTests {
    private static func t(_ frames: Int64) -> CMTime { CMTime(value: frames, timescale: 30) }

    /// Fails for each stored property of `value` that equals the same property of `blank`.
    private func expectEveryFieldSet<T>(_ value: T, differsFrom blank: T, _ name: String, sourceLocation: SourceLocation = #_sourceLocation) {
        let blankFields = Dictionary(uniqueKeysWithValues: Mirror(reflecting: blank).children.compactMap { child in
            child.label.map { ($0, String(describing: child.value)) }
        })
        for child in Mirror(reflecting: value).children {
            guard let label = child.label else { continue }
            if blankFields[label] == String(describing: child.value) {
                Issue.record("\(name).\(label) is at its default: set it here so saving it is tested", sourceLocation: sourceLocation)
            }
        }
    }

    private func roundTrip<T: Codable & Equatable>(_ value: T, sourceLocation: SourceLocation = #_sourceLocation) throws {
        let back = try JSONDecoder().decode(T.self, from: JSONEncoder().encode(value))
        #expect(back == value, sourceLocation: sourceLocation)
    }

    // MARK: The values

    static let placement = Placement(offsetX: 0.1, offsetY: -0.2, scale: 1.4, rotation: 12, opacity: 0.7)
    static let keyframe = Keyframe(time: t(9), placement: placement, easing: .linear)
    static let mask = ClipMask(shape: .heart, centerX: 0.4, centerY: 0.6, size: 0.33, stretch: 1.5, rotation: 20, feather: 0.2,
                               roundness: 0.3, inverted: true)
    static let key = ColorKey(color: ColorKey.blue, strength: 0.7, softness: 0.1, spill: 0.9)
    static let cutout = ClipCutout(removeBackground: .subject, key: key, mask: mask, blend: .screen)

    static var clip: Clip {
        var clip = Clip(
            assetID: UUID(), sourceStart: t(3), duration: t(90), framing: .fit, volume: 1.5, isMuted: true, placement: placement,
            keyframes: [keyframe], background: .color, speed: 0.5, cleansVoice: true, fadeIn: t(5), fadeOut: t(6),
            volumeKeys: [VolumeKey(time: t(10), level: 0.4)], voiceEffect: .echo, equalizer: .lessBass, soundDetached: true,
            transitionOut: ClipTransition(kind: .wipe, duration: t(20)), isFrozen: true, pictureFadeIn: t(7), pictureFadeOut: t(8),
            smoothSpeed: false, look: ClipLook(color: ColorAdjustments(exposure: 0.3, tint: -0.2), filter: FilterChoice(.noir, strength: 0.4)),
            steadiness: 0.6)
        clip.styledMotion = true
        clip.speedCurve = SpeedCurve(.bullet, from: 0.1, to: 0.9)
        clip.smoothSlowMotion = true
        clip.animationIn = ClipAnimation(.blur, duration: t(12))
        clip.animationOut = ClipAnimation(.slideLeft, duration: t(14))
        clip.effects = [ClipEffect(.vhs, strength: 0.9, part: .end, length: t(30))]
        clip.cutout = cutout
        clip.backgroundColor = RGBA(0.1, 0.2, 0.3, 0.9)
        return clip
    }

    static let asset = MediaAsset(
        url: URL(fileURLWithPath: "/media/a.mov"), name: "a", duration: t(300), displaySize: CGSize(width: 1920, height: 1080),
        hasAudio: false, hasVideo: false, isImage: true, frameRate: 25,
        reversedFrom: ReversedSource(assetID: UUID(), range: CMTimeRange(start: t(1), duration: t(2))))

    static let word: Word = {
        var word = Word(text: "ciao", start: t(4), duration: t(5), isKeyword: true, emoji: "👋", captionBreak: .joined,
                        lineBreakAfter: true, endsExactly: true)
        word.translation = CaptionTranslation(source: "ciao", text: "hello")
        return word
    }()

    static let look = TextLook(fontFamily: "Avenir", weight: 0.9, size: 120, textColor: .yellow, outlineColor: .black, outlineWidth: 8,
                               boxColor: .green, boxPerLine: true, shadow: true, uppercase: true, glowColor: .white,
                               popShadowColor: .black, letterSpacing: 0.1)

    static var title: TextOverlay {
        var title = TextOverlay(text: "Hi", style: .comic, look: look, entrance: .fade, start: t(10), duration: t(50),
                                verticalPosition: 0.8, horizontalPosition: 0.3)
        title.followsClip = false
        title.exit = ClipAnimation(.zoom)
        title.loop = .wiggle
        title.rotation = 15
        title.sticker = Sticker(.symbol("star.fill"), color: .yellow, size: 400)
        title.track = [TrackPoint(offset: t(1), x: 0.2, y: 0.3)]
        return title
    }

    static var music: BackgroundMusic {
        var music = BackgroundMusic(assetID: UUID(), sourceStart: t(30), volume: 0.8)
        music.start = t(15)
        music.loops = true
        music.beats = [Beat(time: t(2), isBarStart: true)]
        music.showsBeats = true
        music.lowersUnderSpeech = !music.lowersUnderSpeech
        music.fadesIn = !music.fadesIn
        music.fadesOut = !music.fadesOut
        music.mood = .dramatic
        return music
    }

    static let captions: CaptionSettings = {
        var captions = CaptionSettings()
        captions.isVisible = false
        captions.style = .karaoke
        captions.verticalPosition = 0.3
        captions.fontFamily = "Futura"
        captions.sizeScale = 1.3
        captions.textColor = .yellow
        captions.accentColor = .green
        captions.showsKeywords = false
        captions.showsEmoji = false
        captions.translationLanguage = "de"
        return captions
    }()

    static let shot = Shot(name: "Hook", direction: "Say it", length: t(60), title: "Watch this", isTalking: true, transition: .zoom,
                           entrance: .pop, fitsExactly: true)

    static var storyboard: Storyboard {
        var storyboard = Storyboard(kind: .review)
        storyboard.slots = [Storyboard.Slot(shot: shot, clipID: UUID(), titleID: UUID())]
        storyboard.template = .travel
        return storyboard
    }

    static var project: Project {
        var project = Project()
        project.assets = [asset]
        project.timeline.clips = [clip]
        project.transcripts = [asset.id: Transcript(language: .french, words: [word], isTyped: true)]
        project.captions = captions
        project.titles = [title]
        project.music = music
        project.overlays = [Overlay(clip: clip, start: t(5), layout: .bottomThird, followsClip: false)]
        project.sounds = [SoundClip(clip: clip, start: t(6), isVoiceOver: true, followsClip: false, detachedFrom: UUID(), lowersUnderSpeech: true)]
        project.look = FilterChoice(.dreamy, strength: 0.3)
        project.markers = [Marker(time: t(40), name: "Here", followsClip: false)]
        project.style = .cinematic
        project.storyboard = storyboard
        project.cover = ShortCover(time: t(20), text: "Cover", textPosition: 0.6, showsCaptions: true)
        return project
    }

    // MARK: Tests

    @Test func everyFieldIsSetInTheseValues() {
        let blankClip = Clip(assetID: Self.clip.assetID, sourceStart: .zero, duration: Self.t(1))
        expectEveryFieldSet(Self.clip, differsFrom: blankClip, "Clip")
        expectEveryFieldSet(Self.placement, differsFrom: .identity, "Placement")
        expectEveryFieldSet(Self.keyframe, differsFrom: Keyframe(time: .zero, placement: .identity), "Keyframe")
        expectEveryFieldSet(Self.mask, differsFrom: ClipMask(shape: .line), "ClipMask")
        expectEveryFieldSet(Self.key, differsFrom: ColorKey(), "ColorKey")
        expectEveryFieldSet(Self.cutout, differsFrom: ClipCutout(), "ClipCutout")
        expectEveryFieldSet(Self.asset, differsFrom: MediaAsset(url: URL(fileURLWithPath: "/"), name: "", duration: .zero, displaySize: .zero,
                                                                hasAudio: true, hasVideo: false), "MediaAsset")
        expectEveryFieldSet(Self.word, differsFrom: Word(text: "", start: .zero, duration: .zero), "Word")
        expectEveryFieldSet(Self.look, differsFrom: TextLook(), "TextLook")
        expectEveryFieldSet(Self.title, differsFrom: TextOverlay(text: "", start: .zero, duration: .zero), "TextOverlay")
        expectEveryFieldSet(Self.music, differsFrom: BackgroundMusic(assetID: UUID()), "BackgroundMusic")
        expectEveryFieldSet(Self.captions, differsFrom: CaptionSettings(), "CaptionSettings")
        expectEveryFieldSet(Self.shot, differsFrom: Shot(name: "", direction: "", length: .zero), "Shot")
        expectEveryFieldSet(Self.storyboard, differsFrom: Storyboard(kind: .tutorial), "Storyboard")
        expectEveryFieldSet(Self.project, differsFrom: Project(), "Project")
    }

    @Test func everyFieldComesBackAfterSaving() throws {
        try roundTrip(Self.clip)
        try roundTrip(Self.asset)
        try roundTrip(Self.word)
        try roundTrip(Self.title)
        try roundTrip(Self.music)
        try roundTrip(Self.captions)
        try roundTrip(Self.storyboard)
        try roundTrip(Self.project)
        // And through the file format itself.
        let file = ProjectFile(project: Self.project, bookmarks: [Self.asset.id: Data([9])], name: "All", created: Date(timeIntervalSince1970: 1_000))
        #expect(try ProjectFile.decode(file.encoded()) == file)
    }
}
