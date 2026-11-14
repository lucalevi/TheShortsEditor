import CoreMedia
import Foundation
import Testing
@testable import EditorCore

/// Shorts saved by every earlier version of the app still open, with everything they had.
///
/// `Golden/v<N>.shortsproject` were written by the app's own code at the last commit of each file
/// format version (`Tools/golden/make-golden.sh`, from `Tools/golden/GoldenWriter.swift`) and are
/// never remade. What each should contain is written out here from what the writer did, not read
/// back from the files, so a change that reads an old file differently fails.
struct GoldenFileTests {
    private static func seconds(_ s: Int64) -> CMTime { CMTime(value: s, timescale: 1) }
    private static func frames(_ f: Int64) -> CMTime { CMTime(value: f, timescale: 30) }

    private static func file(_ version: Int) throws -> ProjectFile {
        let url = try #require(Bundle.module.url(forResource: "v\(version)", withExtension: ProjectFile.fileExtension, subdirectory: "Golden"))
        return try ProjectFile.decode(Data(contentsOf: url))
    }

    @Test func thereIsAGoldenFileForTheCurrentVersion() throws {
        // A new format version needs its golden file: Tools/golden/make-golden.sh <version> <commit>.
        #expect(try Self.file(ProjectFile.currentVersion).version == ProjectFile.currentVersion)
    }

    @Test(arguments: 1...8)
    func opensWithEverythingItHad(version: Int) throws {
        let file = try Self.file(version)
        let p = file.project
        #expect(file.version == version)

        // Version 1: clips, framing, volume, captions, a title, music.
        #expect(Array(p.assets.prefix(3).map(\.name)) == ["talk.mov", "song.m4a", "unused.mov"])
        let talk = p.assets[0].id, song = p.assets[1].id
        #expect(file.bookmarks == [talk: Data([1, 2, 3])])
        #expect(file.name == (version >= 3 ? "Golden" : nil))
        let transcript = try #require(p.transcripts[talk])
        #expect(transcript.language == .italian)
        #expect(transcript.words.map(\.text) == ["Ciao", "a", "tutti"])
        #expect(transcript.words[1].start == Self.frames(15))
        #expect(p.captions.style == .highlight)
        #expect(p.titles.map(\.text) == ["Hook\nline two"])
        #expect(p.titles[0].style == (version >= 3 ? .marker : .bold))
        let music = try #require(p.music)
        #expect(music.assetID == song)
        #expect(music.sourceStart == Self.seconds(5))
        #expect(music.volume == 0.5)

        let clips = p.timeline.clips
        // From version 4 a freeze frame splits the first clip at 1 s: talk 0–1 s, freeze, talk 1–4 s.
        let first = clips[0]
        let middle = version >= 4 ? clips[2] : clips[0]  // the talk clip's part that ends at 4 s
        let second = version >= 4 ? clips[3] : clips[1]  // talk 4–10 s
        #expect(first.assetID == talk && second.assetID == talk)
        #expect(first.sourceStart == .zero)
        #expect(middle.sourceStart + middle.duration == Self.seconds(4))
        #expect(second.sourceStart == Self.seconds(4))
        #expect(first.framing == .fit)
        #expect(second.volume == 1.4)
        // Shorts saved before backgrounds existed keep their black bars; later files say what they had.
        #expect(first.background == (version >= 2 ? .blur : .black))

        guard version >= 2 else {
            #expect(clips.count == 2)
            #expect(second.background == .black)
            return
        }
        // Version 2: B-roll, pictures, placement and motion.
        let photo = try #require(p.assets.first { $0.name == "photo.jpg" })
        #expect(photo.isImage && photo.hasVideo && !photo.hasAudio)
        #expect(clips.last?.assetID == photo.id)
        #expect(clips.last?.duration == Self.seconds(3))
        #expect(p.overlays.count == 1)
        #expect(p.overlays[0].start == Self.seconds(1))
        #expect(p.asset(id: p.overlays[0].clip.assetID)?.name == "broll.mov")
        #expect(first.placement == Placement(offsetX: 0.1, offsetY: -0.05, scale: 1.3, rotation: 5))
        #expect(first.keyframes.map(\.time) == [.zero, Self.seconds(2)])
        #expect(first.keyframes[1].placement.scale == 1.5)
        #expect(second.background == .blur)

        // Version 3: speed, title looks, key words and emoji, sounds and voice-overs, layouts.
        #expect(second.speed == (version >= 3 ? 2 : 1))
        #expect(second.duration == (version >= 3 ? Self.seconds(3) : Self.seconds(6)))
        guard version >= 3 else {
            #expect(clips.count == 3)
            #expect(p.overlays[0].layout == .free)
            return
        }
        #expect(transcript.words[2].emoji == "🎉")
        #expect(p.sounds.count == 1)
        #expect(p.sounds[0].isVoiceOver)
        #expect(p.sounds[0].start == Self.seconds(2))
        #expect(p.overlays[0].layout == .top)
        #expect(first.cleansVoice)

        // Version 4: transitions, freeze frames, fades, volume lines, voice effects.
        guard version >= 4 else {
            #expect(clips.count == 3)
            return
        }
        #expect(clips.count == 5)
        #expect(clips[1].isFrozen)
        #expect(middle.transitionOut == ClipTransition(kind: .slideUp, duration: Self.frames(12)))
        #expect(second.pictureFadeIn == Self.frames(10))
        #expect(second.fadeOut == Self.frames(20))
        #expect(second.voiceEffect == .robot)
        // The volume line is in the file's own time, so both pieces of the split clip keep it.
        #expect(first.volumeKeys.map(\.level) == [0.5])
        #expect(middle.volumeKeys == first.volumeKeys)

        // Version 5: colour, filters (per clip and for the whole Short), Stabilize.
        guard version >= 5 else { return }
        #expect(first.look.color.exposure == 0.2)
        #expect(first.look.color.warmth == -0.3)
        #expect(first.look.filter == FilterChoice(.film, strength: 0.7))
        #expect(p.look == FilterChoice(.vivid, strength: 0.5))
        #expect(clips[1].steadiness == 0.8)

        // Version 6: markers.
        guard version >= 6 else { return }
        #expect(p.markers.map(\.name) == ["Punchline"])
        #expect(p.markers[0].time == Self.seconds(3))

        // Version 7: styles, app-made music, storyboards.
        #expect(p.style == (version >= 7 ? .bold : nil))
        #expect(music.mood == (version >= 7 ? .upbeat : nil))
        guard version >= 7 else { return }
        #expect(p.storyboard?.kind == .tutorial)
        #expect(first.styledMotion)

        // Version 8: speed curves, clip animations, smooth slow motion, beats, music placed later or looped.
        #expect(music.start == (version >= 8 ? Self.seconds(1) : .zero))
        #expect(music.loops == (version >= 8))
        guard version >= 8 else { return }
        #expect(clips[1].speedCurve == SpeedCurve(.hero))
        #expect(first.animationIn == ClipAnimation(.spin))
        #expect(clips[1].smoothSlowMotion)
        #expect(music.beats == [Beat(time: .zero, isBarStart: true), Beat(time: Self.frames(15))])
    }
}
