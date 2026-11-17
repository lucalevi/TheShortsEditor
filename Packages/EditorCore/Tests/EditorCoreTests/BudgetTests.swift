import BenchSupport
import CoreGraphics
import CoreMedia
import Foundation
import Testing

@testable import EditorCore

/// Performance budgets for the model (F12): what follows every edit or happens when a Short is
/// saved, opened or listed must stay quick on the biggest Short the app allows, with 30 minutes of
/// footage transcribed. They fail when a change makes them slower than the budget. Budgets are for
/// a Debug build on the slowest supported Mac (M1); `make bench` keeps the numbers.
@Suite(.serialized, .enabled(if: Bench.budgetsApply))
struct BudgetTests {
    /// 10 three-minute videos (30 minutes of transcript) in a 3-minute Short of 60 clips.
    static let big: Project = {
        let videos = (0..<10).map { index in
            MediaAsset(
                url: URL(fileURLWithPath: "/Users/me/Movies/talk-\(index).mov"), name: "talk-\(index)", duration: CMTime(value: 180, timescale: 1),
                displaySize: CGSize(width: 1080, height: 1920), hasAudio: true, hasVideo: true)
        }
        let song = MediaAsset(
            url: URL(fileURLWithPath: "/Users/me/Music/song.m4a"), name: "song", duration: CMTime(value: 200, timescale: 1),
            displaySize: .zero, hasAudio: true, hasVideo: false)
        return BigShort.make(videos: videos, song: song)
    }()

    @Test func theBigShortIsAsBigAsMeant() {
        #expect(Self.big.timeline.clips.count == BigShort.clipCount)
        #expect(Self.big.duration == CMTime(value: 180, timescale: 1))
        #expect(Self.big.transcripts.values.map(\.words.count).reduce(0, +) == 4500)
    }

    @Test func savingIsQuick() throws {
        let file = ProjectFile(project: Self.big)
        let ms = try Bench.best { _ = try file.encoded(compact: true) }
        Bench.record("save big Short", ms)
        // Autosave runs a second after every edit (in the background).
        #expect(ms < 80)
    }

    @Test func openingIsQuick() throws {
        let data = try ProjectFile(project: Self.big).encoded(compact: true)
        let ms = try Bench.best { _ = try ProjectFile.decode(data) }
        Bench.record("open big Short", ms)
        // Opening a Short from All Shorts.
        #expect(ms < 80)
    }

    /// The home window reads a summary of every Short.
    @Test func listingALibraryOf200IsQuick() throws {
        let data = try ProjectFile(project: Self.big).encoded(compact: true)
        let ms = try Bench.best(runs: 3) { for _ in 0..<200 { _ = try ProjectFile.readListing(data) } }
        Bench.record("list 200 big Shorts", ms)
        // Off the main thread, and only for files changed since (the app keeps the rest).
        #expect(ms < 1600)
    }

    @Test func layingOutCaptionsIsQuick() {
        let ms = Bench.best { _ = CaptionLayout.pages(in: Self.big) }
        Bench.record("caption pages big Short", ms)
        // Laid out again after every edit.
        #expect(ms < 25)
    }

    /// What every edit does in the model: the change, then items following their clips.
    @Test func anEditIsQuick() {
        let ms = Bench.best {
            var project = Self.big
            let old = project
            _ = project.timeline.split(at: CMTime(value: 91, timescale: 1))
            project.followClips(from: old)
        }
        Bench.record("edit big Short", ms)
        // Before the rebuild, on the main thread.
        #expect(ms < 5)
    }
}
