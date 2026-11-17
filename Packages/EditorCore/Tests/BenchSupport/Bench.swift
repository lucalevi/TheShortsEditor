import CoreMedia
import EditorCore
import Foundation

/// Measuring for the performance budgets (F12) and benchmarks (F19).
///
/// Numbers are printed, and with `SHORTS_BENCH_LOG` set (`make bench`) added to that CSV file with
/// the date, commit and Mac model, so they can be compared over time (`Tools/bench/history.csv`).
public enum Bench {
    private static let environment = ProcessInfo.processInfo.environment

    /// Budgets are checked in ordinary test runs (`make test`, `make check`), not under the
    /// sanitizers (`make tsan`/`asan` set `SHORTS_NO_BUDGETS`), which slow everything down many times.
    public static var budgetsApply: Bool { environment["SHORTS_NO_BUDGETS"] == nil }

    /// Budgets that need the test process to themselves (the main thread above all: every
    /// main-actor test shares it, and a busy one paused it for 18 s), so they run in a step of
    /// their own (`make check`, `make bench` set `SHORTS_BUDGETS_ALONE`), not with all the tests.
    public static var budgetsRunAlone: Bool { budgetsApply && environment["SHORTS_BUDGETS_ALONE"] != nil }

    /// The best of `runs` timings, in milliseconds: the run least disturbed by other tests running
    /// at the same time, so budgets don't fail by chance.
    public static func best(runs: Int = 5, _ work: () throws -> Void) rethrows -> Double {
        var best = Double.infinity
        for _ in 0..<runs {
            let start = ContinuousClock.now
            try work()
            best = min(best, milliseconds(ContinuousClock.now - start))
        }
        return best
    }

    /// `best(runs:_:)` for async work.
    public nonisolated(nonsending) static func best(runs: Int = 5, _ work: () async throws -> Void) async rethrows -> Double {
        var best = Double.infinity
        for _ in 0..<runs {
            let start = ContinuousClock.now
            try await work()
            best = min(best, milliseconds(ContinuousClock.now - start))
        }
        return best
    }

    public static func milliseconds(_ duration: Duration) -> Double {
        Double(duration.components.seconds) * 1000 + Double(duration.components.attoseconds) / 1e15
    }

    public static func record(_ name: String, _ milliseconds: Double) {
        print(String(format: "BENCH %@: %.2f ms", name, milliseconds))
        guard let log = environment["SHORTS_BENCH_LOG"] else { return }
        let date = Date.now.formatted(.iso8601)
        let commit = environment["SHORTS_BENCH_COMMIT"] ?? "unknown"
        let machine = environment["SHORTS_BENCH_MACHINE"] ?? "unknown"
        let line = "\(date),\(commit),\(machine),\(name),\(String(format: "%.2f", milliseconds))\n"
        let url = URL(filePath: log)
        if !FileManager.default.fileExists(atPath: log) {
            try? "date,commit,machine,measure,milliseconds\n".write(to: url, atomically: true, encoding: .utf8)
        }
        guard let handle = try? FileHandle(forWritingTo: url) else { return }
        defer { try? handle.close() }
        _ = try? handle.seekToEnd()
        try? handle.write(contentsOf: Data(line.utf8))
    }
}

/// The big Short the budgets are measured on: 3 minutes (the longest a Short can be) in 60 clips
/// taken in turn from `videos`, every video with a transcript as long as the video (about 150
/// words a minute) and karaoke captions, 10 B-roll clips, 5 titles and `song` as music.
public enum BigShort {
    public static let clipCount = 60

    public static func make(videos: [MediaAsset], song: MediaAsset? = nil) -> Project {
        var project = Project()
        let ids = videos.map { project.addAsset($0) }
        let clipLength = CMTime(value: 3, timescale: 1)
        for index in 0..<clipCount {
            let asset = videos[index % videos.count]
            // Different parts of each video, wrapping round when it is short.
            let slots = max(Int(asset.duration.seconds / 3), 1)
            let start = CMTime(value: Int64((index / videos.count) % slots) * 3, timescale: 1)
            let length = min(clipLength, asset.duration - start)
            _ = project.appendClip(of: ids[index % ids.count], part: CMTimeRange(start: start, duration: length))
        }
        let words = ["So", "here", "is", "the", "thing", "nobody", "tells", "you", "about", "editing"]
        for (asset, id) in zip(videos, ids) {
            let count = Int(asset.duration.seconds * 2.5)
            project.transcripts[id] = Transcript(
                language: .english,
                words: (0..<count).map { i in
                    Word(text: words[i % words.count], start: CMTime(value: Int64(i) * 2, timescale: 5), duration: CMTime(value: 1, timescale: 3))
                })
        }
        project.captions.style = .karaoke
        let length = project.duration
        for index in 0..<10 {
            _ = project.addOverlay(of: ids[index % ids.count], at: CMTime(value: Int64(index) * length.value / 10, timescale: length.timescale))
        }
        for index in 0..<5 {
            _ = project.addTitle(at: CMTime(value: Int64(index) * 30, timescale: 1), text: "Part \(index + 1)")
        }
        if let song { project.setMusic(project.addAsset(song)) }
        return project
    }
}
