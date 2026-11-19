import AVFoundation
import EditorCore
import Foundation
import Testing

@testable import Shorts_Editor

/// Several Shorts in several windows (F27): each window has its own editor; they share the
/// library; a Short is open in one window at most.
@MainActor
@Suite(.serialized)
struct WindowsTests {
    /// A Short with one clip, saved into the library, and closed.
    private func savedShort(in app: AppState) async throws -> UUID {
        let maker = app.editor(for: UUID())
        let editor = TestEditor(model: maker)
        maker.newShort()
        await editor.importToTimeline([try await TestMedia.video(seconds: 2)])
        let id = try #require(maker.openShortID)
        editor.saveAndWait()
        maker.showHome()
        ProjectStore.finishSaving()
        return id
    }

    @Test func eachWindowHasItsOwnEditorAndTheyShareTheLibrary() {
        let app = AppState()
        let a = app.editor(for: UUID()), b = app.editor(for: UUID())
        #expect(a !== b)
        #expect(a.library === b.library)
        #expect(a.analysis === b.analysis)
        #expect(a.tasks !== b.tasks)
    }

    @Test func aShortOpenInOneWindowIsntOpenedInAnother() async throws {
        let app = AppState()
        let id = try await savedShort(in: app)
        let first = app.editor(for: UUID()), second = app.editor(for: UUID())
        first.openShort(id)
        #expect(first.openShortID == id)
        second.openShort(id)
        #expect(second.openShortID == nil)
        #expect(second.screen == .home)
        #expect(app.editor(showing: id) === first)
        // The library knows it's open, so it isn't deleted from under its window.
        #expect(app.library.openShortIDs() == [id])
    }

    @Test func renamingAShortOpenElsewhereGoesThroughItsWindow() async throws {
        let app = AppState()
        let id = try await savedShort(in: app)
        let first = app.editor(for: UUID()), second = app.editor(for: UUID())
        first.openShort(id)
        second.renameShort(id, to: "From the other window")
        #expect(first.openShortName == "From the other window")
    }

    @Test func closingAWindowSavesItsShortAndLetsItGo() async throws {
        let app = AppState()
        let windowID = UUID()
        let editor = app.editor(for: windowID)
        let test = TestEditor(model: editor)
        editor.newShort()
        await test.importToTimeline([try await TestMedia.video(seconds: 2)])
        let id = try #require(editor.openShortID)
        test.step { editor.splitAtPlayhead() }
        app.close(windowID)
        ProjectStore.finishSaving()
        #expect(app.allEditors.isEmpty)
        #expect(app.editor(showing: id) == nil)
        #expect(FileManager.default.fileExists(atPath: ProjectStore.fileURL(for: id).path))
    }

    /// Launched by opening files, SwiftUI takes the window's content down and puts it back: the
    /// window stays, and its editor must be known again once it is in front (files opened from
    /// Finder were lost when it wasn't).
    @Test func aWindowWhoseContentCameBackIsKnownAgain() {
        let app = AppState()
        let windowID = UUID()
        let editor = app.editor(for: windowID)
        app.didFocus(editor, window: windowID)
        app.close(windowID)
        #expect(app.current == nil && app.allEditors.isEmpty)

        app.didFocus(editor, window: windowID)
        #expect(app.current === editor)
        #expect(app.allEditors.count == 1)
        // A throwaway second window that comes and goes leaves the first one in front.
        let other = UUID()
        app.didFocus(app.editor(for: other), window: other)
        app.close(other)
        #expect(app.current === editor)
    }

    /// Quitting closes the windows; the app must still reopen the Short that was in front.
    @Test func quittingKeepsWhereTheUserWas() async throws {
        let app = AppState()
        let windowID = UUID()
        let editor = app.editor(for: windowID)
        app.didFocus(editor, window: windowID)
        let test = TestEditor(model: editor)
        editor.newShort()
        await test.importToTimeline([try await TestMedia.video(seconds: 2)])
        let id = try #require(editor.openShortID)
        app.prepareToQuit()
        app.close(windowID)
        ProjectStore.finishSaving()

        let next = TestEditor()
        next.model.restoreLastSession()
        #expect(next.model.openShortID == id)
    }
}
