import AppKit
import CoreMedia
import EditorCore
import RenderEngine
import UniformTypeIdentifiers

/// Settings keys shared by the Settings window and the editor.
enum SettingsKey {
    static let pictureSeconds = "pictureSeconds"
    static let picturePlacement = "picturePlacement"
    static let slowMotionAutomatically = "slowMotionAutomatically"
    /// Already used by transitions (`EditorModel.preferredTransition`).
    static let transitionFrames = "transitionFrames"
}

/// Media and finishing: settings for new clips, markers, the clip trimmer, saving a frame,
/// and the Photos library.
extension EditorModel {
    // MARK: Settings

    /// How new clips start, from Settings.
    var newClipSettings: NewClipSettings {
        let defaults = UserDefaults.standard
        let seconds = defaults.object(forKey: SettingsKey.pictureSeconds) as? Double ?? MediaAsset.imageClipDuration.seconds
        let placement = defaults.string(forKey: SettingsKey.picturePlacement).flatMap(NewClipSettings.PicturePlacement.init(rawValue:)) ?? .automatic
        let slowMotion = defaults.object(forKey: SettingsKey.slowMotionAutomatically) as? Bool ?? true
        return NewClipSettings(pictureLength: CMTime(seconds: seconds, preferredTimescale: 600), picturePlacement: placement, slowsDownSlowMotion: slowMotion)
    }

    // MARK: Markers

    /// M: a marker where the pointer is skimming, or at the playhead.
    func addMarker() {
        guard !project.timeline.clips.isEmpty else {
            NSSound.beep()
            return
        }
        let time = skimTime ?? currentTime
        apply("Add Marker") { $0.addMarker(at: time) }
        showTip(.markers)
    }

    func renameMarker(_ id: Marker.ID, to name: String) {
        apply("Rename Marker") { $0.renameMarker(id, to: name) }
    }

    func moveMarker(_ id: Marker.ID, to time: CMTime) {
        apply("Move Marker") { $0.moveMarker(id, to: time) }
    }

    func deleteMarker(_ id: Marker.ID) {
        apply("Delete Marker") { $0.removeMarker(id) }
    }

    /// The marker at the playhead, if there is one there.
    var markerAtPlayhead: Marker? {
        project.markers.first { $0.time == currentTime.snappedToFrame() }
    }

    /// Jumps to the previous or next marker.
    func goToMarker(forward: Bool) {
        guard let marker = project.marker(from: currentTime, forward: forward) else {
            NSSound.beep()
            return
        }
        pause()
        skimTime = nil
        seek(to: marker.time)
    }

    /// Where a marker being dragged lands: on a whole frame, sticking to cuts and edges when snapping is on.
    func markerDropTime(_ time: CMTime, for id: Marker.ID) -> CMTime {
        guard snapsToEdges else { return time.snappedToFrame() }
        let targets = Snapping.targets(in: project, playhead: currentTime, excludingMarker: id)
        return (Snapping.snap(time, to: targets, tolerance: snapTolerance) ?? time).snappedToFrame()
    }

    // MARK: Clip trimmer

    /// The clip the trimmer works on: the selected main clip or B-roll (a video, not a freeze frame).
    var trimmableClip: Clip? {
        guard timelineSelection.count == 1 else { return nil }
        let id: Clip.ID? =
            switch selection {
            case .clip(let id)?, .overlay(let id)?: id
            default: nil
            }
        guard let id, let clip = project.anyClip(id: id), let media = project.asset(id: clip.assetID),
            media.hasVideo, !media.isImage, !clip.isFrozen
        else { return nil }
        return clip
    }

    /// ⌘\: opens the trimmer for the selected clip, or closes it.
    func toggleClipTrimmer() {
        if trimmerClipID != nil {
            trimmerClipID = nil
            return
        }
        guard let clip = trimmableClip else {
            NSSound.beep()
            return
        }
        pause()
        trimmerClipID = clip.id
    }

    /// Moves one end of the trimmer's clip by `sourceDelta` of its file.
    func trimInTrimmer(_ id: Clip.ID, edge: ClipEdge, bySource sourceDelta: CMTime) {
        guard let clip = project.anyClip(id: id) else { return }
        let delta = clip.timelineDuration(ofSource: sourceDelta)
        if project.timeline.index(of: id) != nil {
            trimClip(id, edge: edge, by: delta)
        } else {
            trimOverlay(id, edge: edge, by: delta)
        }
    }

    /// Slides which part of its file the clip shows, keeping its length and place.
    func slipClip(_ id: Clip.ID, bySource delta: CMTime) {
        apply("Slide Clip") { $0.slipClip(id, by: delta) }
    }

    // MARK: Saving a frame

    /// File ▸ Save Frame…: the picture at the playhead (with titles and captions) as a JPEG or PNG,
    /// for the Short's thumbnail.
    func saveFrame() {
        guard !project.timeline.clips.isEmpty else {
            NSSound.beep()
            return
        }
        pause()
        let time = currentTime
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.jpeg, .png]
        panel.allowsOtherFileTypes = false
        panel.canCreateDirectories = true
        let base = documentName.isEmpty ? "Short" : documentName
        panel.nameFieldStringValue = "\(base) at \(TimeFormat.string(time).replacingOccurrences(of: ":", with: "."))"
        panel.message = "Save the picture at the playhead. End the name with .png for a PNG; otherwise it is saved as a JPEG."
        panel.prompt = "Save"
        guard panel.runModal() == .OK, var url = panel.url else { return }
        let format: FrameExport.Format = url.pathExtension.lowercased() == "png" ? .png : .jpeg
        if url.pathExtension.isEmpty { url = url.appendingPathExtension(format == .png ? "png" : "jpg") }
        let project = project
        Task {
            do {
                let image = try await FrameExport.frame(of: project, at: time)
                try FrameExport.write(image, to: url, format: format)
                NSWorkspace.shared.activateFileViewerSelecting([url])
            } catch {
                Log.export.failure("saveFrame", error)
                alert = AlertMessage(title: "The frame couldn't be saved", message: error.localizedDescription)
            }
        }
    }

    /// About how big the exported file will be.
    var exportSizeEstimate: String {
        ExportEstimate.description(bytes: ExportEstimate.bytes(duration: duration, videoBitRate: Exporter.videoBitRate, audioBitRate: Exporter.audioBitRate))
    }
}
