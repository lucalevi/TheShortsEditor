import CoreMedia
import EditorCore
import SwiftUI

/// How a clip's picture sits on screen: framing, background, size, angle, punch-in.
/// Works for a main clip and for B-roll (which has no background of its own).
struct PictureSection: View {
    let model: EditorModel
    let clip: Clip
    let isMain: Bool
    /// A slider being dragged: the value shown until it is let go.
    @State private var dragging: (scale: Double?, rotation: Double?) = (nil, nil)

    private var placement: Placement { model.placementAtPlayhead(of: clip) }
    private var isOnScreen: Bool { model.adjustableClip?.id == clip.id }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Picture").font(.subheadline.weight(.semibold))

            Picker("Framing", selection: Binding(get: { clip.framing }, set: { model.setFraming($0, for: clip.id) })) {
                Text("Fill screen").tag(Framing.fill)
                Text("Show all").tag(Framing.fit)
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            if isMain {
                HStack {
                    Text("Around it")
                    Picker("Around it", selection: Binding(get: { clip.background }, set: { model.setBackground($0, for: [clip.id]) })) {
                        ForEach(ClipBackground.allCases) { Text($0.displayName).tag($0) }
                    }
                    .labelsHidden()
                    .fixedSize()
                }
                Text(clip.background == .blur
                     ? "Where the picture doesn't reach, a blurred copy of it fills the screen."
                     : "Where the picture doesn't reach, the screen is black.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            slider("Size", value: dragging.scale ?? placement.scale, range: 0.25...3, format: { "\(Int(($0 * 100).rounded()))%" }) { value in
                dragging.scale = value
                var p = placement
                p.scale = value
                model.previewPlacement(p, for: clip.id)
            } onEnd: {
                if let value = dragging.scale { model.editPlacement(of: clip, "Resize Picture") { $0.scale = value } }
                dragging.scale = nil
            }
            slider("Angle", value: dragging.rotation ?? placement.rotation, range: -180...180, format: { "\(Int($0.rounded()))°" }) { value in
                // Sticks to straight.
                let value = abs(value) < 3 ? 0 : value
                dragging.rotation = value
                var p = placement
                p.rotation = value
                model.previewPlacement(p, for: clip.id)
            } onEnd: {
                if let value = dragging.rotation { model.editPlacement(of: clip, "Turn Picture") { $0.rotation = value } }
                dragging.rotation = nil
            }

            HStack {
                Button(model.isPunchedIn([clip]) ? "Remove Punch-In" : "Punch In", systemImage: "plus.magnifyingglass") {
                    model.togglePunchIn([clip.id])
                }
                .disabled(clip.hasMotion)
                .help("Zoom in 20%. On every other cut of the same recording, it hides jump cuts.")
                Button("Reset") { model.resetSettings([.picture], of: [clip.id]) }
                    .disabled(!model.project.changedSettings(of: clip.id).contains(.picture) && !clip.hasMotion)
                    .help("Back to how the picture was when added: framing, middle of the screen, full size, no motion")
            }
            .controlSize(.small)

            if model.project.asset(id: clip.assetID)?.isImage != true {
                FollowSubjectButton(model: model, clip: clip)
            }

            Text(isOnScreen
                 ? "Drag the picture in the viewer to move it; drag a corner or pinch to resize it."
                 : "Move the playhead onto this clip to drag its picture in the viewer.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if clip.hasMotion {
                Label("This picture moves, so changes are saved at the playhead as a keyframe.", systemImage: "diamond.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func slider(
        _ title: String, value: Double, range: ClosedRange<Double>, format: @escaping (Double) -> String,
        onChange: @escaping (Double) -> Void, onEnd: @escaping () -> Void
    ) -> some View {
        HStack {
            Text(title).frame(width: 40, alignment: .leading)
            Slider(value: Binding(get: { min(max(value, range.lowerBound), range.upperBound) }, set: onChange), in: range) { editing in
                if !editing { onEnd() }
            }
            .controlSize(.small)
            Text(format(value))
                .monospacedDigit()
                .frame(width: 42, alignment: .trailing)
        }
    }
}

/// The picture moving over time: one-click motions, and keyframes for making your own.
struct MotionSection: View {
    let model: EditorModel
    let clip: Clip

    private let columns = [GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Motion").font(.subheadline.weight(.semibold))
            LazyVGrid(columns: columns, alignment: .leading, spacing: 6) {
                ForEach(MotionPreset.allCases) { preset in
                    Button(preset.displayName, systemImage: preset.systemImage) { model.applyMotion(preset, to: clip.id) }
                        .help(help(for: preset))
                }
            }
            .controlSize(.small)

            if clip.hasMotion {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(clip.visibleKeyframes.enumerated()), id: \.element.id) { index, keyframe in
                        HStack(spacing: 6) {
                            Image(systemName: "diamond.fill").font(.caption2).foregroundStyle(.yellow)
                            Button("Keyframe \(index + 1) at \(TimeFormat.string(clip.timelineOffset(ofSourceTime: keyframe.time)))") {
                                model.goToKeyframe(keyframe, in: clip.id)
                            }
                            .buttonStyle(.link)
                            .help("Go there")
                            Spacer()
                            Text("\(Int((keyframe.placement.scale * 100).rounded()))%")
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                            Button("Delete Keyframe", systemImage: "xmark.circle.fill") { model.removeKeyframe(keyframe.id, from: clip.id) }
                                .labelStyle(.iconOnly)
                                .buttonStyle(.borderless)
                                .foregroundStyle(.secondary)
                        }
                        .font(.caption)
                    }
                    if clip.visibleKeyframes.isEmpty {
                        Text("Its keyframes are outside this piece of the clip.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            HStack {
                Button("Add Keyframe", systemImage: "diamond") { model.addKeyframe(to: clip.id) }
                    .help("Remember where the picture is now, at the playhead. Change it at another time and it moves between the two.")
                if clip.hasMotion {
                    Button("Remove Motion") { model.removeMotion(from: clip.id) }
                        .help("Stop the picture moving, keeping it as it is at the playhead")
                }
            }
            .controlSize(.small)
        }
    }

    private func help(for preset: MotionPreset) -> String {
        switch preset {
        case .slowZoomIn: "Slowly get closer over the whole clip"
        case .slowZoomOut: "Slowly pull back over the whole clip"
        case .panLeft: "Zoom in a little and glide slowly to the left"
        case .panRight: "Zoom in a little and glide slowly to the right"
        case .zoomAtPlayhead: "A quick zoom in at the playhead, for a key word or a punchline"
        }
    }
}
