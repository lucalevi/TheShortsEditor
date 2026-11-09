import CoreMedia
import EditorCore
import SwiftUI

/// Settings of the background song: how loud, which part, and how it fits around speech.
struct MusicInspector: View {
    let model: EditorModel
    let music: BackgroundMusic
    let song: MediaAsset

    @State private var draggingVolume: Double?
    @State private var draggingStart: Double?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label(song.name, systemImage: "music.note")
                .font(.headline)
                .lineLimit(2)

            VStack(alignment: .leading, spacing: 6) {
                Text("Volume").font(.subheadline.weight(.semibold))
                HStack {
                    Slider(value: Binding(get: { draggingVolume ?? music.volume }, set: { draggingVolume = $0 }), in: 0...1) { editing in
                        if !editing, let value = draggingVolume {
                            draggingVolume = nil
                            model.editMusic("Change Music Volume") { $0.volume = (value * 20).rounded() / 20 }
                        }
                    }
                    Text("\(Int(((draggingVolume ?? music.volume) * 100).rounded()))%")
                        .monospacedDigit()
                        .frame(width: 40, alignment: .trailing)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Toggle("Lower while people talk", isOn: Binding(get: { music.lowersUnderSpeech }, set: { on in
                    model.editMusic(on ? "Lower Music Under Speech" : "Keep Music Level") { $0.lowersUnderSpeech = on }
                }))
                Text("The music goes down whenever there's speech in your clips, so every word is heard. The line on the timeline shows it.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Toggle("Fade in at the start", isOn: Binding(get: { music.fadesIn }, set: { on in
                    model.editMusic("Change Music Fade") { $0.fadesIn = on }
                }))
                Toggle("Fade out at the end", isOn: Binding(get: { music.fadesOut }, set: { on in
                    model.editMusic("Change Music Fade") { $0.fadesOut = on }
                }))
            }
            .toggleStyle(.checkbox)

            VStack(alignment: .leading, spacing: 6) {
                Text("Start the song at").font(.subheadline.weight(.semibold))
                let latest = max(song.duration.seconds - 1, 0)
                HStack {
                    Slider(value: Binding(get: { draggingStart ?? music.sourceStart.seconds }, set: { draggingStart = $0 }), in: 0...max(latest, 0.01)) { editing in
                        if !editing, let value = draggingStart {
                            draggingStart = nil
                            model.setMusicStart(CMTime(seconds: value, preferredTimescale: 600))
                        }
                    }
                    .disabled(latest <= 0)
                    Text(TimeFormat.string(CMTime(seconds: draggingStart ?? music.sourceStart.seconds, preferredTimescale: 600)))
                        .monospacedDigit()
                        .frame(width: 48, alignment: .trailing)
                }
                Text("Skip a slow intro so the best part plays under your Short. The song is \(TimeFormat.string(song.duration)) long.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if model.project.musicEndsEarly, let range = model.project.musicRange {
                    Label("The song ends at \(TimeFormat.string(range.end)), before your Short does. Start it earlier, or pick a longer song.", systemImage: "info.circle")
                        .font(.caption)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if model.duration > CMTime(value: 60, timescale: 1) {
                Label("Your Short is longer than 1:00. If the song's owner claims it, YouTube blocks the Short. Use music you have the rights to.", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Button("Change Song…") { MusicImportPanel.run(model: model) }
                Button("Remove Music", systemImage: "trash", role: .destructive) { model.removeMusic() }
            }
        }
    }
}
