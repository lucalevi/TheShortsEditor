import AVFoundation
import EditorCore
import Foundation
import Testing

@testable import Shorts_Editor

/// The editor's own paths: importing, edits through `apply`, undo and redo with their names, and
/// the player being rebuilt after each change.
@Suite(.serialized)
struct EditingTests {
    @Test func importPutsClipsOnTheTimelineAndBuildsThePlayer() async throws {
        let editor = TestEditor.withNewShort()
        let first = try await TestMedia.video(seconds: 2), second = try await TestMedia.video(seconds: 1)
        await editor.importToTimeline([first, second])

        let model = editor.model
        #expect(model.project.assets.count == 2)
        #expect(model.project.timeline.clips.count == 2)
        #expect(model.project.duration == CMTime(value: 3, timescale: 1))
        #expect(model.missingAssets.isEmpty)
        // The player shows the Short as built.
        let item = try #require(model.playback.player.currentItem)
        #expect(try await lasts(item.asset, seconds: 3))
        #expect(model.playback.duration == model.project.duration)
        #expect(editor.undo.undoActionName == "Add to Timeline")
    }

    @Test func importOfAFileTheAppCannotUseSaysSoAndAddsNothing() async throws {
        let editor = TestEditor.withNewShort()
        let text = TestMedia.folder.appending(path: "notes-\(UUID().uuidString).txt")
        try Data("not a video".utf8).write(to: text)
        editor.model.importFiles([text], addToTimeline: true)
        await waitUntil("the import ends") { !editor.model.isImporting && editor.model.alert != nil }
        #expect(editor.model.alert?.title == "This file can't be used")
        #expect(editor.model.project.assets.isEmpty)
    }

    @Test func splitUndoRedoKeepTheTimelineAndSayWhatTheyDo() async throws {
        let editor = TestEditor.withNewShort()
        await editor.importToTimeline([try await TestMedia.video(seconds: 2)])
        let model = editor.model
        let before = model.project

        await editor.seek(to: CMTime(value: 1, timescale: 1))
        editor.step { model.splitAtPlayhead() }
        #expect(model.project.timeline.clips.count == 2)
        #expect(model.project.duration == before.duration)
        #expect(editor.undo.undoActionName == "Split Clip")
        // The second half is selected, as after a split in the app.
        #expect(model.selectedClipID == model.project.timeline.clips[1].id)
        let split = model.project

        editor.undo.undo()
        #expect(model.project == before)
        #expect(editor.undo.redoActionName == "Split Clip")
        editor.undo.redo()
        #expect(model.project == split)
        await model.waitUntilBuilt()
        #expect(model.playback.duration == before.duration)
    }

    @Test func splitAtTheVeryStartDoesNothing() async throws {
        let editor = TestEditor.withNewShort()
        await editor.importToTimeline([try await TestMedia.video(seconds: 1)])
        let before = editor.model.project
        await editor.seek(to: .zero)
        editor.step { editor.model.splitAtPlayhead() }
        #expect(editor.model.project == before)
        #expect(editor.undo.undoActionName != "Split Clip")
    }

    @Test func deletingTheSelectionIsOneStep() async throws {
        let editor = TestEditor.withNewShort()
        await editor.importToTimeline([try await TestMedia.video(seconds: 1), try await TestMedia.video(seconds: 1), try await TestMedia.video(seconds: 1)])
        let model = editor.model
        let clips = model.project.timeline.clips
        model.timelineSelection = TimelineSelection([.clip(clips[0].id), .clip(clips[2].id)])
        editor.step { model.deleteSelection() }
        #expect(model.project.timeline.clips.map(\.id) == [clips[1].id])
        #expect(editor.undo.undoActionName == "Delete 2 Items")
        #expect(model.selection == nil)
        editor.undo.undo()
        #expect(model.project.timeline.clips.map(\.id) == clips.map(\.id))
    }

    @Test func anEditThatChangesNothingIsNoUndoStep() async throws {
        let editor = TestEditor.withNewShort()
        await editor.importToTimeline([try await TestMedia.video(seconds: 1)])
        let clip = try #require(editor.model.project.timeline.clips.first)
        let before = editor.model.project
        editor.step { editor.model.setFraming(clip.framing, for: clip.id) }
        #expect(editor.model.project == before)
        #expect(editor.undo.undoActionName != "Change Framing")
    }

    @Test func titlesFollowTheirClipWhenAClipBeforeThemGoes() async throws {
        let editor = TestEditor.withNewShort()
        await editor.importToTimeline([try await TestMedia.video(seconds: 2), try await TestMedia.video(seconds: 6)])
        let model = editor.model
        // A title on the second clip, a second into it.
        await editor.seek(to: CMTime(value: 3, timescale: 1))
        editor.step { model.addTitle() }
        let titleID = try #require(model.selectedTitleID)
        let start = try #require(model.project.title(id: titleID)).start
        #expect(start == CMTime(value: 3, timescale: 1))

        let firstClip = model.project.timeline.clips[0].id
        model.selectedClipID = firstClip
        editor.step { model.deleteSelection() }
        // `apply` moves the title with its clip, two seconds earlier.
        #expect(model.project.title(id: titleID)?.start == CMTime(value: 1, timescale: 1))
        editor.undo.undo()
        #expect(model.project.title(id: titleID)?.start == start)
    }

    @Test func removingMediaTakesItsClipsOffTheTimeline() async throws {
        let editor = TestEditor.withNewShort()
        let kept = try await TestMedia.video(seconds: 1), removed = try await TestMedia.video(seconds: 1)
        await editor.importToTimeline([kept, removed])
        let model = editor.model
        let removedID = try #require(model.project.assets.first { $0.url.lastPathComponent == removed.lastPathComponent }?.id)
        editor.step { model.removeAssets([removedID]) }
        #expect(model.project.assets.count == 1)
        #expect(model.project.timeline.clips.allSatisfy { $0.assetID != removedID })
        #expect(editor.undo.undoActionName == "Remove Media")
    }

    @Test func manyQuickEditsEndOnTheLastOne() async throws {
        // Each edit cancels the rebuild of the one before: the player must end up showing the last.
        let editor = TestEditor.withNewShort()
        await editor.importToTimeline([try await TestMedia.video(seconds: 2)])
        let model = editor.model
        for frame in stride(from: 50, to: 5, by: -5) {
            await editor.seek(to: CMTime(value: Int64(frame), timescale: 30))
            editor.step { model.splitAtPlayhead() }
        }
        let count = model.project.timeline.clips.count
        #expect(count == 10)
        await model.waitUntilBuilt()
        let item = try #require(model.playback.player.currentItem)
        #expect(try await lasts(item.asset, seconds: 2))
        for _ in 0..<9 { editor.undo.undo() }
        #expect(model.project.timeline.clips.count == 1)
    }
}

/// The asset's length is `seconds`, give or take a frame (a composition's tracks can end a hair apart).
func lasts(_ asset: AVAsset, seconds: Double) async throws -> Bool {
    abs(try await asset.load(.duration).seconds - seconds) < 1.0 / 30
}

/// Export through the editor: the checks, then the movie file.
@Suite(.serialized)
struct ExportTests {
    @Test func exportWritesTheShortAsAnMP4() async throws {
        let editor = TestEditor.withNewShort()
        await editor.importToTimeline([try await TestMedia.video(seconds: 1), try await TestMedia.video(seconds: 1)])
        let model = editor.model
        model.beginExport()
        await waitUntil("the checks are done") {
            if case .review = model.exportPhase { true } else { false }
        }
        let url = TestMedia.folder.appending(path: model.suggestedExportName)
        model.export(to: url)
        await waitUntil("the export is written", seconds: 60) {
            if case .finished = model.exportPhase { true } else { false }
        }
        #expect(model.exportPhase == .finished(url))
        #expect(!model.tasks.isRunning(.export))
        let asset = AVURLAsset(url: url)
        #expect(try await lasts(asset, seconds: 2))
        let video = try #require(try await asset.loadTracks(withMediaType: .video).first)
        #expect(try await video.load(.naturalSize) == CGSize(width: 1080, height: 1920))
        #expect(try await !asset.loadTracks(withMediaType: .audio).isEmpty)
        model.endExport()
        #expect(model.exportPhase == nil)
    }

    @Test func stoppingAnExportLeavesTheSheetAndNoJob() async throws {
        let editor = TestEditor.withNewShort()
        await editor.importToTimeline([try await TestMedia.video(seconds: 2)])
        let model = editor.model
        model.beginExport()
        await waitUntil("the checks are done") {
            if case .review = model.exportPhase { true } else { false }
        }
        model.export(to: TestMedia.folder.appending(path: "stopped-\(UUID().uuidString).mp4"))
        model.endExport()
        #expect(model.exportPhase == nil)
        await waitUntil("the export job ends") { !model.tasks.isRunning(.export) }
        #expect(model.exportPhase == nil)
    }

    @Test func editingWhileAnExportRunsDoesNotChangeTheFile() async throws {
        // The export works from the project as it was when it started.
        let editor = TestEditor.withNewShort()
        await editor.importToTimeline([try await TestMedia.video(seconds: 2)])
        let model = editor.model
        model.beginExport()
        await waitUntil("the checks are done") {
            if case .review = model.exportPhase { true } else { false }
        }
        let url = TestMedia.folder.appending(path: "during-\(UUID().uuidString).mp4")
        model.export(to: url)
        await editor.seek(to: CMTime(value: 1, timescale: 1))
        editor.step { model.splitAtPlayhead() }
        let second = model.project.timeline.clips[1].id
        model.selectedClipID = second
        editor.step { model.deleteSelection() }
        #expect(model.project.duration == CMTime(value: 1, timescale: 1))
        await waitUntil("the export is written", seconds: 60) {
            if case .finished = model.exportPhase { true } else { false }
        }
        #expect(try await lasts(AVURLAsset(url: url), seconds: 2))
    }
}
