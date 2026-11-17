import CoreMedia
import EditorCore
import Foundation
import Testing

@testable import Shorts_Editor

/// The home window lists every Short each time it is shown (F12): a library of 200 Shorts, each
/// with 30 minutes of transcribed footage, must list quickly, and files that haven't changed
/// aren't read again.
@Suite(.serialized)
struct LibraryListingTests {
    /// A Short whose file is as heavy as they get: 10 three-minute videos, all transcribed.
    private static func heavyFile(name: String) throws -> Data {
        var project = Project()
        for index in 0..<10 {
            let id = project.addAsset(
                MediaAsset(
                    url: URL(fileURLWithPath: "/Users/me/Movies/talk-\(index).mov"), name: "talk-\(index)", duration: CMTime(value: 180, timescale: 1),
                    displaySize: CGSize(width: 1080, height: 1920), hasAudio: true, hasVideo: true))
            _ = project.appendClip(of: id, part: CMTimeRange(start: .zero, duration: CMTime(value: 18, timescale: 1)))
            project.transcripts[id] = Transcript(
                language: .english,
                words: (0..<450).map { Word(text: "word\($0)", start: CMTime(value: Int64($0) * 2, timescale: 5), duration: CMTime(value: 1, timescale: 3)) })
        }
        return try ProjectFile(project: project, name: name, created: .now).encoded(compact: true)
    }

    private static func milliseconds(_ work: () -> Void) -> Double {
        let start = ContinuousClock.now
        work()
        let elapsed = ContinuousClock.now - start
        return Double(elapsed.components.seconds) * 1000 + Double(elapsed.components.attoseconds) / 1e15
    }

    @Test func twoHundredHeavyShortsListQuicklyAndOnlyChangedOnesAreReadAgain() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "Library-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let data = try Self.heavyFile(name: "Heavy")
        let ids = (0..<200).map { _ in UUID() }
        for id in ids { try data.write(to: folder.appending(path: "\(id.uuidString).\(ProjectFile.fileExtension)")) }

        var entries: [ShortEntry] = []
        let first = Self.milliseconds { entries = ProjectStore.libraryEntries(in: folder) }
        #expect(entries.count == 200)
        #expect(entries.allSatisfy { $0.name == "Heavy" && $0.clipCount == 10 })
        // Off the main thread; a Debug build on an M1 takes about 0.8 s.
        #expect(first < 2000, "Listing 200 Shorts took \(Int(first)) ms")

        // Shown again: nothing has changed, so nothing is parsed.
        let again = Self.milliseconds { entries = ProjectStore.libraryEntries(in: folder) }
        #expect(entries.count == 200)
        #expect(again < first / 5, "Listing again took \(Int(again)) ms (first \(Int(first)) ms)")

        // A Short saved since (renamed here) is read again.
        try Self.heavyFile(name: "Renamed").write(to: folder.appending(path: "\(ids[7].uuidString).\(ProjectFile.fileExtension)"), options: .atomic)
        entries = ProjectStore.libraryEntries(in: folder)
        #expect(entries.first { $0.id == ids[7] }?.name == "Renamed")
        #expect(entries.filter { $0.name == "Heavy" }.count == 199)
    }
}
