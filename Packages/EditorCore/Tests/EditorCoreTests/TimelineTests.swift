import CoreMedia
import Foundation
import Testing
@testable import EditorCore

private func seconds(_ s: Double) -> CMTime { CMTime(seconds: s, preferredTimescale: 600) }

private func clip(_ length: Double, from start: Double = 0) -> Clip {
    Clip(assetID: UUID(), sourceStart: seconds(start), duration: seconds(length))
}

struct TimelineTests {
    @Test func durationIsSumOfClips() {
        let timeline = Timeline(clips: [clip(2), clip(3.5)])
        #expect(timeline.duration == seconds(5.5))
    }

    @Test func locateAssignsCutsToTheLaterClip() throws {
        let timeline = Timeline(clips: [clip(2), clip(3)])
        let atCut = try #require(timeline.locate(seconds(2)))
        #expect(atCut.index == 1)
        #expect(atCut.offset == .zero)
        #expect(timeline.locate(seconds(1))?.index == 0)
        #expect(timeline.locate(seconds(5)) == nil)
        #expect(timeline.locate(seconds(-1)) == nil)
    }

    @Test func removeClosesTheGap() {
        let a = clip(2), b = clip(3), c = clip(1)
        var timeline = Timeline(clips: [a, b, c])
        timeline.remove(b.id)
        #expect(timeline.clips.map(\.id) == [a.id, c.id])
        #expect(timeline.range(of: c.id)?.start == seconds(2))
    }

    @Test func splitKeepsSourceContinuity() {
        var timeline = Timeline(clips: [clip(2), clip(4, from: 10)])
        let newID = timeline.split(at: seconds(3))
        #expect(newID != nil)
        #expect(timeline.clips.count == 3)
        let first = timeline.clips[1], second = timeline.clips[2]
        #expect(second.id == newID)
        #expect(first.sourceStart == seconds(10))
        #expect(first.duration == seconds(1))
        #expect(second.sourceStart == seconds(11))
        #expect(second.duration == seconds(3))
        #expect(timeline.duration == seconds(6))
    }

    @Test func splitOnACutOrOutsideDoesNothing() {
        var timeline = Timeline(clips: [clip(2), clip(2)])
        #expect(timeline.split(at: seconds(2)) == nil)
        #expect(timeline.split(at: .zero) == nil)
        #expect(timeline.split(at: seconds(9)) == nil)
        #expect(timeline.clips.count == 2)
    }

    @Test func splitSnapsToWholeFrames() throws {
        var timeline = Timeline(clips: [clip(2)])
        let newID = timeline.split(at: CMTime(seconds: 1.0101, preferredTimescale: 10_000))
        try #require(newID != nil)
        #expect(timeline.clips[0].duration == CMTime(value: 30, timescale: 30))
    }

    @Test func moveReorders() {
        let a = clip(1), b = clip(1), c = clip(1)
        var timeline = Timeline(clips: [a, b, c])
        timeline.move(a.id, to: 2)
        #expect(timeline.clips.map(\.id) == [b.id, c.id, a.id])
        timeline.move(a.id, to: -5)
        #expect(timeline.clips.map(\.id) == [a.id, b.id, c.id])
    }

    @Test func projectRoundTripsThroughJSON() throws {
        var project = Project()
        let asset = MediaAsset(url: URL(filePath: "/tmp/a.mov"), name: "a", duration: seconds(4), displaySize: CGSize(width: 1080, height: 1920), hasAudio: true)
        project.appendClip(of: project.addAsset(asset))
        let decoded = try JSONDecoder().decode(Project.self, from: JSONEncoder().encode(project))
        #expect(decoded == project)
    }

    @Test func importingTheSameFileTwiceReusesIt() {
        var project = Project()
        let url = URL(filePath: "/tmp/a.mov")
        let first = project.addAsset(MediaAsset(url: url, name: "a", duration: seconds(1), displaySize: .zero, hasAudio: false))
        let second = project.addAsset(MediaAsset(url: url, name: "a", duration: seconds(1), displaySize: .zero, hasAudio: false))
        #expect(first == second)
        #expect(project.assets.count == 1)
    }

    @Test func horizontalFootageDefaultsToFit() {
        let wide = MediaAsset(url: URL(filePath: "/a"), name: "", duration: seconds(1), displaySize: CGSize(width: 1920, height: 1080), hasAudio: false)
        let tall = MediaAsset(url: URL(filePath: "/b"), name: "", duration: seconds(1), displaySize: CGSize(width: 1080, height: 1920), hasAudio: false)
        #expect(wide.defaultFraming == .fit)
        #expect(tall.defaultFraming == .fill)
    }

    @Test func timeFormat() {
        #expect(TimeFormat.string(.zero) == "0:00.0")
        #expect(TimeFormat.string(CMTime(value: 9, timescale: 30)) == "0:00.3")
        #expect(TimeFormat.string(seconds(75.46)) == "1:15.5")
        #expect(TimeFormat.string(CMTime(value: 49, timescale: 30)) == "0:01.6")
        #expect(TimeFormat.string(CMTime(value: 101, timescale: 30)) == "0:03.4")
        #expect(TimeFormat.string(.invalid) == "0:00.0")
    }
}
