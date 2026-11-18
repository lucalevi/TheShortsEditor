import AVFoundation
import EditorCore
import Foundation
import Testing

@testable import Shorts_Editor

/// Typing a title's words: saved as it goes, one undo step for the whole round of typing.
@Suite(.serialized)
struct TitleTextTests {
    @Test func typingSavedInPiecesIsOneUndoStep() async throws {
        let editor = TestEditor.withNewShort()
        await editor.importToTimeline([try await TestMedia.video(seconds: 4)])
        let model = editor.model
        editor.step { model.addTitle() }
        let id = try #require(model.selectedTitleID)
        // ⌘T puts the cursor in the title on the picture.
        #expect(model.titleEditedInViewer == id)

        // What TitleTextField does after each pause in typing.
        editor.step { model.editTitle(id, "Edit Title") { $0.text = "Big" } }
        // Later pauses register no undo (so they need no undo group open).
        model.editTitle(id, "Edit Title", registersUndo: false) { $0.text = "Big news" }
        model.editTitle(id, "Edit Title", registersUndo: false) { $0.text = "Big news today" }
        #expect(model.project.title(id: id)?.text == "Big news today")
        #expect(editor.undo.undoActionName == "Edit Title")

        editor.undo.undo()
        #expect(model.project.title(id: id)?.text == "Your title")
        #expect(editor.undo.undoActionName == "Add Title")
        editor.undo.redo()
        #expect(model.project.title(id: id)?.text == "Big news today")
    }

    @Test func returnOnASelectedTitleTypesOnThePicture() async throws {
        let editor = TestEditor.withNewShort()
        await editor.importToTimeline([try await TestMedia.video(seconds: 4)])
        let model = editor.model
        editor.step { model.addTitle() }
        let id = try #require(model.selectedTitleID)
        model.titleEditedInViewer = nil
        model.editTitleTextInViewer()
        #expect(model.titleEditedInViewer == id)
    }
}
