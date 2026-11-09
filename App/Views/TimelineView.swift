import AVFoundation
import EditorCore
import RenderEngine
import SwiftUI

/// The storyline and everything over and under it: titles, B-roll, the clips, captions and music,
/// with a ruler for scrubbing and the playhead.
struct TimelineView: View {
    @Bindable var model: EditorModel
    @State private var scrollPosition = ScrollPosition(edge: .leading)
    @State private var visibleRect: CGRect = .zero
    @State private var isDropTargeted = false
    /// A title or B-roll clip being dragged: moved, or one of its edges.
    @State private var blockDrag: BlockDrag?
    /// A main clip being dragged to a new place in the storyline.
    @State private var reorder: Reorder?
    /// An edge of a main clip being dragged.
    @State private var clipTrim: ClipTrim?
    /// Where a dragged edge is sticking, to draw a line there.
    @State private var snapLine: CMTime?
    /// The rectangle being drawn across the timeline to select what it covers.
    @State private var marquee: CGRect?
    /// The selection when the rectangle was started, which it adds to while ⌘ or ⇧ is held.
    @State private var marqueeBase: TimelineSelection?

    struct BlockDrag {
        enum Kind { case move, start, end }
        var item: TimelineItem
        var kind: Kind
        /// How far it moved, already stuck to an edge when close to one.
        var delta: CMTime
    }

    struct Reorder {
        var id: Clip.ID
        var dx: CGFloat
        var destination: Int
    }

    struct ClipTrim {
        var id: Clip.ID
        var edge: ClipEdge
        var delta: CMTime
    }

    // MARK: Layout

    private let rulerHeight: CGFloat = 24
    private let trackHeight: CGFloat = 72
    private let captionLaneHeight: CGFloat = 22
    private let titleRowHeight: CGFloat = 22
    private let overlayRowHeight: CGFloat = 40
    private let musicLaneHeight: CGFloat = 30
    private let soundRowHeight: CGFloat = 26
    private let rowGap: CGFloat = 3
    private let leadingInset: CGFloat = 12

    private var titleRows: [TextOverlay.ID: Int] {
        LanePacking.rows(model.project.titles.map { (id: $0.id, range: $0.range) })
    }
    private var overlayRows: [Clip.ID: Int] {
        LanePacking.rows(model.project.overlays.map { (id: $0.id, range: $0.range) })
    }
    private var soundRows: [Clip.ID: Int] {
        LanePacking.rows(model.project.sounds.map { (id: $0.id, range: $0.range) })
    }
    private var titleRowCount: Int { LanePacking.count(titleRows) }
    private var overlayRowCount: Int { LanePacking.count(overlayRows) }

    private var titlesY: CGFloat { rulerHeight + 6 }
    private var titlesHeight: CGFloat { CGFloat(titleRowCount) * (titleRowHeight + 2) }
    private var overlaysY: CGFloat { titlesY + titlesHeight + rowGap }
    private var overlaysHeight: CGFloat { CGFloat(overlayRowCount) * (overlayRowHeight + rowGap) }
    private var clipsY: CGFloat { overlaysY + overlaysHeight + 2 }
    private var captionsY: CGFloat { clipsY + trackHeight + 6 }
    private var soundsY: CGFloat { captionsY + captionLaneHeight + 4 }
    private var soundsHeight: CGFloat { CGFloat(LanePacking.count(soundRows)) * (soundRowHeight + 2) }
    private var musicY: CGFloat { soundsY + soundsHeight + 2 }
    private var contentHeight: CGFloat { musicY + musicLaneHeight + 12 }

    private var pointsPerSecond: CGFloat { model.timelineZoom }

    private func x(for time: CMTime) -> CGFloat {
        leadingInset + CGFloat(time.seconds) * pointsPerSecond
    }

    private func width(of duration: CMTime) -> CGFloat {
        CGFloat(duration.seconds) * pointsPerSecond
    }

    private func time(at x: CGFloat) -> CMTime {
        CMTime(seconds: max(0, Double((x - leadingInset) / pointsPerSecond)), preferredTimescale: 600)
    }

    private func seconds(_ points: CGFloat) -> CMTime {
        CMTime(seconds: Double(points / pointsPerSecond), preferredTimescale: 600)
    }

    var body: some View {
        VStack(spacing: 0) {
            PanelHeader(title: "Timeline") {
                HStack(spacing: 8) {
                    Text("\(TimeFormat.string(model.duration)) of 3:00")
                        .monospacedDigit()
                        .foregroundStyle(model.project.isOverMaxDuration ? .red : .secondary)
                    Divider().frame(height: 14)
                    Toggle(isOn: $model.snapsToEdges) {
                        Label("Snapping", systemImage: "arrow.right.and.line.vertical.and.arrow.left")
                    }
                    .toggleStyle(.button)
                    .labelStyle(.iconOnly)
                    .controlSize(.small)
                    .help(model.snapsToEdges ? "Snapping is on: dragged edges stick to cuts, other items and the playhead (S)"
                          : "Snapping is off (S)")
                    Divider().frame(height: 14)
                    Image(systemName: "minus.magnifyingglass").foregroundStyle(.secondary)
                    Slider(value: $model.timelineZoom, in: EditorModel.zoomRange)
                        .frame(width: 110)
                        .controlSize(.small)
                        .help("Zoom the timeline (⌘+ / ⌘−)")
                    Image(systemName: "plus.magnifyingglass").foregroundStyle(.secondary)
                }
                .font(.callout)
            }
            GeometryReader { geometry in
                ScrollView([.horizontal, .vertical]) {
                    ZStack(alignment: .topLeading) {
                        marqueeArea
                        ruler
                        titleLane.offset(y: titlesY)
                        overlayLane.offset(y: overlaysY)
                        clipsRow.offset(y: clipsY)
                        captionLane.offset(y: captionsY)
                        soundLane.offset(y: soundsY)
                        musicLane.offset(y: musicY)
                        pauseCuts.offset(y: clipsY)
                        limitMarker
                        snapIndicator
                        playhead
                        marqueeRectangle
                    }
                    .coordinateSpace(.named(Self.contentSpace))
                    .frame(width: max(geometry.size.width, contentWidth), height: max(geometry.size.height, contentHeight), alignment: .topLeading)
                }
                .scrollPosition($scrollPosition)
                .onScrollGeometryChange(for: CGRect.self) { $0.visibleRect } action: { _, newValue in
                    visibleRect = newValue
                }
            }
            .background(isDropTargeted ? Color.accentColor.opacity(0.08) : Color.clear)
            .background(Theme.timeline)
            .dropDestination(for: URL.self) { urls, _ in
                model.importFiles(urls, addToTimeline: true)
                return true
            } isTargeted: { isDropTargeted = $0 }
        }
        .onChange(of: model.currentTime) {
            // Keep the playhead in view while playing.
            let playheadX = x(for: model.currentTime)
            if model.isPlaying, !(visibleRect.minX...visibleRect.maxX).contains(playheadX) {
                scrollPosition.scrollTo(point: CGPoint(x: max(0, playheadX - 40), y: visibleRect.minY))
            }
        }
    }

    /// Coordinates of the whole timeline content, the same ones `time(at:)` understands.
    private static let contentSpace = "timelineContent"

    /// A plain click on an item (not ⌘/⇧) also moves the playhead to where it was clicked, as in CapCut or iMovie.
    private func clickTap(_ select: @escaping (EditorModel.Selection?, NSEvent.ModifierFlags) -> Void) -> some Gesture {
        SpatialTapGesture(coordinateSpace: .named(Self.contentSpace)).onEnded { value in
            let modifiers = NSEvent.modifierFlags
            select(nil, modifiers)
            guard modifiers.isDisjoint(with: [.command, .shift]) else { return }
            model.pause()
            model.seek(to: time(at: value.location.x))
        }
    }

    private var contentWidth: CGFloat {
        x(for: model.duration) + 10 * pointsPerSecond
    }

    /// In a right-click menu: deletes all selected items when this one is among several selected,
    /// otherwise just this one.
    @ViewBuilder
    private func deleteButton(for item: EditorModel.Selection, single: String) -> some View {
        let count = model.timelineSelection.count
        if model.isSelected(item), count > 1 {
            Button("Delete \(count) Selected Items", role: .destructive) { model.deleteSelection() }
        } else {
            Button(single, role: .destructive) {
                model.selection = item
                model.deleteSelection()
            }
        }
    }

    // MARK: Selecting with a rectangle

    /// The empty space behind everything: click to deselect, drag to select with a rectangle
    /// (holding ⌘ or ⇧ adds to what is already selected).
    private var marqueeArea: some View {
        Color.clear
            .contentShape(Rectangle())
            .gesture(emptySpaceGesture)
    }

    /// Click: deselect and move the playhead. Drag: select with a rectangle.
    private var emptySpaceGesture: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named(Self.contentSpace))
                .onChanged { value in
                    let rect = CGRect(x: min(value.startLocation.x, value.location.x),
                                      y: min(value.startLocation.y, value.location.y),
                                      width: abs(value.location.x - value.startLocation.x),
                                      height: abs(value.location.y - value.startLocation.y))
                    guard rect.width > 3 || rect.height > 3 || marquee != nil else { return }
                    if marqueeBase == nil { marqueeBase = model.timelineSelection }
                    marquee = rect
                    var selection = marqueeBase ?? TimelineSelection()
                    let adding = !NSEvent.modifierFlags.isDisjoint(with: [.command, .shift])
                    selection.select(items(in: rect), adding: adding)
                    model.timelineSelection = selection
                }
                .onEnded { value in
                    if marquee == nil, NSEvent.modifierFlags.isDisjoint(with: [.command, .shift]) {
                        model.selection = nil   // a plain click on empty space
                        model.pause()           // ...also moves the playhead there
                        model.seek(to: time(at: value.location.x))
                    }
                    marquee = nil
                    marqueeBase = nil
                }
    }

    @ViewBuilder
    private var marqueeRectangle: some View {
        if let marquee {
            Rectangle()
                .fill(Color.accentColor.opacity(0.15))
                .overlay(Rectangle().strokeBorder(Color.accentColor.opacity(0.9), lineWidth: 1))
                .frame(width: marquee.width, height: marquee.height)
                .offset(x: marquee.minX, y: marquee.minY)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }

    /// The clips, overlays, titles and music a rectangle on the timeline touches.
    private func items(in rect: CGRect) -> Set<EditorModel.Selection> {
        let lanes: [(TimelineLane, CGFloat, CGFloat)] = [
            (.titles, titlesY, titlesHeight),
            (.overlays, overlaysY, overlaysHeight),
            (.clips, clipsY, trackHeight),
            (.sounds, soundsY, soundsHeight),
            (.music, musicY, musicLaneHeight),
        ]
        let covered = Set(lanes.filter { _, y, height in rect.minY < y + height && rect.maxY > y }.map(\.0))
        guard !covered.isEmpty else { return [] }
        let range = CMTimeRange(start: time(at: rect.minX), end: time(at: rect.maxX))
        return model.project.timelineItems(overlapping: range, in: covered)
    }

    // MARK: Ruler, playhead, markers

    /// Seconds along the top. Click or drag here to move the playhead.
    private var ruler: some View {
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
        .contentShape(Rectangle())
        .gesture(DragGesture(minimumDistance: 0).onChanged { value in
            model.pause()
            model.seek(to: time(at: value.location.x))
        })
        .help("Click or drag to move the playhead")
    }

    /// A label every 1, 2, 5, 10… seconds, whichever keeps them about 60 points apart.
    private var rulerStep: Double {
        [1.0, 2, 5, 10, 15, 30, 60].first { $0 * pointsPerSecond >= 60 } ?? 60
    }

    /// A red line at 3:00, the longest a Short can be.
    @ViewBuilder
    private var limitMarker: some View {
        let limitX = x(for: Project.maxDuration)
        if limitX < contentWidth {
            Rectangle()
                .fill(Color.red.opacity(0.7))
                .frame(width: 2)
                .offset(x: limitX)
                .help("3:00 — the maximum length of a Short")
        }
    }

    /// Where a dragged edge is sticking.
    @ViewBuilder
    private var snapIndicator: some View {
        if let snapLine {
            Rectangle()
                .fill(Color.yellow)
                .frame(width: 1)
                .offset(x: x(for: snapLine))
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }

    private var playhead: some View {
        VStack(spacing: 0) {
            Image(systemName: "arrowtriangle.down.fill")
                .font(.system(size: 10))
                .foregroundStyle(.red)
            Rectangle().fill(.red).frame(width: 2)
        }
        .offset(x: x(for: model.currentTime) - 5, y: rulerHeight - 10)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    // MARK: Main clips

    @ViewBuilder
    private var clipsRow: some View {
        let clips = model.project.timeline.clips
        if clips.isEmpty {
            Text("Drop videos or pictures here, or double-click one in Media")
                .foregroundStyle(.secondary)
                .frame(height: trackHeight)
                .padding(.leading, leadingInset)
        } else {
            ZStack(alignment: .topLeading) {
                HStack(spacing: 0) {
                    ForEach(Array(clips.enumerated()), id: \.element.id) { index, clip in
                        clipView(clip, index: index)
                    }
                }
                if let reorder {
                    // Where the dragged clip will go.
                    let others = clips.filter { $0.id != reorder.id }
                    let boundary = others.prefix(reorder.destination).reduce(CMTime.zero) { $0 + $1.duration }
                    Capsule()
                        .fill(Color.yellow)
                        .frame(width: 4, height: trackHeight + 8)
                        .offset(x: width(of: boundary) - 2, y: -4)
                        .allowsHitTesting(false)
                }
            }
            .padding(.leading, leadingInset)
        }
    }

    private func clipView(_ clip: Clip, index: Int) -> some View {
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
            pointsPerSecond: pointsPerSecond,
            isSelected: model.isSelected(.clip(clip.id))
        )
        .equatable()
        .overlay(alignment: .leading) {
            EdgeHandle(edge: .leading, help: "Drag to trim the start of the clip") { dx in
                updateClipTrim(clip, edge: .start, points: dx)
            } onEnd: { endClipTrim() }
        }
        .overlay(alignment: .trailing) {
            EdgeHandle(edge: .trailing, help: "Drag to trim the end of the clip") { dx in
                updateClipTrim(clip, edge: .end, points: dx)
            } onEnd: { endClipTrim() }
        }
        .frame(width: max(shown, 4), height: trackHeight)
        .offset(x: trim?.edge == .start ? delta : 0)
        .offset(x: isDragged ? reorder!.dx : 0, y: isDragged ? -6 : 0)
        .shadow(color: .black.opacity(isDragged ? 0.5 : 0), radius: 6, y: 3)
        .zIndex(isDragged || trim != nil ? 1 : 0)
        .frame(width: slot, height: trackHeight, alignment: .leading)
        .onTapGesture { location in
            let modifiers = NSEvent.modifierFlags
            model.click(.clip(clip.id), modifiers: modifiers)
            // ⌘/⇧-clicks only change the selection; a plain click also moves the playhead.
            guard modifiers.isDisjoint(with: [.command, .shift]) else { return }
            let start = model.project.timeline.startTime(ofClipAt: index)
            model.pause()
            model.seek(to: start + seconds(location.x))
        }
        .gesture(DragGesture(minimumDistance: 4)
            .onChanged { value in
                if reorder == nil {
                    model.pause()
                    if !model.isSelected(.clip(clip.id)) { model.selectedClipID = clip.id }
                }
                reorder = Reorder(id: clip.id, dx: value.translation.width, destination: destination(for: clip, index: index, dx: value.translation.width))
            }
            .onEnded { value in
                let target = destination(for: clip, index: index, dx: value.translation.width)
                reorder = nil
                if target != index { model.moveClip(clip.id, to: target) }
            })
        .contextMenu {
            Button("Split at Playhead") { model.splitAtPlayhead() }
            Button("Trim Start to Playhead") { model.trimToPlayhead(removing: .start) }
            Button("Trim End to Playhead") { model.trimToPlayhead(removing: .end) }
            Picker("Framing", selection: Binding(get: { clip.framing }, set: { model.setFraming($0, for: clip.id) })) {
                Text("Fill Screen").tag(Framing.fill)
                Text("Show All").tag(Framing.fit)
            }
            Button(model.isPunchedIn([clip]) ? "Remove Punch-In" : "Punch In") { model.togglePunchIn([clip.id]) }
                .disabled(clip.hasMotion)
            Divider()
            deleteButton(for: .clip(clip.id), single: "Delete Clip")
        }
    }

    /// Where a clip dragged by `dx` lands among the others: after every clip whose middle it passed.
    private func destination(for clip: Clip, index: Int, dx: CGFloat) -> Int {
        let clips = model.project.timeline.clips
        let start = width(of: model.project.timeline.startTime(ofClipAt: index))
        let middle = start + width(of: clip.duration) / 2 + dx
        var position = CGFloat.zero
        var count = 0
        for other in clips {
            let w = width(of: other.duration)
            if other.id != clip.id, position + w / 2 < middle { count += 1 }
            position += w
        }
        return count
    }

    private func updateClipTrim(_ clip: Clip, edge: ClipEdge, points: CGFloat) {
        model.pause()
        if !model.isSelected(.clip(clip.id)) { model.selectedClipID = clip.id }
        guard let range = model.project.timeline.range(of: clip.id),
              let limits = model.project.trimLimits(for: clip, edge: edge) else { return }
        let edgeTime = edge == .start ? range.start : range.end
        var delta = seconds(points)
        snapLine = nil
        if let stuck = model.snapped(edgeTime + delta, excluding: .clip(clip.id)) {
            delta = stuck - edgeTime
            snapLine = stuck
        }
        delta = delta.snappedToFrame().clamped(limits.start, limits.end)
        clipTrim = ClipTrim(id: clip.id, edge: edge, delta: delta)
    }

    private func endClipTrim() {
        if let trim = clipTrim, trim.delta != .zero { model.trimClip(trim.id, edge: trim.edge, by: trim.delta) }
        clipTrim = nil
        snapLine = nil
    }

    private func aspect(of asset: MediaAsset?) -> CGFloat {
        guard let size = asset?.displaySize, size.height > 0 else { return 9 / 16 }
        return min(max(size.width / size.height, 0.5), 1.8)
    }

    // MARK: B-roll

    /// Videos and pictures over the clips. Drag to move, drag an edge to trim, drop files here to
    /// add them at that time.
    private var overlayLane: some View {
        let rows = overlayRows
        return ZStack(alignment: .topLeading) {
            Color.clear
                .frame(width: max(contentWidth, 1), height: overlaysHeight)
                .contentShape(Rectangle())
                .gesture(emptySpaceGesture)
                .dropDestination(for: URL.self) { urls, location in
                    model.importFiles(urls, to: .overlay(at: time(at: location.x)))
                    return true
                }
                .allowsHitTesting(true)
            if model.project.overlays.isEmpty {
                Label("Drop B-roll or pictures here to show them over your clips", systemImage: "rectangle.on.rectangle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(height: overlayRowHeight)
                    .offset(x: leadingInset + 4)
                    .allowsHitTesting(false)
            }
            ForEach(model.project.overlays) { overlay in
                overlayView(overlay, row: rows[overlay.id] ?? 0)
            }
        }
    }

    private func overlayView(_ overlay: Overlay, row: Int) -> some View {
        let item = TimelineItem.overlay(overlay.id)
        let (start, length) = shownRange(of: item, start: overlay.start, duration: overlay.duration)
        let asset = model.project.asset(id: overlay.clip.assetID)
        return OverlayBlock(
            overlay: overlay,
            name: asset?.name ?? "Missing",
            aspect: aspect(of: asset),
            filmstrip: model.filmstrips[overlay.clip.assetID],
            pointsPerSecond: pointsPerSecond,
            sourceStart: overlay.clip.sourceTime(atOffset: start - overlay.start),
            isSelected: model.isSelected(item),
            isAfterEnd: overlay.visibleRange(in: model.project) == nil
        )
        .overlay(alignment: .leading) {
            EdgeHandle(edge: .leading, help: "Drag to trim the start") { dx in
                updateBlockDrag(item, kind: .start, points: dx, start: overlay.start, duration: overlay.duration)
            } onEnd: { endBlockDrag() }
        }
        .overlay(alignment: .trailing) {
            EdgeHandle(edge: .trailing, help: "Drag to trim the end") { dx in
                updateBlockDrag(item, kind: .end, points: dx, start: overlay.start, duration: overlay.duration)
            } onEnd: { endBlockDrag() }
        }
        .frame(width: max(width(of: length) - 2, 6), height: overlayRowHeight)
        .offset(x: x(for: start) + 1, y: CGFloat(row) * (overlayRowHeight + rowGap))
        .zIndex(blockDrag?.item == item ? 1 : 0)
        .gesture(clickTap { _, modifiers in
            if modifiers.isDisjoint(with: [.command, .shift]) {
                model.selectOverlay(overlay.id)
            } else {
                model.click(item, modifiers: modifiers)
            }
        })
        .gesture(DragGesture(minimumDistance: 3)
            .onChanged { value in
                updateBlockDrag(item, kind: .move, points: value.translation.width, start: overlay.start, duration: overlay.duration)
            }
            .onEnded { _ in endBlockDrag() })
        .contextMenu {
            Button("Split at Playhead") {
                model.selection = item
                model.splitAtPlayhead()
            }
            Button("Start at Playhead") { model.moveOverlay(overlay.id, to: model.currentTime) }
            Button(overlay.clip.isMuted ? "Turn Sound On" : "Turn Sound Off") { model.setClipMuted(overlay.id, !overlay.clip.isMuted) }
                .disabled(asset?.hasAudio != true)
            Divider()
            deleteButton(for: item, single: "Delete")
        }
    }

    // MARK: Titles

    /// The titles, above everything. Click to select, drag to move, drag the right edge to change the length.
    private var titleLane: some View {
        let rows = titleRows
        return ZStack(alignment: .topLeading) {
            ForEach(model.project.titles) { title in
                let item = TimelineItem.title(title.id)
                let (start, length) = shownRange(of: item, start: title.start, duration: title.duration)
                let isAfterEnd = title.visibleRange(in: model.project) == nil
                TitleBlock(title: title, isSelected: model.isSelected(item), isAfterEnd: isAfterEnd) { dx in
                    updateBlockDrag(item, kind: .end, points: dx, start: title.start, duration: title.duration)
                } onResizeEnd: {
                    endBlockDrag()
                }
                .frame(width: max(width(of: length) - 2, 6), height: titleRowHeight)
                .offset(x: x(for: start) + 1, y: CGFloat(rows[title.id] ?? 0) * (titleRowHeight + 2))
                .zIndex(blockDrag?.item == item ? 1 : 0)
                .gesture(clickTap { _, modifiers in
                    if modifiers.isDisjoint(with: [.command, .shift]) {
                        model.selectTitle(title.id)
                    } else {
                        model.click(item, modifiers: modifiers)
                    }
                })
                .gesture(DragGesture(minimumDistance: 3).onChanged { value in
                    updateBlockDrag(item, kind: .move, points: value.translation.width, start: title.start, duration: title.duration)
                }.onEnded { _ in
                    endBlockDrag()
                    if model.timelineSelection.count <= 1 { model.selectTitle(title.id) }
                })
                .contextMenu {
                    Button("Start at Playhead") { model.moveTitle(title.id, to: model.currentTime) }
                    Divider()
                    deleteButton(for: item, single: "Delete Title")
                }
            }
        }
    }

    // MARK: Dragging titles and B-roll

    /// Where a title or overlay is drawn: where it is, or where it is being dragged to.
    private func shownRange(of item: TimelineItem, start: CMTime, duration: CMTime) -> (CMTime, CMTime) {
        guard let drag = blockDrag, drag.item == item else { return (start, duration) }
        switch drag.kind {
        case .move: return (start + drag.delta, duration)
        case .start: return (start + drag.delta, duration - drag.delta)
        case .end: return (start, duration + drag.delta)
        }
    }

    private func updateBlockDrag(_ item: TimelineItem, kind: BlockDrag.Kind, points: CGFloat, start: CMTime, duration: CMTime) {
        model.pause()
        if !model.isSelected(item) { model.selection = item }
        var delta = seconds(points)
        snapLine = nil
        switch kind {
        case .move:
            let moved = max(.zero, start + delta)
            if let stuck = model.snappedStart(moved, duration: duration, excluding: item) {
                delta = stuck - start
                // Draw the line at whichever edge stuck.
                let targets = Snapping.targets(in: model.project, playhead: model.currentTime, excluding: [item])
                snapLine = targets.contains(stuck) ? stuck : stuck + duration
            }
            delta = max(delta, -start)
        case .start:
            if let stuck = model.snapped(start + delta, excluding: item) {
                delta = stuck - start
                snapLine = stuck
            }
            delta = min(max(delta, -start), duration - Clip.minimumDuration)
        case .end:
            if let stuck = model.snapped(start + duration + delta, excluding: item) {
                delta = stuck - start - duration
                snapLine = stuck
            }
            delta = max(delta, Clip.minimumDuration - duration)
        }
        blockDrag = BlockDrag(item: item, kind: kind, delta: delta.snappedToFrame())
    }

    private func endBlockDrag() {
        defer {
            blockDrag = nil
            snapLine = nil
        }
        guard let drag = blockDrag, drag.delta != .zero else { return }
        switch (drag.item, drag.kind) {
        case (.title(let id), .move):
            if let title = model.project.title(id: id) { model.moveTitle(id, to: title.start + drag.delta) }
        case (.title(let id), .end):
            if let title = model.project.title(id: id) { model.setTitleDuration(id, title.duration + drag.delta) }
        case (.overlay(let id), .move):
            if let overlay = model.project.overlay(id: id) { model.moveOverlay(id, to: overlay.start + drag.delta) }
        case (.overlay(let id), .start):
            model.trimOverlay(id, edge: .start, by: drag.delta)
        case (.overlay(let id), .end):
            model.trimOverlay(id, edge: .end, by: drag.delta)
        case (.sound(let id), .move):
            if let sound = model.project.sound(id: id) { model.moveSound(id, to: sound.start + drag.delta) }
        case (.sound(let id), .start):
            model.trimSound(id, edge: .start, by: drag.delta)
        case (.sound(let id), .end):
            model.trimSound(id, edge: .end, by: drag.delta)
        default:
            break
        }
    }

    // MARK: Sound effects and voice-overs

    /// Sound effects and voice-overs, under the captions. Drop sound files here to add them.
    private var soundLane: some View {
        let rows = soundRows
        return ZStack(alignment: .topLeading) {
            Color.clear
                .frame(width: max(contentWidth, 1), height: soundsHeight)
                .contentShape(Rectangle())
                .gesture(emptySpaceGesture)
                .dropDestination(for: URL.self) { urls, location in
                    model.importFiles(urls, to: .sound(at: time(at: location.x)))
                    return true
                }
            if model.project.sounds.isEmpty, !model.project.timeline.clips.isEmpty {
                Label("Sound effects and voice-overs go here (Sounds panel, or drop a sound file)", systemImage: "waveform")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(height: soundRowHeight)
                    .offset(x: leadingInset + 4)
                    .allowsHitTesting(false)
            }
            ForEach(model.project.sounds) { sound in
                soundView(sound, row: rows[sound.id] ?? 0)
            }
        }
    }

    private func soundView(_ sound: SoundClip, row: Int) -> some View {
        let item = TimelineItem.sound(sound.id)
        let (start, length) = shownRange(of: item, start: sound.start, duration: sound.duration)
        let name = model.project.asset(id: sound.clip.assetID)?.name ?? "Missing"
        let isSelected = model.isSelected(item)
        return RoundedRectangle(cornerRadius: 4)
            .fill((sound.isVoiceOver ? Color.pink : Color.indigo).opacity(isSelected ? 0.6 : 0.4))
            .overlay(alignment: .bottom) {
                if let levels = model.audioLevels[sound.clip.assetID] {
                    WaveformView(levels: levels, sourceStart: sound.clip.sourceTime(atOffset: start - sound.start),
                                 pointsPerSecond: pointsPerSecond / CGFloat(sound.clip.speed))
                        .frame(height: soundRowHeight - 12)
                        .opacity(sound.clip.isMuted ? 0.3 : 0.8)
                }
            }
            .overlay(alignment: .topLeading) {
                Label(name, systemImage: sound.isVoiceOver ? "mic.fill" : "waveform")
                    .font(.caption2.weight(.medium))
                    .lineLimit(1)
                    .padding(.horizontal, 4)
            }
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .overlay {
                RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(isSelected ? Color.yellow : Color.white.opacity(0.4), lineWidth: isSelected ? 2 : 1)
            }
            .overlay(alignment: .leading) {
                EdgeHandle(edge: .leading, help: "Drag to trim the start") { dx in
                    updateBlockDrag(item, kind: .start, points: dx, start: sound.start, duration: sound.duration)
                } onEnd: { endBlockDrag() }
            }
            .overlay(alignment: .trailing) {
                EdgeHandle(edge: .trailing, help: "Drag to trim the end") { dx in
                    updateBlockDrag(item, kind: .end, points: dx, start: sound.start, duration: sound.duration)
                } onEnd: { endBlockDrag() }
            }
            .frame(width: max(width(of: length) - 2, 6), height: soundRowHeight)
            .contentShape(Rectangle())
            .offset(x: x(for: start) + 1, y: CGFloat(row) * (soundRowHeight + 2))
            .zIndex(blockDrag?.item == item ? 1 : 0)
            .gesture(clickTap { _, modifiers in
                if modifiers.isDisjoint(with: [.command, .shift]) { model.selectSound(sound.id) } else { model.click(item, modifiers: modifiers) }
            })
            .gesture(DragGesture(minimumDistance: 3)
                .onChanged { value in updateBlockDrag(item, kind: .move, points: value.translation.width, start: sound.start, duration: sound.duration) }
                .onEnded { _ in endBlockDrag() })
            .contextMenu {
                Button("Split at Playhead") {
                    model.selection = item
                    model.splitAtPlayhead()
                }
                Button("Start at Playhead") { model.moveSound(sound.id, to: model.currentTime) }
                Divider()
                deleteButton(for: item, single: "Delete")
            }
            .help("\(sound.isVoiceOver ? "Voice-over" : "Sound"): \(name). Drag to move, drag an edge to trim.")
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(sound.isVoiceOver ? "Voice-over" : "Sound"): \(name)")
            .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    // MARK: Captions, music, pauses

    /// The captions, under the clips they belong to. Click one to go there and fix its words.
    private var captionLane: some View {
        ZStack(alignment: .topLeading) {
            ForEach(model.captionPages) { page in
                let isCurrent = model.currentCaption?.id == page.id
                Text(page.text)
                    .font(.caption2.weight(.medium))
                    .lineLimit(1)
                    .padding(.horizontal, 4)
                    .frame(width: max(width(of: page.range.duration) - 2, 3), height: captionLaneHeight, alignment: .leading)
                    .background(
                        Color.orange.opacity(isCurrent ? 0.55 : 0.3),
                        in: RoundedRectangle(cornerRadius: 4)
                    )
                    .clipped()
                    .offset(x: x(for: page.range.start) + 1)
                    .onTapGesture {
                        model.pause()
                        model.seek(to: page.firstFrame)
                        model.sidebar = .captions
                        model.focusedCaptionID = page.id
                    }
                    .help(page.text)
            }
        }
        .opacity(model.project.captions.isVisible ? 1 : 0.4)
    }

    /// The song, under everything else, with a line showing its volume (it dips where people talk).
    @ViewBuilder
    private var musicLane: some View {
        if let range = model.project.musicRange, let song = model.musicAsset {
            let width = max(width(of: range.duration) - 2, 6)
            let isSelected = model.isSelected(.music)
            RoundedRectangle(cornerRadius: 4)
                .fill(Color.green.opacity(isSelected ? 0.45 : 0.25))
                .overlay {
                    VolumeLine(points: model.musicEnvelope, fullVolume: model.project.music?.volume ?? 1, pointsPerSecond: pointsPerSecond)
                        .stroke(Color.primary.opacity(0.75), lineWidth: 1.5)
                        .padding(.top, 14)
                        .padding(.bottom, 3)
                }
                .overlay(alignment: .topLeading) {
                    Label(song.name, systemImage: "music.note")
                        .font(.caption2.weight(.medium))
                        .lineLimit(1)
                        .padding(.horizontal, 4)
                        .padding(.top, 1)
                }
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .overlay {
                    RoundedRectangle(cornerRadius: 4)
                        .strokeBorder(isSelected ? Color.yellow : Color.green.opacity(0.8), lineWidth: isSelected ? 2 : 1)
                }
                .frame(width: width, height: musicLaneHeight)
                .contentShape(Rectangle())
                .offset(x: leadingInset + 1)
                .gesture(clickTap { _, modifiers in model.click(.music, modifiers: modifiers) })
                .contextMenu {
                    deleteButton(for: .music, single: "Remove Music")
                }
                .help("Music: \(song.name). The line shows its volume; it dips while people talk.")
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Music: \(song.name)")
                .accessibilityAddTraits(isSelected ? .isSelected : [])
        } else if !model.project.timeline.clips.isEmpty {
            Button("Add Music…", systemImage: "music.note") { MusicImportPanel.run(model: model) }
                .buttonStyle(.borderless)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(height: musicLaneHeight)
                .offset(x: leadingInset + 4)
                .help("Add a song to play under your Short. You can also drop a sound file here.")
        }
    }

    /// While choosing pauses to remove: the parts that would be cut, over the clips.
    @ViewBuilder
    private var pauseCuts: some View {
        if let cuts = model.silenceSession?.plan.timelineCuts {
            ZStack(alignment: .topLeading) {
                ForEach(Array(cuts.enumerated()), id: \.offset) { _, cut in
                    Rectangle()
                        .fill(Color.red.opacity(0.45))
                        .overlay(Rectangle().strokeBorder(Color.red, lineWidth: 1))
                        .frame(width: max(width(of: cut.duration), 1), height: trackHeight)
                        .offset(x: x(for: cut.start))
                }
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }
}

// MARK: - Pieces

/// A volume curve drawn across the music: full height is the music's chosen volume, so the dips
/// under speech and the fades are easy to see.
private nonisolated struct VolumeLine: Shape {
    let points: [VolumePoint]
    let fullVolume: Double
    let pointsPerSecond: CGFloat

    func path(in rect: CGRect) -> Path {
        Path { path in
            for (index, point) in points.enumerated() {
                let location = CGPoint(
                    x: rect.minX + CGFloat(point.time.seconds) * pointsPerSecond,
                    y: rect.maxY - rect.height * CGFloat(fullVolume > 0 ? min(point.volume / fullVolume, 1) : 0)
                )
                if index == 0 { path.move(to: location) } else { path.addLine(to: location) }
            }
        }
    }
}

/// A grip on the left or right edge of a block, for trimming it.
private struct EdgeHandle: View {
    let edge: HorizontalEdge
    let help: String
    let onChange: (CGFloat) -> Void
    let onEnd: () -> Void

    var body: some View {
        Rectangle()
            .fill(Color.white.opacity(0.001))
            .frame(width: 8)
            .overlay {
                Capsule().fill(Color.white.opacity(0.7)).frame(width: 3, height: 16)
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .pointerStyle(.frameResize(position: edge == .leading ? .leading : .trailing))
            .gesture(DragGesture(minimumDistance: 1, coordinateSpace: .global)
                .onChanged { onChange($0.translation.width) }
                .onEnded { _ in onEnd() })
            .help(help)
    }
}

/// Stills along a clip, one after another at the clip's own shape.
private struct FilmstripView: View {
    let filmstrip: Filmstrip?
    let sourceStart: CMTime
    let pointsPerSecond: CGFloat
    let aspect: CGFloat

    var body: some View {
        Canvas { context, size in
            guard let filmstrip else { return }
            let tile = max(size.height * aspect, 12)
            var x: CGFloat = 0
            while x < size.width {
                let time = sourceStart + CMTime(seconds: Double((x + tile / 2) / pointsPerSecond), preferredTimescale: 600)
                if let image = filmstrip.image(at: time) {
                    context.draw(Image(decorative: image, scale: 1), in: CGRect(x: x, y: 0, width: tile, height: size.height))
                }
                x += tile
            }
        }
    }
}

/// The sound of a clip as bars, from its file's measured loudness.
private struct WaveformView: View {
    let levels: AudioLevels
    let sourceStart: CMTime
    let pointsPerSecond: CGFloat

    var body: some View {
        Canvas { context, size in
            let framesPerPoint = Double(Project.frameRate) / Double(pointsPerSecond)
            let first = sourceStart.seconds * Double(Project.frameRate)
            var path = Path()
            var x: CGFloat = 0
            while x < size.width {
                let from = Int(first + Double(x) * framesPerPoint)
                let to = max(from + 1, Int(first + Double(x + 2) * framesPerPoint))
                guard from < levels.decibels.count else { break }
                let loudest = levels.decibels[max(from, 0)..<min(to, levels.decibels.count)].max() ?? AudioLevels.silence
                let height = CGFloat(min(max((loudest + 50) / 50, 0), 1)) * size.height
                if height > 0.5 { path.addRect(CGRect(x: x, y: size.height - height, width: 1.5, height: height)) }
                x += 2
            }
            context.fill(path, with: .color(.white.opacity(0.75)))
        }
    }
}

/// One title on the timeline, with a handle on the right edge for changing its length.
private struct TitleBlock: View {
    let title: TextOverlay
    let isSelected: Bool
    let isAfterEnd: Bool
    let onResize: (CGFloat) -> Void
    let onResizeEnd: () -> Void

    var body: some View {
        RoundedRectangle(cornerRadius: 4)
            .fill(Color.purple.opacity(isSelected ? 0.6 : 0.35))
            .overlay(alignment: .leading) {
                Label(title.text.replacingOccurrences(of: "\n", with: " "), systemImage: "textformat")
                    .font(.caption2.weight(.medium))
                    .lineLimit(1)
                    .padding(.horizontal, 4)
                    .padding(.trailing, 6)
            }
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .overlay {
                RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(isSelected ? Color.yellow : Color.purple.opacity(0.8), lineWidth: isSelected ? 2 : 1)
            }
            .overlay(alignment: .trailing) {
                EdgeHandle(edge: .trailing, help: "Drag to change how long the title stays", onChange: onResize, onEnd: onResizeEnd)
            }
            .opacity(isAfterEnd ? 0.4 : 1)
            .contentShape(Rectangle())
            .help(isAfterEnd ? "After the end of your Short, so it won't be seen" : title.text)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Title: \(title.text)")
            .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// A video or picture over the clips (B-roll), on its own row.
private struct OverlayBlock: View {
    let overlay: Overlay
    let name: String
    let aspect: CGFloat
    let filmstrip: Filmstrip?
    let pointsPerSecond: CGFloat
    let sourceStart: CMTime
    let isSelected: Bool
    let isAfterEnd: Bool

    var body: some View {
        RoundedRectangle(cornerRadius: 5)
            .fill(Color.teal.opacity(0.35))
            .overlay {
                FilmstripView(filmstrip: filmstrip, sourceStart: sourceStart, pointsPerSecond: pointsPerSecond / CGFloat(overlay.clip.speed), aspect: aspect)
                    .opacity(0.75)
            }
            .overlay(alignment: .topLeading) {
                HStack(spacing: 3) {
                    Image(systemName: "rectangle.on.rectangle")
                    Text(name).lineLimit(1)
                    if overlay.clip.isMuted { Image(systemName: "speaker.slash.fill").help("No sound") }
                    if overlay.clip.hasMotion { Image(systemName: "move.3d").help("Moves") }
                }
                .font(.caption2.weight(.medium))
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(.black.opacity(0.45), in: RoundedRectangle(cornerRadius: 3))
                .padding(3)
            }
            .clipShape(RoundedRectangle(cornerRadius: 5))
            .overlay {
                RoundedRectangle(cornerRadius: 5)
                    .strokeBorder(isSelected ? Color.yellow : Color.teal.opacity(0.9), lineWidth: isSelected ? 2 : 1)
            }
            .opacity(isAfterEnd ? 0.4 : 1)
            .contentShape(Rectangle())
            .help(isAfterEnd ? "After the end of your Short, so it won't be seen"
                  : "Over the clips: \(name). Drag to move, drag an edge to trim.")
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Over the clips: \(name)")
            .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// A clip on the main storyline: stills along it, its sound, and what has been done to it.
private struct ClipBlock: View, Equatable {
    let clip: Clip
    let name: String
    let aspect: CGFloat
    let filmstrip: Filmstrip?
    let levels: AudioLevels?
    let pointsPerSecond: CGFloat
    let isSelected: Bool

    nonisolated static func == (a: ClipBlock, b: ClipBlock) -> Bool {
        a.clip == b.clip && a.name == b.name && a.aspect == b.aspect && a.pointsPerSecond == b.pointsPerSecond
            && a.isSelected == b.isSelected && a.levels?.decibels.count == b.levels?.decibels.count
            && a.filmstrip?.images.count == b.filmstrip?.images.count
    }

    private let waveHeight: CGFloat = 18

    var body: some View {
        RoundedRectangle(cornerRadius: 6)
            .fill(Color.accentColor.opacity(0.25))
            .overlay(alignment: .top) {
                FilmstripView(filmstrip: filmstrip, sourceStart: clip.sourceStart, pointsPerSecond: pointsPerSecond / CGFloat(clip.speed), aspect: aspect)
                    .padding(.bottom, levels == nil ? 0 : waveHeight)
                    .opacity(0.85)
            }
            .overlay(alignment: .bottom) {
                if let levels {
                    WaveformView(levels: levels, sourceStart: clip.sourceStart, pointsPerSecond: pointsPerSecond / CGFloat(clip.speed))
                        .frame(height: waveHeight - 2)
                        .padding(.bottom, 1)
                        .background(Color.black.opacity(0.35))
                        .opacity(clip.isMuted ? 0.3 : 1)
                }
            }
            .overlay(alignment: .bottomLeading) {
                // Keyframes: where the picture's motion changes.
                ForEach(clip.visibleKeyframes) { keyframe in
                    Image(systemName: "diamond.fill")
                        .font(.system(size: 8))
                        .foregroundStyle(.yellow)
                        .shadow(color: .black, radius: 1)
                        .offset(x: CGFloat(clip.timelineOffset(ofSourceTime: keyframe.time).seconds) * pointsPerSecond - 4, y: -waveHeight - 1)
                }
            }
            .overlay(alignment: .topLeading) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(name).font(.caption.weight(.medium)).lineLimit(1)
                    HStack(spacing: 4) {
                        Text(TimeFormat.string(clip.duration))
                        if clip.isMuted {
                            Image(systemName: "speaker.slash.fill").help("Muted")
                        } else if clip.volume != 1 {
                            Text("\(Int((clip.volume * 100).rounded()))%").help("Volume")
                        }
                        if clip.speed != 1 {
                            Text("\(clip.speed.formatted(.number.precision(.fractionLength(0...2))))×").help("Speed")
                        }
                        if clip.cleansVoice {
                            Image(systemName: "waveform.badge.magnifyingglass").help("Voice cleaned up")
                        }
                        if clip.hasMotion {
                            Image(systemName: "move.3d").help("The picture moves")
                        } else if clip.placement.scale != 1 {
                            Image(systemName: "plus.magnifyingglass").help("Zoomed to \(Int((clip.placement.scale * 100).rounded()))%")
                        }
                    }
                    .font(.caption2)
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .background(.black.opacity(0.45), in: RoundedRectangle(cornerRadius: 4))
                .padding(4)
            }
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay {
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(isSelected ? Color.yellow : Color.accentColor.opacity(0.6), lineWidth: isSelected ? 2 : 1)
            }
            .padding(.horizontal, 1)
            .contentShape(Rectangle())
            .help("\(name). Drag to move it, drag an edge to trim.")
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(isSelected ? .isSelected : [])
            .accessibilityValue(clip.isMuted ? "Muted" : "")
    }
}
