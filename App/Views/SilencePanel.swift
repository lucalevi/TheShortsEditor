import CoreMedia
import EditorCore
import RenderEngine
import SwiftUI

/// Choosing how much of the pauses to cut, with the result marked on the timeline before anything changes.
struct SilencePanel: View {
    @Bindable var model: EditorModel

    var body: some View {
        if let session = model.silenceSession {
            VStack(alignment: .leading, spacing: 18) {
                if session.isMeasuring {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Listening for pauses…")
                    }
                } else {
                    summary(session.plan)
                    controls(session.settings)
                    VStack(alignment: .leading, spacing: 8) {
                        Button("Play Without Pauses", systemImage: "play.fill") { model.previewSilenceRemoval() }
                            .disabled(session.plan.isEmpty)
                        HStack {
                            Button("Cancel") { model.cancelSilenceRemoval() }
                            Button("Remove Pauses") { model.applySilenceRemoval() }
                                .buttonStyle(.borderedProminent)
                                .disabled(session.plan.isEmpty)
                        }
                    }
                }
            }
        }
    }

    private func summary(_ plan: SilencePlan) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if plan.isEmpty {
                Text("No pauses long enough to cut.").font(.headline)
                Text("Try a shorter pause, or counting softer sounds as pauses. With music or noise behind the voice, listen to the voice only.").font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                let count = plan.timelineCuts.count
                Text("Cuts \(TimeFormat.string(plan.removedDuration)) in \(count) \(count == 1 ? "place" : "places")")
                    .font(.headline)
                    .monospacedDigit()
                Text("New length \(TimeFormat.string(model.duration - plan.removedDuration)). The parts to cut are marked in red on the timeline.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func controls(_ settings: SilenceSettings) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            if VoiceCleaner.isAvailable, let session = model.silenceSession {
                VStack(alignment: .leading, spacing: 4) {
                    Toggle(
                        "Listen to the voice only",
                        isOn: Binding(
                            get: { session.listensToVoiceOnly },
                            set: { model.setPausesListenToVoiceOnly($0) }
                        )
                    )
                    .disabled(session.separating != nil)
                    if let fraction = session.separating {
                        ProgressView(value: fraction) { Text("Separating the voice…").font(.caption) }
                    }
                    Text("For music or noise behind the voice: pauses are found in the voice alone, separated on this Mac (once per file).")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("What counts as a pause").font(.subheadline.weight(.semibold))
                Slider(
                    value: Binding(
                        get: { Double(settings.threshold) },
                        set: {
                            var s = settings; s.threshold = Float($0.rounded()); model.updateSilenceSettings(s)
                        }
                    ), in: -60 ... -15
                ) {
                    EmptyView()
                } minimumValueLabel: {
                    Text("Silence").font(.caption)
                } maximumValueLabel: {
                    Text("Soft sounds").font(.caption)
                }
            }
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Shortest pause to cut").font(.subheadline.weight(.semibold))
                    Spacer()
                    Text("\(settings.minimumPause.seconds.formatted(.number.precision(.fractionLength(1)))) s")
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                Slider(
                    value: Binding(
                        get: { settings.minimumPause.seconds },
                        set: {
                            var s = settings; s.minimumPause = CMTime(seconds: ($0 * 10).rounded() / 10, preferredTimescale: 600);
                            model.updateSilenceSettings(s)
                        }
                    ), in: SilenceSettings.minimumPauseRange.lowerBound.seconds...SilenceSettings.minimumPauseRange.upperBound.seconds
                ) {
                    EmptyView()
                } minimumValueLabel: {
                    Text("Short").font(.caption)
                } maximumValueLabel: {
                    Text("Long").font(.caption)
                }
                Text("Shorter pauses are natural and stay.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("Room around words").font(.subheadline.weight(.semibold))
                Slider(
                    value: Binding(
                        get: { Double(settings.padding.value) },
                        set: {
                            var s = settings; s.padding = CMTime(value: Int64($0.rounded()), timescale: Project.frameRate); model.updateSilenceSettings(s)
                        }
                    ), in: 0...12
                ) {
                    EmptyView()
                } minimumValueLabel: {
                    Text("Tight").font(.caption)
                } maximumValueLabel: {
                    Text("Relaxed").font(.caption)
                }
                Text("Keeps a little quiet before and after speech, so words aren't clipped.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
