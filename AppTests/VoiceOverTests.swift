import AVFoundation
import EditorCore
import Foundation
import Testing

@testable import Shorts_Editor

/// What happens to a voice-over once it is recorded: it is offered for Listen / Retake / Delete /
/// Keep, a retake replaces it in one undo step, and Delete leaves nothing behind. (The microphone
/// itself can't be used in tests: a written file stands in for the recording.)
@Suite(.serialized)
struct VoiceOverTests {
    /// Puts `url` on the timeline as a recording, as stopping the recorder does, in one undo step.
    private func place(_ url: URL, at seconds: Int64, in editor: TestEditor, replacing: Clip.ID? = nil) async {
        editor.undo.beginUndoGrouping()
        await editor.model.placeVoiceOver(url, at: CMTime(value: seconds, timescale: 1), replacing: replacing)
        editor.undo.endUndoGrouping()
    }

    @Test func aTakeIsNamedSelectedAndOfferedForReview() async throws {
        let editor = TestEditor.withNewShort()
        await editor.importToTimeline([try await TestMedia.video(seconds: 6)])
        let model = editor.model

        await place(try await TestMedia.video(seconds: 2), at: 1, in: editor)
        let review = try #require(model.reviewedVoiceOver)
        #expect(model.project.asset(id: review.sound.clip.assetID)?.name == "Voice-over 1")
        #expect(review.sound.isVoiceOver && review.sound.start == CMTime(value: 1, timescale: 1))
        #expect(editor.undo.undoActionName == "Record Voice-Over")
        // The test tone is clearly heard.
        await waitUntil("the take is measured") { model.audioLevels[review.sound.clip.assetID] != nil }
        #expect(model.reviewedVoiceOver?.take.isQuiet == false)

        // Clicking anything else keeps it: the review is over.
        model.selection = nil
        #expect(model.reviewedVoiceOver == nil)
        model.selection = .sound(review.sound.id)
        #expect(model.reviewedVoiceOver != nil)
        model.keepVoiceOver()
        #expect(model.reviewedVoiceOver == nil && model.project.sounds.count == 1)

        // The next recording is number 2.
        await place(try await TestMedia.video(seconds: 1), at: 4, in: editor)
        let second = try #require(model.reviewedVoiceOver)
        #expect(model.project.asset(id: second.sound.clip.assetID)?.name == "Voice-over 2")
    }

    @Test func aRetakeReplacesTheTakeInOneUndoStep() async throws {
        let editor = TestEditor.withNewShort()
        await editor.importToTimeline([try await TestMedia.video(seconds: 6)])
        let model = editor.model
        await place(try await TestMedia.video(seconds: 2), at: 2, in: editor)
        let first = try #require(model.reviewedVoiceOver)
        let assetsBefore = model.project.assets.count

        await place(try await TestMedia.video(seconds: 3), at: 2, in: editor, replacing: first.sound.id)
        let retake = try #require(model.reviewedVoiceOver)
        #expect(model.project.sounds.count == 1)
        #expect(retake.sound.start == first.sound.start && retake.sound.duration == CMTime(value: 3, timescale: 1))
        // Keeps its name, and the thrown-away take leaves Media.
        #expect(model.project.asset(id: retake.sound.clip.assetID)?.name == "Voice-over 1")
        #expect(model.project.asset(id: first.sound.clip.assetID) == nil && model.project.assets.count == assetsBefore)
        #expect(editor.undo.undoActionName == "Retake Voice-Over")

        editor.undo.undo()
        #expect(model.project.sounds.map(\.id) == [first.sound.id])
    }

    @Test func deleteThrowsTheTakeAway() async throws {
        let editor = TestEditor.withNewShort()
        await editor.importToTimeline([try await TestMedia.video(seconds: 4)])
        let model = editor.model
        let assetsBefore = model.project.assets.count
        await place(try await TestMedia.video(seconds: 1), at: 0, in: editor)
        #expect(model.reviewedVoiceOver != nil)

        editor.step { model.deleteVoiceOver() }
        #expect(model.project.sounds.isEmpty && model.project.assets.count == assetsBefore)
        #expect(model.reviewedVoiceOver == nil)
        #expect(editor.undo.undoActionName == "Delete Voice-Over")
    }
}
