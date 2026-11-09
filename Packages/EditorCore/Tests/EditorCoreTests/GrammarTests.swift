import CoreGraphics
import CoreMedia
import Foundation
import Testing
@testable import EditorCore

private func t(_ s: Double) -> CMTime { CMTime(seconds: s, preferredTimescale: 600).snappedToFrame() }

private func video(_ name: String, seconds: Int64 = 10) -> MediaAsset {
    MediaAsset(url: URL(fileURLWithPath: "/tmp/\(name)"), name: name, duration: CMTime(value: seconds, timescale: 1),
               displaySize: CGSize(width: 1080, height: 1920), hasAudio: true)
}

/// Clips A (10 s) and B (10 s), back to back.
private func twoFiles() -> (Project, MediaAsset.ID, MediaAsset.ID) {
    var p = Project()
    let a = p.addAsset(video("a.mov"))
    let b = p.addAsset(video("b.mov"))
    p.appendClip(of: a)
    p.appendClip(of: b)
    return (p, a, b)
}

private func lengths(_ p: Project) -> [Double] { p.timeline.clips.map { ($0.duration.seconds * 10).rounded() / 10 } }

struct PuttingMediaInTests {
    @Test func insertCutsTheClipAtTheTime() {
        var (p, a, b) = twoFiles()
        let id = p.insertClip(of: b, part: CMTimeRange(start: t(2), duration: t(3)), at: t(4))
        #expect(lengths(p) == [4, 3, 6, 10])
        #expect(p.timeline.clips[1].id == id && p.timeline.clips[1].sourceStart == t(2))
        #expect(p.timeline.clips[2].assetID == a && p.timeline.clips[2].sourceStart == t(4))
    }

    @Test func insertOnACutGoesBeforeTheNextClip() {
        var (p, _, b) = twoFiles()
        p.insertClip(of: b, part: CMTimeRange(start: .zero, duration: t(1)), at: t(10))
        #expect(lengths(p) == [10, 1, 10])
    }

    @Test func insertAfterTheEndAppends() {
        var (p, a, _) = twoFiles()
        p.insertClip(of: a, at: t(30))
        #expect(lengths(p) == [10, 10, 10])
    }

    @Test func appendAPartOfAFile() {
        var (p, a, _) = twoFiles()
        p.appendClip(of: a, part: CMTimeRange(start: t(8), duration: t(5)))
        #expect(p.timeline.clips.last?.sourceStart == t(8))
        #expect(p.timeline.clips.last?.duration == t(2))
    }

    @Test func replaceModes() {
        var (p, a, _) = twoFiles()
        let c = p.addAsset(video("c.mov", seconds: 20))
        p.timeline.split(at: t(4)) // A: 4 + 6
        let middle = p.timeline.clips[1].id
        var whole = p
        whole.replaceClip(middle, with: c, mode: .replace)
        #expect(lengths(whole) == [4, 20, 10])
        var fromStart = p
        fromStart.replaceClip(middle, with: c, mode: .replaceFromStart)
        #expect(lengths(fromStart) == [4, 6, 10] && fromStart.timeline.clips[1].sourceStart == .zero)
        var fromEnd = p
        fromEnd.replaceClip(middle, with: c, mode: .replaceFromEnd)
        #expect(fromEnd.timeline.clips[1].sourceStart == t(14))
        #expect(fromEnd.timeline.clips[1].assetID == c)
        _ = a
    }

    @Test func dropAsSplitScreenAndCorner() {
        var (p, _, b) = twoFiles()
        let split = p.addOverlay(of: b, part: nil, at: t(1), as: .splitScreen)
        let corner = p.addOverlay(of: b, part: CMTimeRange(start: t(5), duration: t(2)), at: t(3), as: .pictureInPicture)
        #expect(p.overlay(id: split!)?.layout == .top)
        #expect(p.overlay(id: corner!)?.clip.placement.scale ?? 1 < 1)
        #expect(p.overlay(id: corner!)?.clip.sourceStart == t(5) && p.overlay(id: corner!)?.duration == t(2))
    }

    @Test func usedPartsAreMerged() {
        var (p, a, _) = twoFiles()
        p.trimClip(p.timeline.clips[0].id, edge: .end, by: t(-6))   // A 0–4
        p.appendClip(of: a, part: CMTimeRange(start: t(3), duration: t(3)))  // A 3–6
        p.addOverlay(of: a, at: .zero)  // A 0–4 again
        #expect(p.usedParts(of: a) == [CMTimeRange(start: .zero, end: t(6))])
    }

    @Test func editPointsAreTheCutsAndItemEdges() {
        var (p, _, _) = twoFiles()
        p.addTitle(at: t(2), text: "Hi")
        #expect(p.editPoints == [t(0), t(2), t(5), t(10), t(20)])
        #expect(p.editPoint(from: t(2), forward: true) == t(5))
        #expect(p.editPoint(from: t(2), forward: false) == .zero)
        #expect(p.editPoint(from: t(20), forward: true) == nil)
    }
}

struct RangeTests {
    @Test func removeARangeAcrossTwoClips() {
        var (p, _, _) = twoFiles()
        p.removeRange(CMTimeRange(start: t(8), end: t(12)))
        #expect(lengths(p) == [8, 8])
        #expect(p.timeline.clips[1].sourceStart == t(2))
    }

    @Test func trimToRangeKeepsOnlyThePartOfTheTouchedClip() {
        var (p, _, _) = twoFiles()
        p.trimToRange(CMTimeRange(start: t(2), end: t(5)))
        #expect(lengths(p) == [3, 10])
        #expect(p.timeline.clips[0].sourceStart == t(2))
    }

    @Test func trimToRangeAcrossACut() {
        var (p, _, _) = twoFiles()
        p.trimToRange(CMTimeRange(start: t(8), end: t(12)))
        #expect(lengths(p) == [2, 2])
    }

    @Test func speedOnARangeOnly() {
        var (p, _, _) = twoFiles()
        p.setSpeed(2, in: CMTimeRange(start: t(2), end: t(6)))
        #expect(lengths(p) == [2, 2, 4, 10])
        #expect(p.timeline.clips[1].speed == 2)
        #expect(p.timeline.clips[2].speed == 1)
    }

    @Test func volumeOnARangeFadesAtItsEdges() {
        var (p, _, _) = twoFiles()
        p.setVolume(0.2, in: CMTimeRange(start: t(2), end: t(6)))
        #expect(p.timeline.clips.map(\.volume) == [1, 0.2, 1, 1])
        #expect(p.timeline.clips[1].continues(p.timeline.clips[0]))
        #expect(!p.timeline.clips[3].continues(p.timeline.clips[2]))
    }

    @Test func clipRangeIsTheClipUnderTheTime() {
        let (p, _, _) = twoFiles()
        #expect(p.clipRange(at: t(12)) == CMTimeRange(start: t(10), end: t(20)))
    }
}

struct FollowingTests {
    /// A title at 12 s (2 s into clip B) and a B-roll at 3 s (into A).
    private func withItems() -> (Project, TextOverlay.ID, Clip.ID) {
        var (p, a, _) = twoFiles()
        let title = p.addTitle(at: t(12), text: "Hook")
        let overlay = p.addOverlay(of: a, at: t(3))!
        return (p, title, overlay)
    }

    private func edited(_ p: Project, _ edit: (inout Project) -> Void) -> Project {
        var new = p
        edit(&new)
        new.followClips(from: p)
        return new
    }

    @Test func movingAClipCarriesItsItems() {
        let (p, title, overlay) = withItems()
        let b = p.timeline.clips[1].id
        let new = edited(p) { $0.timeline.move(b, to: 0) }
        #expect(new.title(id: title)?.start == t(2))
        #expect(new.overlay(id: overlay)?.start == t(13))
    }

    @Test func deletingAnEarlierClipPullsThemAlong() {
        let (p, title, overlay) = withItems()
        let a = p.timeline.clips[0].id
        let new = edited(p) { $0.timeline.remove(a) }
        #expect(new.title(id: title)?.start == t(2))
        // Its own clip is gone: it stays at its time.
        #expect(new.overlay(id: overlay)?.start == t(3))
    }

    @Test func splittingChangesNothing() {
        let (p, title, overlay) = withItems()
        let new = edited(p) { $0.timeline.split(at: t(12)); $0.timeline.split(at: t(2)) }
        #expect(new.title(id: title)?.start == t(12))
        #expect(new.overlay(id: overlay)?.start == t(3))
    }

    @Test func speedingUpTheClipMovesItsItem() {
        let (p, title, _) = withItems()
        let a = p.timeline.clips[0].id
        let b = p.timeline.clips[1].id
        let new = edited(p) { $0.setSpeed(2, for: a); $0.setSpeed(2, for: b) }
        // A is now 5 s; 2 s into B's source is 1 s into the faster B.
        #expect(new.title(id: title)?.start == t(6))
    }

    @Test func trimmingAwayItsMomentPutsItAtTheNewEdge() {
        let (p, title, _) = withItems()
        let b = p.timeline.clips[1].id
        let new = edited(p) { $0.trimClip(b, edge: .start, by: t(5)) }
        #expect(new.title(id: title)?.start == t(10))
    }

    @Test func removingAPauseBeforeItMovesItEarlier() {
        let (p, title, _) = withItems()
        let b = p.timeline.clips[1].id
        let plan = SilencePlan(sourceCuts: [b: [CMTimeRange(start: t(0.5), end: t(1.5))]], timelineCuts: [])
        let new = edited(p) { $0.apply(plan) }
        #expect(new.title(id: title)?.start == t(11))
    }

    @Test func anItemTheEditMovesItselfStaysWhereItWasPut() {
        let (p, title, _) = withItems()
        let a = p.timeline.clips[0].id
        let new = edited(p) { $0.timeline.remove(a); $0.moveTitle(title, to: t(7)) }
        #expect(new.title(id: title)?.start == t(7))
    }

    @Test func anItemNotFollowingStaysAtItsTime() {
        var (p, title, _) = withItems()
        p.setFollowsClip(false, for: .title(title))
        let a = p.timeline.clips[0].id
        let new = edited(p) { $0.timeline.remove(a) }
        #expect(new.title(id: title)?.start == t(12))
    }

    @Test func insertingBeforeItPushesItLater() {
        let (p, title, _) = withItems()
        let b = p.timeline.clips[1].assetID
        let new = edited(p) { $0.insertClip(of: b, part: CMTimeRange(start: t(8), duration: t(2)), at: t(5)) }
        #expect(new.title(id: title)?.start == t(14))
    }

    @Test func savedFilesWithoutTheSettingFollow() throws {
        let (p, title, overlay) = withItems()
        var json = String(decoding: try JSONEncoder().encode(p), as: UTF8.self)
        json = json.replacingOccurrences(of: ",\"followsClip\":true", with: "").replacingOccurrences(of: "\"followsClip\":true,", with: "")
        #expect(!json.contains("followsClip"))
        let read = try JSONDecoder().decode(Project.self, from: Data(json.utf8))
        #expect(read.title(id: title)?.followsClip == true && read.overlay(id: overlay)?.followsClip == true)
    }
}

struct SettingsTests {
    @Test func pasteMotionPutsItAtTheSamePlaceInTheOtherClip() {
        var (p, _, _) = twoFiles()
        let a = p.timeline.clips[0].id
        let b = p.timeline.clips[1].id
        p.updateAnyClip(a) { $0.applyMotion(.slowZoomIn, playheadSource: .zero) }
        p.timeline.clips[1].sourceStart = t(0)
        p.trimClip(b, edge: .start, by: t(2))   // B shows 2–10
        let source = p.anyClip(id: a)!
        p.pasteSettings([.motion], from: source, to: b)
        let pasted = p.anyClip(id: b)!
        #expect(pasted.keyframes.count == 1 || pasted.keyframes.allSatisfy { $0.time >= t(2) })
        #expect(pasted.hasMotion)
    }

    @Test func pasteSoundAndSpeed() {
        var (p, _, _) = twoFiles()
        let a = p.timeline.clips[0].id
        let b = p.timeline.clips[1].id
        p.updateAnyClip(a) { $0.volume = 1.5; $0.cleansVoice = true }
        p.setSpeed(2, for: a)
        p.pasteSettings([.sound, .speed], from: p.anyClip(id: a)!, to: b)
        let pasted = p.anyClip(id: b)!
        #expect(pasted.volume == 1.5 && pasted.cleansVoice && pasted.speed == 2 && pasted.duration == t(5))
    }

    @Test func resetPutsBackWhatANewClipHas() {
        var (p, _, _) = twoFiles()
        let a = p.timeline.clips[0].id
        p.updateAnyClip(a) { $0.placement.scale = 1.2; $0.volume = 0.5; $0.isMuted = true }
        p.setSpeed(0.5, for: a)
        #expect(p.changedSettings(of: a) == [.picture, .sound, .speed])
        p.resetSettings(Set(SettingsKind.allCases), of: a)
        #expect(p.changedSettings(of: a).isEmpty)
        #expect(p.anyClip(id: a)?.duration == t(10))
    }

    @Test func pasteTitleDesignKeepsTheWords() {
        var p = twoFiles().0
        let one = p.addTitle(at: .zero, text: "One")
        let two = p.addTitle(at: t(5), text: "Two")
        p.updateTitle(one) { $0.applyStyle(.marker); $0.verticalPosition = 0.6 }
        p.pasteTitleDesign(from: p.title(id: one)!, to: two)
        #expect(p.title(id: two)?.style == .marker && p.title(id: two)?.verticalPosition == 0.6 && p.title(id: two)?.text == "Two")
    }
}
