import CoreGraphics
import CoreMedia
import Foundation
import Testing

@testable import EditorCore

private func seconds(_ s: Double) -> CMTime { CMTime(seconds: s, preferredTimescale: 600) }

/// Four 5-second clips, a title from 2 to 5 s, and a 60-second song as music.
private func project() -> Project {
    var project = Project()
    let video = MediaAsset(
        url: URL(fileURLWithPath: "/tmp/v.mov"), name: "v", duration: CMTime(value: 5, timescale: 1),
        displaySize: CGSize(width: 1080, height: 1920), hasAudio: true)
    let song = MediaAsset(
        url: URL(fileURLWithPath: "/tmp/s.m4a"), name: "s", duration: CMTime(value: 60, timescale: 1),
        displaySize: .zero, hasAudio: true, hasVideo: false)
    project.addAsset(video)
    project.addAsset(song)
    for _ in 0..<4 { project.appendClip(of: video.id) }
    project.addTitle(at: seconds(2), text: "Hook")
    project.setMusic(song.id)
    return project
}

private func clip(_ p: Project, _ index: Int) -> TimelineItem { .clip(p.timeline.clips[index].id) }

struct SelectionTests {
    @Test func plainClickSelectsOnlyThatItem() {
        let p = project()
        var s = TimelineSelection()
        s.click(clip(p, 0), .replace, in: p.timeline)
        s.click(clip(p, 2), .replace, in: p.timeline)
        #expect(s.items == [clip(p, 2)])
        #expect(s.single == clip(p, 2))
    }

    @Test func commandClickAddsAndRemoves() {
        let p = project()
        var s = TimelineSelection()
        s.click(clip(p, 0), .replace, in: p.timeline)
        s.click(.music, .toggle, in: p.timeline)
        s.click(clip(p, 3), .toggle, in: p.timeline)
        #expect(s.items == [clip(p, 0), .music, clip(p, 3)])
        #expect(s.single == nil)
        s.click(.music, .toggle, in: p.timeline)
        #expect(s.items == [clip(p, 0), clip(p, 3)])
    }

    @Test func shiftClickSelectsTheClipsInBetween() {
        let p = project()
        var s = TimelineSelection()
        s.click(clip(p, 3), .replace, in: p.timeline)
        s.click(clip(p, 1), .extend, in: p.timeline)
        #expect(s.items == [clip(p, 1), clip(p, 2), clip(p, 3)])
        // The range keeps starting from the same clip.
        s.click(clip(p, 2), .extend, in: p.timeline)
        #expect(s.items.isSuperset(of: [clip(p, 2), clip(p, 3)]))
    }

    @Test func shiftClickOnSomethingElseAddsIt() {
        let p = project()
        var s = TimelineSelection()
        s.click(clip(p, 0), .replace, in: p.timeline)
        s.click(.title(p.titles[0].id), .extend, in: p.timeline)
        #expect(s.items == [clip(p, 0), .title(p.titles[0].id)])
    }

    @Test func rectanglePicksWhatItCoversInItsLanes() {
        let p = project()
        let range = CMTimeRange(start: seconds(4), end: seconds(11))
        #expect(p.timelineItems(overlapping: range, in: [.clips]) == [clip(p, 0), clip(p, 1), clip(p, 2)])
        #expect(p.timelineItems(overlapping: range, in: [.titles, .music]) == [.title(p.titles[0].id), .music])
        // Touching an edge isn't overlapping.
        #expect(p.timelineItems(overlapping: CMTimeRange(start: seconds(5), end: seconds(6)), in: [.clips, .titles]) == [clip(p, 1)])
    }

    @Test func rectangleReplacesOrAdds() {
        let p = project()
        var s = TimelineSelection()
        s.click(.music, .replace, in: p.timeline)
        s.select([clip(p, 0), clip(p, 1)], adding: false)
        #expect(s.items == [clip(p, 0), clip(p, 1)])
        s.select([clip(p, 3)], adding: true)
        #expect(s.items == [clip(p, 0), clip(p, 1), clip(p, 3)])
    }

    @Test func deletingSeveralItemsAtOnce() {
        var p = project()
        let kept = p.timeline.clips[1].id
        p.remove([clip(p, 0), clip(p, 2), clip(p, 3), .title(p.titles[0].id), .music])
        #expect(p.timeline.clips.map(\.id) == [kept])
        #expect(p.titles.isEmpty)
        #expect(p.music == nil)
    }

    @Test func itemsThatAreGoneAreDropped() {
        var p = project()
        var s = TimelineSelection(p.allTimelineItems)
        #expect(s.count == 6)
        p.timeline.remove(p.timeline.clips[0].id)
        p.music = nil
        s.prune(to: p)
        #expect(s.count == 4)
        #expect(!s.contains(.music))
    }
}
