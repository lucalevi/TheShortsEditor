import AVFoundation
import EditorCore
import Foundation
import Testing

@testable import Shorts_Editor

/// The playhead and the player: seeking, stepping, skimming and playing a stretch.
@Suite(.serialized)
struct PlaybackTests {
    private func editorWithClip(seconds: Int = 2) async throws -> TestEditor {
        let editor = TestEditor.withNewShort()
        await editor.importToTimeline([try await TestMedia.video(seconds: seconds)])
        return editor
    }

    @Test func seekingLandsOnWholeFramesInsideTheShort() async throws {
        let playback = try await editorWithClip().model.playback
        playback.seek(to: CMTime(seconds: 0.51, preferredTimescale: 600))
        #expect(playback.currentTime == CMTime(value: 15, timescale: 30))
        playback.seek(to: CMTime(value: 10, timescale: 1))
        #expect(playback.currentTime == CMTime(value: 2, timescale: 1))
        playback.seek(to: CMTime(value: -1, timescale: 1))
        #expect(playback.currentTime == .zero)
    }

    @Test func steppingMovesWholeFramesAndPauses() async throws {
        let playback = try await editorWithClip().model.playback
        playback.seek(to: CMTime(value: 1, timescale: 1))
        playback.step(frames: 3)
        #expect(playback.currentTime == CMTime(value: 33, timescale: 30))
        playback.step(frames: -6)
        #expect(playback.currentTime == CMTime(value: 27, timescale: 30))
        #expect(playback.player.rate == 0)
    }

    @Test func skimmingShowsAMomentWithoutMovingThePlayhead() async throws {
        let editor = try await editorWithClip()
        let playback = editor.model.playback
        await editor.seek(to: CMTime(value: 1, timescale: 2))
        let skimming = playback.skimsTimeline
        playback.skimsTimeline = true
        defer { playback.skimsTimeline = skimming }

        playback.skim(to: CMTime(value: 3, timescale: 2))
        #expect(playback.skimTime == CMTime(value: 3, timescale: 2))
        #expect(playback.currentTime == CMTime(value: 1, timescale: 2))
        await waitUntil("the viewer shows the skimmed moment") {
            playback.player.currentTime().snappedToFrame() == CMTime(value: 3, timescale: 2)
        }
        // The pointer leaves: the viewer goes back to the playhead.
        playback.skim(to: nil)
        #expect(playback.skimTime == nil)
        await waitUntil("the viewer is back at the playhead") {
            playback.player.currentTime().snappedToFrame() == CMTime(value: 1, timescale: 2)
        }
        #expect(playback.currentTime == CMTime(value: 1, timescale: 2))
    }

    @Test func skimmingCanBeTurnedOff() async throws {
        let playback = try await editorWithClip().model.playback
        let skimming = playback.skimsTimeline
        defer { playback.skimsTimeline = skimming }
        playback.skimsTimeline = false
        playback.skim(to: CMTime(value: 1, timescale: 1))
        #expect(playback.skimTime == nil)
    }

    @Test func aRebuildKeepsThePlayhead() async throws {
        let editor = try await editorWithClip()
        let model = editor.model
        await editor.seek(to: CMTime(value: 1, timescale: 1))
        editor.step { model.setClipVolume(model.project.timeline.clips[0].id, 0.5) }
        await model.waitUntilBuilt()
        #expect(model.currentTime == CMTime(value: 1, timescale: 1))
    }

    @Test func playingAStretchStopsAtItsEnd() async throws {
        let editor = try await editorWithClip()
        let playback = editor.model.playback
        let looping = playback.loopsPlayback
        playback.loopsPlayback = false
        defer { playback.loopsPlayback = looping }
        let stretch = CMTimeRange(start: CMTime(value: 6, timescale: 30), duration: CMTime(value: 9, timescale: 30))
        playback.play(stretch)
        await waitUntil("the stretch has played", seconds: 10) { playback.playRange == nil && playback.player.rate == 0 }
        #expect(playback.currentTime == stretch.end)
    }

    @Test func openingAnotherShortPutsThePlayheadAtTheStart() async throws {
        let editor = try await editorWithClip()
        await editor.seek(to: CMTime(value: 1, timescale: 1))
        editor.model.newShort()
        #expect(editor.model.currentTime == .zero)
        #expect(editor.model.playback.skimTime == nil)
    }
}
