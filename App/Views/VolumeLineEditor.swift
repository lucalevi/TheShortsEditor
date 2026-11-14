import AppKit
import CoreMedia
import EditorCore
import SwiftUI

/// The volume line across a clip's waveform, as in iMovie: drag the line up or down to change the
/// volume, ⌥-click it to add a point (⌥-click a point to remove it), drag a point to change the
/// sound there, and drag the handles at the top corners to fade in and out.
struct VolumeLineEditor: View {
    let clip: Clip
    let pointsPerSecond: CGFloat
    /// The fade handles show on the selected clip only, so the timeline stays calm.
    let showsHandles: Bool
    let onSelect: () -> Void
    let onVolume: (Double) -> Void
    let onAddPoint: (CMTime) -> Void
    let onPointLevel: (VolumeKey.ID, Double) -> Void
    let onRemovePoint: (VolumeKey.ID) -> Void
    let onFade: (ClipEdge, CMTime) -> Void

    private enum Drag: Equatable {
        case line(volume: Double)
        case point(id: VolumeKey.ID, level: Double)
        case fade(edge: ClipEdge, length: CMTime)
    }

    @State private var drag: Drag?
    /// What was under the pointer when the drag began.
    @State private var grabbed: Drag?

    private let handleSize: CGFloat = 9
    /// Fade handles keep clear of the clip's trim grips at its very edges.
    private let edgeInset: CGFloat = 13

    /// The clip as it would be with the drag under way, for drawing.
    private var shown: Clip {
        var clip = clip
        switch drag {
        case .line(let volume): clip.volume = volume
        case .point(let id, let level):
            if let index = clip.volumeKeys.firstIndex(where: { $0.id == id }) { clip.volumeKeys[index].level = level }
        case .fade(.start, let length): clip.fadeIn = length
        case .fade(.end, let length): clip.fadeOut = length
        case nil: break
        }
        return clip
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                lineView(size: geometry.size)
                pointDots(size: geometry.size)
                if showsHandles, geometry.size.width > 2 * edgeInset + handleSize {
                    fadeHandle(.start, size: geometry.size)
                    fadeHandle(.end, size: geometry.size)
                }
                labelView
            }
        }
    }

    /// The line, with a wider band around it that takes the clicks and drags.
    private func lineView(size: CGSize) -> some View {
        let line = linePoints(for: shown, in: size)
        let band = Polyline(points: line).stroke(style: StrokeStyle(lineWidth: 10))
        return Polyline(points: line)
            .stroke(Color.yellow, style: StrokeStyle(lineWidth: drag == nil ? 1.5 : 2, lineJoin: .round))
            .shadow(color: .black.opacity(0.8), radius: 1)
            .contentShape(band)
            .pointerStyle(.rowResize)
            .gesture(lineGesture(size: size))
            .help("Volume line: drag up or down. ⌥-click to add a point.")
    }

    private func pointDots(size: CGSize) -> some View {
        let clip = shown
        let centers: [CGPoint] = clip.visibleVolumeKeys.map { item in
            CGPoint(x: x(item.offset), y: y(clip.soundLevel(atOffset: item.offset), size))
        }
        return ForEach(Array(centers.enumerated()), id: \.offset) { _, center in
            Circle()
                .fill(Color.yellow)
                .overlay(Circle().strokeBorder(Color.black, lineWidth: 1))
                .frame(width: 7, height: 7)
                .position(center)
                .allowsHitTesting(false)
        }
    }

    @ViewBuilder
    private var labelView: some View {
        if let label = dragLabel {
            Text(label)
                .font(.caption2.weight(.semibold))
                .monospacedDigit()
                .padding(.horizontal, 4)
                .background(.black.opacity(0.75), in: RoundedRectangle(cornerRadius: 3))
                .foregroundStyle(.white)
                .fixedSize()
                .offset(x: 4, y: -16)
                .allowsHitTesting(false)
        }
    }

    private var dragLabel: String? {
        switch drag {
        case .line(let volume): "Volume \(Int((volume * 100).rounded()))%"
        case .point(_, let level): "Point \(Int((level * 100).rounded()))%"
        case .fade(let edge, let length): "Fade \(edge == .start ? "in" : "out") \(length.seconds.formatted(.number.precision(.fractionLength(1)))) s"
        case nil: nil
        }
    }

    // MARK: Geometry

    private func x(_ offset: CMTime) -> CGFloat { CGFloat(offset.seconds) * pointsPerSecond }

    /// 100% sits halfway up; the top is the loudest a clip can be.
    private func y(_ level: Double, _ size: CGSize) -> CGFloat {
        let fraction = min(max(level / Clip.maxVolume, 0), 1)
        return 2 + (size.height - 4) * (1 - CGFloat(fraction))
    }

    /// The line is short, so a drag changes the level by 1% per point rather than following the
    /// pointer: fine control, and the whole range within a comfortable reach.
    private func levelChange(forDY dy: CGFloat, _ size: CGSize) -> Double {
        -Double(dy) / 100
    }

    private func linePoints(for clip: Clip, in size: CGSize) -> [CGPoint] {
        clip.soundEnvelope().map { CGPoint(x: x($0.time), y: y(clip.isMuted ? 0 : $0.volume, size)) }
    }

    // MARK: Gestures

    private func lineGesture(size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if grabbed == nil {
                    // A point under the pointer is dragged by itself; anywhere else moves the whole line.
                    if let key = nearestKey(to: value.startLocation.x) {
                        grabbed = .point(id: key.id, level: key.level)
                    } else {
                        grabbed = .line(volume: clip.volume)
                    }
                }
                guard abs(value.translation.height) > 1 || drag != nil, !NSEvent.modifierFlags.contains(.option) else { return }
                let change = levelChange(forDY: value.translation.height, size)
                switch grabbed {
                case .point(let id, let level): drag = .point(id: id, level: snapped(Clip.clampedLevel(level + change)))
                case .line(let volume): drag = .line(volume: snapped(Clip.clampedLevel(volume + change)))
                default: break
                }
            }
            .onEnded { value in
                defer {
                    drag = nil
                    grabbed = nil
                }
                switch drag {
                case .line(let volume): onVolume(volume)
                case .point(let id, let level): onPointLevel(id, level)
                default:
                    // A click: ⌥ adds a point (or removes the one clicked), otherwise it selects.
                    if NSEvent.modifierFlags.contains(.option) {
                        if let key = nearestKey(to: value.startLocation.x) {
                            onRemovePoint(key.id)
                        } else {
                            onAddPoint(CMTime(seconds: Double(value.startLocation.x / pointsPerSecond), preferredTimescale: 600))
                        }
                    } else {
                        onSelect()
                    }
                }
            }
    }

    /// Levels stick to whole 5% steps, and to 100%.
    private func snapped(_ level: Double) -> Double { (level * 20).rounded() / 20 }

    private func nearestKey(to x: CGFloat) -> VolumeKey? {
        clip.visibleVolumeKeys
            .map { ($0.key, abs(self.x($0.offset) - x)) }
            .filter { $0.1 <= 6 }
            .min { $0.1 < $1.1 }?.0
    }

    private func fadeHandle(_ edge: ClipEdge, size: CGSize) -> some View {
        let fades = shown.heardFades
        let position = edge == .start ? x(fades.in) : size.width - x(fades.out)
        let current = edge == .start ? clip.fadeIn : clip.fadeOut
        return Circle()
            .fill(Color.white)
            .overlay(Circle().strokeBorder(Color.black, lineWidth: 1))
            .frame(width: handleSize, height: handleSize)
            .padding(4)
            .contentShape(Rectangle())
            .position(x: min(max(position, edgeInset), size.width - edgeInset), y: handleSize / 2)
            .pointerStyle(.frameResize(position: edge == .start ? .trailing : .leading))
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { value in
                        let dx = edge == .start ? value.translation.width : -value.translation.width
                        let seconds = max(current.seconds + Double(dx / pointsPerSecond), 0)
                        let limit = min(Clip.maxFade, clip.duration)
                        drag = .fade(edge: edge, length: CMTime(seconds: (seconds * 10).rounded() / 10, preferredTimescale: 600).clamped(.zero, limit))
                    }
                    .onEnded { _ in
                        if case .fade(let edge, let length) = drag { onFade(edge, length) }
                        drag = nil
                    }
            )
            .help(edge == .start ? "Drag right to fade the sound in" : "Drag left to fade the sound out")
            .accessibilityLabel(edge == .start ? "Fade in handle" : "Fade out handle")
    }
}

/// Straight lines through points.
private nonisolated struct Polyline: Shape {
    let points: [CGPoint]

    func path(in rect: CGRect) -> Path {
        Path { path in
            guard let first = points.first else { return }
            path.move(to: first)
            for point in points.dropFirst() { path.addLine(to: point) }
        }
    }
}
