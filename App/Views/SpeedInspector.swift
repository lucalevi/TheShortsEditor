import CoreMedia
import EditorCore
import RenderEngine
import SwiftUI

/// How fast a clip plays.
struct SpeedSection: View {
    let model: EditorModel
    let clips: [Clip]
    @State private var dragging: Double?

    private var speed: Double { clips.first?.speed ?? 1 }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Speed").font(.subheadline.weight(.semibold))
                Spacer()
                if clips.contains(where: { $0.speed != 1 }) {
                    Button("Reset") { model.setSpeed(1, for: clips.map(\.id)) }
                        .controlSize(.small)
                        .help("Back to normal speed (1×)")
                }
            }
            HStack(spacing: 4) {
                ForEach(Clip.speedPresets, id: \.self) { preset in
                    Button(label(preset)) { model.setSpeed(preset, for: clips.map(\.id)) }
                        .buttonStyle(.bordered)
                        .tint(abs(speed - preset) < 0.001 ? .accentColor : nil)
                        .accessibilityAddTraits(abs(speed - preset) < 0.001 ? .isSelected : [])
                }
            }
            .controlSize(.small)
            HStack {
                // A logarithmic slider: as far from 1× to 2× as from 0.5× to 1×.
                Slider(
                    value: Binding(get: { log2(dragging ?? speed) }, set: { dragging = pow(2, $0) }),
                    in: log2(Clip.speedRange.lowerBound)...log2(Clip.speedRange.upperBound)
                ) { editing in
                    if !editing, let value = dragging {
                        dragging = nil
                        model.setSpeed((value * 20).rounded() / 20, for: clips.map(\.id))
                    }
                }
                .controlSize(.small)
                Text(label(dragging ?? speed)).monospacedDigit().frame(width: 44, alignment: .trailing)
            }
            Text(speed > 1 ? "Faster and shorter. Voices keep their pitch." : speed < 1 ? "Slow motion: longer. Voices keep their pitch." : "As recorded.")
                .font(.caption)
                .foregroundStyle(.secondary)
            RhythmSpeedExtras(model: model, clips: clips)
            TimeExtras(model: model, clips: clips)
        }
    }

    private func label(_ value: Double) -> String {
        value == value.rounded() ? "\(Int(value))×" : "\(value.formatted(.number.precision(.fractionLength(0...2))))×"
    }
}
