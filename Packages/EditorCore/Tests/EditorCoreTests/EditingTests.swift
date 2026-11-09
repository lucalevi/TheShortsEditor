import CoreGraphics
import CoreMedia
import Foundation
import Testing
@testable import EditorCore

private func seconds(_ s: Double) -> CMTime { CMTime(seconds: s, preferredTimescale: 600).snappedToFrame() }

private func video(_ name: String = "talk.mov", seconds: Int64 = 10, size: CGSize = CGSize(width: 1080, height: 1920)) -> MediaAsset {
    MediaAsset(url: URL(fileURLWithPath: "/tmp/\(name)"), name: name, duration: CMTime(value: seconds, timescale: 1), displaySize: size, hasAudio: true)
}

private func picture(_ name: String = "photo.jpg", size: CGSize = CGSize(width: 4000, height: 3000)) -> MediaAsset {
    .image(url: URL(fileURLWithPath: "/tmp/\(name)"), size: size)
}

/// A Short of one 10 s video, cut at 4 s: clips of 4 s and 6 s.
private func twoClips() -> Project {
    var p = Project()
    let id = p.addAsset(video())
    p.appendClip(of: id)
    p.timeline.split(at: seconds(4))
    return p
}

// MARK: - Placement

struct PlacementTests {
    @Test func identityLeavesTheFramingAlone() {
        #expect(Placement.identity.transform() == .identity)
    }

    @Test func scalesAroundTheMiddleOfTheCanvas() {
        let t = Placement(scale: 2).transform()
        let middle = CGPoint(x: 540, y: 960).applying(t)
        #expect(abs(middle.x - 540) < 0.001 && abs(middle.y - 960) < 0.001)
        let corner = CGPoint.zero.applying(t)
        #expect(abs(corner.x + 540) < 0.001 && abs(corner.y + 960) < 0.001)
    }

    @Test func offsetIsAFractionOfTheCanvas() {
        let moved = CGPoint(x: 540, y: 960).applying(Placement(offsetX: 0.1, offsetY: -0.25).transform())
        #expect(abs(moved.x - 648) < 0.001 && abs(moved.y - 480) < 0.001)
    }

    @Test func rotationIsClockwiseOnScreen() {
        // y points down, so a point to the right of the middle turns downwards.
        let p = CGPoint(x: 640, y: 960).applying(Placement(rotation: 90).transform())
        #expect(abs(p.x - 540) < 0.001 && abs(p.y - 1060) < 0.001)
    }

    @Test func normalizedKeepsScaleAndRotationInRange() {
        let p = Placement(scale: 99, rotation: 270).normalized
        #expect(p.scale == Placement.scaleRange.upperBound)
        #expect(p.rotation == -90)
    }

    @Test func zoomInterpolatesInProportion() {
        let half = Placement(scale: 1).interpolated(to: Placement(scale: 4), fraction: 0.5)
        #expect(abs(half.scale - 2) < 0.0001)
    }

    @Test func placedFrameMatchesTheTransform() {
        // Horizontal 1920×1080 shown whole: 1080 wide, 607.5 high, in the middle.
        let frame = Framing.fit.placedFrame(of: CGSize(width: 1920, height: 1080), placement: Placement(offsetY: 0.1, scale: 2))
        #expect(frame.size == CGSize(width: 2160, height: 1215))
        #expect(frame.center == CGPoint(x: 540, y: 1152))
    }

    @Test func coversTellsWhetherTheBackgroundShows() {
        let horizontal = CGSize(width: 1920, height: 1080)
        #expect(Framing.fill.placedFrame(of: horizontal, placement: .identity).covers())
        #expect(!Framing.fit.placedFrame(of: horizontal, placement: .identity).covers())
        #expect(!Framing.fill.placedFrame(of: CGSize(width: 1080, height: 1920), placement: Placement(scale: 0.5)).covers())
        #expect(!Framing.fill.placedFrame(of: CGSize(width: 1080, height: 1920), placement: Placement(rotation: 10)).covers())
        #expect(Framing.fill.placedFrame(of: CGSize(width: 1080, height: 1920), placement: Placement(scale: 2, rotation: 10)).covers())
    }
}

// MARK: - Keyframes and motion

struct MotionTests {
    private func clip(start: Double = 0, length: Double = 4) -> Clip {
        Clip(assetID: UUID(), sourceStart: seconds(start), duration: seconds(length))
    }

    @Test func withoutKeyframesTheFixedPlacementIsUsed() {
        var c = clip()
        c.placement = Placement(scale: 1.5)
        #expect(c.placement(atSourceTime: seconds(2)).scale == 1.5)
    }

    @Test func movesBetweenKeyframesAndHoldsOutside() {
        var c = clip()
        c.keyframes = [Keyframe(time: seconds(1), placement: Placement(offsetX: 0), easing: .linear),
                       Keyframe(time: seconds(3), placement: Placement(offsetX: 0.2), easing: .linear)]
        #expect(c.placement(atSourceTime: seconds(0)).offsetX == 0)
        #expect(abs(c.placement(atSourceTime: seconds(2)).offsetX - 0.1) < 0.0001)
        #expect(c.placement(atSourceTime: seconds(3.5)).offsetX == 0.2)
    }

    @Test func smoothEasingStartsSlowly() {
        var c = clip()
        c.keyframes = [Keyframe(time: seconds(0), placement: Placement(offsetX: 0)),
                       Keyframe(time: seconds(2), placement: Placement(offsetX: 1))]
        #expect(c.placement(atSourceTime: seconds(0.2)).offsetX < 0.1)
        #expect(abs(c.placement(atSourceTime: seconds(1)).offsetX - 0.5) < 0.0001)
    }

    @Test func setPlacementWithoutMotionChangesTheFixedPlacement() {
        var c = clip()
        c.setPlacement(Placement(scale: 1.3), atSourceTime: seconds(1))
        #expect(c.placement.scale == 1.3)
        #expect(c.keyframes.isEmpty)
    }

    @Test func setPlacementWithMotionAddsOrChangesAKeyframe() {
        var c = clip()
        c.addKeyframe(at: seconds(0))
        c.setPlacement(Placement(scale: 2), atSourceTime: seconds(2))
        #expect(c.keyframes.count == 2)
        c.setPlacement(Placement(scale: 3), atSourceTime: seconds(2))
        #expect(c.keyframes.count == 2)
        #expect(c.keyframes[1].placement.scale == 3)
    }

    @Test func removingTheLastKeyframeKeepsItsPlacement() {
        var c = clip()
        c.addKeyframe(at: seconds(1), placement: Placement(scale: 1.4))
        c.removeKeyframe(c.keyframes[0].id)
        #expect(!c.hasMotion)
        #expect(c.placement.scale == 1.4)
    }

    @Test func slowZoomRunsOverTheWholeClip() {
        var c = clip(start: 2, length: 4)
        c.applyMotion(.slowZoomIn, playheadSource: seconds(3))
        #expect(c.keyframes.first?.time == seconds(2))
        #expect(c.keyframes.last!.time >= seconds(5.9))
        #expect(abs(c.placement(atSourceTime: seconds(6)).scale - 1.15) < 0.001)
    }

    @Test func zoomAtPlayheadIsQuickAndStays() {
        var c = clip(start: 0, length: 4)
        c.applyMotion(.zoomAtPlayhead, playheadSource: seconds(1))
        #expect(c.placement(atSourceTime: seconds(0.9)).scale == 1)
        #expect(abs(c.placement(atSourceTime: seconds(3)).scale - 1.3) < 0.001)
        #expect(c.keyframes[1].time - c.keyframes[0].time == MotionPreset.quickZoomLength)
    }

    @Test func zoomAtPlayheadNearTheEndStartsEarlier() {
        var c = clip(start: 0, length: 4)
        c.applyMotion(.zoomAtPlayhead, playheadSource: seconds(3.95))
        #expect(c.keyframes[1].time <= seconds(4))
        #expect(c.keyframes[0].time < c.keyframes[1].time)
    }

    @Test func panNeverShowsTheEdges() {
        var c = clip()
        c.applyMotion(.panLeft, playheadSource: .zero)
        for kf in c.keyframes {
            let frame = Framing.fill.placedFrame(of: CGSize(width: 1080, height: 1920), placement: kf.placement)
            #expect(frame.covers())
        }
        #expect(c.keyframes[0].placement.offsetX > c.keyframes[1].placement.offsetX)
    }

    @Test func motionFollowsTheFootageAcrossASplit() {
        var p = Project()
        let id = p.addAsset(video())
        p.appendClip(of: id)
        p.timeline.clips[0].applyMotion(.slowZoomIn, playheadSource: .zero)
        let before = p.timeline.clips[0].placement(atSourceTime: seconds(6))
        p.timeline.split(at: seconds(5))
        // The second half shows source time 6 s one second in, with the same zoom as before.
        let second = p.timeline.clips[1]
        #expect(second.placement(atSourceTime: second.sourceTime(atOffset: seconds(1))) == before)
        #expect(second.keyframes == p.timeline.clips[0].keyframes)
    }

    @Test func punchInAlternatesWithinTheSameRecording() {
        var p = Project()
        let a = p.addAsset(video("a.mov"))
        let b = p.addAsset(video("b.mov"))
        p.appendClip(of: a)
        p.timeline.split(at: seconds(3))
        p.timeline.split(at: seconds(6))
        p.appendClip(of: b)
        p.punchInOnAlternateCuts()
        #expect(p.timeline.clips.map(\.placement.scale) == [1, Placement.punchInScale, 1, 1])
    }

    @Test func punchInLeavesMovingClipsAlone() {
        var p = twoClips()
        p.timeline.clips[1].applyMotion(.slowZoomOut, playheadSource: seconds(5))
        let keyframes = p.timeline.clips[1].keyframes
        p.punchInOnAlternateCuts()
        #expect(p.timeline.clips[1].keyframes == keyframes)
        #expect(p.timeline.clips[1].placement.scale == 1)
    }
}

// MARK: - Pictures

struct PictureTests {
    @Test func aPictureIsAVisualWithoutSound() {
        let photo = picture()
        #expect(photo.isImage && photo.hasVideo && !photo.hasAudio)
        #expect(photo.duration == MediaAsset.imageDuration)
        #expect(photo.defaultFraming == .fit)
        #expect(picture(size: CGSize(width: 1080, height: 1920)).defaultFraming == .fill)
    }

    @Test func aPictureIsAddedForAFewSeconds() {
        var p = Project()
        let id = p.addAsset(picture())
        p.appendClip(of: id)
        #expect(p.duration == MediaAsset.imageClipDuration)
    }

    @Test func aPictureCanBeMadeLongerFromEitherEdge() {
        var p = Project()
        let id = p.addAsset(picture())
        p.appendClip(of: id)
        let clipID = p.timeline.clips[0].id
        let r9 = p.trimClip(clipID, edge: .end, by: seconds(2))
        #expect(r9)
        let r10 = p.trimClip(clipID, edge: .start, by: seconds(-1))
        #expect(r10)
        #expect(p.duration == seconds(6))
        #expect(p.timeline.clips[0].sourceStart == .zero)
    }

    @Test func picturesAreNotTranscribed() {
        var p = Project()
        let id = p.addAsset(picture())
        p.appendClip(of: id)
        #expect(p.assetsNeedingTranscription(in: .english).isEmpty)
    }
}

// MARK: - Trimming

struct TrimTests {
    @Test func trimmingTheStartTakesOffTheBeginning() {
        var p = twoClips()
        let id = p.timeline.clips[1].id
        let r11 = p.trimClip(id, edge: .start, by: seconds(1))
        #expect(r11)
        #expect(p.timeline.clips[1].sourceStart == seconds(5))
        #expect(p.timeline.clips[1].duration == seconds(5))
        #expect(p.duration == seconds(9))
    }

    @Test func theStartCanComeBackButNotBeforeTheFile() {
        var p = twoClips()
        let id = p.timeline.clips[1].id
        p.trimClip(id, edge: .start, by: seconds(-10))
        #expect(p.timeline.clips[1].sourceStart == .zero)
        #expect(p.timeline.clips[1].duration == seconds(10))
    }

    @Test func theEndCannotGoPastTheFile() {
        var p = twoClips()
        let id = p.timeline.clips[0].id
        p.trimClip(id, edge: .end, by: seconds(20))
        #expect(p.timeline.clips[0].duration == seconds(10))
    }

    @Test func aClipNeverGetsShorterThanTheMinimum() {
        var p = twoClips()
        let id = p.timeline.clips[0].id
        p.trimClip(id, edge: .end, by: seconds(-20))
        #expect(p.timeline.clips[0].duration == Clip.minimumDuration)
        p.trimClip(id, edge: .start, by: seconds(20))
        #expect(p.timeline.clips[0].duration == Clip.minimumDuration)
    }

    @Test func nothingToDoIsReported() {
        var p = twoClips()
        let changed = p.trimClip(p.timeline.clips[0].id, edge: .start, by: seconds(-1))
        #expect(!changed)
    }

    @Test func trimStartToPlayheadRemovesWhatIsBefore() {
        var p = twoClips()
        let playhead = p.trimMainClip(at: seconds(5.5), removing: .start)
        #expect(playhead == seconds(4))
        #expect(p.timeline.clips[1].sourceStart == seconds(5.5))
        #expect(p.duration == seconds(8.5))
    }

    @Test func trimEndToPlayheadRemovesWhatIsAfter() {
        var p = twoClips()
        let playhead = p.trimMainClip(at: seconds(1), removing: .end)
        #expect(playhead == seconds(1))
        #expect(p.timeline.clips[0].duration == seconds(1))
        #expect(p.duration == seconds(7))
    }

    @Test func trimToPlayheadOnACutDoesNothing() {
        var p = twoClips()
        let playhead = p.trimMainClip(at: seconds(4), removing: .start)
        #expect(playhead == nil)
        #expect(p.duration == seconds(10))
    }
}

// MARK: - Overlays

struct OverlayTests {
    @Test func addedAtThePlayheadCoveringTheScreenWithoutSound() throws {
        var p = twoClips()
        let broll = p.addAsset(video("broll.mov", seconds: 8))
        let r1 = p.addOverlay(of: broll, at: seconds(2))
        let id = try #require(r1)
        let overlay = try #require(p.overlay(id: id))
        #expect(overlay.start == seconds(2))
        #expect(overlay.duration == Overlay.defaultVideoDuration)
        #expect(overlay.clip.isMuted && overlay.clip.framing == .fill)
    }

    @Test func nearTheEndItStartsEarlier() throws {
        var p = twoClips()
        let photo = p.addAsset(picture())
        let r2 = p.addOverlay(of: photo, at: seconds(9.5))
        let id = try #require(r2)
        #expect(p.overlay(id: id)?.end == seconds(10))
    }

    @Test func soundCannotBeAnOverlay() {
        var p = twoClips()
        let song = p.addAsset(MediaAsset(url: URL(fileURLWithPath: "/tmp/song.m4a"), name: "song", duration: seconds(30), displaySize: .zero, hasAudio: true, hasVideo: false))
        let id = p.addOverlay(of: song, at: .zero)
        #expect(id == nil)
    }

    @Test func movingStaysInsideTheShort() throws {
        var p = twoClips()
        let r3 = p.addOverlay(of: p.addAsset(picture()), at: .zero)
        let id = try #require(r3)
        p.moveOverlay(id, to: seconds(20))
        #expect(p.overlay(id: id)?.end == p.duration)
        p.moveOverlay(id, to: seconds(-3))
        #expect(p.overlay(id: id)?.start == .zero)
    }

    @Test func trimmingTheStartKeepsTheEndInPlace() throws {
        var p = twoClips()
        let r4 = p.addOverlay(of: p.addAsset(video("broll.mov", seconds: 8)), at: seconds(2))
        let id = try #require(r4)
        p.trimOverlay(id, edge: .start, by: seconds(1))
        let overlay = try #require(p.overlay(id: id))
        #expect(overlay.start == seconds(3) && overlay.end == seconds(6))
        #expect(overlay.clip.sourceStart == seconds(1))
        // Back out, but not before the start of the file.
        p.trimOverlay(id, edge: .start, by: seconds(-5))
        #expect(p.overlay(id: id)?.clip.sourceStart == .zero)
        #expect(p.overlay(id: id)?.start == seconds(2))
    }

    @Test func splittingMakesTwoPiecesOfTheSameFootage() throws {
        var p = twoClips()
        let r5 = p.addOverlay(of: p.addAsset(video("broll.mov", seconds: 8)), at: seconds(2))
        let id = try #require(r5)
        let split = p.splitOverlay(id, at: seconds(3))
        let second = try #require(split)
        #expect(p.overlay(id: id)?.duration == seconds(1))
        #expect(p.overlay(id: second)?.start == seconds(3))
        #expect(p.overlay(id: second)?.clip.sourceStart == seconds(1))
        let outside = p.splitOverlay(id, at: seconds(9))
        #expect(outside == nil)
    }

    @Test func overlaysCanBeSelectedAndDeleted() throws {
        var p = twoClips()
        let r6 = p.addOverlay(of: p.addAsset(picture()), at: .zero)
        let id = try #require(r6)
        #expect(p.allTimelineItems.contains(.overlay(id)))
        #expect(p.timelineItems(overlapping: CMTimeRange(start: .zero, duration: seconds(1)), in: [.overlays]) == [.overlay(id)])
        p.remove([.overlay(id)])
        #expect(p.overlays.isEmpty)
    }

    @Test func overlayMediaIsKeptWhenSaving() throws {
        var p = twoClips()
        let photo = p.addAsset(picture())
        p.addOverlay(of: photo, at: .zero)
        #expect(p.usedAssets.contains { $0.id == photo })
    }

    @Test func onlyOverlaysOnScreenAreReturned() throws {
        var p = twoClips()
        let r7 = p.addOverlay(of: p.addAsset(picture()), at: seconds(2))
        let id = try #require(r7)
        #expect(p.overlaysOnScreen(at: seconds(1)).isEmpty)
        #expect(p.overlaysOnScreen(at: seconds(3)).map(\.id) == [id])
    }

    @Test func sourceTimeOfAnyClip() throws {
        var p = twoClips()
        let r8 = p.addOverlay(of: p.addAsset(video("broll.mov", seconds: 8)), at: seconds(2))
        let id = try #require(r8)
        #expect(p.sourceTime(ofClip: id, at: seconds(3)) == seconds(1))
        #expect(p.sourceTime(ofClip: p.timeline.clips[1].id, at: seconds(5)) == seconds(5))
    }
}

// MARK: - Snapping and rows

struct SnappingTests {
    @Test func targetsIncludeCutsTitlesOverlaysAndThePlayhead() {
        var p = twoClips()
        p.addTitle(at: seconds(1), text: "Hook")
        let targets = Snapping.targets(in: p, playhead: seconds(7))
        for time in [seconds(0), seconds(4), seconds(10), seconds(1), seconds(7)] {
            #expect(targets.contains(time))
        }
    }

    @Test func aDraggedItemDoesNotStickToItself() {
        var p = twoClips()
        let id = p.addTitle(at: seconds(1), text: "Hook")
        let targets = Snapping.targets(in: p, playhead: nil, excluding: [.title(id)])
        #expect(!targets.contains(seconds(1)))
    }

    @Test func snapsOnlyWhenClose() {
        let targets = [seconds(4)]
        #expect(Snapping.snap(seconds(4.1), to: targets, tolerance: seconds(0.2)) == seconds(4))
        #expect(Snapping.snap(seconds(4.5), to: targets, tolerance: seconds(0.2)) == nil)
    }

    @Test func aBlockSticksByWhicheverEdgeIsCloser() {
        // A 2 s block starting at 1.9 ends at 3.9: its end is nearer the cut at 4.
        let start = Snapping.snapBlock(start: seconds(1.9), duration: seconds(2), to: [seconds(1.7), seconds(4)], tolerance: seconds(0.3))
        #expect(start == seconds(2))
    }

    @Test func overlappingThingsGoOnSeparateRows() {
        let rows = LanePacking.rows([
            (id: "a", range: CMTimeRange(start: seconds(0), duration: seconds(3))),
            (id: "b", range: CMTimeRange(start: seconds(1), duration: seconds(3))),
            (id: "c", range: CMTimeRange(start: seconds(3), duration: seconds(1))),
        ])
        #expect(rows == ["a": 0, "b": 1, "c": 0])
        #expect(LanePacking.count(rows) == 2)
        #expect(LanePacking.count([String: Int]()) == 1)
    }
}

// MARK: - Saving

struct EditingFileTests {
    @Test func everythingNewIsSavedAndRead() throws {
        var p = twoClips()
        p.timeline.clips[0].placement = Placement(offsetX: 0.1, scale: 1.2, rotation: 5)
        p.timeline.clips[0].background = .black
        p.timeline.clips[1].applyMotion(.slowZoomIn, playheadSource: seconds(5))
        let photo = p.addAsset(picture())
        p.addOverlay(of: photo, at: seconds(1))
        let read = try ProjectFile.decode(ProjectFile(project: p).encoded()).project
        #expect(read == p)
        #expect(read.asset(id: photo)?.isImage == true)
    }

    @Test func olderFilesStillOpen() throws {
        // What version 1 saved: no overlays, no placement, motion or background on clips.
        let json = """
        {"version":1,"bookmarks":[],"project":{"assets":[],"timeline":{"clips":[{"id":"\(UUID())","assetID":"\(UUID())",
        "sourceStart":{"value":0,"timescale":1},"duration":{"value":2,"timescale":1},"framing":"fit","volume":1,"isMuted":false}]},
        "transcripts":[],"captions":{"isVisible":false,"style":"bold","verticalPosition":0.6},"titles":[]}}
        """
        let project = try ProjectFile.decode(Data(json.utf8)).project
        #expect(project.overlays.isEmpty)
        #expect(project.timeline.clips[0].placement == .identity)
        #expect(project.timeline.clips[0].background == .black)
    }
}
