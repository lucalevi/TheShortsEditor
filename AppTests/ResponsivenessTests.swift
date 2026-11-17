import AVFoundation
import Darwin
import EditorCore
import Foundation
import RenderEngine
import Testing

@testable import Shorts_Editor

/// Phase 6 (responsiveness) through the app itself: a whole edit on the biggest Short, from the
/// change to the viewer showing it (F11, F12); undo is limited and memory stays bounded over a
/// long session (F13).
@MainActor
@Suite(.serialized)
struct ResponsivenessTests {
    /// 3 minutes in 60 clips from three real (small) videos, every video transcribed, with karaoke
    /// captions, 10 B-roll clips and 5 titles.
    private static func loadBigShort(into editor: TestEditor) async throws {
        var videos: [MediaAsset] = []
        for _ in 0..<3 {
            videos.append(try await MediaProbe.probe(try await TestMedia.video(seconds: 12)))
        }
        editor.step {
            editor.model.apply("Big Short") { project in
                let ids = videos.map { project.addAsset($0) }
                for index in 0..<60 {
                    let start = CMTime(value: Int64((index / 3) % 4) * 3, timescale: 1)
                    _ = project.appendClip(of: ids[index % 3], part: CMTimeRange(start: start, duration: CMTime(value: 3, timescale: 1)))
                }
                for id in ids {
                    project.transcripts[id] = Transcript(
                        language: .english,
                        words: (0..<30).map {
                            Word(text: "word\($0)", start: CMTime(value: Int64($0) * 2, timescale: 5), duration: CMTime(value: 1, timescale: 3))
                        })
                }
                project.captions.style = .karaoke
                for index in 0..<10 { _ = project.addOverlay(of: ids[index % 3], at: CMTime(value: Int64(index) * 18, timescale: 1)) }
                for index in 0..<5 { _ = project.addTitle(at: CMTime(value: Int64(index) * 30, timescale: 1), text: "Part \(index + 1)") }
            }
        }
        await editor.model.waitUntilBuilt()
    }

    private static func milliseconds(since start: ContinuousClock.Instant) -> Double {
        let elapsed = ContinuousClock.now - start
        return Double(elapsed.components.seconds) * 1000 + Double(elapsed.components.attoseconds) / 1e15
    }

    /// Memory the app is using (what Activity Monitor shows), in megabytes.
    private static func footprint() -> Double {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count) }
        }
        return result == KERN_SUCCESS ? Double(info.phys_footprint) / 1_048_576 : 0
    }

    @Test func anEditOnTheBiggestShortIsShownQuickly() async throws {
        let editor = TestEditor.withNewShort()
        try await Self.loadBigShort(into: editor)
        let model = editor.model
        #expect(model.project.timeline.clips.count == 60)
        var best = Double.infinity
        // Inside three different clips (91.5, 95.5, 99.5 s), never on a cut, so each one splits.
        for round in 0..<3 {
            let start = ContinuousClock.now
            editor.step { model.apply("Split Clip") { _ = $0.timeline.split(at: CMTime(value: 183 + Int64(round) * 8, timescale: 2)) } }
            await model.waitUntilBuilt()
            best = min(best, Self.milliseconds(since: start))
            #expect(model.project.timeline.clips.count == 61 + round, "The split didn't happen")
        }
        print(String(format: "BENCH app edit big Short: %.2f ms", best))
        // From the edit to the new player item in the viewer, Debug build on an M1.
        // Measured 55 ms (2026-11-17): rebuilding from scratch is quick enough, so no incremental
        // rebuilds (F11) until this budget says otherwise.
        #expect(best < 150, "An edit took \(Int(best)) ms")
    }

    @Test func onlyTheLast200EditsCanBeUndone() async throws {
        let editor = TestEditor.withNewShort()
        await editor.importToTimeline([try await TestMedia.video(seconds: 2)])
        let model = editor.model
        for step in 0..<(EditorModel.undoLevels + 20) {
            editor.step { model.apply("Volume") { $0.timeline.clips[0].volume = 1 + Double(step % 50) / 100 + 0.001 } }
        }
        var undone = 0
        while editor.undo.canUndo {
            editor.undo.undo()
            undone += 1
        }
        #expect(undone == EditorModel.undoLevels)
        await model.waitUntilBuilt()
    }

    /// A long session on the biggest Short (more edits than can be undone) keeps memory bounded.
    @Test func memoryStaysBoundedOverALongSession() async throws {
        let editor = TestEditor.withNewShort()
        try await Self.loadBigShort(into: editor)
        let model = editor.model
        let before = Self.footprint()
        // Each edit changes a clip and adds a title, so every undo step holds a different Short.
        for step in 0..<(EditorModel.undoLevels + 100) {
            editor.step {
                model.apply("Edit") { project in
                    let index = step % project.timeline.clips.count
                    project.timeline.clips[index].volume = 1 + Double(step) / 1000
                    project.addTitle(at: CMTime(value: Int64(step % 170), timescale: 1), text: "Step \(step)")
                }
            }
            if step.isMultiple(of: 50) { await model.waitUntilBuilt() }
        }
        await model.waitUntilBuilt()
        let grown = Self.footprint() - before
        print(String(format: "BENCH app memory after %d edits: %.1f MB", EditorModel.undoLevels + 100, grown))
        // Measured 50–80 MB on an M1. Whether it stops growing past the undo limit is too small
        // to tell from the process's memory (it moves ±20 MB); `onlyTheLast200EditsCanBeUndone`
        // checks the limit itself.
        #expect(grown < 300, "Memory grew by \(Int(grown)) MB")
    }

    /// Hang reports from macOS are kept, the newest 20.
    @Test func hangReportsKeepTheNewest() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "Diagnostics-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: folder) }
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        for day in 0..<(HangReports.kept + 5) {
            HangReports.keep(Data(#"{"day":\#(day)}"#.utf8), named: start.addingTimeInterval(Double(day) * 86_400), in: folder)
        }
        let kept = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil).sorted {
            $0.lastPathComponent < $1.lastPathComponent
        }
        #expect(kept.count == HangReports.kept)
        #expect(try String(contentsOf: try #require(kept.first), encoding: .utf8) == #"{"day":5}"#)
        #expect(try String(contentsOf: try #require(kept.last), encoding: .utf8) == #"{"day":24}"#)
    }
}
