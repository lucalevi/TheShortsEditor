import AVFoundation
import EditorCore
import Foundation
import Testing

@testable import Shorts_Editor

/// Saving and opening Shorts through the app: autosave, the library, damaged files, missing
/// media and File ▸ Revert To. Everything happens in the test run's own library (`AppEnvironment`).
@Suite(.serialized)
struct SavingTests {
    @Test func theTestsUseALibraryOfTheirOwn() {
        #expect(AppEnvironment.isTesting)
        #expect(ProjectStore.appFolder.path.contains("/Shorts Editor Tests/"))
        #expect(AppEnvironment.defaults !== UserDefaults.standard)
    }

    @Test func anEditIsSavedASecondLaterAndOpensAgainAsItWas() async throws {
        let editor = TestEditor.withNewShort()
        await editor.importToTimeline([try await TestMedia.video(seconds: 2)])
        let model = editor.model
        await editor.seek(to: CMTime(value: 1, timescale: 1))
        editor.step { model.splitAtPlayhead() }
        let id = try #require(model.openShortID)
        let url = ProjectStore.fileURL(for: id)

        // Autosave: nothing is written at once, then the Short is there within a few seconds.
        await waitUntil("the Short is autosaved", seconds: 10) {
            ProjectStore.finishSaving()
            return (try? ProjectFile.decode(Data(contentsOf: url)))?.project.timeline.clips.count == 2
        }
        #expect(!model.hasUnsavedChanges)

        let saved = model.project, name = model.openShortName
        model.showHome()
        #expect(model.screen == .home)
        #expect(model.project.timeline.clips.isEmpty)
        model.openShort(id)
        #expect(model.screen == .editor)
        #expect(model.openShortName == name)
        #expect(model.project.timeline == saved.timeline)
        #expect(model.project.assets.map(\.id) == saved.assets.map(\.id))
        await model.waitUntilBuilt()
        #expect(model.missingAssets.isEmpty)
        // Opening isn't an edit: there is nothing to undo.
        #expect(!editor.undo.canUndo)
    }

    @Test func anEmptyShortIsNotKept() async throws {
        let editor = TestEditor.withNewShort()
        let id = try #require(editor.model.openShortID)
        editor.model.save()
        editor.model.showHome()
        ProjectStore.finishSaving()
        #expect(!FileManager.default.fileExists(atPath: ProjectStore.fileURL(for: id).path))
    }

    @Test func aDamagedShortRefusesToOpenAndIsNeverSavedOver() async throws {
        let editor = TestEditor()
        let id = UUID()
        let url = ProjectStore.fileURL(for: id)
        let damaged = Data(#"{"version": 8, "project": {"timeline": 12}}"#.utf8)
        try damaged.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        editor.model.openShort(id)
        #expect(editor.model.alert?.title == "This Short can't be opened")
        #expect(editor.model.openShortID != id)
        #expect(editor.model.screen == .home)
        editor.model.saveNow()
        ProjectStore.finishSaving()
        #expect(try Data(contentsOf: url) == damaged)
    }

    @Test func missingMediaIsReportedAndTheShortStillPlays() async throws {
        let editor = TestEditor.withNewShort()
        let kept = try await TestMedia.video(seconds: 1), gone = try await TestMedia.video(seconds: 2)
        await editor.importToTimeline([kept, gone])
        let model = editor.model
        let id = try #require(model.openShortID)
        let goneID = try #require(model.project.assets.first { $0.url.lastPathComponent == gone.lastPathComponent }?.id)
        editor.saveAndWait()
        model.showHome()

        try FileManager.default.removeItem(at: gone)
        model.openShort(id)
        await model.waitUntilBuilt()
        #expect(model.missingAssets == [goneID])
        #expect(model.missingAssetList.map(\.id) == [goneID])
        // Black and silence take its place: the Short keeps its length.
        let item = try #require(model.playback.player.currentItem)
        #expect(try await lasts(item.asset, seconds: 3))
        #expect(model.project.duration == CMTime(value: 3, timescale: 1))
    }

    @Test func revertingToABackupIsOneUndoableStep() async throws {
        let editor = TestEditor.withNewShort()
        await editor.importToTimeline([try await TestMedia.video(seconds: 2)])
        let model = editor.model
        let id = try #require(model.openShortID)
        editor.saveAndWait()
        let original = model.project
        // A backup of the Short as it is now, as on opening it.
        await withCheckedContinuation { done in ProjectStore.backUp(id, when: .always) { done.resume() } }
        let backup = try #require(ProjectStore.backups(for: id).first)

        await editor.seek(to: CMTime(value: 1, timescale: 1))
        editor.step { model.splitAtPlayhead() }
        let edited = model.project
        editor.step { model.revert(to: backup) }
        #expect(model.project.timeline == original.timeline)
        #expect(editor.undo.undoActionName == "Revert to \(backup.title)")
        editor.undo.undo()
        #expect(model.project == edited)
    }

    @Test func renamingTheOpenShortSavesTheName() async throws {
        let editor = TestEditor.withNewShort()
        await editor.importToTimeline([try await TestMedia.video(seconds: 1)])
        let model = editor.model
        let id = try #require(model.openShortID)
        model.shortName = "  Holiday in Rome\n"
        ProjectStore.finishSaving()
        #expect(model.openShortName == "Holiday in Rome")
        let file = try ProjectFile.decode(Data(contentsOf: ProjectStore.fileURL(for: id)))
        #expect(file.name == "Holiday in Rome")
    }

    @Test func goingHomeWhileFilesAreStillBeingReadAddsThemToNoOtherShort() async throws {
        let editor = TestEditor.withNewShort()
        let model = editor.model
        let url = try await TestMedia.video(seconds: 1)
        // No undo group is opened: the Short the files were for is gone, so no edit may be made
        // (one would register undo with no group open, which raises).
        model.importFiles([url], addToTimeline: true)
        model.showHome()
        await waitUntil("the import ends") { !model.isImporting }
        // The edit would come on the next turn of the main actor.
        try await Task.sleep(for: .milliseconds(300))
        await model.waitUntilBuilt()
        #expect(model.screen == .home)
        #expect(model.project.assets.isEmpty)
        #expect(model.project.timeline.clips.isEmpty)
    }
}

/// The home window's list of Shorts.
@Suite(.serialized)
struct LibraryTests {
    /// A saved Short with one clip, closed (the editor is back on the home window).
    private func savedShort(named name: String) async throws -> (TestEditor, UUID) {
        let editor = TestEditor.withNewShort()
        await editor.importToTimeline([try await TestMedia.video(seconds: 1)])
        editor.model.shortName = name
        let id = try #require(editor.model.openShortID)
        editor.model.showHome()
        ProjectStore.finishSaving()
        return (editor, id)
    }

    private func refreshed(_ library: LibraryModel, until condition: @escaping () -> Bool) async {
        library.refresh()
        await waitUntil("the library is read") { condition() }
    }

    @Test func theLibraryListsSavedShorts() async throws {
        let name = "Listed \(UUID().uuidString.prefix(6))"
        let (editor, id) = try await savedShort(named: name)
        let library = editor.model.library
        await refreshed(library) { library.shorts.contains { $0.id == id } }
        let entry = try #require(library.shorts.first { $0.id == id })
        #expect(entry.name == name)
        #expect(entry.clipCount == 1)
        #expect(entry.duration == CMTime(value: 1, timescale: 1))
    }

    @Test func duplicateAndRenameAShortThatIsNotOpen() async throws {
        let name = "Copied \(UUID().uuidString.prefix(6))"
        let (editor, id) = try await savedShort(named: name)
        let library = editor.model.library
        await refreshed(library) { library.shorts.contains { $0.id == id } }

        library.duplicate(id)
        await waitUntil("the copy is listed") { library.shorts.contains { $0.name == "\(name) copy" } }
        let copy = try #require(library.shorts.first { $0.name == "\(name) copy" })
        #expect(copy.id != id)
        #expect(copy.clipCount == 1)

        editor.model.renameShort(copy.id, to: "Renamed \(name)")
        await waitUntil("the new name is listed") { library.shorts.contains { $0.name == "Renamed \(name)" } }
        // The original is untouched.
        #expect(library.shorts.first { $0.id == id }?.name == name)
    }

    @Test func aNewShortGetsANameNoOtherShortHas() async throws {
        let editor = TestEditor()
        let library = editor.model.library
        await refreshed(library) { true }
        editor.model.newShort()
        #expect(!library.names.contains(editor.model.openShortName))
    }
}

/// The app reopens as it was left (F27): the Short, its playhead, the timeline zoom and the panel.
@MainActor
@Suite(.serialized)
struct SessionRestorationTests {
    @Test func theAppReopensTheShortWhereItWasLeft() async throws {
        let editor = TestEditor.withNewShort()
        await editor.importToTimeline([try await TestMedia.video(seconds: 3)])
        let model = editor.model
        let id = try #require(model.openShortID)
        await editor.seek(to: CMTime(value: 2, timescale: 1))
        model.timelineZoom = 120
        model.sidebar = .captions
        model.hasUnsavedChanges = true
        editor.saveAndWait()

        // Quit and open again.
        let next = TestEditor()
        next.model.restoreLastSession()
        #expect(next.model.screen == .editor)
        #expect(next.model.openShortID == id)
        #expect(next.model.playback.currentTime == CMTime(value: 2, timescale: 1).snappedToFrame())
        #expect(next.model.timelineZoom == 120)
        #expect(next.model.sidebar == .captions)

        // Back to All Shorts: the next launch starts there.
        next.model.showHome()
        let third = TestEditor()
        third.model.restoreLastSession()
        #expect(third.model.screen == .home)
    }

    @Test func filesOpenedFromFinderStartANewShortInstead() async throws {
        let editor = TestEditor.withNewShort()
        await editor.importToTimeline([try await TestMedia.video(seconds: 2)])
        editor.model.hasUnsavedChanges = true
        editor.saveAndWait()
        let next = TestEditor()
        next.model.restoreLastSession(reopening: false)
        #expect(next.model.screen == .home)
    }
}
