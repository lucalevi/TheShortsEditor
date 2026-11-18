import CoreMedia
import EditorCore
import Foundation
import Testing

@testable import RenderEngine

@MainActor
struct StorageCleanerTests {
    private func project(file: URL) -> (Project, Clip.ID) {
        var p = Project()
        let id = p.addAsset(
            MediaAsset(url: file, name: "a", duration: CMTime(value: 10, timescale: 1), displaySize: CGSize(width: 1080, height: 1920), hasAudio: true))
        p.appendClip(of: id)
        return (p, p.timeline.clips[0].id)
    }

    @Test func copiesAShortAsksForCountAsUsed() throws {
        let file = FileManager.default.temporaryDirectory.appending(path: "cleaner-\(UUID().uuidString).mov")
        try Data([1, 2, 3]).write(to: file)
        var (p, id) = project(file: file)
        #expect(StorageCleaner.filesInUse(by: [p]) == [file.standardizedFileURL])
        p.updateAnyClip(id) {
            $0.cutout.removeBackground = .people; $0.cleansVoice = true; $0.steadiness = 0.5
        }
        let used = StorageCleaner.filesInUse(by: [p])
        #expect(used.contains(CutoutCache.copyURL(for: file, subject: .people, isImage: false).standardizedFileURL))
        #expect(used.contains(VoiceCleaner.cleanedURL(for: file).standardizedFileURL))
        #expect(used.contains(ShakeCache.fileURL(for: file).standardizedFileURL))
    }

    @Test func aShortsGeneratedFilesAreItsMadeCopiesNoOtherShortUses() throws {
        let file = FileManager.default.temporaryDirectory.appending(path: "generated-\(UUID().uuidString).mov")
        let shared = FileManager.default.temporaryDirectory.appending(path: "generated-\(UUID().uuidString).mov")
        for media in [file, shared] { try Data([1, 2, 3]).write(to: media) }
        var (mine, mineClip) = project(file: file)
        let sharedID = mine.addAsset(
            MediaAsset(url: shared, name: "b", duration: CMTime(value: 10, timescale: 1), displaySize: CGSize(width: 1080, height: 1920), hasAudio: true))
        mine.appendClip(of: sharedID)
        let sharedClip = mine.timeline.clips[1].id
        for clip in [mineClip, sharedClip] {
            mine.updateAnyClip(clip) {
                $0.cleansVoice = true; $0.steadiness = 0.5
            }
        }
        var (other, otherClip) = project(file: shared)
        other.updateAnyClip(otherClip) { $0.cleansVoice = true }

        // Made: the cleaned voices of both files and the shake path of the first. Not made: the
        // second file's shake path (so it isn't listed).
        let cleaned = VoiceCleaner.cleanedURL(for: file), cleanedShared = VoiceCleaner.cleanedURL(for: shared)
        let shake = ShakeCache.fileURL(for: file)
        for copy in [cleaned, cleanedShared, shake] {
            try FileManager.default.createDirectory(at: copy.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(count: 100).write(to: copy)
        }
        defer { for url in [file, shared, cleaned, cleanedShared, shake] { try? FileManager.default.removeItem(at: url) } }

        let generated = StorageCleaner.generatedFiles(of: mine, others: [other])
        // The other Short still uses the second file's cleaned voice; the media themselves are never listed.
        #expect(Set(generated) == [cleaned.standardizedFileURL, shake.standardizedFileURL])
        #expect(StorageCleaner.remove(generated) > 0)
        #expect(!FileManager.default.fileExists(atPath: cleaned.path) && !FileManager.default.fileExists(atPath: shake.path))
        #expect(FileManager.default.fileExists(atPath: cleanedShared.path) && FileManager.default.fileExists(atPath: file.path))
        #expect(StorageCleaner.generatedFiles(of: mine, others: [other]).isEmpty)
    }

    @Test func onlyOldFilesNoShortUsesAreUnused() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "cleaner-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let old = Date().addingTimeInterval(-10 * 24 * 3600)
        let used = folder.appending(path: "used.mov"), unused = folder.appending(path: "unused.mov"), fresh = folder.appending(path: "fresh.mov")
        for file in [used, unused, fresh] { try Data(count: 10).write(to: file) }
        for file in [used, unused] { try FileManager.default.setAttributes([.modificationDate: old], ofItemAtPath: file.path) }
        let found = StorageCleaner.unusedFiles(in: [folder], inUse: [used.standardizedFileURL], before: Date().addingTimeInterval(-7 * 24 * 3600))
        #expect(found.map(\.lastPathComponent) == ["unused.mov"])
        #expect(StorageCleaner.size(of: [unused]) > 0)
    }
}
