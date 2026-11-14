import AVFoundation
import EditorCore
import RenderEngine
import SwiftUI

/// Trimming, B-roll, and where pictures sit on screen (placement, punch-in, motion).
extension EditorModel {
    // MARK: Lookups

    var selectedOverlayID: Clip.ID? {
        if case .overlay(let id)? = selection { id } else { nil }
    }

    var selectedOverlay: Overlay? {
        selectedOverlayID.flatMap(project.overlay(id:))
    }

    /// The main clip playing at the playhead.
    var clipAtPlayhead: Clip? {
        project.timeline.locate(currentTime.snappedToFrame()).map { project.timeline.clips[$0.index] }
            ?? (currentTime >= duration ? project.timeline.clips.last : nil)
    }

    /// The selected clip (main or B-roll) when its picture is on screen at the playhead, so it
    /// can be moved and resized in the viewer.
    var adjustableClip: Clip? {
        switch selection {
        case .overlay(let id)?:
            guard let overlay = project.overlay(id: id), overlay.visibleRange(in: project)?.containsTime(currentTime) == true else { return nil }
            return overlay.clip
        case .clip(let id)?:
            return clipAtPlayhead?.id == id ? clipAtPlayhead : nil
        default:
            return nil
        }
    }

    /// The source time of a clip (main or B-roll) at the playhead.
    func sourceTimeAtPlayhead(of clipID: Clip.ID) -> CMTime {
        project.sourceTime(ofClip: clipID, at: currentTime) ?? .zero
    }

    /// Where a clip's picture is at the playhead.
    func placementAtPlayhead(of clip: Clip) -> Placement {
        clip.placement(atSourceTime: sourceTimeAtPlayhead(of: clip.id))
    }

    /// Where a keyframe is on the timeline, for going to it.
    func timelineTime(of keyframe: Keyframe, in clipID: Clip.ID) -> CMTime? {
        guard let clip = project.anyClip(id: clipID), let start = project.timelineStart(ofClip: clipID) else { return nil }
        return start + clip.timelineOffset(ofSourceTime: keyframe.time)
    }

    // MARK: Trimming

    /// Moves an edge of a main clip (dragged on the timeline). The clips after it follow.
    func trimClip(_ id: Clip.ID, edge: ClipEdge, by delta: CMTime) {
        apply("Trim Clip") { $0.trimClip(id, edge: edge, by: delta) }
    }

    /// Takes off the part of the clip before the playhead (Q) or after it (W). Works on the
    /// selected B-roll when it is under the playhead, otherwise on the main clip there.
    func trimToPlayhead(removing edge: ClipEdge) {
        player.pause()
        let time = currentTime.snappedToFrame()
        if let overlay = selectedOverlay, overlay.range.containsTime(time), time > overlay.start {
            let delta = edge == .start ? time - overlay.start : time - overlay.end
            apply(edge == .start ? "Trim Start" : "Trim End") { $0.trimOverlay(overlay.id, edge: edge, by: delta) }
            return
        }
        var playhead: CMTime?
        apply(edge == .start ? "Trim Start" : "Trim End") { playhead = $0.trimMainClip(at: time, removing: edge) }
        if let playhead { seek(to: playhead) } else { NSSound.beep() }
    }

    // MARK: Snapping

    /// How close an edge must come to stick, as time at the current timeline zoom.
    var snapTolerance: CMTime {
        CMTime(seconds: Snapping.distance / Double(timelineZoom), preferredTimescale: 600)
    }

    /// `time` stuck to the nearest edge or the playhead, when snapping is on and one is close.
    func snapped(_ time: CMTime, excluding item: TimelineItem? = nil) -> CMTime? {
        guard snapsToEdges else { return nil }
        let targets = Snapping.targets(in: project, playhead: currentTime, excluding: item.map { [$0] } ?? [])
        return Snapping.snap(time, to: targets, tolerance: snapTolerance)
    }

    /// For a block keeping its length: the start that makes one of its edges stick.
    func snappedStart(_ start: CMTime, duration: CMTime, excluding item: TimelineItem) -> CMTime? {
        guard snapsToEdges else { return nil }
        let targets = Snapping.targets(in: project, playhead: currentTime, excluding: [item])
        return Snapping.snapBlock(start: start, duration: duration, to: targets, tolerance: snapTolerance)
    }

    // MARK: B-roll

    /// Puts a video or picture over the clips at the playhead (B-roll), and selects it.
    func addOverlay(_ assetID: MediaAsset.ID) {
        guard !project.timeline.clips.isEmpty else { return }
        player.pause()
        var id: Clip.ID?
        apply("Add Over Clips") { id = $0.addOverlay(of: assetID, at: currentTime) }
        if let id { selection = .overlay(id) }
    }

    func moveOverlay(_ id: Clip.ID, to start: CMTime) {
        apply("Move Clip") { $0.moveOverlay(id, to: start) }
    }

    func trimOverlay(_ id: Clip.ID, edge: ClipEdge, by delta: CMTime) {
        apply("Trim Clip") { $0.trimOverlay(id, edge: edge, by: delta) }
    }

    /// Selects a B-roll clip and moves the playhead onto it when it isn't there already.
    func selectOverlay(_ id: Clip.ID) {
        selection = .overlay(id)
        guard let overlay = project.overlay(id: id), let range = overlay.visibleRange(in: project) else { return }
        if !range.containsTime(currentTime) {
            player.pause()
            seek(to: range.start)
        }
    }

    // MARK: Where the picture sits

    /// Shows `placement` for a clip straight away while it is dragged in the viewer, without
    /// changing the Short yet. Nil goes back to what the Short has.
    func previewPlacement(_ placement: Placement?, for clipID: Clip.ID) {
        LivePreview.set(placement, for: clipID)
        redrawCurrentFrame()
    }

    /// Sets where a clip's picture is at the playhead: its fixed placement, or a keyframe there
    /// when it moves.
    func setPlacement(_ placement: Placement, for clipID: Clip.ID, actionName: String = "Move Picture") {
        let sourceTime = sourceTimeAtPlayhead(of: clipID)
        let before = project
        apply(actionName) { $0.updateAnyClip(clipID) { $0.setPlacement(placement, atSourceTime: sourceTime) } }
        // A real change keeps showing the dragged placement until the rebuilt Short arrives (it
        // clears it); no change means no rebuild, so stop showing it now.
        if project == before { previewPlacement(nil, for: clipID) }
    }

    /// Changes part of the placement at the playhead (size, position, angle).
    func editPlacement(of clip: Clip, _ actionName: String, _ change: (inout Placement) -> Void) {
        var placement = placementAtPlayhead(of: clip)
        change(&placement)
        setPlacement(placement, for: clip.id, actionName: actionName)
    }

    func resetPlacement(of clipIDs: [Clip.ID]) {
        apply("Reset Position and Size") { project in
            for id in clipIDs {
                project.updateAnyClip(id) { clip in
                    clip.placement = .identity
                    clip.keyframes = []
                }
            }
        }
    }

    func setBackground(_ background: ClipBackground, for clipIDs: [Clip.ID]) {
        apply("Change Background") { project in
            for id in clipIDs { project.updateAnyClip(id) { $0.background = background } }
        }
    }

    /// Whether every one of these clips is punched in (and none moves over time).
    func isPunchedIn(_ clips: [Clip]) -> Bool {
        !clips.isEmpty && clips.allSatisfy { !$0.hasMotion && abs($0.placement.scale - Placement.punchInScale) < 0.001 }
    }

    /// Zooms the clips in a little (or back out when they all are), keeping where they sit.
    func togglePunchIn(_ clipIDs: [Clip.ID]) {
        let clips = clipIDs.compactMap(project.anyClip(id:)).filter { !$0.hasMotion }
        guard !clips.isEmpty else { return }
        let zoomOut = isPunchedIn(clips)
        apply(zoomOut ? "Remove Punch-In" : "Punch In") { project in
            for clip in clips { project.updateAnyClip(clip.id) { $0.placement.scale = zoomOut ? 1 : Placement.punchInScale } }
        }
    }

    /// Zooms in on every other cut of the same recording: the selected clips, or all of them.
    func punchInOnAlternateCuts() {
        let selected = Set(
            timelineSelection.items.compactMap { item -> Clip.ID? in
                if case .clip(let id) = item { id } else { nil }
            })
        apply("Punch In on Every Other Cut") { $0.punchInOnAlternateCuts(selected.count > 1 ? selected : nil) }
    }

    // MARK: Motion

    func applyMotion(_ preset: MotionPreset, to clipID: Clip.ID) {
        let source = sourceTimeAtPlayhead(of: clipID)
        apply(preset.displayName) { $0.updateAnyClip(clipID) { $0.applyMotion(preset, playheadSource: source) } }
    }

    /// Records where the picture is now as a keyframe at the playhead; from then on, changes made
    /// at other times add keyframes there, and the picture moves between them.
    func addKeyframe(to clipID: Clip.ID) {
        let source = sourceTimeAtPlayhead(of: clipID)
        apply("Add Keyframe") { $0.updateAnyClip(clipID) { $0.addKeyframe(at: source) } }
    }

    func removeKeyframe(_ keyframeID: Keyframe.ID, from clipID: Clip.ID) {
        apply("Delete Keyframe") { $0.updateAnyClip(clipID) { $0.removeKeyframe(keyframeID) } }
    }

    func removeMotion(from clipID: Clip.ID) {
        let source = sourceTimeAtPlayhead(of: clipID)
        apply("Remove Motion") { $0.updateAnyClip(clipID) { $0.removeMotion(keepingPlacementAt: source) } }
    }

    func goToKeyframe(_ keyframe: Keyframe, in clipID: Clip.ID) {
        guard let time = timelineTime(of: keyframe, in: clipID) else { return }
        player.pause()
        seek(to: time)
    }

    // MARK: Private

    /// Draws the frame at the playhead again (after a live placement or look change).
    func redrawCurrentFrame() {
        guard player.currentItem != nil, !isPlaying else { return }
        // A paused player may keep the frame it has for a seek to the very same time, so every
        // other redraw asks for a millisecond later: the same picture, but drawn anew.
        redrawNudged.toggle()
        let time = currentTime.snappedToFrame() + (redrawNudged ? CMTime(value: 1, timescale: 1000) : .zero)
        player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
    }
}

@MainActor private var redrawNudged = false
