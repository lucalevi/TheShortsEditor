@preconcurrency import AVFoundation
import EditorCore
import Foundation
import Testing

@testable import RenderEngine

/// How fast the compositor draws full-size frames: real-time playback needs under 33 ms a frame.
/// Slow (writes 1080p fixtures), so it runs only with `SHORTS_BENCH=1 swift test --filter PerformanceTests`.
@MainActor
@Suite(.serialized, .enabled(if: ProcessInfo.processInfo.environment["SHORTS_BENCH"] != nil))
struct PerformanceTests {
    private let seconds = 4

    /// Milliseconds per frame, reading every frame of `project` through the compositor (as export does).
    private func msPerFrame(_ project: Project) async throws -> Double {
        let built = try await CompositionBuilder.build(project)
        let reader = try AVAssetReader(asset: built.composition)
        let output = AVAssetReaderVideoCompositionOutput(
            videoTracks: try await built.composition.loadTracks(withMediaType: .video),
            videoSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
        output.videoComposition = built.videoComposition
        output.alwaysCopiesSampleData = false
        reader.add(output)
        reader.startReading()
        let start = ContinuousClock.now
        var frames = 0
        while output.copyNextSampleBuffer() != nil { frames += 1 }
        let elapsed = ContinuousClock.now - start
        let ms = Double(elapsed.components.attoseconds) / 1e15 + Double(elapsed.components.seconds) * 1000
        return ms / Double(max(frames, 1))
    }

    private func clipOfWide(width: Int = 1920, height: Int = 1080) async throws -> (Project, MediaAsset.ID) {
        let url = try await Fixture.video(
            width: width, height: height, seconds: seconds, bgra: (40, 90, 200, 255), bottomBGRA: (200, 200, 40, 255), toneFrom: 0)
        var p = Project()
        let id = p.addAsset(try await MediaProbe.probe(url))
        return (p, id)
    }

    @Test(arguments: [(1920, 1080), (3840, 2160)])
    func framesDrawInRealTime(size: (Int, Int)) async throws {
        var (plain, wide) = try await clipOfWide(width: size.0, height: size.1)
        plain.appendClip(of: wide)
        let plainMs = try await msPerFrame(plain)

        // Everything at once: two clips with a transition, a look, an effect, two B-roll videos,
        // spoken-word captions, a title and a filter over the whole Short.
        var heavy = plain
        let upright = try await Fixture.video(width: 1080, height: 1920, seconds: seconds, bgra: (200, 40, 40, 255))
        let upID = heavy.addAsset(try await MediaProbe.probe(upright))
        let half = CMTime(value: Int64(seconds), timescale: 2)
        heavy.timeline.clips = [Clip(assetID: wide, sourceStart: .zero, duration: half), Clip(assetID: wide, sourceStart: half, duration: half)]
        heavy.setTransition(ClipTransition(kind: .dissolve), after: heavy.timeline.clips[0].id)
        for index in heavy.timeline.clips.indices {
            heavy.timeline.clips[index].look = ClipLook(filter: FilterChoice(.vivid))
            heavy.timeline.clips[index].effects = [ClipEffect(.glitch, part: .wholeClip)]
        }
        heavy.addOverlay(of: upID, at: .zero)
        heavy.addOverlay(of: upID, at: CMTime(value: 1, timescale: 1))
        heavy.transcripts[wide] = Transcript(
            language: .english,
            words: (0..<(seconds * 3)).map { i in
                Word(
                    text: ["This", "is", "really", "fast", "now"][i % 5], start: CMTime(value: Int64(i), timescale: 3), duration: CMTime(value: 1, timescale: 4)
                )
            })
        heavy.captions.style = .karaoke
        heavy.addTitle(at: .zero, text: "Watch this")
        heavy.look = FilterChoice(.film)
        let heavyMs = try await msPerFrame(heavy)
        // A rebuild follows every edit: it should feel instant.
        let buildStart = ContinuousClock.now
        for _ in 0..<5 { _ = try await CompositionBuilder.build(heavy) }
        let build = (ContinuousClock.now - buildStart) / 5
        print("BENCH rebuild of the heavy Short: \(build.formatted(.units(allowed: [.milliseconds])))")
        #expect(build < .milliseconds(150))
        print(String(format: "BENCH %dx%d: plain %.1f ms/frame, heavy %.1f ms/frame", size.0, size.1, plainMs, heavyMs))
        #expect(heavyMs < 33)
    }
}
