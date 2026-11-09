import CoreMedia
import EditorCore
import RenderEngine
import SwiftUI

/// Editing the selected title: its words, look, entrance, place and timing.
struct TitleInspector: View {
    let model: EditorModel
    let title: TextOverlay

    /// What the user is typing. Saved once, when editing ends. Only written while editing: as focus
    /// leaves, the field hands back the project's text, which must not replace what was typed.
    @State private var draft = ""
    @FocusState private var isEditing: Bool

    private var isCovered: Bool {
        TitlePreview.frame(of: title).map(SafeZone.covers) ?? false
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Text").font(.subheadline.weight(.semibold))
                TextField("Your title", text: Binding(get: { isEditing ? draft : title.text }, set: { if isEditing { draft = $0 } }), axis: .vertical)
                    .lineLimit(1...5)
                    .textFieldStyle(.roundedBorder)
                    .focused($isEditing)
                    .onSubmit { isEditing = false }
                    .onChange(of: isEditing) { _, editing in
                        if editing {
                            draft = title.text
                        } else {
                            save()
                        }
                    }
                Text("Press Return when done. Long titles wrap onto more lines by themselves.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Style").font(.subheadline.weight(.semibold))
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 72), spacing: 6)], spacing: 6) {
                    ForEach(TitleStyle.allCases) { style in
                        StyleChip(name: style.displayName, isSelected: title.style == style, makeImage: { TitlePreview.image(for: style) }) {
                            model.editTitle(title.id, "Change Title Style") { $0.style = style }
                        }
                    }
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Appears with").font(.subheadline.weight(.semibold))
                Picker("Appears with", selection: Binding(get: { title.entrance }, set: { entrance in
                    model.editTitle(title.id, "Change Title Animation") { $0.entrance = entrance }
                })) {
                    ForEach(TitleEntrance.allCases) { Text($0.displayName).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Position").font(.subheadline.weight(.semibold))
                Picker("Position", selection: Binding(get: { TitlePlacement(exactly: title.verticalPosition) }, set: { placement in
                    guard let placement else { return }
                    model.editTitle(title.id, "Move Title") { $0.verticalPosition = placement.verticalPosition }
                })) {
                    ForEach(TitlePlacement.allCases) { Text($0.displayName).tag(Optional($0)) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                Text("Or drag the title up and down in the viewer.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if isCovered {
                    Label("Part of it is in an area YouTube covers. Move it towards the middle.", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Timing").font(.subheadline.weight(.semibold))
                if title.visibleRange(in: model.project) == nil {
                    Label("It's after the end of your Short, so it won't be seen.", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text("From \(TimeFormat.string(title.start)) to \(TimeFormat.string(title.end))")
                    .monospacedDigit()
                Stepper {
                    Text("On screen for \(title.duration.seconds, format: .number.precision(.fractionLength(1))) s").monospacedDigit()
                } onIncrement: {
                    model.setTitleDuration(title.id, title.duration + CMTime(value: 1, timescale: 2))
                } onDecrement: {
                    model.setTitleDuration(title.id, title.duration - CMTime(value: 1, timescale: 2))
                }
                Button("Start at Playhead") { model.moveTitle(title.id, to: model.currentTime) }
                    .help("Make the title appear where the playhead is")
                Text("You can also drag it on the timeline, or drag its right edge to change how long it stays.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button("Delete Title", systemImage: "trash", role: .destructive) { model.deleteSelection() }
        }
        .onAppear(perform: focusTextIfAsked)
        .onChange(of: model.wantsTitleTextFocus) { focusTextIfAsked() }
        .onDisappear { if isEditing { save() } }
    }

    private func focusTextIfAsked() {
        guard model.wantsTitleTextFocus else { return }
        model.wantsTitleTextFocus = false
        draft = title.text
        isEditing = true
    }

    private func save() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, text != title.text else { return }
        model.editTitle(title.id, "Edit Title") { $0.text = text }
    }
}
