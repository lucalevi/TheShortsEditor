import EditorCore
import SwiftUI

/// Details of the selected clip, or of the whole Short when nothing is selected.
struct InspectorView: View {
    @Bindable var model: EditorModel

    var body: some View {
        VStack(spacing: 0) {
            PanelHeader(title: model.silenceSession != nil ? "Remove Pauses" : model.selectedClip == nil ? "Your Short" : "Clip")
            ScrollView {
                Group {
                    if model.silenceSession != nil {
                        SilencePanel(model: model)
                    } else if let clip = model.selectedClip {
                        ClipInspector(model: model, clip: clip)
                    } else {
                        ProjectInspector(model: model)
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

private struct ClipInspector: View {
    let model: EditorModel
    let clip: Clip

    private var asset: MediaAsset? { model.project.asset(id: clip.assetID) }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Thumbnail(image: model.thumbnails[clip.assetID])
                .frame(height: 110)
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 4) {
                Text(asset?.name ?? "Missing media").font(.headline).lineLimit(2)
                Text("Length \(TimeFormat.string(clip.duration))").foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Framing").font(.subheadline.weight(.semibold))
                Picker("Framing", selection: Binding(get: { clip.framing }, set: { model.setFraming($0, for: clip.id) })) {
                    Text("Fill screen").tag(Framing.fill)
                    Text("Show all").tag(Framing.fit)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                Text(clip.framing == .fill
                     ? "The video covers the whole screen. Edges that don't fit are cropped."
                     : "The whole video is visible, with black bars where it doesn't reach.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Button("Split at Playhead", systemImage: "scissors") { model.splitAtPlayhead() }
                Button("Delete", systemImage: "trash", role: .destructive) { model.deleteSelectedClip() }
            }
        }
    }
}

private struct ProjectInspector: View {
    let model: EditorModel

    private var fractionOfLimit: Double {
        min(model.duration.seconds / Project.maxDuration.seconds, 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Length").font(.subheadline.weight(.semibold))
                Text("\(TimeFormat.string(model.duration)) of 3:00 max")
                    .monospacedDigit()
                ProgressView(value: fractionOfLimit)
                    .tint(model.project.isOverMaxDuration ? .red : .accentColor)
                if model.project.isOverMaxDuration {
                    Label("Too long for a Short. Trim it to 3:00 or less.", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                        .font(.caption)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Format").font(.subheadline.weight(.semibold))
                Text("Vertical 9:16 · 1080 × 1920 · 30 fps").foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Tips").font(.subheadline.weight(.semibold))
                Tip(icon: "bolt.fill", text: "Make the very first second the hook. Cut any intro.")
                Tip(icon: "rectangle.dashed", text: "Keep faces and text out of the dimmed areas. YouTube covers them.")
                Tip(icon: "hand.tap", text: "Click a clip to select it. Click on the timeline to move the playhead.")
            }
        }
    }
}

private struct Tip: View {
    let icon: String
    let text: String

    var body: some View {
        Label {
            Text(text).fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: icon).foregroundStyle(.tint)
        }
        .font(.callout)
    }
}
