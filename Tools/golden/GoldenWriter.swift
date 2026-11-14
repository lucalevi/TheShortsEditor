// Writes a project file as the EditorCore of an old commit saves it. Copied into that commit's
// EditorCoreTests by Tools/golden/make-golden.sh, compiled with -DGOLDEN_V1 … -DGOLDEN_Vn (every
// version up to the commit's), and run with GOLDEN_OUT set. Each block only uses what existed when
// its format version was current, so the block for version n compiles at every later commit too.
import CoreGraphics
import CoreMedia
import Foundation
import Testing

@testable import EditorCore

@Test func writeGoldenProject() throws {
    guard let out = ProcessInfo.processInfo.environment["GOLDEN_OUT"] else { return }
    func seconds(_ s: Int64) -> CMTime { CMTime(value: s, timescale: 1) }
    func frames(_ f: Int64) -> CMTime { CMTime(value: f, timescale: 30) }
    func asset(_ name: String, _ length: Int64, video: Bool = true) -> MediaAsset {
        MediaAsset(
            url: URL(fileURLWithPath: "/golden/\(name)"), name: name, duration: seconds(length),
            displaySize: video ? CGSize(width: 1080, height: 1920) : .zero, hasAudio: true, hasVideo: video)
    }

    // Version 1: clips, framing, volume, captions, a title, music.
    var p = Project()
    let talk = p.addAsset(asset("talk.mov", 10))
    let song = p.addAsset(asset("song.m4a", 60, video: false))
    p.addAsset(asset("unused.mov", 5))
    p.appendClip(of: talk)
    p.timeline.split(at: seconds(4))
    p.timeline.clips[1].volume = 1.4
    p.timeline.clips[0].framing = .fit
    p.transcripts[talk] = Transcript(
        language: .italian,
        words: [
            Word(text: "Ciao", start: .zero, duration: frames(15)),
            Word(text: "a", start: frames(15), duration: frames(6)),
            Word(text: "tutti", start: frames(21), duration: frames(12)),
        ])
    p.captions.style = .highlight
    p.addTitle(at: .zero, text: "Hook\nline two")
    p.setMusic(song)
    p.setMusicStart(seconds(5))

    #if GOLDEN_V2
    // Version 2: B-roll, pictures, placement and motion.
    let photo = p.addAsset(
        MediaAsset(
            url: URL(fileURLWithPath: "/golden/photo.jpg"), name: "photo.jpg", duration: .zero,
            displaySize: CGSize(width: 3000, height: 4000), hasAudio: false, isImage: true))
    let broll = p.addAsset(asset("broll.mov", 8))
    _ = p.addOverlay(of: broll, at: seconds(1))
    p.appendClip(of: photo)
    p.timeline.clips[0].placement = Placement(offsetX: 0.1, offsetY: -0.05, scale: 1.3, rotation: 5)
    p.timeline.clips[0].keyframes = [
        Keyframe(time: .zero, placement: .identity),
        Keyframe(time: seconds(2), placement: Placement(scale: 1.5)),
    ]
    p.timeline.clips[1].background = .blur
    #endif

    #if GOLDEN_V3
    // Version 3: speed, title looks, key words and emoji, sounds and voice-overs, layouts.
    p.setSpeed(2, for: p.timeline.clips[1].id)
    p.titles[0].applyStyle(.marker)
    p.transcripts[talk]?.words[2].emoji = "🎉"
    let voice = p.addAsset(asset("voice.m4a", 3, video: false))
    _ = p.addSound(of: voice, at: seconds(2), isVoiceOver: true)
    p.overlays[0].layout = .top
    p.timeline.clips[0].cleansVoice = true
    #endif

    #if GOLDEN_V4
    // Version 4: transitions, freeze frames, fades, volume lines, voice effects.
    p.timeline.clips[0].transitionOut = ClipTransition(kind: .slideUp, duration: frames(12))
    p.timeline.clips[1].pictureFadeIn = frames(10)
    p.timeline.clips[1].fadeOut = frames(20)
    p.timeline.clips[0].volumeKeys = [VolumeKey(time: seconds(1), level: 0.5)]
    p.timeline.clips[1].voiceEffect = .robot
    _ = p.addFreezeFrame(at: seconds(1))
    #endif

    #if GOLDEN_V5
    // Version 5: colour, filters (per clip and for the whole Short), Stabilize.
    p.timeline.clips[0].look = ClipLook(
        color: ColorAdjustments(exposure: 0.2, contrast: 0.1, warmth: -0.3),
        filter: FilterChoice(.film, strength: 0.7))
    p.look = FilterChoice(.vivid, strength: 0.5)
    p.timeline.clips[1].steadiness = 0.8
    #endif

    #if GOLDEN_V6
    // Version 6: markers.
    p.markers = [Marker(time: seconds(3), name: "Punchline")]
    #endif

    #if GOLDEN_V7
    // Version 7: styles, app-made music, storyboards.
    p.style = .bold
    p.music?.mood = .upbeat
    p.storyboard = Storyboard(kind: .tutorial)
    p.timeline.clips[0].styledMotion = true
    #endif

    #if GOLDEN_V8
    // Version 8: speed curves, clip animations, smooth slow motion, beats, music placed later or looped.
    p.timeline.clips[1].speedCurve = SpeedCurve(.hero)
    p.timeline.clips[0].animationIn = ClipAnimation(.spin)
    p.timeline.clips[1].smoothSlowMotion = true
    p.music?.beats = [Beat(time: .zero, isBarStart: true), Beat(time: frames(15))]
    p.music?.start = seconds(1)
    p.music?.loops = true
    #endif

    #if GOLDEN_NAMED
    // Files from the home window on carry the Short's name and when it was made.
    let file = ProjectFile(project: p, bookmarks: [talk: Data([1, 2, 3])], name: "Golden", created: Date(timeIntervalSince1970: 1_800_000_000))
    #else
    let file = ProjectFile(project: p, bookmarks: [talk: Data([1, 2, 3])])
    #endif
    try file.encoded().write(to: URL(fileURLWithPath: out))
}
