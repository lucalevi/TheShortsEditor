import AppKit
import CoreMedia
import EditorCore
import SwiftUI

// A main clip on the timeline: its block, trimming by its edges, clicking and dragging it.
extension TimelineView {
    /// `shift`: how far the clip slides aside while others are dragged past it.
    func clipView(_ clip: Clip, index: Int, shift: CGFloat) -> some View {
        let slot = max(width(of: clip.duration), 2)
        let trim = clipTrim?.id == clip.id ? clipTrim : nil
        let delta = trim.map { width(of: $0.delta) } ?? 0
        let shown = trim?.edge == .start ? slot - delta : trim?.edge == .end ? slot + delta : slot
        let isDragged = reorder.map { !$0.isCancelled && $0.ids.contains(clip.id) } ?? false
        let asset = model.project.asset(id: clip.assetID)
        return ClipBlock(
            clip: clip,
            name: asset?.name ?? "Missing",
            aspect: aspect(of: asset),
            filmstrip: model.filmstrips[clip.assetID],
            levels: model.audioLevels[clip.assetID],
            tooLoud: model.tooLoudRanges(of: clip),
            pointsPerSecond: pointsPerSecond,
            isSelected: model.isSelected(.clip(clip.id)), waveHeight: waveHeight,
            isReversed: asset?.reversedFrom != nil,
            progress: model.tasks.progress(.backwards(clip.id))
        )
        .equatable()
        .modifier(TimelineItemAccessibility(clip: clip, index: index, model: model))
        .accessibilityIdentifier("timeline.clip") // found by the UI tests
        .overlay(alignment: .bottom) {
            if trim == nil, !clip.soundDetached, !clip.isFrozen, model.audioLevels[clip.assetID] != nil, slot > 16 {
                volumeEditor(for: clip, item: .clip(clip.id))
                    .frame(height: waveHeight - 2)
                    .padding(.horizontal, 1)
                    .padding(.bottom, 1)
            }
        }
        .overlay(alignment: .leading) {
            EdgeHandle(edge: .leading, help: "Drag to trim the start of the clip") { dx in
                updateClipTrim(clip, edge: .start, points: dx)
            } onEnd: {
                endClipTrim()
            }
        }
        .overlay(alignment: .trailing) {
            EdgeHandle(edge: .trailing, help: "Drag to trim the end of the clip") { dx in
                updateClipTrim(clip, edge: .end, points: dx)
            } onEnd: {
                endClipTrim()
            }
        }
        .frame(width: max(shown, 4), height: trackHeight)
        .offset(x: trim?.edge == .start ? delta : 0)
        .opacity(isDragged ? 0.8 : 1)
        .offset(x: isDragged ? reorderDX : shift, y: isDragged ? -6 : 0)
        .shadow(color: .black.opacity(isDragged ? 0.5 : 0), radius: 6, y: 3)
        .zIndex(isDragged || trim != nil ? 1 : 0)
        .frame(width: slot, height: trackHeight, alignment: .leading)
        .onTapGesture { location in
            let modifiers = NSEvent.modifierFlags
            model.timelineRange = nil
            model.click(.clip(clip.id), modifiers: modifiers)
            // ⌘/⇧-clicks only change the selection; a plain click also moves the playhead.
            guard modifiers.isDisjoint(with: [.command, .shift]) else { return }
            let start = model.project.timeline.startTime(ofClipAt: index)
            model.playback.pause()
            model.playback.seek(to: start + seconds(location.x))
        }
        .gesture(clipDragGesture(clip))
        .contextMenu { clipMenu(clip, index: index) }
    }
}

// Dragging main clips to a new place: the others slide aside to show where they land.
extension TimelineView {
    /// Dragging a main clip moves it (with the other selected clips); with R held it picks a range.
    func clipDragGesture(_ clip: Clip) -> some Gesture {
        DragGesture(minimumDistance: 4, coordinateSpace: .named(Self.contentSpace))
            .onChanged { value in
                // With R held, dragging picks a range instead of moving the clip.
                if rangeAnchor != nil || (reorder == nil && model.isRangeKeyDown) {
                    if rangeAnchor == nil {
                        model.playback.pause()
                        rangeAnchor = time(at: value.startLocation.x)
                    }
                    model.setTimelineRange(from: rangeAnchor!, to: time(at: value.location.x))
                    return
                }
                if reorder == nil {
                    model.playback.pause()
                    if !model.isSelected(.clip(clip.id)) { model.selectedClipID = clip.id }
                    let ids = model.clipsMovedWith(clip.id)
                    reorder = Reorder(
                        ids: ids, startX: value.startLocation.x, pointerX: value.location.x, scrollX: visibleRect.minX,
                        destination: model.project.timeline.dropIndex(moving: ids, at: time(at: value.location.x)))
                    watchReorder()
                }
                guard reorder?.isCancelled == false else { return }
                reorder?.pointerX = value.location.x
                reorder?.scrollX = visibleRect.minX
                updateReorderDestination()
            }
            .onEnded { _ in
                if rangeAnchor != nil {
                    rangeAnchor = nil
                    return
                }
                endReorder()
            }
    }

    /// Where the pointer is now, in content coordinates, also while the timeline scrolls by itself.
    var reorderPointerX: CGFloat {
        guard let reorder else { return 0 }
        return reorder.pointerX + visibleRect.minX - reorder.scrollX
    }

    /// How far the dragged clips have moved from where they were.
    var reorderDX: CGFloat {
        guard let reorder else { return 0 }
        return reorderPointerX - reorder.startX
    }

    /// The clips as they will be if the drag ends here.
    var reorderPreview: [Clip]? {
        guard let reorder, !reorder.isCancelled else { return nil }
        return model.project.timeline.reordered(moving: reorder.ids, to: reorder.destination)
    }

    /// How far each clip not being dragged slides to open the gap.
    var reorderShifts: [Clip.ID: CGFloat] {
        guard let preview = reorderPreview else { return [:] }
        var shifts: [Clip.ID: CGFloat] = [:]
        var now = CMTime.zero, then = CMTime.zero
        let newStarts = Dictionary(
            uniqueKeysWithValues: preview.map { clip in
                defer { then = then + clip.duration }
                return (clip.id, then)
            })
        for clip in model.project.timeline.clips {
            shifts[clip.id] = width(of: (newStarts[clip.id] ?? now) - now)
            now = now + clip.duration
        }
        return shifts
    }

    /// The gap the dragged clips will fill: its start and length.
    var reorderSlot: (start: CMTime, duration: CMTime)? {
        guard let reorder, let preview = reorderPreview, let first = preview.firstIndex(where: { reorder.ids.contains($0.id) }) else { return nil }
        let start = preview[..<first].reduce(CMTime.zero) { $0 + $1.duration }
        let length = preview.filter { reorder.ids.contains($0.id) }.reduce(CMTime.zero) { $0 + $1.duration }
        return (start, length)
    }

    func updateReorderDestination() {
        guard let reorder, !reorder.isCancelled else { return }
        let destination = model.project.timeline.dropIndex(moving: reorder.ids, at: time(at: reorderPointerX))
        if destination != reorder.destination {
            withAnimation(.snappy(duration: 0.2)) { self.reorder?.destination = destination }
        }
    }

    func endReorder() {
        guard let reorder else { return }
        self.reorder = nil
        if !reorder.isCancelled { model.moveClips(reorder.ids, to: reorder.destination) }
    }

    /// Escape: the clips go back where they were; the drag does nothing more until the mouse is let go.
    func cancelReorder() {
        guard reorder != nil else { return }
        withAnimation(.snappy(duration: 0.2)) { reorder?.isCancelled = true }
    }

    /// While clips are dragged: the timeline scrolls when they are near its left or right edge, and
    /// Escape cancels. (Key presses don't arrive while the mouse button is down, so Escape is
    /// looked at here.)
    func watchReorder() {
        Task { @MainActor in
            while let reorder, !reorder.isCancelled {
                if CGEventSource.keyState(.combinedSessionState, key: 53) {
                    cancelReorder()
                    return
                }
                let x = reorderPointerX
                let edge: CGFloat = 40
                var step: CGFloat = 0
                if x > visibleRect.maxX - edge, visibleRect.maxX < contentWidth {
                    step = min(16, (x - (visibleRect.maxX - edge)) / 2 + 2)
                } else if x < visibleRect.minX + edge, visibleRect.minX > 0 {
                    step = -min(16, ((visibleRect.minX + edge) - x) / 2 + 2)
                }
                if step != 0 {
                    scrollPosition.scrollTo(point: CGPoint(x: max(0, visibleRect.minX + step), y: visibleRect.minY))
                    updateReorderDestination()
                }
                try? await Task.sleep(for: .milliseconds(16))
            }
        }
    }
}

// Tiles dragged from the browser (titles, transitions, effects, filters, music).
extension TimelineView {
    /// Files and browser tiles dropped on the main clips.
    var clipRowDrop: ClipRowDrop {
        ClipRowDrop(onUpdate: dropHover, onDrop: drop) { texts, x in dropBrowserTiles(texts, at: x) }
    }

    @discardableResult
    func dropBrowserTiles(_ texts: [String], at x: CGFloat) -> Bool {
        let drops = texts.compactMap(BrowserDrop.init(text:))
        guard !drops.isEmpty else { return false }
        for drop in drops { model.dropBrowserItem(drop, at: time(at: x)) }
        return true
    }
}

// The ruler across the top: click or drag it to move the playhead.
extension TimelineView {
    var ruler: some View {
        Canvas { context, size in
            let step = rulerStep
            var second = 0.0
            while leadingInset + CGFloat(second) * pointsPerSecond < size.width {
                let x = leadingInset + CGFloat(second) * pointsPerSecond
                context.fill(Path(CGRect(x: x, y: size.height - 8, width: 1, height: 8)), with: .color(.secondary))
                let label = TimeFormat.string(CMTime(seconds: second, preferredTimescale: 600)).dropLast(2)
                context.draw(Text(label).font(.caption2).foregroundStyle(.secondary), at: CGPoint(x: x + 3, y: 7), anchor: .leading)
                second += step
            }
        }
        .frame(height: rulerHeight)
        .background(Theme.timeline)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0).onChanged { value in
                model.playback.pause()
                model.playback.seek(to: time(at: value.location.x))
            }
        )
        .help("Click or drag to move the playhead")
        .playheadAccessibility(model.playback)
    }

    /// A label every 1, 2, 5, 10… seconds, whichever keeps them about 60 points apart.
    var rulerStep: Double {
        [1.0, 2, 5, 10, 15, 30, 60].first { $0 * pointsPerSecond >= 60 } ?? 60
    }
}
