import AVFoundation
import EditorCore
import RenderEngine
import SwiftUI
import UniformTypeIdentifiers

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
    /// Where a range being dragged with R started.
    @State private var rangeAnchor: CMTime?
    /// Where files are being dragged over the clips, for the landing marker.
    @State private var dropX: CGFloat?
    /// A caption edge being dragged in the captions lane, and where it is now.
    @State private var captionEdgeDrag: (pageID: CaptionPage.ID, edge: CaptionEdge, time: CMTime)?
    /// While the music is dragged along the timeline: how far it has moved.
    @State private var musicDrag: CMTime?

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
    private let soundRowHeight: CGFloat = 34
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
                        TimelineMarkers(model: model, leadingInset: leadingInset, pointsPerSecond: pointsPerSecond,
                                        rulerHeight: rulerHeight, height: contentHeight)
                        titleLane.offset(y: titlesY)
                        overlayLane.offset(y: overlaysY)
                        pinLines
                        clipsRow
                            .onDrop(of: [.fileURL], delegate: ClipRowDrop(onUpdate: dropHover, onDrop: drop))
                            .offset(y: clipsY)
                        captionLane.offset(y: captionsY)
                        soundLane.offset(y: soundsY)
                        musicLane.offset(y: musicY)
                        pauseCuts.offset(y: clipsY)
                        rangeOverlay
                        dropMarker
                        limitMarker
                        snapIndicator
                        skimmer
                        playhead
                        marqueeRectangle
                        dragLabel
                    }
                    .coordinateSpace(.named(Self.contentSpace))
                    .onContinuousHover { phase in
                        switch phase {
                        case .active(let point):
                            guard reorder == nil, clipTrim == nil, blockDrag == nil, marquee == nil, rangeAnchor == nil else { return }
                            model.skim(to: time(at: point.x))
                        case .ended:
                            model.skim(to: nil)
                        }
                    }
                    .frame(width: max(geometry.size.width, contentWidth), height: max(geometry.size.height, contentHeight), alignment: .topLeading)
                }
                .scrollPosition($scrollPosition)
                .onScrollGeometryChange(for: CGRect.self) { $0.visibleRect } action: { _, newValue in
                    visibleRect = newValue
                }
            }
            .overlay(alignment: .bottom) {
                if let id = model.trimmerClipID {
                    ClipTrimmerView(model: model, clipID: id)
                        .onChange(of: model.selection) {
                            // Follows the selection to another clip; closes when there is none.
                            model.trimmerClipID = model.trimmableClip?.id
                        }
                }
            }
            .overlay(alignment: .bottom) {
                if let tip = model.tip {
                    TipBanner(tip: tip) { model.dismissTip() }
                        .padding(.bottom, model.trimmerClipID == nil ? 8 : 128)
                        .transition(.opacity)
                }
            }
            .background(isDropTargeted ? Color.accentColor.opacity(0.08) : Color.clear)
            .background(Theme.timeline)
            .dropDestination(for: URL.self) { urls, _ in
                model.importFiles(urls, addToTimeline: true)
                return true
            } isTargeted: { isDropTargeted = $0 }
        }
        .onChange(of: model.project.timeline.clips.isEmpty, initial: true) {
            if !model.project.timeline.clips.isEmpty { model.showTip(.skimming) }
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
                    if rangeAnchor != nil || (marquee == nil && model.isRangeKeyDown && abs(value.translation.width) > 3) {
                        if rangeAnchor == nil {
                            model.pause()
                            rangeAnchor = time(at: value.startLocation.x)
                        }
                        model.setTimelineRange(from: rangeAnchor!, to: time(at: value.location.x))
                        return
                    }
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
                    if rangeAnchor != nil {
                        rangeAnchor = nil
                        return
                    }
                    if marquee == nil, NSEvent.modifierFlags.isDisjoint(with: [.command, .shift]) {
                        model.selection = nil   // a plain click on empty space
                        model.selectedAssetID = nil
                        model.timelineRange = nil
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

    // MARK: Skimming, ranges, live numbers, pins

    /// The white line under the pointer while skimming.
    @ViewBuilder
    private var skimmer: some View {
        if let skim = model.skimTime, !model.isPlaying, reorder == nil, clipTrim == nil, blockDrag == nil, rangeAnchor == nil {
            Rectangle()
                .fill(Color.white)
                .frame(width: 1)
                .offset(x: x(for: skim), y: rulerHeight)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }

    /// The range picked with R (or X), over the clips.
    @ViewBuilder
    private var rangeOverlay: some View {
        if let range = model.timelineRange {
            RoundedRectangle(cornerRadius: 4)
                .fill(Color.yellow.opacity(0.18))
                .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Color.yellow, style: StrokeStyle(lineWidth: 3)))
                .overlay(alignment: .bottomLeading) {
                    Text("Range \(TimeFormat.string(range.duration))")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 4)
                        .background(Color.yellow, in: RoundedRectangle(cornerRadius: 3))
                        .fixedSize()
                        .padding(3)
                }
                .frame(width: max(width(of: range.duration), 3), height: trackHeight + 8)
                .offset(x: x(for: range.start), y: clipsY - 4)
                .allowsHitTesting(false)
                .accessibilityLabel("Range of \(TimeFormat.string(range.duration))")
        }
    }

    @ViewBuilder
    private var rangeMenuItems: some View {
        Button("Delete Range") { model.deleteRange() }
        Button("Trim to Range") { model.trimToRange() }
        Menu("Speed of Range") {
            ForEach(Clip.speedPresets, id: \.self) { speed in
                Button(speed == 1 ? "Normal (1×)" : "\(speed.formatted())×") { model.setSpeedInRange(speed) }
            }
        }
        Button("Mute Range") { model.setVolumeInRange(1, muted: true) }
        Button("Play Range") { model.playSelection() }
        Button("Clear Range") { model.clearRanges() }
    }

    /// Copy, paste and reset settings, for a clip's right-click menu.
    @ViewBuilder
    private func settingsMenuItems(for item: TimelineItem, clipID: Clip.ID) -> some View {
        Button("Copy Settings") {
            if !model.isSelected(item) { model.selection = item }
            model.copySettings()
        }
        Menu("Paste Settings") {
            Button("All") { pasteSettings(Set(SettingsKind.allCases), onto: item) }
            Divider()
            ForEach(SettingsKind.allCases) { kind in
                Button(kind.displayName) { pasteSettings([kind], onto: item) }
            }
        }
        .disabled(model.copiedClip == nil)
        Button("Reset All Settings") { model.resetSettings(Set(SettingsKind.allCases), of: [clipID]) }
            .disabled(model.project.changedSettings(of: clipID).isEmpty)
    }

    private func pasteSettings(_ kinds: Set<SettingsKind>, onto item: TimelineItem) {
        if !model.isSelected(item) { model.selection = item }
        model.pasteSettings(kinds)
    }

    /// Thin lines from titles, B-roll and sounds down (or up) to the clip they move with.
    private var pinLines: some View {
        let titleRows = titleRows, overlayRows = overlayRows, soundRows = soundRows
        let end = model.duration
        var pins: [(item: TimelineItem, time: CMTime, top: CGFloat, bottom: CGFloat)] = []
        for title in model.project.titles where title.followsClip && title.start < end {
            let top = titlesY + CGFloat(titleRows[title.id] ?? 0) * (titleRowHeight + 2) + titleRowHeight
            pins.append((.title(title.id), title.start, top, clipsY + 8))
        }
        for overlay in model.project.overlays where overlay.followsClip && overlay.start < end {
            let top = overlaysY + CGFloat(overlayRows[overlay.id] ?? 0) * (overlayRowHeight + rowGap) + overlayRowHeight
            pins.append((.overlay(overlay.id), overlay.start, top, clipsY + 8))
        }
        for sound in model.project.sounds where sound.followsClip && sound.start < end {
            let bottom = soundsY + CGFloat(soundRows[sound.id] ?? 0) * (soundRowHeight + 2)
            pins.append((.sound(sound.id), sound.start, clipsY + trackHeight - 8, bottom))
        }
        return ZStack(alignment: .topLeading) {
            ForEach(pins, id: \.item) { pin in
                let selected = model.isSelected(pin.item)
                Rectangle()
                    .fill(selected ? Color.yellow : Color.white.opacity(0.45))
                    .frame(width: selected ? 2 : 1, height: max(pin.bottom - pin.top, 0))
                    .overlay(alignment: pin.bottom > clipsY + trackHeight / 2 ? .bottom : .top) {
                        Circle().fill(selected ? Color.yellow : Color.white.opacity(0.7)).frame(width: 5, height: 5)
                    }
                    .offset(x: x(for: pin.time) + 1, y: pin.top)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// While dragging: the new length at a trimmed edge, or where the dragged item lands.
    @ViewBuilder
    private var dragLabel: some View {
        if let (text, time) = dragLabelInfo {
            Text(text)
                .font(.caption.weight(.semibold).monospacedDigit())
                .foregroundStyle(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.black.opacity(0.85), in: Capsule())
                .overlay(Capsule().strokeBorder(Color.white.opacity(0.6), lineWidth: 1))
                .fixedSize()
                .offset(x: x(for: time) + 6, y: rulerHeight + 2)
                .allowsHitTesting(false)
        }
    }

    private var dragLabelInfo: (String, CMTime)? {
        if let trim = clipTrim, let clip = model.project.anyClip(id: trim.id), let range = model.project.timeline.range(of: trim.id) {
            let length = trim.edge == .start ? clip.duration - trim.delta : clip.duration + trim.delta
            let edge = trim.edge == .start ? range.start + trim.delta : range.end + trim.delta
            return ("Length \(TimeFormat.string(length))  \(signed(trim.edge == .start ? -trim.delta : trim.delta))", edge)
        }
        if let reorder {
            let others = model.project.timeline.clips.filter { $0.id != reorder.id }
            let boundary = others.prefix(reorder.destination).reduce(CMTime.zero) { $0 + $1.duration }
            return ("Goes at \(TimeFormat.string(boundary))", boundary)
        }
        if let drag = blockDrag, let start = model.project.start(of: drag.item), let length = duration(of: drag.item) {
            switch drag.kind {
            case .move: return ("Starts at \(TimeFormat.string(start + drag.delta))", start + drag.delta)
            case .start: return ("Length \(TimeFormat.string(length - drag.delta))  \(signed(-drag.delta))", start + drag.delta)
            case .end: return ("Length \(TimeFormat.string(length + drag.delta))  \(signed(drag.delta))", start + length + drag.delta)
            }
        }
        if rangeAnchor != nil, let range = model.timelineRange {
            return ("Range \(TimeFormat.string(range.duration))", range.end)
        }
        return nil
    }

    private func duration(of item: TimelineItem) -> CMTime? {
        switch item {
        case .title(let id): model.project.title(id: id)?.duration
        case .overlay(let id): model.project.overlay(id: id)?.duration
        case .sound(let id): model.project.sound(id: id)?.duration
        default: nil
        }
    }

    /// "+0:00.5" or "−0:00.5".
    private func signed(_ delta: CMTime) -> String {
        delta < .zero ? "−\(TimeFormat.string(-delta))" : "+\(TimeFormat.string(delta))"
    }

    // MARK: Dropping on the clips

    private enum DropTarget: Equatable {
        /// Between clips (or at the end): put in there.
        case cut(CMTime)
        /// On a clip: ask what to do.
        case clip(Clip.ID, CMTime)
    }

    /// A drop near a cut goes in there; on a clip, it asks.
    private func dropTarget(at x: CGFloat) -> DropTarget {
        var cuts: [CMTime] = [.zero]
        for clip in model.project.timeline.clips { cuts.append(cuts.last! + clip.duration) }
        if let near = cuts.min(by: { abs(self.x(for: $0) - x) < abs(self.x(for: $1) - x) }), abs(self.x(for: near) - x) <= 12 {
            return .cut(near)
        }
        let time = time(at: x)
        guard let (index, _) = model.project.timeline.locate(time) else { return .cut(model.duration) }
        return .clip(model.project.timeline.clips[index].id, time.snappedToFrame())
    }

    private func dropHover(_ x: CGFloat?) {
        dropX = x
        if x != nil { model.showTip(.dropOnClip) }
    }

    private func drop(_ urls: [URL], at x: CGFloat) {
        dropX = nil
        guard !urls.isEmpty else { return }
        // Songs and Short files do what they always did (become the music, open the Short).
        let isPicture = { (url: URL) in
            let type = UTType(filenameExtension: url.pathExtension.lowercased())
            return type?.conforms(to: .movie) == true || type?.conforms(to: .image) == true
        }
        guard urls.contains(where: isPicture), !model.project.timeline.clips.isEmpty else {
            model.importFiles(urls, addToTimeline: true)
            return
        }
        switch dropTarget(at: x) {
        case .cut(let time): model.dropFiles(urls, insertingAt: time)
        case .clip(let id, let time): model.showDropMenu(for: urls, on: id, at: time)
        }
    }

    /// Where dragged files would land: a bar on a cut ("put in here"), or a frame around a clip.
    @ViewBuilder
    private var dropMarker: some View {
        if let dropX, !model.project.timeline.clips.isEmpty {
            switch dropTarget(at: dropX) {
            case .cut(let time):
                Capsule()
                    .fill(Color.blue)
                    .overlay(Capsule().strokeBorder(Color.white, lineWidth: 1))
                    .frame(width: 6, height: trackHeight + 12)
                    .overlay(alignment: .top) {
                        Text("Put in here").font(.caption2.weight(.bold)).padding(.horizontal, 4)
                            .background(Color.blue, in: Capsule()).foregroundStyle(.white).fixedSize().offset(y: -16)
                    }
                    .offset(x: x(for: time) - 3, y: clipsY - 6)
                    .allowsHitTesting(false)
            case .clip(let id, _):
                if let range = model.project.timeline.range(of: id) {
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(Color.blue, style: StrokeStyle(lineWidth: 3, dash: [6, 3]))
                        .overlay(alignment: .top) {
                            Text("Drop for options: replace, insert, over it").font(.caption2.weight(.bold)).padding(.horizontal, 4)
                                .background(Color.blue, in: Capsule()).foregroundStyle(.white).fixedSize().offset(y: -16)
                        }
                        .frame(width: width(of: range.duration), height: trackHeight)
                        .offset(x: x(for: range.start), y: clipsY)
                        .allowsHitTesting(false)
                }
            }
        }
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
                if reorder == nil, clipTrim == nil {
                    // Transitions: a band over the time each plays, and a marker on its cut.
                    ForEach(model.project.timeline.transitionSpans, id: \.from) { span in
                        RoundedRectangle(cornerRadius: 2)
                            .fill(LinearGradient(colors: [.white.opacity(0.05), .white.opacity(0.55), .white.opacity(0.05)], startPoint: .leading, endPoint: .trailing))
                            .frame(width: max(width(of: span.range.duration), 4), height: trackHeight - ClipBlock.waveHeight - 6)
                            .offset(x: width(of: span.range.start), y: 3)
                            .allowsHitTesting(false)
                        CutBadge(model: model, clipID: span.from, kind: span.kind)
                            .offset(x: width(of: span.cut) - 10, y: (trackHeight - ClipBlock.waveHeight) / 2 - 10)
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
            tooLoud: model.tooLoudRanges(of: clip),
            pointsPerSecond: pointsPerSecond,
            isSelected: model.isSelected(.clip(clip.id)),
            isReversed: asset?.reversedFrom != nil,
            progress: model.reversing[clip.id]
        )
        .equatable()
        .overlay(alignment: .bottom) {
            if trim == nil, !clip.soundDetached, !clip.isFrozen, model.audioLevels[clip.assetID] != nil, slot > 16 {
                volumeEditor(for: clip, item: .clip(clip.id))
                    .frame(height: ClipBlock.waveHeight - 2)
                    .padding(.horizontal, 1)
                    .padding(.bottom, 1)
            }
        }
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
            model.timelineRange = nil
            model.click(.clip(clip.id), modifiers: modifiers)
            // ⌘/⇧-clicks only change the selection; a plain click also moves the playhead.
            guard modifiers.isDisjoint(with: [.command, .shift]) else { return }
            let start = model.project.timeline.startTime(ofClipAt: index)
            model.pause()
            model.seek(to: start + seconds(location.x))
        }
        .gesture(DragGesture(minimumDistance: 4, coordinateSpace: .named(Self.contentSpace))
            .onChanged { value in
                // With R held, dragging picks a range instead of moving the clip.
                if rangeAnchor != nil || (reorder == nil && model.isRangeKeyDown) {
                    if rangeAnchor == nil {
                        model.pause()
                        rangeAnchor = time(at: value.startLocation.x)
                    }
                    model.setTimelineRange(from: rangeAnchor!, to: time(at: value.location.x))
                    return
                }
                if reorder == nil {
                    model.pause()
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
            if index + 1 < model.project.timeline.clips.count {
                Menu("Transition into the Next Clip") {
                    Button("None") { model.setTransition(nil, after: clip.id) }
                    Divider()
                    ForEach(TransitionKind.allCases) { kind in
                        Button(kind.displayName) { model.setTransition(kind, after: clip.id) }
                    }
                }
            }
            Button("Add Freeze Frame at Playhead") { model.addFreezeFrame() }
            Button("Instant Replay") {
                model.selectedClipID = clip.id
                model.addInstantReplay()
            }
            if model.project.canReverse(clip) {
                Button(model.project.isReversed(clip) ? "Play Forwards" : "Play Backwards") { model.toggleBackwards(for: [clip.id]) }
            }
            Divider()
            if clip.isFrozen {
                // A freeze frame has no sound.
            } else if clip.soundDetached {
                Button("Bring Sound Back") { model.reattachSound(of: clip.id) }
            } else if model.audioLevels[clip.assetID] != nil {
                Button("Detach Sound") { model.detachSound(of: [clip.id]) }
                if !clip.volumeKeys.isEmpty { Button("Remove Volume Points") { model.removeVolumePoints(of: [clip.id]) } }
            }
            Divider()
            settingsMenuItems(for: .clip(clip.id), clipID: clip.id)
            if model.timelineRange != nil {
                Divider()
                rangeMenuItems
            }
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
        model.showEdgeFrame(ofClip: clip.id, edge: edge, delta: delta)
    }

    private func endClipTrim() {
        if let trim = clipTrim { model.showEdgeFrame(ofClip: trim.id, edge: trim.edge, delta: nil) }
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
            settingsMenuItems(for: item, clipID: overlay.id)
            Divider()
            deleteButton(for: item, single: "Delete")
        }
    }

    // MARK: Titles

    /// The titles, above everything. Click to select, drag to move, drag the right edge to change the length.
    private var titleLane: some View {
        let rows = titleRows
        return ZStack(alignment: .topLeading) {
            if model.project.titles.isEmpty, !model.project.timeline.clips.isEmpty {
                Label("Titles go here: ⌘T adds one at the playhead", systemImage: "textformat")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(height: titleRowHeight)
                    .offset(x: leadingInset + 4)
                    .allowsHitTesting(false)
            }
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
                    Button("Copy Title Design") {
                        if !model.isSelected(item) { model.selection = item }
                        model.copySettings()
                    }
                    Button("Paste Title Design") {
                        if !model.isSelected(item) { model.selection = item }
                        model.pasteTitleDesign()
                    }
                    .disabled(model.copiedTitle == nil)
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
                                 pointsPerSecond: pointsPerSecond / CGFloat(sound.clip.averageSpeed),
                                 tooLoud: model.tooLoudRanges(of: sound.clip).map { CMTimeRange(start: $0.start - (start - sound.start), duration: $0.duration) })
                        .frame(height: soundRowHeight - 14)
                        .opacity(sound.clip.isMuted ? 0.3 : 0.8)
                }
            }
            .overlay(alignment: .topLeading) {
                Label(sound.detachedFrom != nil ? "Sound of \(name)" : name,
                      systemImage: sound.isVoiceOver ? "mic.fill" : sound.detachedFrom != nil ? "waveform.path" : "waveform")
                    .font(.caption2.weight(.medium))
                    .lineLimit(1)
                    .padding(.horizontal, 4)
            }
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .overlay {
                RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(isSelected ? Color.yellow : Color.white.opacity(0.4), lineWidth: isSelected ? 2 : 1)
            }
            .overlay(alignment: .bottom) {
                if blockDrag?.item != item, model.audioLevels[sound.clip.assetID] != nil, width(of: length) > 16 {
                    volumeEditor(for: sound.clip, item: item)
                        .frame(height: soundRowHeight - 14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
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

    /// The volume line over a clip's or sound's waveform.
    private func volumeEditor(for clip: Clip, item: TimelineItem) -> some View {
        VolumeLineEditor(
            clip: clip,
            pointsPerSecond: pointsPerSecond,
            showsHandles: model.isSelected(item),
            onSelect: { model.selection = item },
            onVolume: { model.setClipVolume(clip.id, $0) },
            onAddPoint: { model.addVolumePoint(to: clip.id, atOffset: $0) },
            onPointLevel: { model.setVolumePoint($0, of: clip.id, level: $1) },
            onRemovePoint: { model.removeVolumePoint($0, of: clip.id) },
            onFade: { model.setFade($0, to: $1, for: [clip.id]) }
        )
    }

    // MARK: Captions, music, pauses

    /// The captions, under the clips they belong to. Click one to go there and fix its words; drag
    /// its left or right edge to change when it comes and goes.
    private var captionLane: some View {
        ZStack(alignment: .topLeading) {
            ForEach(model.captionPages) { page in
                let isCurrent = model.currentCaption?.id == page.id
                let range = shownRange(of: page)
                Text(page.plainText)
                    .font(.caption2.weight(.medium))
                    .lineLimit(1)
                    .padding(.horizontal, 5)
                    .frame(width: max(width(of: range.duration) - 2, 3), height: captionLaneHeight, alignment: .leading)
                    .background(
                        Color.orange.opacity(isCurrent ? 0.55 : 0.3),
                        in: RoundedRectangle(cornerRadius: 4)
                    )
                    .overlay(alignment: .leading) {
                        if page.source == .sound {
                            // Heard in a voice-over: a small mark so it reads apart from the clip's own.
                            Rectangle().fill(.primary.opacity(0.5)).frame(width: 2).padding(.vertical, 4)
                        }
                    }
                    .clipped()
                    .overlay { captionEdges(page) }
                    .offset(x: x(for: range.start) + 1)
                    .onTapGesture {
                        model.pause()
                        model.seek(to: page.firstFrame)
                        model.sidebar = .captions
                        model.focusedCaptionID = page.id
                    }
                    .help(page.text + "\nDrag an edge to change when it shows")
            }
        }
        .opacity(model.project.captions.isVisible ? 1 : 0.4)
    }

    /// Where a caption is drawn: where it is, or where its edge is being dragged to.
    private func shownRange(of page: CaptionPage) -> CMTimeRange {
        guard let drag = captionEdgeDrag, drag.pageID == page.id else { return page.range }
        switch drag.edge {
        case .start: return CMTimeRange(start: min(drag.time, page.range.end - .oneFrame), end: page.range.end)
        case .end: return CMTimeRange(start: page.range.start, end: max(drag.time, page.range.start + .oneFrame))
        }
    }

    private func captionEdges(_ page: CaptionPage) -> some View {
        HStack(spacing: 0) {
            captionEdgeHandle(page, .start)
            Spacer(minLength: 0)
            captionEdgeHandle(page, .end)
        }
    }

    private func captionEdgeHandle(_ page: CaptionPage, _ edge: CaptionEdge) -> some View {
        Rectangle()
            .fill(Color.primary.opacity(captionEdgeDrag?.pageID == page.id && captionEdgeDrag?.edge == edge ? 0.6 : 0.001))
            .frame(width: 6)
            .contentShape(Rectangle())
            .pointerStyle(.frameResize(position: edge == .start ? .leading : .trailing))
            .gesture(
                DragGesture(minimumDistance: 2, coordinateSpace: .global)
                    .onChanged { value in
                        let base = edge == .start ? page.range.start : page.range.end
                        let time = max(base + seconds(value.translation.width), .zero).snappedToFrame()
                        captionEdgeDrag = (page.id, edge, time)
                        model.pause()
                        model.seek(to: time)
                    }
                    .onEnded { _ in
                        if let drag = captionEdgeDrag { model.moveCaptionEdge(page, drag.edge, to: drag.time) }
                        captionEdgeDrag = nil
                    }
            )
            .help(edge == .start ? "Drag to change when this caption starts" : "Drag to change when this caption ends")
    }

    /// The song, under everything else, with a line showing its volume (it dips where people talk).
    @ViewBuilder
    private var musicLane: some View {
        if let range = model.project.musicRange, let song = model.musicAsset {
            let width = max(width(of: range.duration) - 2, 6)
            let isSelected = model.isSelected(.music)
            let shift = musicDrag ?? .zero
            RoundedRectangle(cornerRadius: 4)
                .fill(Color.green.opacity(isSelected ? 0.45 : 0.25))
                .overlay {
                    VolumeLine(points: model.musicEnvelope, origin: range.start, fullVolume: model.project.music?.volume ?? 1, pointsPerSecond: pointsPerSecond)
                        .stroke(Color.primary.opacity(0.75), lineWidth: 1.5)
                        .padding(.top, 14)
                        .padding(.bottom, 3)
                }
                .overlay {
                    if model.project.music?.showsBeats == true {
                        BeatMarks(beats: model.project.timelineBeats, origin: range.start, pointsPerSecond: pointsPerSecond)
                            .allowsHitTesting(false)
                    }
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
                .offset(x: x(for: range.start + shift) + 1)
                .gesture(clickTap { _, modifiers in model.click(.music, modifiers: modifiers) })
                .gesture(DragGesture(minimumDistance: 3)
                    .onChanged { value in
                        model.pause()
                        if !model.isSelected(.music) { model.selection = .music }
                        var start = max(.zero, range.start + seconds(value.translation.width))
                        snapLine = nil
                        if let stuck = model.snapped(start) {
                            start = stuck
                            snapLine = stuck
                        }
                        start = min(start, max(.zero, model.duration - CMTime(value: 1, timescale: 1)))
                        musicDrag = (start - range.start).snappedToFrame()
                    }
                    .onEnded { _ in
                        if let drag = musicDrag, drag != .zero { model.setMusicTimelineStart(range.start + drag) }
                        musicDrag = nil
                        snapLine = nil
                    })
                .contextMenu {
                    deleteButton(for: .music, single: "Remove Music")
                }
                .help("Music: \(song.name). The line shows its volume; it dips while people talk. Drag it to start the music later.")
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
    /// The timeline time at the left edge of the shape.
    var origin: CMTime = .zero
    let fullVolume: Double
    let pointsPerSecond: CGFloat

    func path(in rect: CGRect) -> Path {
        Path { path in
            for (index, point) in points.enumerated() {
                let location = CGPoint(
                    x: rect.minX + CGFloat((point.time - origin).seconds) * pointsPerSecond,
                    y: rect.maxY - rect.height * CGFloat(fullVolume > 0 ? min(point.volume / fullVolume, 1) : 0)
                )
                if index == 0 { path.move(to: location) } else { path.addLine(to: location) }
            }
        }
    }
}

/// The music's beats: a short tick on each, a taller one where a bar begins, along its bottom.
private struct BeatMarks: View {
    let beats: [TimelineBeat]
    let origin: CMTime
    let pointsPerSecond: CGFloat

    var body: some View {
        Canvas { context, size in
            var small = Path(), tall = Path()
            for beat in beats {
                let x = CGFloat((beat.time - origin).seconds) * pointsPerSecond
                guard x >= 0, x <= size.width else { continue }
                if beat.isBarStart {
                    tall.move(to: CGPoint(x: x, y: size.height * 0.35))
                    tall.addLine(to: CGPoint(x: x, y: size.height))
                } else {
                    small.move(to: CGPoint(x: x, y: size.height * 0.7))
                    small.addLine(to: CGPoint(x: x, y: size.height))
                }
            }
            context.stroke(small, with: .color(.primary.opacity(0.55)), lineWidth: 1)
            context.stroke(tall, with: .color(.primary.opacity(0.9)), lineWidth: 1.5)
        }
        .accessibilityHidden(true)
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
    /// Where the sound is loud enough to crackle (offsets from the left edge, in timeline time):
    /// those bars are drawn red, full height, with a dark top edge.
    var tooLoud: [CMTimeRange] = []

    var body: some View {
        Canvas { context, size in
            let framesPerPoint = Double(Project.frameRate) / Double(pointsPerSecond)
            let first = sourceStart.seconds * Double(Project.frameRate)
            var path = Path()
            var loud = Path()
            let loudX = tooLoud.map { (CGFloat($0.start.seconds) * pointsPerSecond, CGFloat($0.end.seconds) * pointsPerSecond) }
            var x: CGFloat = 0
            while x < size.width {
                let from = Int(first + Double(x) * framesPerPoint)
                let to = max(from + 1, Int(first + Double(x + 2) * framesPerPoint))
                guard from < levels.decibels.count else { break }
                let loudest = levels.decibels[max(from, 0)..<min(to, levels.decibels.count)].max() ?? AudioLevels.silence
                let height = CGFloat(min(max((loudest + 50) / 50, 0), 1)) * size.height
                if loudX.contains(where: { x + 1 >= $0.0 && x < $0.1 }) {
                    loud.addRect(CGRect(x: x, y: 0, width: 1.5, height: size.height))
                } else if height > 0.5 {
                    path.addRect(CGRect(x: x, y: size.height - height, width: 1.5, height: height))
                }
                x += 2
            }
            context.fill(path, with: .color(.white.opacity(0.75)))
            context.fill(loud, with: .color(.red))
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
                FilmstripView(filmstrip: filmstrip, sourceStart: sourceStart, pointsPerSecond: pointsPerSecond / CGFloat(overlay.clip.averageSpeed), aspect: aspect)
                    .opacity(0.75)
            }
            .overlay(alignment: .topLeading) {
                HStack(spacing: 3) {
                    Image(systemName: "rectangle.on.rectangle")
                    Text(name).lineLimit(1)
                    if overlay.clip.isMuted { Image(systemName: "speaker.slash.fill").help("No sound") }
                    if overlay.clip.hasMotion { Image(systemName: "move.3d").help("Moves") }
                    if overlay.clip.placement.opacity < 1 || overlay.clip.hasPictureFades {
                        Image(systemName: "circle.lefthalf.striped.horizontal").help("See-through, or fades in or out")
                    }
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
    /// Where the sound may crackle, as offsets into the clip.
    let tooLoud: [CMTimeRange]
    let pointsPerSecond: CGFloat
    let isSelected: Bool
    /// Plays a backwards copy of its file.
    var isReversed = false
    /// Being turned round: how far the backwards copy is.
    var progress: Double?

    nonisolated static func == (a: ClipBlock, b: ClipBlock) -> Bool {
        a.clip == b.clip && a.isReversed == b.isReversed && a.progress == b.progress && a.name == b.name && a.tooLoud == b.tooLoud && a.aspect == b.aspect && a.pointsPerSecond == b.pointsPerSecond
            && a.isSelected == b.isSelected && a.levels?.decibels.count == b.levels?.decibels.count
            && a.filmstrip?.images.count == b.filmstrip?.images.count
    }

    static let waveHeight: CGFloat = 24
    private var waveHeight: CGFloat { Self.waveHeight }

    var body: some View {
        RoundedRectangle(cornerRadius: 6)
            .fill(Color.accentColor.opacity(0.25))
            .overlay(alignment: .top) {
                // A freeze frame shows its one picture all along.
                FilmstripView(filmstrip: filmstrip, sourceStart: clip.sourceStart, pointsPerSecond: clip.isFrozen ? 1_000_000 : pointsPerSecond / CGFloat(clip.averageSpeed), aspect: aspect)
                    .padding(.bottom, levels == nil ? 0 : waveHeight)
                    .opacity(0.85)
            }
            .overlay(alignment: .bottom) {
                if levels != nil, clip.isFrozen {
                    Label("Freeze frame", systemImage: "snowflake")
                        .font(.caption2)
                        .frame(maxWidth: .infinity, maxHeight: waveHeight, alignment: .leading)
                        .padding(.leading, 4)
                        .background(Color.black.opacity(0.35))
                } else if let levels, clip.soundDetached {
                    Label("Sound detached", systemImage: "waveform.path")
                        .font(.caption2)
                        .frame(maxWidth: .infinity, maxHeight: waveHeight, alignment: .leading)
                        .padding(.leading, 4)
                        .background(Color.black.opacity(0.35))
                        .opacity(levels.decibels.isEmpty ? 0 : 0.8)
                } else if let levels {
                    WaveformView(levels: levels, sourceStart: clip.sourceStart, pointsPerSecond: pointsPerSecond / CGFloat(clip.averageSpeed), tooLoud: tooLoud)
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
                        if clip.soundDetached {
                            // Its sound settings live on the detached sound now.
                        } else if clip.isMuted {
                            Image(systemName: "speaker.slash.fill").help("Muted")
                        } else if clip.volume != 1 {
                            Text("\(Int((clip.volume * 100).rounded()))%").help("Volume")
                        }
                        if clip.speed != 1 {
                            Text("\(clip.speed.formatted(.number.precision(.fractionLength(0...2))))×").help("Speed")
                        }
                        if let curve = clip.speedCurve {
                            Label(curve.shape.displayName, systemImage: "speedometer").help("Speed curve: \(curve.shape.displayName)")
                        }
                        if clip.animationIn != nil || clip.animationOut != nil {
                            Image(systemName: "sparkles").help("Comes in or goes out with an animation")
                        }
                        if clip.isFrozen {
                            Image(systemName: "snowflake").help("Freeze frame")
                        }
                        if isReversed {
                            Image(systemName: "backward.fill").help("Plays backwards")
                        }
                        if clip.cleansVoice {
                            Image(systemName: "waveform.badge.magnifyingglass").help("Voice cleaned up")
                        }
                        if let effect = clip.voiceEffect, !clip.soundDetached {
                            Image(systemName: effect.systemImage).help("Voice effect: \(effect.displayName)")
                        }
                        if !tooLoud.isEmpty, !clip.isMuted {
                            Image(systemName: "exclamationmark.triangle.fill").help("Too loud in places: it may crackle")
                        }
                        if let filter = clip.look.filter, filter.strength > 0 {
                            Image(systemName: "camera.filters").help("Filter: \(filter.filter.displayName)")
                        } else if !clip.look.color.isNeutral {
                            Image(systemName: "paintpalette").help("Colour changed")
                        }
                        if clip.steadiness > 0 {
                            Image(systemName: "hand.raised.slash").help("Steadied")
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
            .overlay(alignment: .bottom) {
                if let progress {
                    ProgressView(value: progress)
                        .progressViewStyle(.linear)
                        .padding(.horizontal, 6)
                        .padding(.bottom, waveHeight + 4)
                        .help("Turning the clip round…")
                }
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

/// Files dragged over the main clips: tells where they are (for the landing marker) and hands
/// over the files when dropped.
private struct ClipRowDrop: DropDelegate {
    let onUpdate: (CGFloat?) -> Void
    let onDrop: ([URL], CGFloat) -> Void

    func validateDrop(info: DropInfo) -> Bool { info.hasItemsConforming(to: [.fileURL]) }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        onUpdate(info.location.x)
        return DropProposal(operation: .copy)
    }

    func dropExited(info: DropInfo) { onUpdate(nil) }

    func performDrop(info: DropInfo) -> Bool {
        let providers = info.itemProviders(for: [.fileURL])
        let x = info.location.x
        onUpdate(nil)
        Task { @MainActor in
            var urls: [URL] = []
            for provider in providers {
                if let url = await Self.url(from: provider) { urls.append(url) }
            }
            onDrop(urls, x)
        }
        return true
    }

    private static func url(from provider: NSItemProvider) async -> URL? {
        await withCheckedContinuation { continuation in
            _ = provider.loadObject(ofClass: URL.self) { url, _ in continuation.resume(returning: url) }
        }
    }
}

/// A one-time hint across the top of the timeline.
private struct TipBanner: View {
    let tip: EditorTip
    let dismiss: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: tip.systemImage).font(.title3)
            Text(tip.text).fixedSize(horizontal: false, vertical: true)
            Button("Got It", action: dismiss).controlSize(.small)
        }
        .font(.callout)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: 620)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.white.opacity(0.3), lineWidth: 1))
        .shadow(radius: 8)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Tip: \(tip.text)")
    }
}
