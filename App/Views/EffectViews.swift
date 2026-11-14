import CoreMedia
import EditorCore
import RenderEngine
import SwiftUI

/// The clip's effects: a grid of every effect drawn on the clip's own picture (click to add),
/// then each added effect with where it plays, its strength and length.
struct EffectsSection: View {
    let model: EditorModel
    let clip: Clip
    @State private var previews: [EffectKind: CGImage] = [:]

    private let columns = [GridItem(.adaptive(minimum: 70), spacing: 6)]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Effects").font(.subheadline.weight(.semibold))
            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(EffectKind.allCases) { kind in
                    tile(kind)
                }
            }
            .task(id: previewKey) { await makePreviews() }
            ForEach(clip.effects) { effect in
                EffectRow(model: model, clip: clip, effect: effect)
            }
            if clip.effects.isEmpty {
                Text("Click one to add it. It stays on this clip wherever the clip goes.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var previewKey: String {
        let time = model.project.sourceTime(ofClip: clip.id, at: model.currentTime)?.seconds ?? 0
        return "\(clip.id)|\(clip.assetID)|\((time * 2).rounded())|\(clip.look.hashValue)"
    }

    private func tile(_ kind: EffectKind) -> some View {
        let isOn = clip.effects.contains { $0.kind == kind }
        return Button {
            if let effect = clip.effects.first(where: { $0.kind == kind }) {
                model.removeEffect(effect.id, from: clip.id)
            } else {
                model.addEffect(kind, to: [clip.id])
            }
        } label: {
            VStack(spacing: 2) {
                ZStack {
                    Rectangle().fill(.quaternary)
                    if let image = previews[kind] {
                        Image(decorative: image, scale: 1).resizable().scaledToFill()
                    } else {
                        Image(systemName: kind.systemImage).foregroundStyle(.secondary)
                    }
                }
                .frame(height: 64)
                .clipShape(RoundedRectangle(cornerRadius: 5))
                .overlay {
                    // On is shown by a frame and a tick, not by colour alone.
                    RoundedRectangle(cornerRadius: 5).strokeBorder(isOn ? Color.accentColor : .clear, lineWidth: 2.5)
                }
                .overlay(alignment: .topTrailing) {
                    if isOn {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.white, Color.accentColor)
                            .padding(3)
                    }
                }
                Text(kind.displayName)
                    .font(.caption2)
                    .lineLimit(1)
                    .foregroundStyle(isOn ? .primary : .secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(isOn ? "\(kind.displayName): on. Click to take it off." : kind.hint)
        .accessibilityLabel(kind.displayName)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    private func makePreviews() async {
        guard let frame = await model.lookFrame(of: clip, maxSize: CGSize(width: 160, height: 160)) else {
            previews = [:]
            return
        }
        let made = await Task.detached(priority: .userInitiated) {
            var made: [EffectKind: CGImage] = [:]
            for kind in EffectKind.allCases { made[kind] = EffectRenderer.preview(frame, kind: kind) }
            return made
        }.value
        guard !Task.isCancelled else { return }
        previews = made
    }
}

/// One effect on a clip: where it plays, how strong, how long, and taking it off.
private struct EffectRow: View {
    let model: EditorModel
    let clip: Clip
    let effect: ClipEffect
    @State private var strength: Double?
    @State private var length: Double?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label(effect.kind.displayName, systemImage: effect.kind.systemImage).font(.callout.weight(.medium))
                Spacer()
                Button("Play", systemImage: "play.fill") {
                    if let start = model.project.timelineStart(ofClip: clip.id) { model.playEffect(effect, of: clip, at: start) }
                }
                .labelStyle(.iconOnly)
                .help("Play the part of the clip it is on")
                Button("Remove", systemImage: "xmark.circle.fill") { model.removeEffect(effect.id, from: clip.id) }
                    .labelStyle(.iconOnly)
                    .help("Take this effect off")
            }
            .buttonStyle(.borderless)
            Picker("Plays", selection: Binding(get: { effect.part }, set: { part in
                model.updateEffect(effect.id, on: clip.id, "Effect Timing") { $0.part = part }
            })) {
                ForEach(EffectPart.allCases) { Text($0.displayName).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .controlSize(.small)
            slider("Strength", value: strength ?? effect.strength, in: 0.1...1, label: "\(Int(((strength ?? effect.strength) * 100).rounded()))%") {
                strength = $0
            } done: {
                if let value = strength {
                    strength = nil
                    model.updateEffect(effect.id, on: clip.id, "Effect Strength") { $0.strength = (value * 20).rounded() / 20 }
                }
            }
            if effect.part != .wholeClip {
                let seconds = length ?? effect.length.seconds
                slider("Length", value: seconds, in: ClipEffect.lengthRange, label: "\(seconds.formatted(.number.precision(.fractionLength(1)))) s") {
                    length = $0
                } done: {
                    if let value = length {
                        length = nil
                        model.updateEffect(effect.id, on: clip.id, "Effect Length") { $0.length = CMTime(seconds: value, preferredTimescale: 600) }
                    }
                }
            }
        }
        .padding(8)
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 6))
    }

    private func slider(_ name: String, value: Double, in range: ClosedRange<Double>, label: String,
                        change: @escaping @MainActor (Double) -> Void, done: @escaping () -> Void) -> some View {
        HStack {
            Text(name).font(.caption).frame(width: 52, alignment: .leading)
            Slider(value: Binding(get: { value }, set: change), in: range) { editing in if !editing { done() } }
                .controlSize(.small)
            Text(label).monospacedDigit().font(.caption).frame(width: 38, alignment: .trailing)
        }
    }
}
