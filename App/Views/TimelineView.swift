import AVFoundation
import EditorCore
import RenderEngine
import SwiftUI
import UniformTypeIdentifiers

/// The storyline and everything over and under it: titles, B-roll, the clips, captions and music,
/// with a ruler for scrubbing and the playhead.
struct TimelineView: View {
    @Bindable var model: EditorModel
    @State var scrollPosition = ScrollPosition(edge: .leading)
    @State var visibleRect: CGRect = .zero
    @State var isDropTargeted = false
    /// A title or B-roll clip being dragged: moved, or one of its edges.
    @State var blockDrag: BlockDrag?
    /// A main clip being dragged to a new place in the storyline.
    @State var reorder: Reorder?
    /// An edge of a main clip being dragged.
    @State var clipTrim: ClipTrim?
    /// Where a dragged edge is sticking, to draw a line there.
    @State var snapLine: CMTime?
    /// The rectangle being drawn across the timeline to select what it covers.
    @State var marquee: CGRect?
    /// The selection when the rectangle was started, which it adds to while ⌘ or ⇧ is held.
    @State var marqueeBase: TimelineSelection?
    /// Where a range being dragged with R started.
    @State var rangeAnchor: CMTime?
    /// Where files are being dragged over the clips, for the landing marker.
    @State var dropX: CGFloat?
    /// A caption edge being dragged in the captions lane, and where it is now.
    @State var captionEdgeDrag: (pageID: CaptionPage.ID, edge: CaptionEdge, time: CMTime)?
    /// While the music is dragged along the timeline: how far it has moved.
    @State var musicDrag: CMTime?

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

    let rulerHeight: CGFloat = 24
    let trackHeight: CGFloat = 72
    let captionLaneHeight: CGFloat = 22
    let titleRowHeight: CGFloat = 22
    let overlayRowHeight: CGFloat = 40
    let musicLaneHeight: CGFloat = 30
    let soundRowHeight: CGFloat = 34
    let rowGap: CGFloat = 3
    let leadingInset: CGFloat = 12

    var titleRows: [TextOverlay.ID: Int] {
        LanePacking.rows(model.project.titles.map { (id: $0.id, range: $0.range) })
    }
    var overlayRows: [Clip.ID: Int] {
        LanePacking.rows(model.project.overlays.map { (id: $0.id, range: $0.range) })
    }
    var soundRows: [Clip.ID: Int] {
        LanePacking.rows(model.project.sounds.map { (id: $0.id, range: $0.range) })
    }
    var titleRowCount: Int { LanePacking.count(titleRows) }
    var overlayRowCount: Int { LanePacking.count(overlayRows) }

    var titlesY: CGFloat { rulerHeight + 6 }
    var titlesHeight: CGFloat { CGFloat(titleRowCount) * (titleRowHeight + 2) }
    var overlaysY: CGFloat { titlesY + titlesHeight + rowGap }
    var overlaysHeight: CGFloat { CGFloat(overlayRowCount) * (overlayRowHeight + rowGap) }
    var clipsY: CGFloat { overlaysY + overlaysHeight + 2 }
    var captionsY: CGFloat { clipsY + trackHeight + 6 }
    var soundsY: CGFloat { captionsY + captionLaneHeight + 4 }
    var soundsHeight: CGFloat { CGFloat(LanePacking.count(soundRows)) * (soundRowHeight + 2) }
    var musicY: CGFloat { soundsY + soundsHeight + 2 }
    var contentHeight: CGFloat { musicY + musicLaneHeight + 12 }

    var pointsPerSecond: CGFloat { model.timelineZoom }

    func x(for time: CMTime) -> CGFloat {
        leadingInset + CGFloat(time.seconds) * pointsPerSecond
    }

    func width(of duration: CMTime) -> CGFloat {
        CGFloat(duration.seconds) * pointsPerSecond
    }

    func time(at x: CGFloat) -> CMTime {
        CMTime(seconds: max(0, Double((x - leadingInset) / pointsPerSecond)), preferredTimescale: 600)
    }

    func seconds(_ points: CGFloat) -> CMTime {
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
                    .help(
                        model.snapsToEdges
                            ? "Snapping is on: dragged edges stick to cuts, other items and the playhead (S)"
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
                        TimelineMarkers(
                            model: model, leadingInset: leadingInset, pointsPerSecond: pointsPerSecond,
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
                .onScrollGeometryChange(for: CGRect.self) {
                    $0.visibleRect
                } action: { _, newValue in
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
            } isTargeted: {
                isDropTargeted = $0
            }
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
    static let contentSpace = "timelineContent"

    /// A plain click on an item (not ⌘/⇧) also moves the playhead to where it was clicked, as in CapCut or iMovie.
    func clickTap(_ select: @escaping (EditorModel.Selection?, NSEvent.ModifierFlags) -> Void) -> some Gesture {
        SpatialTapGesture(coordinateSpace: .named(Self.contentSpace)).onEnded { value in
            let modifiers = NSEvent.modifierFlags
            select(nil, modifiers)
            guard modifiers.isDisjoint(with: [.command, .shift]) else { return }
            model.pause()
            model.seek(to: time(at: value.location.x))
        }
    }

    var contentWidth: CGFloat {
        x(for: model.duration) + 10 * pointsPerSecond
    }

    /// In a right-click menu: deletes all selected items when this one is among several selected,
    /// otherwise just this one.
    @ViewBuilder
    func deleteButton(for item: EditorModel.Selection, single: String) -> some View {
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
    var marqueeArea: some View {
        Color.clear
            .contentShape(Rectangle())
            .gesture(emptySpaceGesture)
    }

    /// Click: deselect and move the playhead. Drag: select with a rectangle.
    var emptySpaceGesture: some Gesture {
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
                let rect = CGRect(
                    x: min(value.startLocation.x, value.location.x),
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
                    model.selection = nil // a plain click on empty space
                    model.selectedAssetID = nil
                    model.timelineRange = nil
                    model.pause() // ...also moves the playhead there
                    model.seek(to: time(at: value.location.x))
                }
                marquee = nil
                marqueeBase = nil
            }
    }

    @ViewBuilder
    var marqueeRectangle: some View {
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
    func items(in rect: CGRect) -> Set<EditorModel.Selection> {
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
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0).onChanged { value in
                model.pause()
                model.seek(to: time(at: value.location.x))
            }
        )
        .help("Click or drag to move the playhead")
    }

    /// A label every 1, 2, 5, 10… seconds, whichever keeps them about 60 points apart.
    var rulerStep: Double {
        [1.0, 2, 5, 10, 15, 30, 60].first { $0 * pointsPerSecond >= 60 } ?? 60
    }

    /// A red line at 3:00, the longest a Short can be.
    @ViewBuilder
    var limitMarker: some View {
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
    var snapIndicator: some View {
        if let snapLine {
            Rectangle()
                .fill(Color.yellow)
                .frame(width: 1)
                .offset(x: x(for: snapLine))
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }

    var playhead: some View {
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
    var skimmer: some View {
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
    var rangeOverlay: some View {
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
    var rangeMenuItems: some View {
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
    func settingsMenuItems(for item: TimelineItem, clipID: Clip.ID) -> some View {
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

    func pasteSettings(_ kinds: Set<SettingsKind>, onto item: TimelineItem) {
        if !model.isSelected(item) { model.selection = item }
        model.pasteSettings(kinds)
    }

    /// Thin lines from titles, B-roll and sounds down (or up) to the clip they move with.
    var pinLines: some View {
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
    var dragLabel: some View {
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

    var dragLabelInfo: (String, CMTime)? {
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

    func duration(of item: TimelineItem) -> CMTime? {
        switch item {
        case .title(let id): model.project.title(id: id)?.duration
        case .overlay(let id): model.project.overlay(id: id)?.duration
        case .sound(let id): model.project.sound(id: id)?.duration
        default: nil
        }
    }

    /// "+0:00.5" or "−0:00.5".
    func signed(_ delta: CMTime) -> String {
        delta < .zero ? "−\(TimeFormat.string(-delta))" : "+\(TimeFormat.string(delta))"
    }

    // MARK: Dropping on the clips

    enum DropTarget: Equatable {
        /// Between clips (or at the end): put in there.
        case cut(CMTime)
        /// On a clip: ask what to do.
        case clip(Clip.ID, CMTime)
    }

    /// A drop near a cut goes in there; on a clip, it asks.
    func dropTarget(at x: CGFloat) -> DropTarget {
        var cuts: [CMTime] = [.zero]
        for clip in model.project.timeline.clips { cuts.append(cuts.last! + clip.duration) }
        if let near = cuts.min(by: { abs(self.x(for: $0) - x) < abs(self.x(for: $1) - x) }), abs(self.x(for: near) - x) <= 12 {
            return .cut(near)
        }
        let time = time(at: x)
        guard let (index, _) = model.project.timeline.locate(time) else { return .cut(model.duration) }
        return .clip(model.project.timeline.clips[index].id, time.snappedToFrame())
    }

    func dropHover(_ x: CGFloat?) {
        dropX = x
        if x != nil { model.showTip(.dropOnClip) }
    }

    func drop(_ urls: [URL], at x: CGFloat) {
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
    var dropMarker: some View {
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
    var clipsRow: some View {
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
                            .fill(
                                LinearGradient(
                                    colors: [.white.opacity(0.05), .white.opacity(0.55), .white.opacity(0.05)], startPoint: .leading, endPoint: .trailing)
                            )
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
            model.pause()
            model.seek(to: start + seconds(location.x))
        }
        .gesture(
            DragGesture(minimumDistance: 4, coordinateSpace: .named(Self.contentSpace))
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
                }
        )
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
    func destination(for clip: Clip, index: Int, dx: CGFloat) -> Int {
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

    func updateClipTrim(_ clip: Clip, edge: ClipEdge, points: CGFloat) {
        model.pause()
        if !model.isSelected(.clip(clip.id)) { model.selectedClipID = clip.id }
        guard let range = model.project.timeline.range(of: clip.id),
            let limits = model.project.trimLimits(for: clip, edge: edge)
        else { return }
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

    func endClipTrim() {
        if let trim = clipTrim { model.showEdgeFrame(ofClip: trim.id, edge: trim.edge, delta: nil) }
        if let trim = clipTrim, trim.delta != .zero { model.trimClip(trim.id, edge: trim.edge, by: trim.delta) }
        clipTrim = nil
        snapLine = nil
    }

    func aspect(of asset: MediaAsset?) -> CGFloat {
        guard let size = asset?.displaySize, size.height > 0 else { return 9 / 16 }
        return min(max(size.width / size.height, 0.5), 1.8)
    }
}
