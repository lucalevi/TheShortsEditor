import AVFoundation
import EditorCore
import Observation
import RenderEngine
import SwiftUI
import Transcription

/// The state of the open Short and everything the views can do to it.
///
/// Every change to the project goes through `apply(_:_:)`, which registers undo and rebuilds what
/// the player shows. Views never touch the project or the player in any other way.
@Observable
final class EditorModel {
    private(set) var project = Project()
    var selectedClipID: Clip.ID?
    var selectedAssetID: MediaAsset.ID?
    var showsSafeZone = true
    /// Timeline zoom, in points per second.
    var timelineZoom: CGFloat = 60
    private(set) var currentTime: CMTime = .zero
    private(set) var isPlaying = false
    private(set) var thumbnails: [MediaAsset.ID: CGImage] = [:]
    private(set) var isImporting = false
    var alert: AlertMessage?

    /// Which list the left panel shows.
    var sidebar: Sidebar = .media
    var captionLanguage = CaptionLanguage.preferred()
    /// What the caption maker is doing, while it works.
    private(set) var captionJob: CaptionJob?
    /// The captions as they appear on the timeline. Updated with every edit.
    private(set) var captionPages: [CaptionPage] = []
    /// The caption the user last clicked on the timeline, so the Captions list can show it.
    var focusedCaptionID: CaptionPage.ID?
    /// Set while the Export sheet is open.
    var exportPhase: ExportPhase?
    /// Set while the user is choosing which pauses to remove.
    private(set) var silenceSession: SilenceSession?
    /// Sound levels of each file, measured once when first needed.
    @ObservationIgnored private var audioLevels: [MediaAsset.ID: AudioLevels] = [:]
    /// Where a preview skip is heading, so it isn't started again while the seek lands.
    @ObservationIgnored private var skipTarget: CMTime?

    let player = AVPlayer()
    /// The editor window, set by the main view whenever its window becomes active. Undo goes to
    /// that window's undo manager, the one Edit ▸ Undo and ⌘Z use. (Opening files from Finder can
    /// briefly create a second window that then closes, so the first window seen isn't reliable,
    /// and neither is SwiftUI's environment undo manager.)
    @ObservationIgnored weak var window: NSWindow?
    private var undoManager: UndoManager? { (window ?? NSApp.mainWindow)?.undoManager }

    @ObservationIgnored private var rebuildTask: Task<Void, Never>?
    @ObservationIgnored private var captionTask: Task<Void, Never>?
    @ObservationIgnored private var exportTask: Task<Void, Never>?
    @ObservationIgnored private var timeObserver: Any?
    @ObservationIgnored private var statusObservation: NSKeyValueObservation?

    static let zoomRange: ClosedRange<CGFloat> = 15...400

    enum Sidebar: String, CaseIterable, Identifiable {
        case media = "Media"
        case captions = "Captions"
        var id: String { rawValue }
    }

    enum ExportPhase: Equatable {
        /// Running the checks before export.
        case checking
        /// Showing what the checks found; the user decides whether to go on.
        case review([ExportIssue])
        case exporting(Double)
        case finished(URL)
        case failed(String)
    }

    struct SilenceSession {
        var isMeasuring = true
        var settings = SilenceSettings()
        var plan = SilencePlan(sourceCuts: [:], timelineCuts: [])
    }

    enum CaptionJob: Equatable {
        /// Downloading the language's speech model, the first time it is used.
        case downloading(Double)
        /// Listening to file `index` of `count`.
        case listening(index: Int, count: Int)
    }

    struct AlertMessage: Identifiable {
        let id = UUID()
        let title: String
        let message: String
    }

    init() {
        player.actionAtItemEnd = .pause
        timeObserver = player.addPeriodicTimeObserver(forInterval: .oneFrame, queue: .main) { [weak self] time in
            MainActor.assumeIsolated { self?.playheadMoved(to: time) }
        }
        statusObservation = player.observe(\.timeControlStatus) { [weak self] player, _ in
            let playing = player.timeControlStatus != .paused
            Task { @MainActor in self?.isPlaying = playing }
        }
    }

    // MARK: Lookups

    var selectedClip: Clip? {
        selectedClipID.flatMap { id in project.timeline.clips.first { $0.id == id } }
    }

    var duration: CMTime { project.duration }

    // MARK: Editing

    /// Applies an edit as one undoable step.
    func apply(_ actionName: String, _ edit: (inout Project) -> Void) {
        var updated = project
        edit(&updated)
        replaceProject(with: updated, actionName: actionName)
    }

    private func replaceProject(with new: Project, actionName: String) {
        guard new != project else { return }
        let old = project
        project = new
        undoManager?.registerUndo(withTarget: self) { model in
            MainActor.assumeIsolated { model.replaceProject(with: old, actionName: actionName) }
        }
        undoManager?.setActionName(actionName)
        projectDidChange()
    }

    /// Reads the files, adds the usable ones to Media and, if asked, to the end of the timeline.
    func importFiles(_ urls: [URL], addToTimeline: Bool) {
        guard !urls.isEmpty else { return }
        isImporting = true
        Task {
            var probed: [MediaAsset] = []
            var failures: [String] = []
            for url in urls {
                // Keep access to files the user handed us for as long as the app runs.
                _ = url.startAccessingSecurityScopedResource()
                if let existing = project.assets.first(where: { $0.url.standardizedFileURL == url.standardizedFileURL }) {
                    probed.append(existing)
                    continue
                }
                do {
                    probed.append(try await MediaProbe.probe(url))
                } catch {
                    failures.append(url.lastPathComponent)
                }
            }
            isImporting = false

            apply(addToTimeline ? "Add to Timeline" : "Import") { project in
                for asset in probed {
                    let id = project.addAsset(asset)
                    if addToTimeline { project.appendClip(of: id) }
                }
            }
            for asset in probed where thumbnails[asset.id] == nil {
                loadThumbnail(for: asset)
            }
            if !failures.isEmpty {
                alert = AlertMessage(
                    title: failures.count == 1 ? "This file can't be used" : "These files can't be used",
                    message: failures.joined(separator: "\n") + "\n\nOnly video files can be added for now."
                )
            }
        }
    }

    func appendToTimeline(_ assetID: MediaAsset.ID) {
        apply("Add to Timeline") { $0.appendClip(of: assetID) }
    }

    func splitAtPlayhead() {
        var newID: Clip.ID?
        apply("Split Clip") { newID = $0.timeline.split(at: currentTime) }
        if let newID { selectedClipID = newID } else { NSSound.beep() }
    }

    func deleteSelectedClip() {
        guard let id = selectedClipID else { return }
        apply("Delete Clip") { $0.timeline.remove(id) }
        selectedClipID = nil
    }

    func setFraming(_ framing: Framing, for clipID: Clip.ID) {
        apply("Change Framing") { project in
            guard let index = project.timeline.index(of: clipID) else { return }
            project.timeline.clips[index].framing = framing
        }
    }

    func moveClip(_ clipID: Clip.ID, to index: Int) {
        apply("Move Clip") { $0.timeline.move(clipID, to: index) }
    }

    // MARK: Captions

    /// Transcribes the clips on the timeline that don't have captions in the chosen language yet,
    /// then shows the captions. The result is one undoable step.
    func makeCaptions() {
        guard captionJob == nil else { return }
        let language = captionLanguage
        let assets = project.assetsNeedingTranscription(in: language)
        guard !project.timeline.clips.isEmpty else { return }
        sidebar = .captions
        guard !assets.isEmpty else {
            apply("Show Captions") { $0.captions.isVisible = true }
            return
        }
        captionJob = .downloading(0)
        captionTask = Task {
            defer { captionJob = nil }
            do {
                try await Transcriber.prepare(language) { fraction in
                    if case .downloading = self.captionJob { self.captionJob = .downloading(fraction) }
                }
                var transcripts: [MediaAsset.ID: Transcript] = [:]
                for (index, asset) in assets.enumerated() {
                    try Task.checkCancellation()
                    captionJob = .listening(index: index + 1, count: assets.count)
                    transcripts[asset.id] = try await Transcriber.transcribe(asset.url, name: asset.name, language: language)
                }
                try Task.checkCancellation()
                apply("Make Captions") { project in
                    project.transcripts.merge(transcripts) { $1 }
                    project.captions.isVisible = true
                }
                if !project.hasCaptions {
                    alert = AlertMessage(
                        title: "No speech found",
                        message: "No words in \(language.displayName) were heard in your clips. Check the language, or that the clips have someone talking."
                    )
                }
            } catch is CancellationError {
                // The user stopped it; nothing changes.
            } catch {
                alert = AlertMessage(title: "Captions couldn't be made", message: error.localizedDescription)
            }
        }
    }

    func cancelCaptions() {
        captionTask?.cancel()
    }

    func setCaptionsVisible(_ visible: Bool) {
        apply(visible ? "Show Captions" : "Hide Captions") { $0.captions.isVisible = visible }
    }

    func setCaptionStyle(_ style: CaptionStyle) {
        apply("Change Caption Style") { $0.captions.style = style }
    }

    func setCaptionPosition(_ position: Double) {
        apply("Move Captions") { $0.captions.verticalPosition = position }
    }

    /// Replaces the words of a caption with what the user typed.
    func editCaption(_ page: CaptionPage, text: String) {
        guard text != page.text else { return }
        apply("Edit Caption") { $0.replaceWords(page.words.map(\.wordID), in: page.assetID, with: text) }
    }

    /// The caption on screen at the playhead.
    var currentCaption: CaptionPage? {
        CaptionLayout.page(at: currentTime, in: captionPages)
    }

    // MARK: Export

    /// Opens the Export sheet and runs the checks.
    func beginExport() {
        guard !project.timeline.clips.isEmpty, exportPhase == nil else { return }
        player.pause()
        exportPhase = .checking
        let project = project
        exportTask = Task {
            let firstSecond = CMTimeRange(start: .zero, duration: min(CMTime(value: 1, timescale: 1), project.duration))
            let peak: Float?
            do {
                peak = try await AudioProbe.peak(of: project, in: firstSecond)
            } catch {
                peak = 1  // Couldn't measure: skip that check rather than claim silence.
            }
            guard exportPhase == .checking else { return }
            exportPhase = .review(ExportReview.issues(for: project, openingPeak: peak))
        }
    }

    /// Writes the Short to `url`, showing progress in the Export sheet.
    func export(to url: URL) {
        let project = project
        exportPhase = .exporting(0)
        exportTask = Task {
            do {
                try await Exporter.export(project, to: url) { fraction in
                    if case .exporting = self.exportPhase { self.exportPhase = .exporting(fraction) }
                }
                exportPhase = .finished(url)
            } catch is CancellationError {
                exportPhase = nil
            } catch {
                exportPhase = .failed(error.localizedDescription)
            }
        }
    }

    /// Stops a running export (removing the partial file) or closes the sheet.
    func endExport() {
        exportTask?.cancel()
        exportTask = nil
        exportPhase = nil
    }

    /// A file name for the export, from the first clip's name.
    var suggestedExportName: String {
        let base = project.timeline.clips.first.flatMap { project.asset(id: $0.assetID)?.name } ?? "My"
        return "\(base) Short.mp4"
    }

    // MARK: Removing pauses

    /// Opens the Remove Pauses panel: measures the sound of the clips (once per file) and plans
    /// the cuts with settings suggested from the sound itself. Nothing changes until `applySilenceRemoval`.
    func beginRemovingSilences() {
        guard silenceSession == nil, !project.timeline.clips.isEmpty else { return }
        player.pause()
        silenceSession = SilenceSession()
        let assets = Dictionary(project.timeline.clips.compactMap { project.asset(id: $0.assetID) }.map { ($0.id, $0) }) { a, _ in a }
        Task {
            for asset in assets.values where asset.hasAudio && audioLevels[asset.id] == nil {
                if let levels = try? await AudioProbe.levels(of: asset.url) {
                    audioLevels[asset.id] = levels
                }
            }
            guard silenceSession != nil else { return }
            var settings = SilenceSettings()
            // Suggest from the file used most on the timeline.
            let main = project.timeline.clips.max { $0.duration < $1.duration }?.assetID
            if let main, let levels = audioLevels[main] { settings.threshold = levels.suggestedThreshold.rounded() }
            silenceSession?.isMeasuring = false
            updateSilenceSettings(settings)
        }
    }

    func updateSilenceSettings(_ settings: SilenceSettings) {
        guard silenceSession != nil else { return }
        silenceSession?.settings = settings
        silenceSession?.plan = SilencePlan.make(for: project, levels: audioLevels, settings: settings)
    }

    func applySilenceRemoval() {
        guard let plan = silenceSession?.plan, !plan.isEmpty else { return }
        silenceSession = nil
        apply("Remove Pauses") { $0.apply(plan) }
    }

    func cancelSilenceRemoval() {
        silenceSession = nil
    }

    /// Plays from the start, skipping the parts that would be cut.
    func previewSilenceRemoval() {
        seek(to: .zero)
        player.play()
    }

    // MARK: Playback

    private func playheadMoved(to time: CMTime) {
        currentTime = time
        // While previewing pause removal, jump over the parts that would be cut.
        // Compare whole frames: the player reports nanoseconds, and 3.233333333 s is a hair before
        // a cut ending at 97/30 s, which would otherwise jump to the same place forever.
        let frame = time.snappedToFrame()
        if let target = skipTarget, frame < target { return }
        skipTarget = nil
        if let cuts = silenceSession?.plan.timelineCuts, player.rate > 0,
           let cut = cuts.first(where: { $0.containsTime(frame) }) {
            skipTarget = cut.end
            seek(to: cut.end)
        }
    }

    func togglePlayback() {
        if isPlaying {
            player.pause()
        } else {
            if currentTime >= duration - .oneFrame { seek(to: .zero) }
            player.play()
        }
    }

    /// J/K/L shuttle: each press of L (or J) doubles the speed forwards (or backwards).
    func shuttle(forward: Bool) {
        let rate = player.rate
        if forward {
            player.rate = rate > 0 ? min(rate * 2, 8) : 1
        } else {
            player.rate = rate < 0 ? max(rate * 2, -8) : -1
        }
    }

    func pause() { player.pause() }

    func step(frames: Int) {
        player.pause()
        seek(to: currentTime + CMTime(value: Int64(frames), timescale: Project.frameRate))
    }

    func seek(to time: CMTime) {
        let clamped = CMTimeClampToRange(time.snappedToFrame(), range: CMTimeRange(start: .zero, duration: duration))
        currentTime = clamped
        player.seek(to: clamped, toleranceBefore: .zero, toleranceAfter: .zero)
    }

    // MARK: Timeline zoom

    func zoom(by factor: CGFloat) {
        timelineZoom = min(max(timelineZoom * factor, Self.zoomRange.lowerBound), Self.zoomRange.upperBound)
    }

    // MARK: Private

    /// Rebuilds the player's content from the project, keeping the playhead where it was.
    private func projectDidChange() {
        captionPages = CaptionLayout.pages(in: project)
        if let settings = silenceSession?.settings { updateSilenceSettings(settings) }
        rebuildTask?.cancel()
        let project = project
        rebuildTask = Task {
            guard !project.timeline.clips.isEmpty else {
                player.replaceCurrentItem(with: nil)
                currentTime = .zero
                return
            }
            do {
                let built = try await CompositionBuilder.build(project)
                guard !Task.isCancelled else { return }
                let time = min(currentTime, project.duration)
                player.replaceCurrentItem(with: built.makePlayerItem())
                seek(to: time)
            } catch {
                guard !Task.isCancelled else { return }
                alert = AlertMessage(title: "Playback problem", message: error.localizedDescription)
            }
        }
    }

    private func loadThumbnail(for asset: MediaAsset) {
        Task {
            if let image = try? await MediaProbe.thumbnail(for: asset.url) {
                thumbnails[asset.id] = image
            }
        }
    }
}
