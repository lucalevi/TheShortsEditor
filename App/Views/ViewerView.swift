import AVFoundation
import EditorCore
import RenderEngine
import SwiftUI

/// The 9:16 preview with its transport controls.
struct ViewerView: View {
    @Bindable var model: EditorModel
    @State private var isDropTargeted = false

    private var canvasAspect: CGFloat { Project.canvasSize.width / Project.canvasSize.height }

    var body: some View {
        VStack(spacing: 0) {
            if !model.missingAssets.isEmpty {
                MissingMediaBar(model: model)
            }
            ZStack {
                Theme.viewer
                if model.project.timeline.clips.isEmpty {
                    emptyState
                } else {
                    PlayerView(player: model.player)
                        .overlay { if model.showsSafeZone { SafeZoneOverlay() } }
                        .overlay { PictureHandles(model: model) }
                        .overlay { CaptionHandle(model: model) }
                        .overlay { TitleHandles(model: model) }
                        .overlay { VoiceOverBadge(model: model) }
                        .aspectRatio(canvasAspect, contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                        .shadow(radius: 6)
                        .padding(16)
                }
                if let image = model.mediaSkimImage, let skim = model.mediaSkim {
                    MediaSkimView(model: model, image: image, assetID: skim.assetID, time: skim.time)
                }
            }
            .dropDestination(for: URL.self) { urls, _ in
                model.importFiles(urls, addToTimeline: true)
                return true
            } isTargeted: { isDropTargeted = $0 }
            TransportBar(model: model)
        }
    }

    private var emptyState: some View {
        RoundedRectangle(cornerRadius: 12)
            .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [8, 6]))
            .foregroundStyle(isDropTargeted ? Color.accentColor : Color.secondary.opacity(0.5))
            .background(isDropTargeted ? Color.accentColor.opacity(0.08) : .clear, in: RoundedRectangle(cornerRadius: 12))
            .overlay {
                VStack(spacing: 12) {
                    Image(systemName: "arrow.down.to.line.compact")
                        .font(.system(size: 36))
                    Text("Drop your videos or pictures here to start")
                        .font(.title3)
                    Text("They go straight onto the timeline, in order.")
                        .foregroundStyle(.secondary)
                    Button("Choose Videos…") { MediaImportPanel.run(model: model, addToTimeline: true) }
                        .controlSize(.large)
                        .padding(.top, 4)
                }
            }
            .aspectRatio(canvasAspect, contentMode: .fit)
            .padding(24)
    }
}

/// Shown while files used by the Short can't be found: their parts play black and silent.
private struct MissingMediaBar: View {
    let model: EditorModel

    var body: some View {
        let names = model.missingAssetList.map(\.url.lastPathComponent)
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 1) {
                Text(names.count == 1 ? "A file can't be found" : "\(names.count) files can't be found").font(.headline)
                Text("\(names.joined(separator: ", ")). Their parts play black and silent until you find them.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer()
            Button("Find Missing Files…") { model.findMissingFiles() }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.orange.opacity(0.15))
        .overlay(alignment: .bottom) { Divider() }
    }
}

/// Play/pause, frame stepping and the time readout under the viewer.
private struct TransportBar: View {
    @Bindable var model: EditorModel

    var body: some View {
        HStack(spacing: 14) {
            Button("Go to Start", systemImage: "backward.end.fill") { model.seek(to: .zero) }
            Button("Previous Frame", systemImage: "chevron.left") { model.step(frames: -1) }
            Button(model.isPlaying ? "Pause" : "Play", systemImage: model.isPlaying ? "pause.fill" : "play.fill") {
                model.togglePlayback()
            }
            .font(.title2)
            .frame(width: 28)
            Button("Next Frame", systemImage: "chevron.right") { model.step(frames: 1) }
            Text("\(TimeFormat.string(model.skimTime ?? model.currentTime)) / \(TimeFormat.string(model.duration))")
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(minWidth: 110, alignment: .leading)
            Toggle("Loop", systemImage: "repeat", isOn: $model.loopsPlayback)
                .toggleStyle(.button)
                .help(model.loopsPlayback ? "Loop is on: playing starts again at the end, as a Short does on YouTube (⌘L)" : "Play over and over, as a Short does on YouTube (⌘L)")
            Button("Play Full Screen", systemImage: "arrow.up.left.and.arrow.down.right") { model.toggleFullScreenPreview() }
                .help("Watch it full screen on a phone, with YouTube's buttons over it (⇧⌘F)")
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.borderless)
        .disabled(model.project.timeline.clips.isEmpty)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .background(Theme.header)
        .overlay(alignment: .top) { Divider() }
    }
}

/// Dims the areas YouTube covers with its own interface, so titles and faces stay clear of them.
private struct SafeZoneOverlay: View {
    var body: some View {
        GeometryReader { geometry in
            let scale = geometry.size.width / Project.canvasSize.width
            ForEach(Array(SafeZone.coveredRects.enumerated()), id: \.offset) { _, rect in
                Rectangle()
                    .fill(Color.black.opacity(0.35))
                    .overlay(Rectangle().strokeBorder(Color.white.opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [4, 4])))
                    .frame(width: rect.width * scale, height: rect.height * scale)
                    .offset(x: rect.minX * scale, y: rect.minY * scale)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// A box around the selected clip's picture: drag inside to move it, drag a corner (or pinch) to
/// resize it, drag the knob above it to turn it. Clicking a picture selects it. The change is shown
/// straight away and becomes one undoable edit when the drag ends.
private struct PictureHandles: View {
    let model: EditorModel
    /// The placement being dragged, shown instead of the clip's own.
    @State private var dragged: (clipID: Clip.ID, start: Placement, now: Placement)?
    @State private var guides: (vertical: Bool, horizontal: Bool) = (false, false)
    @State private var pinchStart: Placement?

    private let canvas = Project.canvasSize

    var body: some View {
        GeometryReader { geometry in
            let scale = geometry.size.width / canvas.width
            ZStack(alignment: .topLeading) {
                // Clicking the video selects the picture under the pointer.
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { location in selectPicture(at: CGPoint(x: location.x / scale, y: location.y / scale)) }
                if let clip = model.adjustableClip, let asset = model.project.asset(id: clip.assetID) {
                    let placement = dragged?.clipID == clip.id ? dragged!.now : model.placementAtPlayhead(of: clip)
                    let frame = clip.framing.placedFrame(of: asset.displaySize, placement: placement, region: region(of: clip))
                    box(for: clip, frame: frame, scale: scale, viewSize: geometry.size)
                }
                if guides.vertical {
                    Rectangle().fill(Color.yellow).frame(width: 1, height: geometry.size.height)
                        .offset(x: geometry.size.width / 2).allowsHitTesting(false)
                }
                if guides.horizontal {
                    Rectangle().fill(Color.yellow).frame(width: geometry.size.width, height: 1)
                        .offset(y: geometry.size.height / 2).allowsHitTesting(false)
                }
            }
            .coordinateSpace(.named("viewer"))
        }
    }

    @ViewBuilder
    private func box(for clip: Clip, frame: PlacedFrame, scale: CGFloat, viewSize: CGSize) -> some View {
        let center = CGPoint(x: frame.center.x * scale, y: frame.center.y * scale)
        let size = CGSize(width: frame.size.width * scale, height: frame.size.height * scale)
        let angle = Angle.degrees(frame.rotation)
        Rectangle()
            .strokeBorder(Color.yellow, lineWidth: 2)
            .contentShape(Rectangle())
            .frame(width: size.width, height: size.height)
            .rotationEffect(angle)
            .position(center)
            .gesture(DragGesture(minimumDistance: 1, coordinateSpace: .named("viewer"))
                .onChanged { value in move(clip, by: value.translation, scale: scale) }
                .onEnded { _ in finish(clip, actionName: "Move Picture") })
            .simultaneousGesture(MagnifyGesture()
                .onChanged { value in pinch(clip, magnification: value.magnification) }
                .onEnded { _ in
                    pinchStart = nil
                    finish(clip, actionName: "Resize Picture")
                })
            .pointerStyle(.grabIdle)
            .help("Drag to move. Drag a corner or pinch to resize. Drag the round knob to turn it.")
        // Corners: kept inside the viewer, so they can be grabbed even when the picture is bigger.
        ForEach(0..<4, id: \.self) { corner in
            let point = clampedInside(cornerPoint(corner, center: center, size: size, angle: angle), viewSize)
            Rectangle()
                .fill(Color.yellow)
                .frame(width: 10, height: 10)
                .overlay(Rectangle().strokeBorder(Color.black.opacity(0.6), lineWidth: 1))
                .position(point)
                .gesture(DragGesture(minimumDistance: 1, coordinateSpace: .named("viewer"))
                    .onChanged { value in resize(clip, center: center, from: value.startLocation, to: value.location) }
                    .onEnded { _ in finish(clip, actionName: "Resize Picture") })
                .pointerStyle(.frameResize(position: corner == 0 ? .topLeading : corner == 1 ? .topTrailing : corner == 2 ? .bottomTrailing : .bottomLeading))
        }
        // The knob for turning, above the top edge.
        let knob = clampedInside(rotated(CGPoint(x: 0, y: -size.height / 2 - 22), by: angle, around: center), viewSize)
        Circle()
            .fill(Color.yellow)
            .frame(width: 12, height: 12)
            .overlay(Circle().strokeBorder(Color.black.opacity(0.6), lineWidth: 1))
            .position(knob)
            .gesture(DragGesture(minimumDistance: 1, coordinateSpace: .named("viewer"))
                .onChanged { value in rotate(clip, center: center, from: value.startLocation, to: value.location) }
                .onEnded { _ in finish(clip, actionName: "Turn Picture") })
            .help("Drag to turn the picture. It sticks to straight angles.")
    }

    // MARK: Gestures

    private func begin(_ clip: Clip) -> Placement {
        if let dragged, dragged.clipID == clip.id { return dragged.start }
        model.pause()
        let start = model.placementAtPlayhead(of: clip)
        dragged = (clip.id, start, start)
        return start
    }

    private func show(_ clip: Clip, _ placement: Placement) {
        guard let start = dragged?.start else { return }
        let placement = placement.normalized
        dragged = (clip.id, start, placement)
        model.previewPlacement(placement, for: clip.id)
    }

    /// Where the clip is drawn: the whole canvas, or its half of a split screen.
    private func region(of clip: Clip) -> CGRect {
        model.project.regions(at: model.currentTime).region(for: clip.id, isMain: model.project.timeline.index(of: clip.id) != nil)
    }

    private func move(_ clip: Clip, by translation: CGSize, scale: CGFloat) {
        let start = begin(clip)
        let area = region(of: clip).size
        var p = start
        p.offsetX = start.offsetX + translation.width / scale / area.width
        p.offsetY = start.offsetY + translation.height / scale / area.height
        // Stick to the middle of the screen (or its half), within a few points.
        let tolerance = 6 / scale
        let snapX = abs(p.offsetX * area.width) < tolerance
        let snapY = abs(p.offsetY * area.height) < tolerance
        if snapX { p.offsetX = 0 }
        if snapY { p.offsetY = 0 }
        guides = (snapX, snapY)
        show(clip, p)
    }

    private func resize(_ clip: Clip, center: CGPoint, from: CGPoint, to: CGPoint) {
        let start = begin(clip)
        let before = max(hypot(from.x - center.x, from.y - center.y), 1)
        let now = hypot(to.x - center.x, to.y - center.y)
        var p = start
        p.scale = start.scale * now / before
        show(clip, p)
    }

    private func pinch(_ clip: Clip, magnification: CGFloat) {
        if pinchStart == nil { pinchStart = begin(clip) }
        guard let start = pinchStart else { return }
        var p = start
        p.scale = start.scale * magnification
        show(clip, p)
    }

    private func rotate(_ clip: Clip, center: CGPoint, from: CGPoint, to: CGPoint) {
        let start = begin(clip)
        let a = atan2(from.y - center.y, from.x - center.x)
        let b = atan2(to.y - center.y, to.x - center.x)
        var degrees = start.rotation + (b - a) * 180 / .pi
        // Stick to straight angles.
        let nearest = (degrees / 90).rounded() * 90
        if abs(degrees - nearest) < 4 { degrees = nearest }
        var p = start
        p.rotation = degrees
        show(clip, p)
    }

    private func finish(_ clip: Clip, actionName: String) {
        guides = (false, false)
        guard let dragged, dragged.clipID == clip.id else { return }
        self.dragged = nil
        if dragged.now != dragged.start {
            model.setPlacement(dragged.now, for: clip.id, actionName: actionName)
        } else {
            model.previewPlacement(nil, for: clip.id)
        }
    }

    // MARK: Selecting by clicking

    /// Selects the topmost picture under `point` (canvas pixels): a B-roll clip, else the main clip.
    private func selectPicture(at point: CGPoint) {
        let time = model.currentTime
        for overlay in model.project.overlaysOnScreen(at: time).reversed() {
            guard let asset = model.project.asset(id: overlay.clip.assetID) else { continue }
            let placement = overlay.clip.placement(atSourceTime: overlay.sourceTime(at: time))
            if contains(overlay.clip.framing.placedFrame(of: asset.displaySize, placement: placement, region: region(of: overlay.clip)), point) {
                if model.selection != .overlay(overlay.id) { model.selection = .overlay(overlay.id) }
                return
            }
        }
        if let clip = model.clipAtPlayhead, model.selection != .clip(clip.id) {
            model.selection = .clip(clip.id)
        }
    }

    private func contains(_ frame: PlacedFrame, _ point: CGPoint) -> Bool {
        let local = rotated(CGPoint(x: point.x - frame.center.x, y: point.y - frame.center.y), by: .degrees(-frame.rotation), around: .zero)
        return abs(local.x) <= frame.size.width / 2 && abs(local.y) <= frame.size.height / 2
    }

    // MARK: Geometry

    private func cornerPoint(_ corner: Int, center: CGPoint, size: CGSize, angle: Angle) -> CGPoint {
        let x = corner == 0 || corner == 3 ? -size.width / 2 : size.width / 2
        let y = corner < 2 ? -size.height / 2 : size.height / 2
        return rotated(CGPoint(x: x, y: y), by: angle, around: center)
    }

    private func rotated(_ offset: CGPoint, by angle: Angle, around center: CGPoint) -> CGPoint {
        let r = angle.radians
        return CGPoint(x: center.x + offset.x * cos(r) - offset.y * sin(r), y: center.y + offset.x * sin(r) + offset.y * cos(r))
    }

    private func clampedInside(_ point: CGPoint, _ size: CGSize) -> CGPoint {
        CGPoint(x: min(max(point.x, 8), size.width - 8), y: min(max(point.y, 8), size.height - 8))
    }
}

/// A box around the caption on screen: drag it up or down to move all the captions. They stay
/// clear of the areas YouTube covers.
private struct CaptionHandle: View {
    let model: EditorModel
    @State private var dy: CGFloat?
    @State private var isHovered = false

    var body: some View {
        GeometryReader { geometry in
            let scale = geometry.size.width / Project.canvasSize.width
            if model.project.captions.isVisible, model.currentCaption != nil,
               let frame = CaptionPreview.frame(in: model.project, at: model.currentTime) {
                let rect = frame.offsetBy(dx: 0, dy: (dy ?? 0) / scale)
                RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    .foregroundStyle(Color.white.opacity(isHovered || dy != nil ? 0.9 : 0))
                    .contentShape(Rectangle())
                    .frame(width: rect.width * scale, height: rect.height * scale)
                    .offset(x: rect.minX * scale, y: rect.minY * scale)
                    .onHover { isHovered = $0 }
                    .pointerStyle(.frameResize(position: .top, directions: [.inward, .outward]))
                    .gesture(DragGesture(minimumDistance: 2).onChanged { value in
                        model.pause()
                        dy = value.translation.height
                    }.onEnded { value in
                        dy = nil
                        let middle = frame.midY + value.translation.height / scale
                        model.setCaptionPositionByDragging(Double(middle / Project.canvasSize.height))
                    })
                    .help("Drag up or down to move the captions")
            }
        }
    }
}

/// The 3-2-1 before a voice-over, then a recording sign.
private struct VoiceOverBadge: View {
    let model: EditorModel

    var body: some View {
        switch model.voiceOver {
        case .countdown(let n)?:
            Text("\(n)")
                .font(.system(size: 96, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .shadow(radius: 8)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black.opacity(0.35))
                .allowsHitTesting(false)
        case .recording?:
            VStack {
                Button {
                    model.stopVoiceOver()
                } label: {
                    Label("Recording — click or press Space to stop", systemImage: "record.circle")
                        .font(.callout.weight(.semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.red.opacity(0.85), in: Capsule())
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
                .padding(.top, 10)
                Spacer()
            }
        case nil:
            EmptyView()
        }
    }
}

/// Boxes over the titles on screen: click one to select it, drag it up or down to move it.
/// The selected title has a visible frame; the others show one when the pointer is over them.
private struct TitleHandles: View {
    let model: EditorModel
    @State private var drag: (id: TextOverlay.ID, offset: CGSize)?
    @State private var hovered: TextOverlay.ID?

    var body: some View {
        GeometryReader { geometry in
            let scale = geometry.size.width / Project.canvasSize.width
            ForEach(model.project.titlesOnScreen(at: model.currentTime)) { title in
                if let frame = TitlePreview.frame(of: title) {
                    let isSelected = model.selectedTitleID == title.id
                    let offset = drag?.id == title.id ? drag!.offset : .zero
                    let rect = clamped(frame.offsetBy(dx: offset.width / scale, dy: offset.height / scale))
                    RoundedRectangle(cornerRadius: 4)
                        .strokeBorder(style: StrokeStyle(lineWidth: isSelected ? 2 : 1, dash: isSelected ? [] : [4, 3]))
                        .foregroundStyle(isSelected ? Color.yellow : Color.white.opacity(hovered == title.id || drag != nil ? 0.9 : 0))
                        .contentShape(Rectangle())
                        .frame(width: rect.width * scale, height: rect.height * scale)
                        .offset(x: rect.minX * scale, y: rect.minY * scale)
                        .onHover { hovered = $0 ? title.id : (hovered == title.id ? nil : hovered) }
                        .pointerStyle(.grabIdle)
                        .onTapGesture(count: 2) {
                            model.selectedTitleID = title.id
                            model.wantsTitleTextFocus = true
                        }
                        .onTapGesture { model.selectedTitleID = title.id }
                        .gesture(DragGesture(minimumDistance: 2).onChanged { value in
                            model.pause()
                            if model.selectedTitleID != title.id { model.selectedTitleID = title.id }
                            var translation = value.translation
                            // Sticks to the middle across.
                            if abs(frame.midX + translation.width / scale - Project.canvasSize.width / 2) < 8 / scale {
                                translation.width = (Project.canvasSize.width / 2 - frame.midX) * scale
                            }
                            drag = (title.id, translation)
                        }.onEnded { _ in
                            let offset = drag?.offset ?? .zero
                            drag = nil
                            let moved = clamped(frame.offsetBy(dx: offset.width / scale, dy: offset.height / scale))
                            let vertical = Double(moved.midY / Project.canvasSize.height)
                            let across = Double(moved.midX / Project.canvasSize.width)
                            model.editTitle(title.id, "Move Title") { title in
                                title.verticalPosition = min(max(vertical, 0), 1)
                                title.horizontalPosition = abs(across - 0.5) < 0.005 ? 0.5 : min(max(across, 0), 1)
                            }
                        })
                        .help("Click to edit, drag to move. Double-click to change the words.")
                }
            }
        }
    }

    /// Keeps a title's box on the canvas, as the renderer does.
    private func clamped(_ rect: CGRect) -> CGRect {
        var rect = rect
        rect.origin.y = min(max(rect.minY, 0), Project.canvasSize.height - rect.height)
        rect.origin.x = min(max(rect.minX, 0), max(Project.canvasSize.width - rect.width, 0))
        return rect
    }
}

/// AVPlayerLayer hosted in an NSView: smoother and lighter than SwiftUI's VideoPlayer, and without
/// its built-in controls.
struct PlayerView: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context: Context) -> PlayerNSView {
        let view = PlayerNSView()
        view.playerLayer.player = player
        return view
    }

    func updateNSView(_ view: PlayerNSView, context: Context) {
        if view.playerLayer.player !== player { view.playerLayer.player = player }
    }
}

final class PlayerNSView: NSView {
    let playerLayer = AVPlayerLayer()

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = .black
        playerLayer.videoGravity = .resizeAspect
        layer?.addSublayer(playerLayer)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        playerLayer.frame = bounds
        CATransaction.commit()
    }
}

/// A file in Media being skimmed: its frame under the pointer, shown in the viewer.
private struct MediaSkimView: View {
    let model: EditorModel
    let image: CGImage
    let assetID: MediaAsset.ID
    let time: CMTime

    var body: some View {
        ZStack {
            Color.black
            Image(decorative: image, scale: 1)
                .resizable()
                .aspectRatio(contentMode: .fit)
        }
        .overlay(alignment: .top) {
            let name = model.project.asset(id: assetID)?.name ?? ""
            Label("\(name) · \(TimeFormat.string(time))", systemImage: "film.stack")
                .font(.caption.weight(.semibold).monospacedDigit())
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(.black.opacity(0.75), in: Capsule())
                .foregroundStyle(.white)
                .padding(8)
        }
        .aspectRatio(Project.canvasSize.width / Project.canvasSize.height, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .padding(16)
        .allowsHitTesting(false)
        .accessibilityLabel("Looking through a file in Media")
    }
}
