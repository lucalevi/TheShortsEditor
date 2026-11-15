@preconcurrency import AVFoundation
import EditorCore
import Foundation
import Testing

@testable import RenderEngine

/// What is measured about files is kept per `MediaAnalysis` (no process-wide state), keyed by the
/// file as it is now, so a file changed on disk is measured again.
@MainActor
struct MediaAnalysisTests {
    @Test func levelsAreMeasuredOnceAndAgainWhenTheFileChanges() async throws {
        let url = try await Fixture.sound(seconds: 1, amplitude: 0.3)
        let analysis = MediaAnalysis()
        let first = try #require(await analysis.levels(of: url))
        #expect(await analysis.levels(of: url) == first)

        // The same place, other content: a quieter tone, written over it.
        let quieter = try await Fixture.sound(seconds: 2, amplitude: 0.05)
        try FileManager.default.removeItem(at: url)
        try FileManager.default.copyItem(at: quieter, to: url)
        let second = try #require(await analysis.levels(of: url))
        #expect(second != first)
        #expect(second.decibels.count > first.decibels.count)
    }

    @Test func eachAnalysisKeepsItsOwnMeasurements() async throws {
        let url = try await Fixture.sound(seconds: 1)
        let one = MediaAnalysis(), other = MediaAnalysis()
        _ = await one.levels(of: url)
        // Nothing measured by `one` is seen by `other`; it measures for itself, with the same result.
        #expect(await other.levels(of: url) == (await one.levels(of: url)))
    }

    @Test func aFileIsKnownByItsPathSizeAndDate() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "identity-\(UUID().uuidString).txt")
        try Data("one".utf8).write(to: url)
        let before = FileIdentity.key(of: url)
        #expect(FileIdentity.key(of: url) == before)
        try Data("three".utf8).write(to: url)
        #expect(FileIdentity.key(of: url) != before)
    }
}
