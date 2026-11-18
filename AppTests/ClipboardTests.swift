import AVFoundation
import EditorCore
import Foundation
import Testing

@testable import Shorts_Editor

/// Cut, Copy, Paste and Duplicate of timeline items (⌘X, ⌘C, ⌘V, ⌘D), through the editor.
@Suite(.serialized)
struct AppClipboardTests {
    @Test func copiedTitlePastesAtThePlayheadAgainAndAgain() async throws {
        let editor = TestEditor.withNewShort()
        await editor.importToTimeline([try await TestMedia.video(seconds: 8)])
        let model = editor.model
        editor.step { model.addTitle() }
        let original = try #require(model.selectedTitleID)
        model.copyItems()
        #expect(model.canPasteItems)

        await editor.seek(to: CMTime(value: 2, timescale: 1))
        editor.step { model.pasteItems() }
        #expect(model.project.titles.count == 2)
        #expect(editor.undo.undoActionName == "Paste Title")
        // The copy is selected (and shown), not the original.
        let pasted = try #require(model.selectedTitleID)
        #expect(pasted != original)
        #expect(model.project.title(id: pasted)?.start == CMTime(value: 2, timescale: 1))

        editor.step { model.pasteItems() }
        #expect(model.project.titles.count == 3)
        editor.undo.undo()
        #expect(model.project.titles.count == 2)
    }

    @Test func cutRemovesAndDuplicatePutsACopyAfter() async throws {
        let editor = TestEditor.withNewShort()
        await editor.importToTimeline([try await TestMedia.video(seconds: 2), try await TestMedia.video(seconds: 1)])
        let model = editor.model
        let first = model.project.timeline.clips[0]

        model.selectedClipID = first.id
        editor.step { model.duplicateItems() }
        #expect(model.project.timeline.clips.count == 3)
        #expect(model.project.timeline.clips[1].assetID == first.assetID)
        #expect(model.selectedClipID == model.project.timeline.clips[1].id)
        #expect(editor.undo.undoActionName == "Duplicate Clip")

        editor.step { model.cutItems() }
        #expect(model.project.timeline.clips.count == 2)
        #expect(model.timelineSelection.isEmpty)
        #expect(editor.undo.undoActionName == "Cut Clip")
        #expect(model.canPasteItems)
    }

    @Test func theMusicAloneCannotBeCopied() async throws {
        let editor = TestEditor.withNewShort()
        await editor.importToTimeline([try await TestMedia.video(seconds: 2)])
        editor.model.selection = .music
        #expect(!editor.model.canCopyItems)
    }
}
