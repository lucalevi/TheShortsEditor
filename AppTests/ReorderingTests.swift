import EditorCore
import Foundation
import Testing

@testable import Shorts_Editor

/// Reordering clips (usability pass 2): dragging one of several selected clips moves them all,
/// Move Earlier / Move Later step the selection, each one undo step.
@Suite(.serialized)
struct ReorderingTests {
    @Test func selectedClipsMoveTogetherInOneStep() async throws {
        let editor = TestEditor.withNewShort()
        await editor.importToTimeline([
            try await TestMedia.video(seconds: 1), try await TestMedia.video(seconds: 1), try await TestMedia.video(seconds: 1),
        ])
        let model = editor.model
        let ids = model.project.timeline.clips.map(\.id)
        model.timelineSelection = TimelineSelection([.clip(ids[0]), .clip(ids[1])])

        // Dragging a selected clip moves every selected one; an unselected clip moves alone.
        #expect(model.clipsMovedWith(ids[0]) == [ids[0], ids[1]])
        #expect(model.clipsMovedWith(ids[2]) == [ids[2]])

        editor.step { model.moveClips(model.clipsMovedWith(ids[1]), to: 1) }
        #expect(model.project.timeline.clips.map(\.id) == [ids[2], ids[0], ids[1]])
        #expect(editor.undo.undoActionName == "Move Clips")
        editor.undo.undo()
        #expect(model.project.timeline.clips.map(\.id) == ids)

        // Dropping where they already are is no edit at all.
        editor.step { model.moveClips([ids[2]], to: 2) }
        #expect(!editor.undo.canUndo || editor.undo.undoActionName != "Move Clip")
    }

    @Test func moveEarlierAndLaterStepTheSelection() async throws {
        let editor = TestEditor.withNewShort()
        await editor.importToTimeline([
            try await TestMedia.video(seconds: 1), try await TestMedia.video(seconds: 1), try await TestMedia.video(seconds: 1),
        ])
        let model = editor.model
        let ids = model.project.timeline.clips.map(\.id)
        model.selectedClipID = ids[0]
        #expect(!model.canMoveSelectedClips(by: -1))
        #expect(model.canMoveSelectedClips(by: 1))

        editor.step { model.moveSelectedClips(by: 1) }
        #expect(model.project.timeline.clips.map(\.id) == [ids[1], ids[0], ids[2]])
        #expect(editor.undo.undoActionName == "Move Clip")
        // The moved clip stays selected, so the shortcut can be pressed again.
        #expect(model.selectedClipID == ids[0])
        editor.step { model.moveSelectedClips(by: 1) }
        #expect(model.project.timeline.clips.map(\.id) == [ids[1], ids[2], ids[0]])
        #expect(!model.canMoveSelectedClips(by: 1))
    }
}
