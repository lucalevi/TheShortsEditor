import CoreMedia
import EditorCore
import Foundation
import RenderEngine
import Testing

@testable import Shorts_Editor

/// Delete Generated Files (F24): each Short in the library is told apart by its own made copies.
struct StorageTests {
    private static func write(_ media: URL, cleansVoice: Bool, as id: UUID) throws {
        var project = Project()
        let asset = project.addAsset(
            MediaAsset(url: media, name: "talk", duration: CMTime(value: 4, timescale: 1), displaySize: CGSize(width: 1080, height: 1920), hasAudio: true))
        project.appendClip(of: asset)
        if cleansVoice { project.updateAnyClip(project.timeline.clips[0].id) { $0.cleansVoice = true } }
        try FileManager.default.createDirectory(at: ProjectStore.libraryFolder, withIntermediateDirectories: true)
        try ProjectFile(project: project, name: "Storage test", created: .now).encoded(compact: true)
            .write(to: ProjectStore.fileURL(for: id), options: .atomic)
    }

    @Test func eachShortsGeneratedFilesAreFoundInTheLibrary() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "Storage-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let talk = folder.appending(path: "talk.mov"), other = folder.appending(path: "other.mov")
        for media in [talk, other] { try Data(count: 64).write(to: media) }
        let cleaned = VoiceCleaner.cleanedURL(for: talk)
        try FileManager.default.createDirectory(at: cleaned.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(count: 4096).write(to: cleaned)

        let withCopy = UUID(), without = UUID()
        try Self.write(talk, cleansVoice: true, as: withCopy)
        try Self.write(other, cleansVoice: true, as: without) // its cleaned voice was never made
        defer {
            for url in [folder, cleaned, ProjectStore.fileURL(for: withCopy), ProjectStore.fileURL(for: without)] {
                try? FileManager.default.removeItem(at: url)
            }
        }

        let found = ProjectStore.generatedFilesByShort()
        #expect(found[withCopy] == [cleaned.standardizedFileURL])
        #expect(found[without] == nil)

        // A second Short using the same copy: it belongs to neither alone, so neither lists it.
        let sharing = UUID()
        try Self.write(talk, cleansVoice: true, as: sharing)
        defer { try? FileManager.default.removeItem(at: ProjectStore.fileURL(for: sharing)) }
        let shared = ProjectStore.generatedFilesByShort()
        #expect(shared[withCopy] == nil && shared[sharing] == nil)
    }
}
