import AppKit
import CoreMedia
import EditorCore
import SwiftUI

// A main clip on the timeline: its block, trimming by its edges, clicking and dragging it.
extension TimelineView {
    func clipView(_ clip: Clip, index: Int) -> some View {
        let slot = max(width(of: clip.duration), 2)
        let trim = clipTrim?.id == clip.id ? clipTrim : nil
        let delta = trim.map { width(of: $0.delta) } ?? 0
        let shown = trim?.edge == .start ? slot - delta : trim?.edge == .end ? slot + delta : slot
        let isDragged = reorder?.id == clip.id
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
        .offset(x: isDragged ? reorder!.dx : 0, y: isDragged ? -6 : 0)
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
        .gesture(
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
                    }
                    reorder = Reorder(id: clip.id, dx: value.translation.width, destination: destination(for: clip, index: index, dx: value.translation.width))
                }
                .onEnded { value in
                    if rangeAnchor != nil {
                        rangeAnchor = nil
                        return
                    }
                    let target = destination(for: clip, index: index, dx: value.translation.width)
                    reorder = nil
                    if target != index { model.moveClip(clip.id, to: target) }
                }
        )
        .contextMenu { clipMenu(clip, index: index) }
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
