import EditorCore
import RenderEngine
import SwiftUI

// Stage K (cut-outs): Remove Background, green screen, masks and blend modes, in the clip and
// B-roll inspector.

/// Taking part of the clip's picture away: its background, a coloured screen, everything
/// outside a shape; and for B-roll, how it mixes into the clips under it.
struct CutoutSection: View {
    let model: EditorModel
    let clip: Clip
    let isMain: Bool
    /// Settings while a slider is dragged: shown live, saved when it is let go.
    @State private var draft: ClipCutout?
    @State private var frame: CGImage?

    private var cutout: ClipCutout { draft ?? clip.cutout }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Cut-out").font(.subheadline.weight(.semibold))
            removeBackground
            Divider()
            greenScreen
            Divider()
            maskPart
            if !isMain {
                Divider()
                blendPart
            }
        }
        .task(id: "\(clip.id)|\(clip.assetID)|\(clip.look.hashValue)") {
            frame = await model.lookFrame(of: clip, maxSize: CGSize(width: 160, height: 160))
        }
    }

    // MARK: Remove Background

    private var removeBackground: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Remove background").font(.callout)
            Picker("Remove background", selection: Binding(get: { clip.cutout.removeBackground }, set: { model.setRemoveBackground($0, for: [clip.id]) })) {
                Text("Off").tag(CutoutSubject?.none)
                ForEach(CutoutSubject.allCases) { Text($0.displayName).tag(Optional($0)) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            if let progress = model.cutoutProgress(of: clip) {
                HStack {
                    ProgressView(value: progress).controlSize(.small)
                    Text("\(Int((progress * 100).rounded()))%").monospacedDigit().font(.caption)
                }
                Text("Taking the background away, frame by frame, on this Mac. It is done once for each file.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text(clip.cutout.removeBackground?.hint.appending(". What is under it shows through.")
                     ?? (isMain ? "Keep only the people or the main subject, over the colour behind the picture."
                               : "Keep only the people or the main subject, over the clips under it."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: Green screen

    private var greenScreen: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle("Green screen", isOn: Binding(get: { clip.cutout.key != nil }, set: { model.setColorKey($0, for: clip.id) }))
            if let key = cutout.key {
                HStack(spacing: 8) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color(key.color))
                        .frame(width: 22, height: 16)
                        .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(.secondary, lineWidth: 0.5))
                        .help("The colour taken away")
                        .accessibilityLabel("Colour taken away")
                    let picking = model.colorPick == ColorPick(clipID: clip.id, target: .white, forKey: true)
                    Button(picking ? "Click the Screen…" : "Pick from Video", systemImage: "eyedropper") { model.beginKeyColorPick(for: clip.id) }
                        .help("Click the screen behind the person in the video")
                    Spacer()
                }
                .controlSize(.small)
                slider("Strength", key.strength, in: 0...1, help: "How far from the screen's colour is still taken away") { $0.key?.strength = $1 }
                slider("Soft edge", key.softness, in: 0...1, help: "How gradually edges and hair fade out") { $0.key?.softness = $1 }
                slider("Clean tint", key.spill, in: 0...1, help: "Takes the screen's coloured glow off hair and edges") { $0.key?.spill = $1 }
            } else {
                Text("Takes away a green or blue screen behind someone.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: Mask

    private var maskPart: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Shape").font(.callout)
            // Two fixed rows (not a lazy grid, which can widen the inspector as it lays out).
            let shapes: [ClipMask.Shape?] = [nil] + ClipMask.Shape.allCases.map(Optional.some)
            VStack(spacing: 6) {
                ForEach([0, 4], id: \.self) { first in
                    HStack(spacing: 6) {
                        ForEach(first..<(first + 4), id: \.self) { index in
                            if index < shapes.count {
                                maskTile(shapes[index]).frame(maxWidth: .infinity)
                            } else {
                                Color.clear.frame(maxWidth: .infinity, maxHeight: 1)
                            }
                        }
                    }
                }
            }
            if let mask = cutout.mask {
                slider("Across", mask.centerX, in: 0...1, help: "Left and right") { $0.mask?.centerX = $1 }
                slider("Up/down", mask.centerY, in: 0...1, help: "Up and down") { $0.mask?.centerY = $1 }
                if mask.shape.hasSize {
                    slider("Size", mask.size, in: ClipMask.sizeRange, help: mask.shape == .band ? "How thick the band is" : "How big the shape is") { $0.mask?.size = $1 }
                }
                if mask.shape.stretches {
                    // Stretch is shown from narrow (left) to wide (right) evenly.
                    slider("Stretch", log2(mask.stretch), in: -2...2, label: { String(format: "%.1f×", pow(2, $0)) },
                           help: "Narrower or wider") { $0.mask?.stretch = pow(2, $1) }
                }
                slider("Turn", mask.rotation, in: -180...180, label: { "\(Int($0.rounded()))°" }, help: "Turn the shape") { cutout, value in
                    cutout.mask?.rotation = abs(value) < 3 ? 0 : value
                }
                slider("Soft edge", mask.feather, in: 0...1, help: "How soft the shape's edge is") { $0.mask?.feather = $1 }
                if mask.shape == .rectangle {
                    slider("Corners", mask.roundness, in: 0...1, help: "How round the corners are") { $0.mask?.roundness = $1 }
                }
                Toggle("Hide the shape instead", isOn: Binding(get: { mask.inverted }, set: { on in
                    model.updateCutout(of: clip.id, "Invert Mask") { $0.mask?.inverted = on }
                }))
            } else {
                Text("Keep only a shape of the picture: a circle, one side of a line, a band…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func maskTile(_ shape: ClipMask.Shape?) -> some View {
        let isOn = clip.cutout.mask?.shape == shape
        let name = shape?.displayName ?? "None"
        return Button {
            model.setMask(shape, for: clip.id)
        } label: {
            VStack(spacing: 2) {
                ZStack {
                    Rectangle().fill(.quaternary)
                    if let frame {
                        let picture = Image(decorative: frame, scale: 1).resizable().scaledToFill()
                        if let shape {
                            // Outside the shape dimmed, inside as it is.
                            picture.opacity(0.25)
                            picture.mask { MaskShapeView(shape: shape) }
                        } else {
                            picture
                        }
                    } else if let shape {
                        Image(systemName: shape.systemImage).foregroundStyle(.secondary)
                    }
                }
                .frame(height: 44)
                .clipShape(RoundedRectangle(cornerRadius: 5))
                .overlay {
                    RoundedRectangle(cornerRadius: 5).strokeBorder(isOn ? Color.accentColor : .clear, lineWidth: 2.5)
                }
                .overlay(alignment: .topTrailing) {
                    if isOn {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.white, Color.accentColor)
                            .padding(2)
                    }
                }
                Text(name).font(.caption2).lineLimit(1).foregroundStyle(isOn ? .primary : .secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(shape == nil ? "No shape: the whole picture" : "Keep a \(name.lowercased()) of the picture")
        .accessibilityLabel("Shape: \(name)")
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    // MARK: Blend

    private var blendPart: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Mix with the clips under it")
                Spacer()
                Picker("Mix with the clips under it", selection: Binding(get: { clip.cutout.blend }, set: { mode in
                    model.updateCutout(of: clip.id, "Blend Mode") { $0.blend = mode }
                })) {
                    ForEach(BlendMode.allCases) { Text($0.displayName).tag($0) }
                }
                .labelsHidden()
                .fixedSize()
            }
            Text(clip.cutout.blend.hint + ".")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Sliders

    private func slider(_ name: String, _ value: Double, in range: ClosedRange<Double>,
                        label: @escaping (Double) -> String = { "\(Int(($0 * 100).rounded()))%" }, help: String,
                        _ set: @escaping (inout ClipCutout, Double) -> Void) -> some View {
        HStack {
            Text(name).font(.caption).frame(width: 58, alignment: .leading)
            Slider(value: Binding(get: { value }, set: { newValue in
                var changed = cutout
                set(&changed, newValue)
                draft = changed
                model.previewCutout(changed, for: clip.id)
            }), in: range) { editing in
                guard !editing, let final = draft else { return }
                draft = nil
                model.updateCutout(of: clip.id, "Change \(name)") { $0 = final }
            }
            .controlSize(.small)
            Text(label(value)).monospacedDigit().font(.caption).frame(width: 40, alignment: .trailing)
        }
        .help(help)
    }
}

/// A mask shape drawn the way the picture keeps it, filling its frame (for the shape tiles).
private struct MaskShapeView: View {
    let shape: ClipMask.Shape

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size, side = min(size.width, size.height) * 0.7
            switch shape {
            case .line:
                Rectangle().frame(height: size.height / 2).frame(maxHeight: .infinity, alignment: .top)
            case .band:
                Rectangle().frame(height: size.height * 0.3).frame(maxHeight: .infinity)
            case .circle:
                Circle().frame(width: side, height: side).frame(maxWidth: .infinity, maxHeight: .infinity)
            case .rectangle:
                RoundedRectangle(cornerRadius: side * 0.1).frame(width: side, height: side).frame(maxWidth: .infinity, maxHeight: .infinity)
            case .heart, .star:
                Image(systemName: shape == .heart ? "heart.fill" : "star.fill")
                    .resizable().scaledToFit()
                    .frame(width: side, height: side).frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}
