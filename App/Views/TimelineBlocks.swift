import AVFoundation
import EditorCore
import RenderEngine
import SwiftUI
import UniformTypeIdentifiers

// Pieces of the timeline: clip, B-roll and title blocks, filmstrips, waveforms, beat marks.
/// A volume curve drawn across the music: full height is the music's chosen volume, so the dips
/// under speech and the fades are easy to see.
nonisolated struct VolumeLine: Shape {
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
struct BeatMarks: View {
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
struct EdgeHandle: View {
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
struct FilmstripView: View {
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
struct WaveformView: View {
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
struct TitleBlock: View {
    let title: TextOverlay
    let isSelected: Bool
    let isAfterEnd: Bool
    let onResize: (CGFloat) -> Void
    let onResizeEnd: () -> Void

    var body: some View {
        RoundedRectangle(cornerRadius: 4)
            .fill(Color.purple.opacity(isSelected ? 0.6 : 0.35))
            .overlay(alignment: .leading) {
                Label(title.text.replacingOccurrences(of: "\n", with: " "), systemImage: title.isSticker ? "face.smiling" : title.track != nil ? "scope" : "textformat")
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
struct OverlayBlock: View {
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
struct ClipBlock: View, Equatable {
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
                        // On a narrow clip the length is cut off, never wrapped onto a second line.
                        Text(TimeFormat.string(clip.duration)).lineLimit(1).fixedSize()
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
                        if !clip.effects.isEmpty {
                            Label("\(clip.effects.count)", systemImage: "wand.and.stars")
                                .help("Effects: " + clip.effects.map(\.kind.displayName).joined(separator: ", "))
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
                        if clip.cutout.removeBackground != nil {
                            Image(systemName: "person.and.background.dotted").help("Background removed")
                        } else if clip.cutout.key != nil {
                            Image(systemName: "person.crop.square.filled.and.at.rectangle").help("Green screen taken away")
                        }
                        if let mask = clip.cutout.mask {
                            Image(systemName: mask.shape.systemImage).help("Shape: \(mask.shape.displayName)")
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
struct ClipRowDrop: DropDelegate {
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
struct TipBanner: View {
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
