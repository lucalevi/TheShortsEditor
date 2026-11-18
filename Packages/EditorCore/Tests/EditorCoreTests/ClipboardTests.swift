import CoreGraphics
import CoreMedia
import Foundation
import Testing

@testable import EditorCore

private func seconds(_ s: Double) -> CMTime { CMTime(seconds: s, preferredTimescale: 600) }

private let video = MediaAsset(
    url: URL(fileURLWithPath: "/tmp/v.mov"), name: "v", duration: CMTime(value: 5, timescale: 1),
    displaySize: CGSize(width: 1080, height: 1920), hasAudio: true)
private let effect = MediaAsset(
    url: URL(fileURLWithPath: "/tmp/whoosh.m4a"), name: "whoosh", duration: CMTime(value: 1, timescale: 1),
    displaySize: .zero, hasAudio: true, hasVideo: false)

/// Three 5-second clips, a styled title from 2 to 6 s, B-roll at 8 s and a sound at 11 s.
private func project() -> Project {
    var project = Project()
    project.addAsset(video)
    project.addAsset(effect)
    for _ in 0..<3 { project.appendClip(of: video.id) }
    let title = project.addTitle(at: seconds(2), text: "Hook")
    project.updateTitle(title) { $0.look.size = 1.5 }
    project.addOverlay(of: video.id, at: seconds(8))
    project.addSound(of: effect.id, at: seconds(11))
    return project
}

struct ClipboardTests {
    @Test func aTitlePastesAtThePlayheadWithItsLook() throws {
        var p = project()
        let title = p.titles[0]
        let board = p.copy([.title(title.id)])
        #expect(board.count == 1)

        let pasted = p.paste(board, at: seconds(9))
        #expect(p.titles.count == 2)
        let copy = try #require(p.titles.last)
        #expect(pasted == [.title(copy.id)])
        #expect(copy.id != title.id)
        #expect(copy.text == "Hook")
        #expect(copy.look == title.look)
        #expect(copy.start == seconds(9).snappedToFrame())
        #expect(copy.duration == title.duration)
    }

    @Test func theSameClipboardPastesAgainAndAgain() {
        var p = project()
        let board = p.copy([.title(p.titles[0].id)])
        p.paste(board, at: seconds(1))
        p.paste(board, at: seconds(4))
        p.paste(board, at: seconds(7))
        #expect(p.titles.count == 4)
        #expect(Set(p.titles.map(\.id)).count == 4)
    }

    @Test func pastingNearTheEndKeepsTheItemInsideTheShort() throws {
        var p = project()
        let board = p.copy([.title(p.titles[0].id)])
        p.paste(board, at: seconds(14))
        let copy = try #require(p.titles.last)
        #expect(copy.start + copy.duration <= p.duration)
    }

    @Test func clipsAreInsertedAtThePlayheadSplittingTheClipThere() {
        var p = project()
        let first = p.timeline.clips[0]
        let board = p.copy([.clip(first.id)])
        let pasted = p.paste(board, at: seconds(7))
        // 0–5 first, 5–7 half of the second, the copy, 7–10 the rest, then the third.
        #expect(p.timeline.clips.count == 5)
        #expect(p.duration == seconds(20).snappedToFrame())
        let copy = p.timeline.clips[2]
        #expect(pasted == [.clip(copy.id)])
        #expect(copy.id != first.id)
        #expect(copy.sourceStart == first.sourceStart && copy.duration == first.duration)
    }

    @Test func aGroupKeepsItsLayout() throws {
        var p = project()
        let items: Set<TimelineItem> = [.title(p.titles[0].id), .overlay(p.overlays[0].id)]
        let board = p.copy(items)
        p.paste(board, at: seconds(1))
        let title = try #require(p.titles.last)
        let overlay = try #require(p.overlays.last)
        // The title was at 2 s and the B-roll at 8 s: 6 s apart, still.
        #expect(title.start == seconds(1).snappedToFrame())
        #expect(overlay.start == seconds(7).snappedToFrame())
    }

    @Test func cutItemsStillPaste() {
        var p = project()
        let items: Set<TimelineItem> = [.sound(p.sounds[0].id)]
        let board = p.copy(items)
        p.remove(items)
        #expect(p.sounds.isEmpty)
        p.paste(board, at: seconds(3))
        #expect(p.sounds.count == 1)
        #expect(p.sounds[0].start == seconds(3).snappedToFrame())
    }

    @Test func theMusicIsNotCopied() {
        let p = project()
        #expect(p.copy([.music]).isEmpty)
    }

    @Test func duplicatePutsTheCopyRightAfter() throws {
        var p = project()
        let title = p.titles[0]
        let pasted = p.duplicate([.title(title.id)])
        let copy = try #require(p.titles.last)
        #expect(pasted == [.title(copy.id)])
        #expect(copy.start == title.start + title.duration)

        let clip = p.timeline.clips[1]
        p.duplicate([.clip(clip.id)])
        #expect(p.timeline.clips.count == 4)
        #expect(p.timeline.clips[2].sourceStart == clip.sourceStart && p.timeline.clips[2].id != clip.id)
    }

    @Test func pastingIntoAnotherShortBringsTheFiles() throws {
        let p = project()
        let board = p.copy([.clip(p.timeline.clips[0].id), .sound(p.sounds[0].id)])
        var other = Project()
        other.paste(board, at: .zero)
        #expect(Set(other.assets.map(\.id)) == [video.id, effect.id])
        #expect(other.timeline.clips.count == 1)
        #expect(other.sounds.count == 1)

        // A Short that already has the file (imported on its own, so with another id) uses it.
        var third = Project()
        let same = MediaAsset(url: video.url, name: "v", duration: video.duration, displaySize: video.displaySize, hasAudio: true)
        third.addAsset(same)
        third.paste(p.copy([.clip(p.timeline.clips[0].id)]), at: .zero)
        #expect(third.assets.count == 1)
        #expect(third.timeline.clips[0].assetID == same.id)
    }

    @Test func aDetachedSoundFollowsItsClipOrBecomesItsOwn() throws {
        var p = project()
        let clip = p.timeline.clips[0]
        let detached = p.detachSound(of: clip.id)
        let soundID = try #require(detached)

        // Copied alone, the clip plays its own sound again.
        let clipOnly = p.copy([.clip(clip.id)])
        #expect(clipOnly.clips[0].soundDetached == false)

        // Copied alone, the sound belongs to no clip.
        let soundOnly = p.copy([.sound(soundID)])
        #expect(soundOnly.sounds[0].detachedFrom == nil)

        // Copied together, the pasted sound belongs to the pasted clip.
        p.paste(p.copy([.clip(clip.id), .sound(soundID)]), at: seconds(15))
        let newClip = try #require(p.timeline.clips.last)
        let newSound = try #require(p.sounds.last)
        #expect(newClip.soundDetached)
        #expect(newSound.detachedFrom == newClip.id)
    }
}
