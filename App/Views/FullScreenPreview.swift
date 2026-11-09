import CoreMedia
import EditorCore
import SwiftUI

/// The Short full screen in a phone, with a sketch of the buttons and text YouTube puts over a
/// Short, so it can be watched the way viewers will see it (⇧⌘F). Escape or Done leaves.
struct FullScreenPreview: View {
    @Bindable var model: EditorModel

    private let canvas = Project.canvasSize

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            GeometryReader { geometry in
                // The phone: the screen plus a bezel, as tall as the window allows.
                let screenHeight = geometry.size.height - 130
                let screenWidth = screenHeight * canvas.width / canvas.height
                ZStack {
                    RoundedRectangle(cornerRadius: 44)
                        .fill(Color(white: 0.12))
                        .overlay(RoundedRectangle(cornerRadius: 44).strokeBorder(Color(white: 0.35), lineWidth: 2))
                        .frame(width: screenWidth + 24, height: screenHeight + 24)
                    PlayerView(player: model.player)
                        .overlay { ShortsInterface(name: model.shortName, progress: progress) }
                        .frame(width: screenWidth, height: screenHeight)
                        .clipShape(RoundedRectangle(cornerRadius: 34))
                        .contentShape(Rectangle())
                        .onTapGesture { model.togglePlayback() }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            VStack {
                HStack {
                    Spacer()
                    Button("Done") { model.toggleFullScreenPreview() }
                        .keyboardShortcut(.cancelAction)
                        .controlSize(.large)
                }
                Spacer()
                Text(model.loopsPlayback ? "Click the video or press Space to play or pause. Loop is on (⌘L). Escape leaves."
                     : "Click the video or press Space to play or pause. Escape leaves.")
                    .font(.callout)
                    .foregroundStyle(.white.opacity(0.7))
            }
            .padding(20)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Full-screen preview")
    }

    private var progress: Double {
        model.duration > .zero ? min(max(model.currentTime.seconds / model.duration.seconds, 0), 1) : 0
    }
}

/// A plain sketch of what YouTube draws over a Short: the buttons down the right, the channel
/// and description at the bottom, the progress line. Drawn where `SafeZone` says they sit.
private struct ShortsInterface: View {
    let name: String
    let progress: Double

    var body: some View {
        GeometryReader { geometry in
            let scale = geometry.size.width / Project.canvasSize.width
            ZStack(alignment: .topLeading) {
                // The buttons down the right.
                VStack(spacing: 34 * scale) {
                    button("hand.thumbsup.fill", "Like", scale)
                    button("hand.thumbsdown.fill", "Dislike", scale)
                    button("text.bubble.fill", "Comments", scale)
                    button("arrowshape.turn.up.right.fill", "Share", scale)
                    button("arrow.triangle.2.circlepath", "Remix", scale)
                }
                .frame(width: SafeZone.right * scale)
                .offset(x: geometry.size.width - SafeZone.right * scale, y: SafeZone.rightColumnTop * scale + 20 * scale)

                // The channel and the description.
                VStack(alignment: .leading, spacing: 18 * scale) {
                    HStack(spacing: 18 * scale) {
                        Circle().fill(Color.white.opacity(0.85)).frame(width: 64 * scale, height: 64 * scale)
                        Text("@yourchannel").font(.system(size: 34 * scale, weight: .semibold))
                        Text("Subscribe")
                            .font(.system(size: 30 * scale, weight: .semibold))
                            .foregroundStyle(.black)
                            .padding(.horizontal, 22 * scale)
                            .padding(.vertical, 10 * scale)
                            .background(Color.white, in: Capsule())
                    }
                    Text(name.isEmpty ? "Your Short" : name)
                        .font(.system(size: 34 * scale))
                        .lineLimit(2)
                    Label("Original sound", systemImage: "music.note")
                        .font(.system(size: 28 * scale))
                }
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.6), radius: 3)
                .frame(width: (Project.canvasSize.width - SafeZone.right - 60) * scale, alignment: .leading)
                .offset(x: 36 * scale, y: (Project.canvasSize.height - SafeZone.bottom + 150) * scale)

                // The progress line along the bottom.
                ZStack(alignment: .leading) {
                    Rectangle().fill(Color.white.opacity(0.3))
                    Rectangle().fill(Color.white).frame(width: geometry.size.width * progress)
                }
                .frame(width: geometry.size.width, height: max(6 * scale, 2))
                .offset(y: geometry.size.height - max(6 * scale, 2))
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func button(_ symbol: String, _ label: String, _ scale: CGFloat) -> some View {
        VStack(spacing: 8 * scale) {
            Image(systemName: symbol).font(.system(size: 54 * scale))
            Text(label).font(.system(size: 24 * scale, weight: .medium))
        }
        .foregroundStyle(.white)
        .shadow(color: .black.opacity(0.6), radius: 3)
    }
}
