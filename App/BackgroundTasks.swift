import EditorCore
import Foundation
import Observation

/// Every long piece of work the app does in the background (cleaning a voice, turning a clip
/// round, removing a background, making captions, exporting…), in one place with one shape: what
/// it is about, a title, how far it has got, and a way to stop it. The views ask it whether
/// something is being made (`progress(_:)`); the Background Tasks window (⌘9) lists them all.
///
/// A job runs inside `run(_:title:_:)`: it is listed while the operation runs, its progress is
/// what the operation reports, and stopping it (from the window, or by cancelling the task that
/// called `run`) cancels the operation.
@Observable
final class BackgroundTasks {
    /// What a job is about. Two jobs never share a key: callers check `isRunning` first.
    enum Key: Hashable {
        /// Removing music and noise from a file's sound (Clean Up Voice).
        case voiceCleanUp(MediaAsset.ID)
        /// A clip's voice effect or EQ, rendered into a copy of its sound.
        case processedSound(Clip.ID)
        /// The backwards copy of a clip's file.
        case backwards(Clip.ID)
        /// Finding the subject of a clip to follow it.
        case reframe(Clip.ID)
        /// Measuring a file's shake for Stabilize.
        case steadying(MediaAsset.ID)
        /// The see-through copy of a file for Remove Background.
        case cutout(MediaAsset.ID, CutoutSubject)
        /// Looking at a clip's picture for Enhance or Match Color.
        case lookAnalysis(Clip.ID)
        /// Listening to the music for its beats.
        case beats
        /// A title or sticker learning to follow something in the video.
        case tracking(TextOverlay.ID)
        /// Making a voice from text.
        case speech
        /// A clip's smooth slow-motion copy.
        case smoothSlowMotion(Clip.ID)
        /// Copying an item in from the Photos library (by its local identifier).
        case photo(String)
        /// Making the music of a style.
        case style(ShortStyle)
        /// Reading files being added.
        case importing
        /// Turning speech into captions.
        case captions
        /// Separating the voice to find pauses on it alone.
        case voiceSeparation
        /// Apple Intelligence reading the script.
        case wordModel
        /// Writing the Short to a movie file.
        case export

        var kind: Kind {
            switch self {
            case .voiceCleanUp: .voiceCleanUp
            case .processedSound: .processedSound
            case .backwards: .backwards
            case .reframe: .reframe
            case .steadying: .steadying
            case .cutout: .cutout
            case .lookAnalysis: .lookAnalysis
            case .beats: .beats
            case .tracking: .tracking
            case .speech: .speech
            case .smoothSlowMotion: .smoothSlowMotion
            case .photo: .photo
            case .style: .style
            case .importing: .importing
            case .captions: .captions
            case .voiceSeparation: .voiceSeparation
            case .wordModel: .wordModel
            case .export: .export
            }
        }
    }

    /// What sort of work a key is, whatever it is about.
    enum Kind: CaseIterable {
        case voiceCleanUp, processedSound, backwards, reframe, steadying, cutout, lookAnalysis, beats, tracking, speech
        case smoothSlowMotion, photo, style, importing, captions, voiceSeparation, wordModel, export

        /// An SF Symbol for the Background Tasks window.
        var symbol: String {
            switch self {
            case .voiceCleanUp, .voiceSeparation: "waveform.badge.mic"
            case .processedSound: "slider.vertical.3"
            case .backwards: "backward"
            case .reframe, .tracking: "scope"
            case .steadying: "hand.raised"
            case .cutout: "person.crop.rectangle"
            case .lookAnalysis: "camera.filters"
            case .beats, .style: "music.note"
            case .speech: "text.bubble"
            case .smoothSlowMotion: "tortoise"
            case .photo: "photo.on.rectangle"
            case .importing: "square.and.arrow.down"
            case .captions: "captions.bubble"
            case .wordModel: "apple.intelligence"
            case .export: "square.and.arrow.up"
            }
        }
    }

    struct Job: Identifiable {
        let id = UUID()
        let key: Key
        let title: String
        /// What it is doing now, when that says more than the title ("Listening to file 2 of 3").
        var detail: String?
        /// 0…1, or nil when how far it has got can't be told.
        var fraction: Double?
        let started = Date.now
    }

    /// A job that ended badly: it failed, or was stopped.
    struct Ended: Identifiable {
        let id = UUID()
        let title: String
        /// Why it failed; nil when it was stopped.
        let error: String?
        let date = Date.now
    }

    /// The jobs running now, oldest first.
    private(set) var jobs: [Job] = []
    /// Jobs that failed or were stopped since the app started, newest first (at most 20).
    private(set) var ended: [Ended] = []
    /// Keys whose job failed or was stopped. Work the app starts by itself (copies a clip needs
    /// after an edit) isn't tried again for them, so an error isn't shown after every edit; a
    /// new Short starts afresh (`forgetFailures`).
    private(set) var failed: Set<Key> = []
    @ObservationIgnored private var cancellers: [Job.ID: @Sendable () -> Void] = [:]

    // MARK: Asking

    func isRunning(_ key: Key) -> Bool { jobs.contains { $0.key == key } }

    /// Whether a job of this kind is running, whatever it is about (e.g. any clip being turned round).
    func isRunning(kind: Kind) -> Bool { jobs.contains { $0.key.kind == kind } }

    /// How far the job for `key` has got, while it runs (0 when that can't be told); nil when
    /// nothing is running for it.
    func progress(_ key: Key) -> Double? {
        jobs.first { $0.key == key }.map { $0.fraction ?? 0 }
    }

    func job(_ key: Key) -> Job? { jobs.first { $0.key == key } }

    /// The job for `key` isn't running and hasn't failed: work started by the app may begin it.
    func mayStart(_ key: Key) -> Bool { !isRunning(key) && !failed.contains(key) }

    // MARK: Running

    /// Starts `operation` as a listed job, listed at once (so a second click finds it running).
    /// Progress it reports shows on the job; stopping the job cancels the returned task, which
    /// then throws `CancellationError`. A failure is kept in `ended` and `failed`. The job is
    /// gone from `jobs` before anyone awaiting the task resumes.
    @discardableResult
    func start<T: Sendable>(
        _ key: Key, title: String, _ operation: @escaping (JobProgress) async throws -> T
    ) -> Task<T, Error> {
        let job = Job(key: key, title: title)
        jobs.append(job)
        let progress = JobProgress(id: job.id, tasks: self)
        let work = Task { [weak self] in
            do {
                let value = try await operation(progress)
                try Task.checkCancellation()
                self?.finish(job, error: nil)
                return value
            } catch {
                self?.finish(job, error: error)
                throw error
            }
        }
        cancellers[job.id] = { work.cancel() }
        return work
    }

    /// Runs `operation` as a listed job and waits for it (see `start`). Cancelling the calling
    /// task stops the job too.
    func run<T: Sendable>(
        _ key: Key, title: String, _ operation: @escaping (JobProgress) async throws -> T
    ) async throws -> T {
        let work = start(key, title: title, operation)
        return try await withTaskCancellationHandler {
            try await work.value
        } onCancel: {
            work.cancel()
        }
    }

    private func finish(_ job: Job, error: Error?) {
        jobs.removeAll { $0.id == job.id }
        cancellers[job.id] = nil
        guard let error else {
            failed.remove(job.key)
            return
        }
        failed.insert(job.key)
        remember(Ended(title: job.title, error: error is CancellationError ? nil : error.localizedDescription))
    }

    /// Stops a running job (its operation is cancelled).
    func cancel(_ id: Job.ID) {
        cancellers[id]?()
    }

    func cancelAll() {
        for cancel in cancellers.values { cancel() }
    }

    /// Lets work that failed or was stopped be tried again (a new Short is open).
    func forgetFailures() {
        failed = []
    }

    func clearEnded() {
        ended = []
    }

    fileprivate func update(_ id: Job.ID, fraction: Double? = nil, detail: String? = nil) {
        guard let index = jobs.firstIndex(where: { $0.id == id }) else { return }
        if let fraction { jobs[index].fraction = min(max(fraction, 0), 1) }
        if let detail { jobs[index].detail = detail }
    }

    private func remember(_ job: Ended) {
        ended.insert(job, at: 0)
        if ended.count > 20 { ended.removeLast(ended.count - 20) }
    }
}

/// Reports how far a job has got. Can be called from any thread; reports arriving after the job
/// ended are ignored.
struct JobProgress: Sendable {
    let id: BackgroundTasks.Job.ID
    weak var tasks: BackgroundTasks?

    nonisolated func callAsFunction(_ fraction: Double) {
        report(fraction: fraction, detail: nil)
    }

    nonisolated func detail(_ text: String) {
        report(fraction: nil, detail: text)
    }

    private nonisolated func report(fraction: Double?, detail: String?) {
        let id = id
        if Thread.isMainThread {
            MainActor.assumeIsolated { tasks?.update(id, fraction: fraction, detail: detail) }
        } else {
            Task { @MainActor [tasks] in tasks?.update(id, fraction: fraction, detail: detail) }
        }
    }
}
