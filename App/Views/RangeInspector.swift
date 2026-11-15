import CoreMedia
import EditorCore
import RenderEngine
import SwiftUI

/// A stretch of the storyline picked with R or X: what can be done to just that part.
struct RangeInspector: View {
    let model: EditorModel
    let range: CMTimeRange
    @State private var volume: Double = 1

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("\(TimeFormat.string(range.duration)) picked").font(.headline).monospacedDigit()
                Text("From \(TimeFormat.string(range.start)) to \(TimeFormat.string(range.end))")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 6) {
                Button("Delete This Part", systemImage: "trash") { model.deleteRange() }
                    .help("Take it out; what comes after closes up (⌫)")
                Button("Keep Only This Part", systemImage: "scissors") { model.trimToRange() }
                    .help("Trim the clips it touches to just this part (⌥/)")
                Button("Play It", systemImage: "play.fill") { model.playSelection() }
                    .help("Play just this part (/). With Loop on, it plays over and over.")
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("Speed of this part").font(.subheadline.weight(.semibold))
                HStack(spacing: 4) {
                    ForEach(Clip.speedPresets, id: \.self) { speed in
                        Button(speed == 1 ? "1×" : "\(speed.formatted())×") { model.setSpeedInRange(speed) }
                            .buttonStyle(.bordered)
                    }
                }
                .controlSize(.small)
                Text("The picture eases into and out of the new speed. Turn that off under Speed on the clip.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Instant Replay", systemImage: "gobackward") { model.addInstantReplay() }
                    .controlSize(.small)
                    .help("Show this part once more straight after itself, at half speed")
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("Volume of this part").font(.subheadline.weight(.semibold))
                HStack {
                    Slider(value: $volume, in: 0...Clip.maxVolume) { editing in
                        if !editing { model.setVolumeInRange((volume * 20).rounded() / 20) }
                    }
                    .controlSize(.small)
                    Text("\(Int((volume * 100).rounded()))%").monospacedDigit().frame(width: 44, alignment: .trailing)
                }
                Button("Mute This Part", systemImage: "speaker.slash") { model.setVolumeInRange(1, muted: true) }
                    .controlSize(.small)
                Text("The sound fades smoothly into and out of the new volume.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Button("Clear Range") { model.clearRanges() }
                .controlSize(.small)
            Text("Hold R and drag across clips to pick another part, or press X for the clip under the pointer. Escape lets go.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
