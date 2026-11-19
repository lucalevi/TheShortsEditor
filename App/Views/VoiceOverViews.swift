import CoreMedia
import EditorCore
import SwiftUI

// Recording a voice-over in the viewer: the countdown, the recording bar, and the take that was
// just recorded (Listen / Retake / Delete / Keep).

/// The 3-2-1 before a voice-over (the bar under the picture shows the recording itself).
struct VoiceOverBadge: View {
    let model: EditorModel

    var body: some View {
        if case .countdown(let n)? = model.voiceOver {
            Text("\(n)")
                .font(.system(size: 96, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .shadow(radius: 8)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black.opacity(0.35))
                .allowsHitTesting(false)
        }
    }
}

/// While a voice-over is recorded: how long so far, how loud the microphone is, and Stop.
struct RecordingBar: View {
    let model: EditorModel
    let start: CMTime

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "record.circle").foregroundStyle(.red).symbolEffect(.pulse)
            Text("Recording \(TimeFormat.string(max(model.currentTime - start, .zero)))")
                .font(.callout.weight(.semibold))
                .monospacedDigit()
            SwiftUI.TimelineView(.periodic(from: .now, by: 0.05)) { _ in
                MicrophoneMeter(level: model.microphoneLevel())
            }
            .frame(width: 120, height: 8)
            .help("How loud your voice is. Speak so the bar reaches the middle or more.")
            Spacer()
            Button("Stop", systemImage: "stop.fill") { model.stopVoiceOver() }
                .help("Stop recording (Space)")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color.red.opacity(0.15))
        .overlay(alignment: .top) { Divider() }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Recording a voice-over")
    }
}

/// A level meter: a bar filled as far as the sound is loud.
private struct MicrophoneMeter: View {
    let level: Double

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.secondary.opacity(0.3))
                Capsule().fill(level > 0.9 ? Color.orange : Color.green).frame(width: geometry.size.width * level)
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Microphone level")
        .accessibilityValue("\(Int(level * 100)) percent")
    }
}

/// After recording: listen to the take, record it again, throw it away, or keep it (as iMovie
/// offers on iPhone). Shown while the new take is selected.
struct TakeBar: View {
    let model: EditorModel
    let take: EditorModel.VoiceOverTake
    let sound: SoundClip

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: take.isQuiet ? "exclamationmark.triangle.fill" : "mic.fill")
                .foregroundStyle(take.isQuiet ? .orange : .secondary)
            VStack(alignment: .leading, spacing: 1) {
                Text("\(model.project.asset(id: sound.clip.assetID)?.name ?? "Voice-over"), \(TimeFormat.string(sound.duration))")
                    .font(.callout.weight(.semibold))
                    .lineLimit(1)
                if take.isQuiet {
                    Text("Almost nothing was heard. Check the microphone in System Settings ▸ Sound.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 4)
            Button("Listen", systemImage: "play.fill") { model.listenToVoiceOver() }
                .help("Play this part of the Short with your voice")
            Button("Retake", systemImage: "arrow.counterclockwise") { model.retakeVoiceOver() }
                .help("Record it again from the same place; this take is replaced")
            Button("Delete", systemImage: "trash") { model.deleteVoiceOver() }
                .help("Throw this take away")
                .accessibilityLabel("Delete Take")
            Button("Keep") { model.keepVoiceOver() }
                .buttonStyle(.borderedProminent)
                .help("Keep this take")
        }
        .controlSize(.small)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Theme.header)
        .overlay(alignment: .top) { Divider() }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Voice-over take")
    }
}
