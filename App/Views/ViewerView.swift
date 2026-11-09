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
            ZStack {
                Color(nsColor: .underPageBackgroundColor)
                if model.project.timeline.clips.isEmpty {
                    emptyState
                } else {
                    PlayerView(player: model.player)
                        .overlay { if model.showsSafeZone { SafeZoneOverlay() } }
                        .overlay { TitleHandles(model: model) }
                        .aspectRatio(canvasAspect, contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                        .shadow(radius: 6)
                        .padding(16)
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
                    Text("Drop your videos here to start")
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
            Text("\(TimeFormat.string(model.currentTime)) / \(TimeFormat.string(model.duration))")
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(minWidth: 110, alignment: .leading)
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.borderless)
        .disabled(model.project.timeline.clips.isEmpty)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .background(.bar)
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

/// Boxes over the titles on screen: click one to select it, drag it up or down to move it.
/// The selected title has a visible frame; the others show one when the pointer is over them.
private struct TitleHandles: View {
    let model: EditorModel
    @State private var drag: (id: TextOverlay.ID, dy: CGFloat)?
    @State private var hovered: TextOverlay.ID?

    var body: some View {
        GeometryReader { geometry in
            let scale = geometry.size.width / Project.canvasSize.width
            ForEach(model.project.titlesOnScreen(at: model.currentTime)) { title in
                if let frame = TitlePreview.frame(of: title) {
                    let isSelected = model.selectedTitleID == title.id
                    let dy = drag?.id == title.id ? drag!.dy : 0
                    let rect = clamped(frame.offsetBy(dx: 0, dy: dy / scale))
                    RoundedRectangle(cornerRadius: 4)
                        .strokeBorder(style: StrokeStyle(lineWidth: isSelected ? 2 : 1, dash: isSelected ? [] : [4, 3]))
                        .foregroundStyle(isSelected ? Color.yellow : Color.white.opacity(hovered == title.id || drag != nil ? 0.9 : 0))
                        .contentShape(Rectangle())
                        .frame(width: rect.width * scale, height: rect.height * scale)
                        .offset(x: rect.minX * scale, y: rect.minY * scale)
                        .onHover { hovered = $0 ? title.id : (hovered == title.id ? nil : hovered) }
                        .pointerStyle(.frameResize(position: .top, directions: [.inward, .outward]))
                        .onTapGesture(count: 2) {
                            model.selectedTitleID = title.id
                            model.wantsTitleTextFocus = true
                        }
                        .onTapGesture { model.selectedTitleID = title.id }
                        .gesture(DragGesture(minimumDistance: 2).onChanged { value in
                            model.pause()
                            if model.selectedTitleID != title.id { model.selectedTitleID = title.id }
                            drag = (title.id, value.translation.height)
                        }.onEnded { value in
                            drag = nil
                            let moved = clamped(frame.offsetBy(dx: 0, dy: value.translation.height / scale))
                            let position = Double(moved.midY / Project.canvasSize.height)
                            model.editTitle(title.id, "Move Title") { $0.verticalPosition = min(max(position, 0), 1) }
                        })
                        .help("Click to edit, drag up or down to move. Double-click to change the words.")
                }
            }
        }
    }

    /// Keeps a title's box on the canvas, as the renderer does.
    private func clamped(_ rect: CGRect) -> CGRect {
        var rect = rect
        rect.origin.y = min(max(rect.minY, 0), Project.canvasSize.height - rect.height)
        return rect
    }
}

/// AVPlayerLayer hosted in an NSView: smoother and lighter than SwiftUI's VideoPlayer, and without
/// its built-in controls.
private struct PlayerView: NSViewRepresentable {
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

private final class PlayerNSView: NSView {
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
