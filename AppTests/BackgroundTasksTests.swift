import EditorCore
import Foundation
import Testing

@testable import Shorts_Editor

/// Every long job goes through `BackgroundTasks`: listed at once, progress shown, stoppable, and
/// failures remembered so the app doesn't start them again by itself after every edit.
@Suite struct BackgroundTasksTests {
    struct Failure: LocalizedError {
        var errorDescription: String? { "The file is damaged." }
    }

    @Test func aJobIsListedAtOnceShowsProgressAndIsGoneWhenDone() async throws {
        let tasks = BackgroundTasks()
        let gate = Gate()
        let work = tasks.start(.beats, title: "Listening") { progress in
            progress(0.25)
            progress.detail("Bar 1 of 4")
            await gate.wait()
            return 42
        }
        #expect(tasks.isRunning(.beats))
        #expect(tasks.isRunning(kind: .beats))
        #expect(!tasks.mayStart(.beats))
        await waitUntil("the progress is shown") { tasks.progress(.beats) == 0.25 }
        #expect(tasks.job(.beats)?.detail == "Bar 1 of 4")
        await gate.open()
        #expect(try await work.value == 42)
        #expect(tasks.jobs.isEmpty)
        #expect(tasks.ended.isEmpty)
        #expect(tasks.mayStart(.beats))
    }

    @Test func progressIsKeptBetweenZeroAndOne() async throws {
        let tasks = BackgroundTasks()
        let gate = Gate()
        let work = tasks.start(.speech, title: "Speaking") { progress in
            progress(7)
            await gate.wait()
        }
        await waitUntil("the progress is shown") { tasks.progress(.speech) == 1 }
        await gate.open()
        try await work.value
    }

    @Test func aFailedJobIsRememberedAndNotStartedAgainByTheApp() async throws {
        let tasks = BackgroundTasks()
        let key = BackgroundTasks.Key.steadying(UUID())
        await #expect(throws: Failure.self) {
            try await tasks.run(key, title: "Measuring shake") { _ in throw Failure() }
        }
        #expect(tasks.jobs.isEmpty)
        #expect(!tasks.mayStart(key))
        #expect(tasks.ended.first?.title == "Measuring shake")
        #expect(tasks.ended.first?.error == "The file is damaged.")
        // A new Short starts afresh.
        tasks.forgetFailures()
        #expect(tasks.mayStart(key))
    }

    @Test func stoppingAJobCancelsItsWork() async throws {
        let tasks = BackgroundTasks()
        let work = tasks.start(.export, title: "Exporting") { _ in
            try await Task.sleep(for: .seconds(60))
        }
        let job = try #require(tasks.job(.export))
        tasks.cancel(job.id)
        await #expect(throws: CancellationError.self) { try await work.value }
        #expect(tasks.jobs.isEmpty)
        // Stopped, not failed: no error to show, but the app won't start it again by itself.
        #expect(tasks.ended.first?.error == nil)
        #expect(!tasks.mayStart(.export))
    }

    @Test func cancellingTheCallerStopsTheJob() async throws {
        let tasks = BackgroundTasks()
        let caller = Task {
            try await tasks.run(.captions, title: "Making captions") { _ in try await Task.sleep(for: .seconds(60)) }
        }
        await waitUntil("the job is listed") { tasks.isRunning(.captions) }
        caller.cancel()
        await #expect(throws: CancellationError.self) { try await caller.value }
        #expect(!tasks.isRunning(.captions))
    }

    @Test func workThatIgnoresCancellationStillEndsAsStopped() async throws {
        let tasks = BackgroundTasks()
        let work = tasks.start(.wordModel, title: "Reading") { _ in "finished anyway" }
        tasks.cancelAll()
        // The value is thrown away: a stopped job never hands back a result.
        await #expect(throws: CancellationError.self) { try await work.value }
        #expect(tasks.jobs.isEmpty)
    }

    @Test func progressReportedAfterTheEndIsIgnored() async throws {
        let tasks = BackgroundTasks()
        var kept: JobProgress?
        try await tasks.run(.importing, title: "Adding") { progress in kept = progress }
        kept?(0.5)
        kept?.detail("late")
        await Task.yield()
        #expect(tasks.jobs.isEmpty)
    }

    @Test func atMostTwentyEndedJobsAreKept() async throws {
        let tasks = BackgroundTasks()
        for index in 0..<25 {
            _ = try? await tasks.run(.photo("\(index)"), title: "Copy \(index)") { _ in throw Failure() }
        }
        #expect(tasks.ended.count == 20)
        #expect(tasks.ended.first?.title == "Copy 24")
        tasks.clearEnded()
        #expect(tasks.ended.isEmpty)
    }

    /// F20: many jobs, stopped at random moments while others finish or fail, from the main actor
    /// and from background threads (progress). Every job must end, none twice, nothing left over.
    @Test func manyJobsStoppedAtRandomAllEnd() async throws {
        let tasks = BackgroundTasks()
        var generator = SeededGenerator(seed: 2026)
        var works: [Task<Int, Error>] = []
        for index in 0..<200 {
            let delay = Int.random(in: 0...20, using: &generator)
            let fails = index % 7 == 0
            let work = tasks.start(.processedSound(UUID()), title: "Job \(index)") { progress in
                for step in 0..<4 {
                    try await Task.sleep(for: .milliseconds(delay))
                    // Reported from a background thread, as AVFoundation's callbacks do.
                    await Task.detached { progress(Double(step) / 4) }.value
                }
                if fails { throw Failure() }
                return index
            }
            works.append(work)
            if Bool.random(using: &generator), let victim = tasks.jobs.randomElement(using: &generator) {
                tasks.cancel(victim.id)
            }
        }
        var finished = 0, stopped = 0, failed = 0
        for work in works {
            do {
                _ = try await work.value
                finished += 1
            } catch is CancellationError {
                stopped += 1
            } catch {
                failed += 1
            }
        }
        #expect(finished + stopped + failed == 200)
        #expect(stopped > 0 && finished > 0 && failed > 0)
        #expect(tasks.jobs.isEmpty)
        #expect(tasks.failed.count == stopped + failed)
    }
}

/// Lets a test hold a job until it says so.
actor Gate {
    private var isOpen = false
    private var waiting: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        if isOpen { return }
        await withCheckedContinuation { waiting.append($0) }
    }

    func open() {
        isOpen = true
        waiting.forEach { $0.resume() }
        waiting = []
    }
}

/// The same random numbers on every run.
struct SeededGenerator: RandomNumberGenerator {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        return state
    }
}
