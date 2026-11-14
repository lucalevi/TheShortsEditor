import CoreGraphics
import CoreMedia
import Foundation
import Testing

@testable import EditorCore

private func seconds(_ s: Double) -> CMTime { CMTime(seconds: s, preferredTimescale: 600) }

private func project(seconds length: Int64) -> Project {
    var project = Project()
    let asset = MediaAsset(
        url: URL(fileURLWithPath: "/tmp/a.mov"), name: "a", duration: CMTime(value: length, timescale: 1),
        displaySize: CGSize(width: 1080, height: 1920), hasAudio: true)
    project.addAsset(asset)
    project.appendClip(of: asset.id)
    return project
}

struct TitleTests {
    @Test func addedAtThePlayheadForThreeSeconds() throws {
        var p = project(seconds: 10)
        let id = p.addTitle(at: seconds(2.01), text: "Hook")
        let title = try #require(p.title(id: id))
        #expect(title.start == CMTime(value: 60, timescale: 30))
        #expect(title.duration == CMTime(value: 3, timescale: 1))
        #expect(title.text == "Hook")
        #expect(title.verticalPosition == TitlePlacement.top.verticalPosition)
    }

    @Test func nearTheEndItStartsEarlierInstead() throws {
        var p = project(seconds: 10)
        let id = p.addTitle(at: seconds(9.5), text: "Bye")
        let title = try #require(p.title(id: id))
        #expect(title.start == CMTime(value: 7, timescale: 1))
        #expect(title.end == p.duration)
    }

    @Test func aShortShorterThanThreeSecondsGetsAShorterTitle() throws {
        var p = project(seconds: 2)
        let id = p.addTitle(at: .zero, text: "Hi")
        let title = try #require(p.title(id: id))
        #expect(title.duration == CMTime(value: 2, timescale: 1))
    }

    @Test func staysAtItsTimeWhenClipsChangeAndIsCutAtTheEnd() throws {
        var p = project(seconds: 10)
        let id = p.addTitle(at: seconds(6), text: "Late")
        p.timeline.split(at: seconds(5))
        p.timeline.remove(p.timeline.clips[1].id) // Short is now 5 s.
        #expect(p.title(id: id)?.start == CMTime(value: 6, timescale: 1))
        #expect(p.title(id: id)?.visibleRange(in: p) == nil)
        #expect(p.titlesOnScreen(at: seconds(4)).isEmpty)

        var q = project(seconds: 10)
        let early = q.addTitle(at: seconds(4), text: "Cut")
        q.timeline.split(at: seconds(5))
        q.timeline.remove(q.timeline.clips[1].id)
        let visible = try #require(q.title(id: early)?.visibleRange(in: q))
        #expect(visible.end == CMTime(value: 5, timescale: 1))
    }

    @Test func movingKeepsTheLengthAndStaysInside() throws {
        var p = project(seconds: 10)
        let id = p.addTitle(at: .zero, text: "Hook")
        p.moveTitle(id, to: seconds(4.01))
        #expect(p.title(id: id)?.start == CMTime(value: 120, timescale: 30))
        p.moveTitle(id, to: seconds(9))
        #expect(p.title(id: id)?.start == CMTime(value: 7, timescale: 1))
        p.moveTitle(id, to: seconds(-2))
        #expect(p.title(id: id)?.start == .zero)
        #expect(p.title(id: id)?.duration == CMTime(value: 3, timescale: 1))
    }

    @Test func lengthHasAMinimumAndStopsAtTheEnd() throws {
        var p = project(seconds: 10)
        let id = p.addTitle(at: seconds(5), text: "Hook")
        p.setTitleDuration(id, seconds(0.05))
        #expect(p.title(id: id)?.duration == TextOverlay.minimumDuration)
        p.setTitleDuration(id, seconds(20))
        #expect(p.title(id: id)?.end == p.duration)
    }

    @Test func onScreenOnlyDuringItsTime() {
        var p = project(seconds: 10)
        p.addTitle(at: seconds(1), text: "A")
        #expect(p.titlesOnScreen(at: seconds(0.5)).isEmpty)
        #expect(p.titlesOnScreen(at: seconds(1)).count == 1)
        #expect(p.titlesOnScreen(at: seconds(3.99)).count == 1)
        #expect(p.titlesOnScreen(at: seconds(4)).isEmpty)
    }

    @Test func placementsAreRecognisedOnlyWhenExact() {
        #expect(TitlePlacement(exactly: TitlePlacement.middle.verticalPosition) == .middle)
        #expect(TitlePlacement(exactly: 0.33) == nil)
    }

    @Test func survivesSavingAndLoading() throws {
        var p = project(seconds: 10)
        let id = p.addTitle(at: seconds(1), text: "Two\nlines")
        p.updateTitle(id) {
            $0.style = .marker; $0.entrance = .fade; $0.verticalPosition = 0.4
        }
        let decoded = try JSONDecoder().decode(Project.self, from: JSONEncoder().encode(p))
        #expect(decoded == p)
    }

    @Test func removing() {
        var p = project(seconds: 10)
        let id = p.addTitle(at: .zero, text: "A")
        p.removeTitle(id)
        #expect(p.titles.isEmpty)
    }
}
