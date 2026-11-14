import CoreMedia
import EditorCore
import RenderEngine
import SwiftUI

// Stage L: the template chooser and the cover sheet.

/// Every template with its shots, timed to its music; then choose the clips to fill it.
struct TemplateChooser: View {
    @Bindable var model: EditorModel
    @State private var chosen: ShortTemplate = .montage

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Start from a Template").font(.title2.weight(.semibold))
                Text(
                    "Choose your clips and get a finished Short: each shot cut on the beat of the music, with its text and transitions. Swap any shot afterwards."
                )
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
            HStack(alignment: .top, spacing: 16) {
                VStack(spacing: 6) {
                    ForEach(ShortTemplate.allCases) { template in
                        Button {
                            chosen = template
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: template.systemImage).frame(width: 22)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(template.displayName).font(.body.weight(chosen == template ? .bold : .regular))
                                    Text(template.hint).font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer(minLength: 0)
                                if chosen == template { Image(systemName: "checkmark") }
                            }
                            .padding(8)
                            .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(chosen == template ? 0.12 : 0.03)))
                            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(chosen == template ? Color.accentColor : .clear, lineWidth: 2))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(chosen == template ? .isSelected : [])
                    }
                }
                .frame(width: 250)

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("\(chosen.shots.count) shots · \(String(format: "%.0f", chosen.length.seconds)) s")
                            .font(.headline)
                        Spacer()
                        Label("\(chosen.style.displayName) · \(chosen.style.music.displayName) music", systemImage: chosen.style.systemImage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .help("The style and music it comes in. You can change them any time (the cuts then stay where they are).")
                    }
                    ScrollView {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(Array(zip(chosen.shots, chosen.shotLengths).enumerated()), id: \.offset) { index, pair in
                                let (shot, length) = pair
                                HStack(alignment: .top, spacing: 8) {
                                    Text("\(index + 1)")
                                        .font(.caption.weight(.bold))
                                        .frame(width: 20, height: 20)
                                        .background(Circle().fill(Color.white.opacity(0.12)))
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text("\(shot.name) · \(String(format: "%.1f", length.seconds)) s").font(.callout.weight(.semibold))
                                        Text(shot.direction).font(.caption).foregroundStyle(.secondary)
                                        if let title = shot.title {
                                            Label("“\(title)”", systemImage: "textformat").font(.caption).foregroundStyle(.secondary)
                                        }
                                    }
                                    Spacer(minLength: 0)
                                    if let transition = shot.transition {
                                        Image(systemName: "arrow.right.square")
                                            .foregroundStyle(.secondary)
                                            .help("Comes in with \(transition.displayName)")
                                            .accessibilityLabel("Comes in with \(transition.displayName)")
                                    }
                                }
                            }
                        }
                    }
                }
                .frame(width: 320, height: 320)
            }
            HStack {
                Text("Your clips play in the order they were filmed; swap any shot afterwards. Fewer than the shots is fine.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Cancel", role: .cancel) { model.choosesTemplate = false }
                    .keyboardShortcut(.cancelAction)
                Button("Choose Clips…") { model.newShort(fromTemplate: chosen) }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(22)
        .onAppear { model.prepareMusic(chosen.style.music) }
        .onChange(of: chosen) { model.prepareMusic(chosen.style.music) }
    }
}

/// The cover: a moment of the Short with big text, saved as a picture for YouTube.
struct CoverSheet: View {
    @Bindable var model: EditorModel
    @State private var cover: ShortCover
    @State private var preview: CGImage?

    init(model: EditorModel, cover: ShortCover) {
        self.model = model
        _cover = State(initialValue: cover)
    }

    private var lastFrame: Double { max(model.project.duration.seconds - 1.0 / 30, 0) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Cover").font(.title2.weight(.semibold))
                Text("The picture people see before they tap. Upload it to YouTube as the Short's thumbnail. It is also this Short's picture in All Shorts.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(alignment: .top, spacing: 18) {
                ZStack {
                    Rectangle().fill(.black)
                    if let preview {
                        Image(decorative: preview, scale: 1).resizable().scaledToFit()
                    } else {
                        ProgressView()
                    }
                }
                .frame(width: 216, height: 384)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .accessibilityLabel("Cover preview")

                VStack(alignment: .leading, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Moment").font(.headline)
                        Slider(
                            value: Binding(
                                get: { cover.time.seconds },
                                set: { cover.time = CMTime(seconds: $0, preferredTimescale: 600).snappedToFrame() }),
                            in: 0...max(lastFrame, 0.01))
                        HStack {
                            Text(TimeFormat.string(cover.time)).monospacedDigit().font(.caption)
                            Spacer()
                            Button("Use Playhead") { cover.time = model.currentTime.snappedToFrame() }
                                .controlSize(.small)
                                .help("The frame the viewer shows")
                        }
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Text").font(.headline)
                        TextField("A few big words", text: $cover.text, axis: .vertical)
                            .lineLimit(1...3)
                            .textFieldStyle(.roundedBorder)
                        HStack {
                            Text("Place").font(.caption)
                            Slider(value: $cover.textPosition, in: 0.12...0.7)
                                .controlSize(.small)
                                .help("Higher or lower on the picture (YouTube's buttons cover the bottom)")
                        }
                        .disabled(cover.text.trimmingCharacters(in: .whitespaces).isEmpty)
                        Text("Big text in the Short's style. Four or five words read best.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Toggle("Show the captions too", isOn: $cover.showsCaptions)
                        .disabled(!model.project.hasCaptions)
                    Spacer(minLength: 0)
                }
                .frame(width: 260)
            }
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { model.coverDraft = nil }
                    .keyboardShortcut(.cancelAction)
                Button("Keep") {
                    model.keepCover(cover)
                    model.coverDraft = nil
                }
                .help("Keep this cover with the Short, without saving a picture")
                Button("Save Cover…") {
                    model.saveCover(cover)
                    model.coverDraft = nil
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(22)
        .task(id: cover) {
            // Drawn a moment after the last change, so dragging the slider stays smooth.
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled else { return }
            preview = try? await ProjectPoster.cover(of: model.project, cover, maxSize: CGSize(width: 432, height: 768))
        }
    }
}
