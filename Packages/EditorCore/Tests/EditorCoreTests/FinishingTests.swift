import CoreGraphics
import CoreMedia
import Foundation
import Testing
@testable import EditorCore

private func t(_ s: Double) -> CMTime { CMTime(seconds: s, preferredTimescale: 600).snappedToFrame() }

private func video(_ name: String, seconds: Int64 = 10, size: CGSize = CGSize(width: 1080, height: 1920), frameRate: Double? = nil) -> MediaAsset {
    MediaAsset(url: URL(fileURLWithPath: "/tmp/\(name)"), name: name, duration: CMTime(value: seconds, timescale: 1),
               displaySize: size, hasAudio: true, frameRate: frameRate)
}

private func picture(_ name: String, size: CGSize) -> MediaAsset {
    MediaAsset.image(url: URL(fileURLWithPath: "/tmp/\(name)"), size: size)
}

struct NewClipSettingsTests {
    @Test func picturesTakeTheLengthFromSettings() {
        var p = Project()
        let id = p.addAsset(picture("a.jpg", size: CGSize(width: 3000, height: 4000)))
        NewClipSettings.$current.withValue(NewClipSettings(pictureLength: t(5))) {
            p.appendClip(of: id)
            _ = p.addOverlay(of: id, at: .zero)
        }
        #expect(p.timeline.clips[0].duration == t(5))
        #expect(p.overlays[0].duration == t(5))
        // Without settings, the usual three seconds.
        p.appendClip(of: id)
        #expect(p.timeline.clips[1].duration == t(3))
    }

    @Test func pictureLengthIsKeptInRange() {
        #expect(NewClipSettings(pictureLength: t(60)).pictureLength == t(10))
        #expect(NewClipSettings(pictureLength: t(0.1)).pictureLength == t(0.5))
    }

    @Test func picturePlacement() {
        let wide = picture("wide.jpg", size: CGSize(width: 4000, height: 3000))
        for (placement, framing) in [(NewClipSettings.PicturePlacement.automatic, Framing.fit), (.fill, .fill), (.fit, .fit), (.slowZoom, .fill)] {
            var p = Project()
            let id = p.addAsset(wide)
            NewClipSettings.$current.withValue(NewClipSettings(picturePlacement: placement)) { p.appendClip(of: id) }
            #expect(p.timeline.clips[0].framing == framing, "\(placement)")
            #expect(p.timeline.clips[0].hasMotion == (placement == .slowZoom))
        }
    }

    @Test func picturePlacementLeavesVideosAlone() {
        var p = Project()
        let id = p.addAsset(video("wide.mov", size: CGSize(width: 1920, height: 1080)))
        NewClipSettings.$current.withValue(NewClipSettings(picturePlacement: .slowZoom)) { p.appendClip(of: id) }
        #expect(p.timeline.clips[0].framing == .fit)
        #expect(!p.timeline.clips[0].hasMotion)
    }

    @Test func automaticSlowMotionCanBeTurnedOff() {
        var p = Project()
        let id = p.addAsset(video("slomo.mov", frameRate: 120))
        p.appendClip(of: id)
        NewClipSettings.$current.withValue(NewClipSettings(slowsDownSlowMotion: false)) { p.appendClip(of: id) }
        #expect(p.timeline.clips[0].speed == 0.25)
        #expect(p.timeline.clips[1].speed == 1)
        #expect(p.timeline.clips[1].duration == t(10))
    }
}

struct MarkerTests {
    private func twoClips() -> Project {
        var p = Project()
        let a = p.addAsset(video("a.mov"))
        let b = p.addAsset(video("b.mov"))
        p.appendClip(of: a)
        p.appendClip(of: b)
        return p
    }

    @Test func addingNamesAndSortsMarkers() {
        var p = twoClips()
        let second = p.addMarker(at: t(12.01))
        let first = p.addMarker(at: t(3))
        #expect(p.markers.map(\.id) == [first, second])
        #expect(p.marker(id: second)?.name == "Marker 1")
        #expect(p.marker(id: first)?.name == "Marker 2")
        #expect(p.marker(id: second)?.time == t(12))
        // The same time again gives the marker already there.
        #expect(p.addMarker(at: t(3)) == first)
        #expect(p.markers.count == 2)
        // Past the end, it goes on the end.
        let late = p.addMarker(at: t(99))
        #expect(p.marker(id: late)?.time == t(20))
    }

    @Test func renameMoveAndRemove() {
        var p = twoClips()
        let id = p.addMarker(at: t(5))
        p.renameMarker(id, to: "  Beat drop  ")
        #expect(p.marker(id: id)?.name == "Beat drop")
        p.renameMarker(id, to: "   ")
        #expect(p.marker(id: id)?.name == "Beat drop")
        p.moveMarker(id, to: t(7.5))
        #expect(p.marker(id: id)?.time == t(7.5))
        p.removeMarker(id)
        #expect(p.markers.isEmpty)
    }

    @Test func markersFollowTheirClip() {
        var p = twoClips()
        let id = p.addMarker(at: t(14))  // 4 s into the second clip
        let old = p
        p.timeline.remove(p.timeline.clips[0].id)
        p.followClips(from: old)
        #expect(p.marker(id: id)?.time == t(4))
        // Switched off, it keeps its time.
        var q = twoClips()
        let fixed = q.addMarker(at: t(14))
        q.markers[0].followsClip = false
        let before = q
        q.timeline.remove(q.timeline.clips[0].id)
        q.followClips(from: before)
        #expect(q.marker(id: fixed)?.time == t(14))
    }

    @Test func anItemOnAFreezeFrameStaysThereWhenAnotherClipOfTheFileChanges() {
        var p = Project()
        let a = p.addAsset(video("a.mov"))
        p.appendClip(of: a, part: CMTimeRange(start: .zero, duration: t(2)))
        p.appendClip(of: a, part: CMTimeRange(start: t(4), duration: t(2)))
        // A 3 s freeze frame of the file's picture at 4.5 s, between the two clips.
        var freeze = p.timeline.clips[1].piece(sourceStart: t(4.5), duration: t(3))
        freeze.isFrozen = true
        p.timeline.clips.insert(freeze, at: 1)
        let id = p.addMarker(at: t(3))  // 1 s into the freeze frame
        let old = p
        // Showing another part of the last clip, which now contains 4.5 s of the file.
        p.slipClip(p.timeline.clips[2].id, by: t(-1))
        p.followClips(from: old)
        #expect(p.marker(id: id)?.time == t(3))
        // Moving the freeze frame first takes the marker along.
        let before = p
        p.timeline.move(p.timeline.clips[1].id, to: 0)
        p.followClips(from: before)
        #expect(p.marker(id: id)?.time == t(1))
    }

    @Test func edgesSnapToMarkersAndEditPointsStopThere() {
        var p = twoClips()
        let id = p.addMarker(at: t(6))
        #expect(Snapping.targets(in: p, playhead: nil).contains(t(6)))
        #expect(!Snapping.targets(in: p, playhead: nil, excludingMarker: id).contains(t(6)))
        #expect(p.editPoint(from: t(2), forward: true) == t(6))
        #expect(p.marker(from: t(2), forward: true)?.id == id)
        #expect(p.marker(from: t(6), forward: true) == nil)
        #expect(p.marker(from: t(9), forward: false)?.id == id)
    }

    @Test func markersAreSavedAndReadBack() throws {
        var p = twoClips()
        p.addMarker(at: t(2.5), name: "Hook ends")
        let read = try JSONDecoder().decode(Project.self, from: JSONEncoder().encode(p))
        #expect(read.markers == p.markers)
        #expect(ProjectFile.currentVersion >= 6)
    }
}

struct SlipTests {
    @Test func slidingShowsAnotherStretchAtTheSameLength() {
        var p = Project()
        let a = p.addAsset(video("a.mov"))
        p.appendClip(of: a, part: CMTimeRange(start: t(2), duration: t(4)))
        let id = p.timeline.clips[0].id
        let slid = p.slipClip(id, by: t(1.5))
        #expect(slid)
        #expect(p.timeline.clips[0].sourceStart == t(3.5))
        #expect(p.timeline.clips[0].duration == t(4))
        // It stops at the end of the file…
        p.slipClip(id, by: t(100))
        #expect(p.timeline.clips[0].sourceStart == t(6))
        let further = p.slipClip(id, by: t(1))
        #expect(!further)
        // …and at its start.
        p.slipClip(id, by: t(-100))
        #expect(p.timeline.clips[0].sourceStart == .zero)
        #expect(p.slipLimits(of: id) == CMTimeRange(start: .zero, end: t(6)))
    }

    @Test func motionAndVolumePointsMoveWithTheFootage() {
        var p = Project()
        let a = p.addAsset(video("a.mov"))
        p.appendClip(of: a, part: CMTimeRange(start: t(2), duration: t(4)))
        let id = p.timeline.clips[0].id
        p.updateAnyClip(id) { clip in
            clip.applyMotion(.slowZoomIn, playheadSource: t(2))
            clip.volumeKeys = [VolumeKey(time: t(3), level: 0.5)]
        }
        let before = p.timeline.clips[0]
        p.slipClip(id, by: t(2))
        let after = p.timeline.clips[0]
        #expect(after.keyframes.map { after.timelineOffset(ofSourceTime: $0.time) } == before.keyframes.map { before.timelineOffset(ofSourceTime: $0.time) })
        #expect(after.volumeKeys[0].time == t(5))
    }

    @Test func picturesAndFreezeFramesDontSlide() {
        var p = Project()
        let photo = p.addAsset(picture("a.jpg", size: CGSize(width: 100, height: 100)))
        p.appendClip(of: photo)
        let slid = p.slipClip(p.timeline.clips[0].id, by: t(1))
        #expect(!slid)
        #expect(p.slipLimits(of: p.timeline.clips[0].id) == nil)
    }
}

struct ExportEstimateTests {
    @Test func sizeFollowsLengthAndBitRate() {
        let bytes = ExportEstimate.bytes(duration: t(60), videoBitRate: 12_000_000, audioBitRate: 320_000)
        // 12.32 Mbit/s for a minute is 92.4 MB, plus a little.
        #expect(bytes > 92_000_000 && bytes < 94_000_000)
        #expect(ExportEstimate.description(bytes: bytes) == "about 95 MB")
        #expect(ExportEstimate.description(bytes: 4_560_000) == "about \(4.6.formatted(.number.precision(.fractionLength(1)))) MB")
        #expect(ExportEstimate.description(bytes: 400_000) == "under 1 MB")
    }
}
