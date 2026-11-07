import AVFoundation
import EditorCore
import Observation
import RenderEngine
import SwiftUI

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

    let player = AVPlayer()
    /// The window's undo manager, so Edit ▸ Undo and ⌘Z work. Set by the main view.
    var undoManager: UndoManager?

    @ObservationIgnored private var rebuildTask: Task<Void, Never>?
    @ObservationIgnored private var timeObserver: Any?
    @ObservationIgnored private var statusObservation: NSKeyValueObservation?

    static let zoomRange: ClosedRange<CGFloat> = 15...400

    struct AlertMessage: Identifiable {
        let id = UUID()
        let title: String
        let message: String
    }

    init() {
        player.actionAtItemEnd = .pause
        timeObserver = player.addPeriodicTimeObserver(forInterval: .oneFrame, queue: .main) { [weak self] time in
            MainActor.assumeIsolated { self?.currentTime = time }
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

    // MARK: Playback

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
