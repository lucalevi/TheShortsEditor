@preconcurrency import AVFoundation
import EditorCore
import Foundation
import Testing

@testable import RenderEngine

/// F20: work the app cancels all the time (a rebuild after every edit, an export the user stops,
/// sound being measured) stopped at random moments, many times over, and run alongside each other.
/// Nothing may hang, crash, leave a half-written file or race (`make tsan` runs these too).
@MainActor
@Suite(.serialized)
struct CancellationStressTests {
    /// A Short with a little of everything that costs time to build: two clips, a transition,
    /// B-roll, a title and music.
    private func busyShort() async throws -> Project {
        var project = Project()
        let first = try await Fixture.video(width: 180, height: 320, seconds: 2, bgra: (40, 40, 220, 255), toneFrom: 0)
        let second = try await Fixture.video(width: 320, height: 180, seconds: 2, bgra: (220, 60, 30, 255), toneFrom: 0.5)
        let song = try await Fixture.sound(seconds: 5)
        let firstID = project.addAsset(try await MediaProbe.probe(first))
        let secondID = project.addAsset(try await MediaProbe.probe(second))
        project.appendClip(of: firstID)
        project.appendClip(of: secondID)
        project.setTransition(ClipTransition(kind: .dissolve), after: project.timeline.clips[0].id)
        project.addOverlay(of: secondID, at: CMTime(value: 1, timescale: 2))
        project.addTitle(at: .zero, text: "Stress")
        project.setMusic(project.addAsset(try await MediaProbe.probe(song)))
        return project
    }

    /// Like the editor after every edit: a new build cancels the one before it, often before it
    /// is done. Each build either finishes whole or throws `CancellationError`.
    @Test func rebuildsCancelledAtRandomEndCleanly() async throws {
        let project = try await busyShort()
        let analysis = MediaAnalysis()
        var generator = SeededGenerator(seed: 7)
        var builds: [Task<PlayableComposition, Error>] = []
        for _ in 0..<60 {
            builds.last?.cancel()
            builds.append(Task { try await CompositionBuilder.build(project, analysis: analysis) })
            let wait = Int.random(in: 0...6, using: &generator)
            if wait > 0 { try await Task.sleep(for: .milliseconds(wait)) }
        }
        var finished = 0
        for build in builds {
            do {
                let built = try await build.value
                #expect(try await built.composition.load(.duration) > .zero)
                finished += 1
            } catch is CancellationError {
                continue
            }
        }
        // The last one was never cancelled.
        #expect(finished >= 1)
        let last = try await builds.last!.value
        #expect(abs(try await last.composition.load(.duration).seconds - project.duration.seconds) < 0.05)
    }

    /// The user stops exports at random moments: a stopped export leaves no file behind, one that
    /// wasn't stopped leaves a whole one.
    @Test func exportsStoppedAtRandomLeaveNoHalfFile() async throws {
        let project = try await busyShort()
        let analysis = MediaAnalysis()
        var generator = SeededGenerator(seed: 11)
        for round in 0..<6 {
            let url = FileManager.default.temporaryDirectory.appending(path: "stress-\(round)-\(UUID().uuidString).mp4")
            let export = Task { try await Exporter.export(project, to: url, analysis: analysis) }
            // From at once (while measuring loudness) to well into writing.
            try await Task.sleep(for: .milliseconds(Int.random(in: 0...900, using: &generator)))
            export.cancel()
            do {
                try await export.value
                let asset = AVURLAsset(url: url)
                #expect(abs(try await asset.load(.duration).seconds - project.duration.seconds) < 0.1)
                try? FileManager.default.removeItem(at: url)
            } catch is CancellationError {
                #expect(!FileManager.default.fileExists(atPath: url.path), "round \(round): a stopped export left its file")
            }
        }
    }

    /// Building, measuring sound and exporting the same Short at the same time, as the editor
    /// does when the user exports while the viewer rebuilds and waveforms are measured.
    @Test func buildMeasureAndExportTogether() async throws {
        let project = try await busyShort()
        let analysis = MediaAnalysis()
        let url = FileManager.default.temporaryDirectory.appending(path: "together-\(UUID().uuidString).mp4")
        defer { try? FileManager.default.removeItem(at: url) }
        async let exported: Void = Exporter.export(project, to: url, analysis: analysis)
        async let builds: Int = {
            var count = 0
            for _ in 0..<10 {
                _ = try await CompositionBuilder.build(project, analysis: analysis)
                count += 1
            }
            return count
        }()
        async let loudness = AudioProbe.loudness(of: project, analysis: analysis)
        async let levels = analysis.levels(of: project.assets[0].url)
        _ = try await exported
        #expect(try await builds == 10)
        #expect(try await loudness != nil)
        #expect(await levels != nil)
        #expect(FileManager.default.fileExists(atPath: url.path))
    }
}

/// The same random numbers on every run.
struct SeededGenerator: RandomNumberGenerator {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        return state
    }
}
