import CoreMedia
import EditorCore
import RenderEngine
import SwiftUI

/// Voice clean-up for clips with sound.
struct CleanVoiceToggle: View {
    let model: EditorModel
    let clips: [Clip]

    var body: some View {
        let progress = clips.compactMap { model.tasks.progress(.voiceCleanUp($0.assetID)) }.first
        VStack(alignment: .leading, spacing: 4) {
            Toggle("Clean up voice", isOn: Binding(get: { clips.allSatisfy(\.cleansVoice) }, set: { model.setCleansVoice($0, for: clips.map(\.id)) }))
                .disabled(progress != nil)
            if let progress {
                ProgressView(value: progress) { Text("Cleaning up the sound…").font(.caption) }
            } else {
                Text("Removes background noise and hum, keeps the voice. Done on this Mac with Apple's voice isolation.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// A sound effect or voice-over.
struct SoundInspector: View {
    let model: EditorModel
    let sound: SoundClip

    var body: some View {
        let asset = model.project.asset(id: sound.clip.assetID)
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Label(
                    sound.detachedFrom != nil ? "Sound of \(asset?.name ?? "a clip")" : asset?.name ?? "Missing sound",
                    systemImage: sound.isVoiceOver ? "mic.fill" : sound.detachedFrom != nil ? "waveform.path" : "waveform"
                )
                .font(.headline)
                .lineLimit(2)
                Text("From \(TimeFormat.string(sound.start)) for \(TimeFormat.string(sound.duration))")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            LiveVolumeSlider(model: model, clip: sound.clip)
            if sound.detachedFrom != nil {
                Text(
                    "Detached from its clip. Drag its start earlier to hear it before the picture changes, "
                        + "or its end later to let it carry on over the next clip."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
            SoundShapingSection(model: model, clip: sound.clip)
                .id(sound.id)
            if sound.detachedFrom == nil {
                Toggle(
                    "It's a voice-over",
                    isOn: Binding(
                        get: { sound.isVoiceOver },
                        set: { on in
                            model.apply(on ? "Mark as Voice-Over" : "Mark as Sound Effect") { $0.updateSound(sound.id) { $0.isVoiceOver = on } }
                        }))
                Text("The music is lowered under voice-overs, as under people talking in your clips.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if sound.canLowerUnderSpeech {
                Toggle(
                    "Lower while people talk",
                    isOn: Binding(
                        get: { sound.lowersUnderSpeech },
                        set: { on in
                            model.apply(on ? "Lower Sound Under Speech" : "Keep Sound Level") { $0.updateSound(sound.id) { $0.lowersUnderSpeech = on } }
                        }))
                Text("For a second song or background sound: it goes quieter whenever someone speaks, like the music.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if sound.isVoiceOver || sound.detachedFrom != nil { CleanVoiceToggle(model: model, clips: [sound.clip]) }
            FollowClipToggle(model: model, item: .sound(sound.id))
            HStack {
                Button("Start at Playhead") { model.moveSound(sound.id, to: model.playback.currentTime) }
                Button("Delete", systemImage: "trash", role: .destructive) { model.deleteSelection() }
            }
            .controlSize(.small)
        }
    }
}

/// One volume for several clips and sounds, with Mute; shows "Mixed" until they are set alike.
struct MultipleVolumeSlider: View {
    let model: EditorModel
    let clips: [Clip]
    @State private var dragging: Double?

    var body: some View {
        let allMuted = clips.allSatisfy(\.isMuted)
        let common = Set(clips.map(\.volume)).count == 1 ? clips.first?.volume : nil
        VStack(alignment: .leading, spacing: 6) {
            Text("Volume").font(.subheadline.weight(.semibold))
            HStack {
                Button(allMuted ? "Unmute All" : "Mute All", systemImage: allMuted ? "speaker.slash.fill" : "speaker.wave.2.fill") {
                    model.setClipsMuted(clips.map(\.id), !allMuted)
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .help(allMuted ? "Turn their sound back on" : "Silence all of them")
                Slider(value: Binding(get: { dragging ?? common ?? 1 }, set: { dragging = $0 }), in: 0...Clip.maxVolume) { editing in
                    if !editing, let value = dragging {
                        dragging = nil
                        model.setClipsVolume(clips.map(\.id), (value * 20).rounded() / 20)
                    }
                }
                .disabled(allMuted)
                .accessibilityLabel("Volume of all selected")
                Text(allMuted ? "Off" : (dragging ?? common).map { "\(Int(($0 * 100).rounded()))%" } ?? "Mixed")
                    .monospacedDigit()
                    .frame(width: 44, alignment: .trailing)
            }
            Text("Sets every selected clip and sound to the same volume.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

/// Volume with a live value while dragging, saved when let go.
struct LiveVolumeSlider: View {
    let model: EditorModel
    let clip: Clip
    @State private var dragging: Double?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Volume").font(.subheadline.weight(.semibold))
            HStack {
                Button(clip.isMuted ? "Unmute" : "Mute", systemImage: clip.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill") {
                    model.setClipMuted(clip.id, !clip.isMuted)
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                Slider(value: Binding(get: { dragging ?? clip.volume }, set: { dragging = $0 }), in: 0...Clip.maxVolume) { editing in
                    if !editing, let value = dragging {
                        dragging = nil
                        model.setClipVolume(clip.id, (value * 20).rounded() / 20)
                    }
                }
                .disabled(clip.isMuted)
                Text(clip.isMuted ? "Off" : "\(Int(((dragging ?? clip.volume) * 100).rounded()))%")
                    .monospacedDigit()
                    .frame(width: 40, alignment: .trailing)
            }
        }
    }
}
