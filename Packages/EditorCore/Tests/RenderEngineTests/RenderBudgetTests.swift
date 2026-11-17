@preconcurrency import AVFoundation
import BenchSupport
import EditorCore
import Foundation
import Testing

@testable import RenderEngine

/// Performance budgets for rendering (F12), checked in every test run: the rebuild after every
/// edit, drawing a full-size frame with everything on it, and the main thread staying free while
/// a long Short's sound is measured. Budgets are for a Debug build on the slowest supported Mac
/// (M1); `make bench` keeps the numbers. They run in a step of their own (`Bench.budgetsRunAlone`).
@MainActor
@Suite(.serialized, .enabled(if: Bench.budgetsRunAlone))
struct RenderBudgetTests {
    /// The big Short (3 minutes, 60 clips, B-roll, titles, karaoke captions, music) made of small
    /// real files: what costs time here is the number of pieces, not the size of the files.
    private func bigShort() async throws -> Project {
        var videos: [MediaAsset] = []
        for (index, colour) in [(40, 90, 200, 255), (200, 60, 40, 255), (40, 180, 90, 255)].enumerated() {
            let url = try await Fixture.video(
                width: 180, height: 320, seconds: 12, bgra: (UInt8(colour.0), UInt8(colour.1), UInt8(colour.2), 255), toneFrom: Double(index))
            videos.append(try await MediaProbe.probe(url))
        }
        let song = try await MediaProbe.probe(try await Fixture.sound(seconds: 30))
        return BigShort.make(videos: videos, song: song)
    }

    @Test func theRebuildAfterAnEditIsQuick() async throws {
        let project = try await bigShort()
        #expect(project.timeline.clips.count == BigShort.clipCount)
        let analysis = MediaAnalysis()
        _ = try await CompositionBuilder.build(project, analysis: analysis)
        let ms = try await Bench.best { _ = try await CompositionBuilder.build(project, analysis: analysis) }
        Bench.record("rebuild big Short", ms)
        // Every edit waits for it before the viewer shows the change.
        #expect(ms < 100)
    }

    @Test func aFullSizeFrameWithEverythingDrawsInRealTime() async throws {
        var project = try await bigShort()
        // A transition, a look, an effect on every clip, and a filter over the whole Short.
        for index in project.timeline.clips.indices {
            project.timeline.clips[index].look = ClipLook(filter: FilterChoice(.vivid))
            project.timeline.clips[index].effects = [ClipEffect(.glitch, part: .wholeClip)]
        }
        project.setTransition(ClipTransition(kind: .dissolve), after: project.timeline.clips[0].id)
        project.look = FilterChoice(.film)
        let built = try await CompositionBuilder.build(project)
        // The first two seconds: the dissolve, B-roll, the first title and captions.
        let reader = try AVAssetReader(asset: built.composition)
        reader.timeRange = CMTimeRange(start: .zero, duration: CMTime(value: 2, timescale: 1))
        let output = AVAssetReaderVideoCompositionOutput(
            videoTracks: try await built.composition.loadTracks(withMediaType: .video),
            videoSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
        output.videoComposition = built.videoComposition
        output.alwaysCopiesSampleData = false
        reader.add(output)
        reader.startReading()
        var times: [Double] = []
        var last = ContinuousClock.now
        while output.copyNextSampleBuffer() != nil {
            let now = ContinuousClock.now
            times.append(Bench.milliseconds(now - last))
            last = now
        }
        // The first frames warm up (colour tables, fonts).
        let steady = times.dropFirst(5).sorted()
        let median = try #require(steady.isEmpty ? nil : steady[steady.count / 2])
        Bench.record("frame big Short", median)
        // Playback needs one frame every 33 ms.
        #expect(median < 33)
    }

    /// Measuring the loudness of a whole Short (before export) decodes all of its sound: seconds
    /// for a long one. The main thread must stay free meanwhile.
    @Test func theMainThreadStaysFreeWhileTheSoundIsMeasured() async throws {
        let project = try await bigShort()
        final class Flag { var isSet = false }
        let done = Flag()
        let measuring = Task {
            defer { done.isSet = true }
            return try await AudioProbe.loudness(of: project)
        }
        var longestGap = Duration.zero
        var last = ContinuousClock.now
        while !done.isSet {
            try await Task.sleep(for: .milliseconds(5))
            let now = ContinuousClock.now
            longestGap = max(longestGap, now - last)
            last = now
        }
        let meter = try #require(try await measuring.value)
        #expect(meter.integratedLoudness != nil)
        Bench.record("main thread gap while measuring", Bench.milliseconds(longestGap))
        // The composition is still built on the main thread (tens of milliseconds); the decoding isn't.
        #expect(longestGap < .milliseconds(250), "The main thread was busy for \(longestGap)")
    }
}
