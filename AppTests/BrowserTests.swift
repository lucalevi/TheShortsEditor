import AVFoundation
import EditorCore
import Foundation
import Testing

@testable import Shorts_Editor

/// The browser on the left: its tabs, and tiles added with a click or dropped on the timeline.
@Suite(.serialized)
struct BrowserTests {
    @Test func dragPayloadsComeBackAsTheyLeft() {
        let drops: [BrowserDrop] = [
            .title(.marker), .transition(.dissolve), .effect(.glitch), .filter(.noir), .filter(nil), .music(.chill),
        ]
        for drop in drops { #expect(BrowserDrop(text: drop.text) == drop) }
        // Ordinary text dragged in (from another app) is not a tile.
        #expect(BrowserDrop(text: "Hello") == nil)
        #expect(BrowserDrop(text: "shorts-editor:title:nonsense") == nil)
    }

    @Test func everyPanelBelongsToATab() {
        for sidebar in EditorModel.Sidebar.allCases where sidebar != .storyboard {
            let tab = BrowserTab(sidebar)
            #expect(tab != nil)
            // A tab opens on a panel that is its own.
            if let tab { #expect(BrowserTab(tab.sidebar) == tab) }
        }
        #expect(BrowserTab(.photos) == .media)
        #expect(BrowserTab(.script) == .captions)
    }

    @Test func aTitleTileAddsAStyledTitleInOneStep() async throws {
        let editor = TestEditor.withNewShort()
        await editor.importToTimeline([try await TestMedia.video(seconds: 4)])
        let model = editor.model
        editor.step { model.addTitle(style: .marker) }
        let id = try #require(model.selectedTitleID)
        #expect(model.project.title(id: id)?.style == .marker)
        #expect(editor.undo.undoActionName == "Add Title")
        editor.undo.undo()
        #expect(model.project.titles.isEmpty)
    }

    @Test func droppedTilesGoWhereTheyAreDropped() async throws {
        let editor = TestEditor.withNewShort()
        await editor.importToTimeline([try await TestMedia.video(seconds: 2), try await TestMedia.video(seconds: 2)])
        let model = editor.model
        let first = model.project.timeline.clips[0].id, second = model.project.timeline.clips[1].id

        // A transition dropped near the cut goes on it.
        editor.step { model.dropBrowserItem(.transition(.dissolve), at: CMTime(value: 19, timescale: 10)) }
        #expect(model.project.transition(after: first)?.kind == .dissolve)

        // An effect or filter goes on the clip it was dropped on.
        editor.step { model.dropBrowserItem(.effect(.flash), at: CMTime(value: 3, timescale: 1)) }
        #expect(model.project.anyClip(id: second)?.effects.map(\.kind) == [.flash])
        editor.step { model.dropBrowserItem(.filter(.noir), at: CMTime(value: 1, timescale: 2)) }
        #expect(model.project.anyClip(id: first)?.look.filter?.filter == .noir)

        // A title is added where it was dropped (kept inside this 4-second Short).
        editor.step { model.dropBrowserItem(.title(.bold), at: CMTime(value: 1, timescale: 1)) }
        let title = try #require(model.project.titles.first)
        #expect(title.style == .bold)
        #expect(title.start <= CMTime(value: 1, timescale: 1))
    }
}
