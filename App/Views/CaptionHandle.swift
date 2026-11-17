import EditorCore
import RenderEngine
import SwiftUI

/// A box around the caption on screen: drag it up or down to move all the captions. They stay
/// clear of the areas YouTube covers.
struct CaptionHandle: View {
    let model: EditorModel
    @State private var dy: CGFloat?
    @State private var isHovered = false

    var body: some View {
        GeometryReader { geometry in
            let scale = geometry.size.width / Project.canvasSize.width
            if model.project.captions.isVisible, model.currentCaption != nil,
                let frame = CaptionPreview.frame(in: model.project, at: model.playback.currentTime)
            {
                let rect = frame.offsetBy(dx: 0, dy: (dy ?? 0) / scale)
                RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    .foregroundStyle(Color.white.opacity(isHovered || dy != nil ? 0.9 : 0))
                    .contentShape(Rectangle())
                    .frame(width: rect.width * scale, height: rect.height * scale)
                    .offset(x: rect.minX * scale, y: rect.minY * scale)
                    .onHover { isHovered = $0 }
                    .pointerStyle(.frameResize(position: .top, directions: [.inward, .outward]))
                    .gesture(
                        DragGesture(minimumDistance: 2).onChanged { value in
                            model.playback.pause()
                            dy = value.translation.height
                        }.onEnded { value in
                            dy = nil
                            let middle = frame.midY + value.translation.height / scale
                            model.setCaptionPositionByDragging(Double(middle / Project.canvasSize.height))
                        }
                    )
                    .help("Drag up or down to move the captions")
                    .captionBoxAccessibility(middle: Double(frame.midY / Project.canvasSize.height), model: model)
            }
        }
    }
}
