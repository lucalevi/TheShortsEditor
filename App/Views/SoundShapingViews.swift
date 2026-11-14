import CoreMedia
import EditorCore
import RenderEngine
import SwiftUI

/// Fades, volume points, voice effects and EQ for a clip's sound, and (for a main clip)
/// detaching its sound. Shown in the inspector under the volume.
struct SoundShapingSection: View {
    let model: EditorModel
    let clip: Clip
    /// A clip on the main storyline (it can have its sound detached).
    var isMain = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if isMain, clip.soundDetached {
                detachedNote
            } else {
                loudnessWarning
                FadeSliders(model: model, clip: clip)
                volumePoints
                VoiceEffectPicker(model: model, clip: clip)
                equalizer
                if isMain {
                    Button("Detach Sound", systemImage: "waveform.path") { model.detachSound(of: [clip.id]) }
                        .controlSize(.small)
                        .help(
                            "Put this clip's sound on the sound row, so you can trim or move it on its own: start it before the picture, or let it carry on into the next clip (⌥⌘B)"
                        )
                }
            }
        }
    }

    private var detachedNote: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Sound detached", systemImage: "waveform.path").font(.subheadline.weight(.semibold))
            Text("This clip's sound is on the sound row under the captions. Drag its edges to start it before the picture or let it carry on after.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                if let sound = model.project.sounds.first(where: { $0.detachedFrom == clip.id }) {
                    Button("Select the Sound") { model.selection = .sound(sound.id) }
                }
                Button("Bring Sound Back") { model.reattachSound(of: clip.id) }
                    .help("Remove the detached sound and play the clip's own sound again")
            }
            .controlSize(.small)
        }
    }

    @ViewBuilder
    private var loudnessWarning: some View {
        let ranges = model.tooLoudRanges(of: clip)
        if !ranges.isEmpty {
            let seconds = ranges.reduce(0) { $0 + $1.duration.seconds }
            Label {
                Text(
                    "Too loud in places (\(seconds.formatted(.number.precision(.fractionLength(1)))) s): it may crackle. Lower the volume, or the line where the waveform is marked."
                )
                .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill")
            }
            .font(.caption)
            .foregroundStyle(.red)
        }
    }

    @ViewBuilder
    private var volumePoints: some View {
        VStack(alignment: .leading, spacing: 4) {
            if clip.volumeKeys.isEmpty {
                Text("To make the sound rise or fall, ⌥-click the volume line on the clip to add points, then drag them up or down.")
            } else {
                HStack {
                    Text("The volume rises and falls along the line")
                    Spacer()
                    Button("Remove Points") { model.removeVolumePoints(of: [clip.id]) }.controlSize(.small)
                }
                Text("Drag a point up or down; ⌥-click it to remove it.")
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var equalizer: some View {
        VStack(alignment: .leading, spacing: 4) {
            Picker("Tone", selection: Binding(get: { clip.equalizer }, set: { model.setEqualizer($0, for: [clip.id]) })) {
                Text("As recorded").tag(SoundEQ?.none)
                ForEach(SoundEQ.allCases) { Text($0.displayName).tag(SoundEQ?.some($0)) }
            }
            .controlSize(.small)
            .disabled(model.soundProcessing[clip.id] != nil)
            Text(clip.equalizer?.hint ?? "Shape the tone: clearer speech, fuller music, or less rumble.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

/// How long the sound takes to come in and go out. Saved when a slider is let go.
private struct FadeSliders: View {
    let model: EditorModel
    let clip: Clip
    @State private var dragging: (edge: ClipEdge, seconds: Double)?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Fades").font(.subheadline.weight(.semibold))
            row("In", edge: .start, value: clip.fadeIn.seconds)
            row("Out", edge: .end, value: clip.fadeOut.seconds)
            Text("Or drag the small handles at the top corners of the clip's waveform.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func row(_ title: String, edge: ClipEdge, value: Double) -> some View {
        let shown = dragging?.edge == edge ? dragging!.seconds : value
        let limit = min(Clip.maxFade.seconds, clip.duration.seconds)
        return HStack {
            Text(title).frame(width: 28, alignment: .leading)
            Slider(value: Binding(get: { shown }, set: { dragging = (edge, $0) }), in: 0...max(limit, 0.1)) { editing in
                if !editing, let drag = dragging {
                    dragging = nil
                    model.setFade(edge, to: CMTime(seconds: (drag.seconds * 10).rounded() / 10, preferredTimescale: 600), for: [clip.id])
                }
            }
            .controlSize(.small)
            Text(shown < 0.05 ? "Off" : "\(shown.formatted(.number.precision(.fractionLength(1)))) s")
                .monospacedDigit()
                .frame(width: 40, alignment: .trailing)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Fade \(title.lowercased())")
    }
}

/// The voice effects as a grid of buttons, with "None".
struct VoiceEffectPicker: View {
    let model: EditorModel
    let clip: Clip

    private let columns = [GridItem(.adaptive(minimum: 84), spacing: 6)]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Voice effect").font(.subheadline.weight(.semibold))
            LazyVGrid(columns: columns, alignment: .leading, spacing: 6) {
                button(nil, title: "None", image: "person.wave.2")
                ForEach(VoiceEffect.allCases) { button($0, title: $0.displayName, image: $0.systemImage) }
            }
            .disabled(model.soundProcessing[clip.id] != nil)
            if let progress = model.soundProcessing[clip.id] {
                ProgressView(value: progress) { Text("Making the effect…").font(.caption) }
            }
        }
    }

    private func button(_ effect: VoiceEffect?, title: String, image: String) -> some View {
        let isOn = clip.voiceEffect == effect
        return Button {
            model.setVoiceEffect(effect, for: [clip.id])
        } label: {
            Label(title, systemImage: isOn ? "checkmark" : image)
                .font(.caption)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.bordered)
        .tint(isOn ? .accentColor : nil)
        .controlSize(.small)
        .accessibilityAddTraits(isOn ? .isSelected : [])
        .help(effect == nil ? "The voice as recorded" : "Make the voice sound like: \(title)")
    }
}
