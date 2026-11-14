import CoreGraphics
import CoreMedia
import Foundation
import Testing

@testable import EditorCore

private func asset(_ name: String, seconds: Int64 = 10, video: Bool = true) -> MediaAsset {
    MediaAsset(
        url: URL(fileURLWithPath: "/Users/me/Movies/\(name)"), name: name, duration: CMTime(value: seconds, timescale: 1),
        displaySize: video ? CGSize(width: 1080, height: 1920) : .zero, hasAudio: true, hasVideo: video)
}

/// A project using everything that gets saved.
private func fullProject() -> Project {
    var p = Project()
    let video = p.addAsset(asset("talk.mov"))
    let song = p.addAsset(asset("song.m4a", seconds: 60, video: false))
    p.addAsset(asset("unused.mov"))
    p.appendClip(of: video)
    p.timeline.split(at: CMTime(value: 4, timescale: 1))
    p.timeline.clips[1].volume = 1.4
    p.timeline.clips[0].framing = .fit
    p.transcripts[video] = Transcript(language: .italian, words: [Word(text: "Ciao", start: .zero, duration: CMTime(value: 1, timescale: 2))])
    p.captions.style = .highlight
    p.addTitle(at: .zero, text: "Hook\nline two")
    p.setMusic(song)
    p.setMusicStart(CMTime(value: 5, timescale: 1))
    return p
}

struct ProjectFileTests {
    @Test func everythingComesBackAfterSaving() throws {
        let p = fullProject()
        let file = ProjectFile(project: p, bookmarks: [p.assets[0].id: Data([1, 2, 3])])
        let read = try ProjectFile.decode(file.encoded())
        #expect(read == file)
        #expect(read.project == p)
    }

    @Test func aNewerFileIsRefusedClearly() throws {
        var file = ProjectFile(project: fullProject())
        file.version = ProjectFile.currentVersion + 1
        #expect(throws: ProjectFile.ReadError.newerVersion) { try ProjectFile.decode(file.encoded()) }
    }

    @Test func otherFilesAreUnreadable() {
        #expect(throws: ProjectFile.ReadError.unreadable) { try ProjectFile.decode(Data("hello".utf8)) }
        #expect(throws: ProjectFile.ReadError.unreadable) { try ProjectFile.decode(Data(#"{"version":1}"#.utf8)) }
    }

    @Test func usedAssetsAreClipsAndMusic() {
        #expect(fullProject().usedAssets.map(\.name) == ["talk.mov", "song.m4a"])
    }

    @Test func relinkingKeepsTheEdits() {
        var p = fullProject()
        let id = p.assets[0].id
        let before = p.timeline
        p.relink(id, to: URL(fileURLWithPath: "/Volumes/Disk/talk-final.mov"))
        #expect(p.assets[0].url.path == "/Volumes/Disk/talk-final.mov")
        #expect(p.assets[0].name == "talk-final")
        #expect(p.timeline == before)
        #expect(p.transcripts[id] != nil)
    }

    @Test func missingFilesAreFoundByNameInAFolder() {
        let p = fullProject()
        let missing: Set = [p.assets[0].id, p.assets[1].id]
        let folder = ["TALK.MOV", "other.mov", "notes.txt"].map { URL(fileURLWithPath: "/Volumes/Disk/\($0)") }
        let matches = p.relinkMatches(for: missing, in: folder)
        #expect(matches.count == 1)
        #expect(matches[p.assets[0].id]?.lastPathComponent == "TALK.MOV")
    }

    @Test func replacementMustBeTheSameKindAndLength() {
        let original = asset("a.mov", seconds: 10)
        #expect(Project.isLikelySameMedia(original, as: asset("b.mov", seconds: 10)))
        #expect(!Project.isLikelySameMedia(original, as: asset("b.mov", seconds: 30)))
        #expect(!Project.isLikelySameMedia(original, as: asset("b.m4a", seconds: 10, video: false)))
    }

    @Test func missingMediaIsTheFirstWarning() {
        let p = fullProject()
        let issues = ExportReview.issues(for: p, openingPeak: 0.5, missing: [p.assets[1].id, p.assets[2].id])
        #expect(issues.first?.kind == .missingMedia)
        // The unused file doesn't count.
        #expect(issues.first?.title == "A file can't be found")
        #expect(!ExportReview.issues(for: p, openingPeak: 0.5).contains { $0.kind == .missingMedia })
    }
}
