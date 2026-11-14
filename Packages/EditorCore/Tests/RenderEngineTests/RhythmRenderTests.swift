@preconcurrency import AVFoundation
import EditorCore
import Testing

@testable import RenderEngine

private let red: (UInt8, UInt8, UInt8, UInt8) = (0, 0, 255, 255)
private let blue: (UInt8, UInt8, UInt8, UInt8) = (255, 0, 0, 255)

private typealias Pixel = (r: UInt8, g: UInt8, b: UInt8)

/// Stage I in the composition: speed curves, music placed later or looped, clip animations,
/// beats found in a song, smooth slow motion.
@MainActor
struct RhythmRenderTests {
    private func frame(of built: PlayableComposition, at seconds: Double) async throws -> CGImage {
        let generator = AVAssetImageGenerator(asset: built.composition)
        generator.videoComposition = built.videoComposition
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        return try await generator.image(at: CMTime(seconds: seconds, preferredTimescale: 600)).image
    }

    private func pixel(_ built: PlayableComposition, at seconds: Double, x: Int = 540, y: Int = 960) async throws -> Pixel {
        Fixture.pixel(try await frame(of: built, at: seconds), x: x, y: y)
    }

    private func isRed(_ p: Pixel) -> Bool { p.r > 200 && p.g < 60 && p.b < 60 }
    private func isBlue(_ p: Pixel) -> Bool { p.b > 200 && p.r < 60 && p.g < 60 }
    private func isBlack(_ p: Pixel) -> Bool { p.r < 40 && p.g < 40 && p.b < 40 }

    private func t(_ seconds: Double) -> CMTime { CMTime(seconds: seconds, preferredTimescale: 600).snappedToFrame() }

    // MARK: Speed curves

    @Test func aSpeedCurvePlaysInStepsAndKeepsPictureAndSoundInPlace() async throws {
        // Red for 3 s, then blue, with sound throughout.
        let url = try await Fixture.video(width: 180, height: 320, seconds: 6, bgra: red, toneFrom: 0, laterBGRA: blue, laterFrom: 3)
        var project = Project()
        project.appendClip(of: project.addAsset(try await MediaProbe.probe(url)))
        project.setSpeedCurve(.bullet, for: project.timeline.clips[0].id)
        let clip = project.timeline.clips[0]
        let built = try await CompositionBuilder.build(project)
        #expect(abs(built.composition.duration.seconds - clip.duration.seconds) < 0.05)
        let video = try #require(try await built.composition.loadTracks(withMediaType: .video).first)
        // Steps of the same speed next to each other join into one stretch.
        #expect(video.segments.count > 20)
        let audio = try #require(try await built.composition.loadTracks(withMediaType: .audio).first)
        #expect(audio.segments.count > 3) // the sound in stretches of at least 0.2 s
        // The file's third second (the change to blue) is where the curve says it plays.
        let change = clip.timelineOffset(ofSourceTime: t(3)).seconds
        #expect(isRed(try await pixel(built, at: change - 0.1)))
        #expect(isBlue(try await pixel(built, at: change + 0.1)))
    }

    @Test func curvedSoundHasNoSliversAndNeverOutlastsThePicture() async throws {
        // Slivers of sound, or sound a nanosecond longer than the picture, stall the player.
        var project = Project()
        for _ in 0..<3 {
            let url = try await Fixture.video(width: 180, height: 320, seconds: 5, bgra: red, toneFrom: 0)
            project.appendClip(of: project.addAsset(try await MediaProbe.probe(url)))
        }
        for shape in SpeedCurveShape.allCases {
            project.setSpeedCurve(shape, for: project.timeline.clips[0].id)
            project.setSpeedCurve(.bullet, for: project.timeline.clips[2].id)
            let built = try await CompositionBuilder.build(project)
            let video = try #require(try await built.composition.loadTracks(withMediaType: .video).first)
            let audio = try #require(try await built.composition.loadTracks(withMediaType: .audio).first)
            #expect(audio.timeRange.end <= video.timeRange.end, "\(shape)")
            #expect(audio.segments.allSatisfy { $0.timeMapping.target.duration.seconds > 0.001 }, "\(shape)")
        }
    }

    // MARK: Music

    @Test func musicCanStartLaterAndLoop() async throws {
        var project = Project()
        project.appendClip(of: project.addAsset(try await MediaProbe.probe(try await Fixture.video(width: 180, height: 320, seconds: 6, bgra: red))))
        let song = project.addAsset(try await MediaProbe.probe(try await Fixture.sound(seconds: 2)))
        project.setMusic(song)
        project.setMusicTimelineStart(t(1))
        project.music?.loops = true
        let built = try await CompositionBuilder.build(project)
        let tracks = try await built.composition.loadTracks(withMediaType: .audio)
        let music = try #require(tracks.last)
        let ranges = music.segments.filter { !$0.isEmpty }.map(\.timeMapping.target)
        // 1–3, 3–5, 5–6.
        #expect(ranges.count == 3)
        #expect(abs(ranges[0].start.seconds - 1) < 0.02)
        #expect(abs(ranges[2].end.seconds - 6) < 0.05)
        #expect(built.musicEnvelope.first.map { abs($0.time.seconds - 1) < 0.02 } == true)
    }

    // MARK: Clip animations

    @Test func aFadeInStartsDarkAndASlideMovesThePicture() async throws {
        var project = Project()
        project.appendClip(of: project.addAsset(try await MediaProbe.probe(try await Fixture.video(width: 1080, height: 1920, seconds: 2, bgra: red))))
        let id = project.timeline.clips[0].id
        project.setAnimation(ClipAnimation(.fade, duration: t(1)), entering: true, for: id)
        var built = try await CompositionBuilder.build(project)
        let start = try await pixel(built, at: 0), middle = try await pixel(built, at: 0.5), after = try await pixel(built, at: 1.5)
        #expect(start.r < 60)
        #expect(middle.r > start.r && middle.r < after.r)
        #expect(isRed(after))

        // Going out sliding left: near the end the right side of the canvas is empty (black).
        project.setAnimation(nil, entering: true, for: id)
        project.setAnimation(ClipAnimation(.slideLeft, duration: t(1)), entering: false, for: id)
        built = try await CompositionBuilder.build(project)
        #expect(isRed(try await pixel(built, at: 0.5, x: 1000)))
        #expect(isBlack(try await pixel(built, at: 1.93, x: 1000)))
    }

    // MARK: Beats

    @Test func theBeatsOfAClickTrackAreFound() async throws {
        let url = try Self.clickTrack(bpm: 120, seconds: 12, firstClick: 0.25)
        let beats = await BeatDetector.beats(of: url)
        #expect(beats.count >= 22 && beats.count <= 24)
        guard beats.count > 4 else { return }
        let gaps = zip(beats, beats.dropFirst()).map { ($1.time - $0.time).seconds }
        #expect(gaps.allSatisfy { abs($0 - 0.5) < 0.03 })
        // On the clicks: 0.25, 0.75, …
        let offGrid = beats.map { abs(($0.time.seconds - 0.25).truncatingRemainder(dividingBy: 0.5)) }.map { min($0, 0.5 - $0) }
        #expect(offGrid.allSatisfy { $0 < 0.012 }, "\(beats.prefix(3).map { $0.time.seconds })")
        // The loud click every fourth beat starts the bars.
        let bars = beats.filter(\.isBarStart).map { $0.time.seconds }
        #expect(
            bars.allSatisfy { abs(($0 - 0.25).truncatingRemainder(dividingBy: 2)) < 0.05 || abs(($0 - 0.25).truncatingRemainder(dividingBy: 2) - 2) < 0.05 })
    }

    /// A WAV of short clicks (a low thump on every fourth), `bpm` a minute.
    static func clickTrack(bpm: Double, seconds: Double, firstClick: Double) throws -> URL {
        let rate = 44_100.0
        let url = FileManager.default.temporaryDirectory.appending(path: "clicks-\(UUID().uuidString).wav")
        let format = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 1)!
        let count = Int(seconds * rate)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(count))!
        buffer.frameLength = AVAudioFrameCount(count)
        let data = buffer.floatChannelData![0]
        for i in 0..<count { data[i] = 0 }
        var time = firstClick, beat = 0
        while time < seconds {
            let start = Int(time * rate)
            let strong = beat % 4 == 0
            for j in 0..<Int(0.06 * rate) where start + j < count {
                let decay = Float(exp(-Double(j) / (0.012 * rate)))
                let tone = strong ? sin(2 * Double.pi * 70 * Double(j) / rate) : sin(2 * Double.pi * 2000 * Double(j) / rate)
                data[start + j] += Float(tone) * decay * (strong ? 0.9 : 0.5)
            }
            beat += 1
            time += 60 / bpm
        }
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        try file.write(from: buffer)
        return url
    }

    // MARK: Smooth slow motion

    @Test func smoothSlowMotionMakesPicturesInBetween() async throws {
        let url = try await Fixture.video(width: 320, height: 180, seconds: 1, bgra: red, laterBGRA: blue, laterFrom: 0.5)
        let media = try await MediaProbe.probe(url)
        var clip = Clip(assetID: media.id, sourceStart: .zero, duration: t(1))
        clip.speed = 0.25
        clip.smoothSlowMotion = true
        let recipe = try #require(FrameInterpolator.recipe(for: clip, media: media))
        #expect(recipe.factor == 4)
        let copy = try await FrameInterpolator.makeCopy(of: url, recipe: recipe)
        let asset = AVURLAsset(url: copy)
        let track = try #require(try await asset.loadTracks(withMediaType: .video).first)
        let (rate, range) = try await track.load(.nominalFrameRate, .timeRange)
        // Four pictures for each of the original's (the last has nothing after it).
        #expect(rate > 100)
        #expect(abs(range.duration.seconds - 1) < 0.05)
        #expect(FrameInterpolator.existingCopy(for: clip, media: media) != nil)

        // Played at a quarter speed, the composition uses the copy.
        var project = Project()
        let id = project.addAsset(media)
        clip.assetID = id
        clip.duration = t(4)
        project.timeline.clips = [clip]
        let built = try await CompositionBuilder.build(project)
        #expect(abs(built.composition.duration.seconds - 4) < 0.05)
        #expect(isRed(try await pixel(built, at: 0.5)))
        #expect(isBlue(try await pixel(built, at: 3.5)))
        clip.speed = 1
        #expect(FrameInterpolator.recipe(for: clip, media: media) == nil)
    }
}
