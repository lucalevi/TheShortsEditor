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
            if let sticker = title.sticker {
                StickerSection(model: model, title: title, sticker: sticker)
            } else {
                textSections
            }

            TitleMotionSection(model: model, title: title)

            FollowSubjectSection(model: model, title: title)

            FollowClipToggle(model: model, item: .title(title.id))

            positionAndTiming

            if !title.isSticker {
                Button("Read It Aloud…", systemImage: "waveform") { model.beginSpeech(for: title.id) }
                    .help("A voice reads this title, added as a voice-over where it starts")
            }

            Button(title.isSticker ? "Delete Sticker" : "Delete Title", systemImage: "trash", role: .destructive) { model.deleteSelection() }
        }
        .onAppear(perform: focusTextIfAsked)
        .onChange(of: model.wantsTitleTextFocus) { focusTextIfAsked() }
        .onDisappear { if isEditing { save() } }
    }

    @ViewBuilder
    private var textSections: some View {
            VStack(alignment: .leading, spacing: 6) {
                Text("Text").font(.subheadline.weight(.semibold))
                TextField("Your title", text: Binding(get: { isEditing ? draft : title.text }, set: { if isEditing { draft = $0 } }), axis: .vertical)
                    .lineLimit(1...5)
                    .textFieldStyle(.roundedBorder)
                    .focused($isEditing)
                    .onSubmit { isEditing = false }
                    .onChange(of: draft) { _, typed in
                        // Shown in the viewer as it is typed; saved when editing ends.
                        guard isEditing else { return }
                        let text = typed.trimmingCharacters(in: .whitespacesAndNewlines)
                        model.previewTitleText(text.isEmpty ? nil : text, for: title.id)
                    }
                    .onChange(of: isEditing) { _, editing in
                        if editing {
                            draft = title.text
                        } else {
                            save()
                        }
                    }
                Text("The viewer shows it as you type. Press Return when done. Long titles wrap onto more lines by themselves.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Style").font(.subheadline.weight(.semibold))
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 72), spacing: 6)], spacing: 6) {
                    // Each look shown with the title's own first words.
                    let sample = String(title.text.split(separator: "\n").first?.prefix(10) ?? "Hook")
                    ForEach(TitleStyle.allCases) { style in
                        StyleChip(name: style.displayName, isSelected: title.style == style, makeImage: { TitlePreview.image(for: style.look, text: sample) }) {
                            model.editTitle(title.id, "Change Title Style") { $0.applyStyle(style) }
                        }
                    }
                }
            }

            TitleLookSection(model: model, title: title)
    }

    @ViewBuilder
    private var positionAndTiming: some View {
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
                HStack {
                    Text(title.isSticker ? "Or drag it anywhere in the viewer." : "Or drag the title anywhere in the viewer.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if title.horizontalPosition != 0.5 {
                        Button("Centre Across") { model.editTitle(title.id, "Move Title") { $0.horizontalPosition = 0.5 } }
                            .controlSize(.small)
                    }
                }
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
                    .help("Make it appear where the playhead is")
                Text("You can also drag it on the timeline, or drag its right edge to change how long it stays.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
    }

    private func focusTextIfAsked() {
        guard model.wantsTitleTextFocus else { return }
        model.wantsTitleTextFocus = false
        draft = title.text
        isEditing = true
    }

    private func save() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, text != title.text else {
            model.previewTitleText(nil, for: title.id)
            return
        }
        // The typed text stays shown until the rebuilt Short (which has it) arrives.
        model.editTitle(title.id, "Edit Title") { $0.text = text }
    }
}

/// The title's own look: font, size, colours, outline, box, shadow, capitals, and saved styles.
private struct TitleLookSection: View {
    let model: EditorModel
    let title: TextOverlay
    @State private var dragging: Double?
    @State private var isNaming = false
    @State private var newName = ""

    private var look: TextLook { title.look }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Design").font(.subheadline.weight(.semibold))
                Spacer()
                if title.isCustomized {
                    Button("Reset") { model.editTitle(title.id, "Reset Title Design") { $0.applyStyle($0.style) } }
                        .controlSize(.small)
                        .help("Back to how the \(title.style.displayName) style looks")
                }
            }
            HStack {
                FontMenu(model: model, selection: look.fontFamily) { family in
                    model.editTitleLook(title.id, "Change Font") { $0.fontFamily = family }
                }
                Toggle("Bold", isOn: Binding(get: { look.isBold }, set: { bold in
                    model.editTitleLook(title.id, bold ? "Bold" : "Not Bold") { $0.weight = bold ? 0.62 : 0 }
                }))
                .toggleStyle(.button)
                Toggle("AA", isOn: Binding(get: { look.uppercase }, set: { on in
                    model.editTitleLook(title.id, "Change Capitals") { $0.uppercase = on }
                }))
                .toggleStyle(.button)
                .help("All capitals")
            }
            .controlSize(.small)
            HStack {
                Text("Size").frame(width: 34, alignment: .leading)
                Slider(value: Binding(get: { dragging ?? look.size }, set: { dragging = $0 }), in: TextLook.sizeRange) { editing in
                    if !editing, let value = dragging {
                        dragging = nil
                        model.editTitleLook(title.id, "Change Size") { $0.size = value.rounded() }
                    }
                }
                .controlSize(.small)
                Text("\(Int((dragging ?? look.size).rounded()))").monospacedDigit().frame(width: 32, alignment: .trailing)
            }
            ColorRow(title: "Letters", selection: look.textColor) { color in
                if let color { model.editTitleLook(title.id, "Change Colour") { $0.textColor = color } }
            }
            ColorRow(title: "Outline", selection: look.outlineColor, allowsNone: true) { color in
                model.editTitleLook(title.id, "Change Outline") { $0.outlineColor = color }
            }
            ColorRow(title: "Box behind", selection: look.boxColor, allowsNone: true) { color in
                model.editTitleLook(title.id, "Change Box") { $0.boxColor = color }
            }
            HStack {
                if look.boxColor != nil {
                    Toggle("A box per line", isOn: Binding(get: { look.boxPerLine }, set: { on in
                        model.editTitleLook(title.id, "Change Box") { $0.boxPerLine = on }
                    }))
                }
                Toggle("Shadow", isOn: Binding(get: { look.shadow }, set: { on in
                    model.editTitleLook(title.id, "Change Shadow") { $0.shadow = on }
                }))
            }
            .controlSize(.small)

            HStack {
                Menu("My Styles") {
                    if model.savedTextStyles.isEmpty {
                        Text("No saved styles yet")
                    }
                    ForEach(model.savedTextStyles) { style in
                        Button(style.name) { model.applySavedStyle(style, to: title.id) }
                    }
                    if !model.savedTextStyles.isEmpty {
                        Divider()
                        Menu("Delete") {
                            ForEach(model.savedTextStyles) { style in
                                Button(style.name, role: .destructive) { model.deleteSavedStyle(style.id) }
                            }
                        }
                    }
                }
                .fixedSize()
                .help("Your saved looks, for every Short")
                Button("Save Style…") {
                    newName = ""
                    isNaming = true
                }
                .help("Keep this look (and how it appears) to use on other titles and Shorts")
            }
            .controlSize(.small)
            if isNaming {
                HStack {
                    TextField("Name, e.g. Brand Hook", text: $newName)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit(save)
                    Button("Save", action: save).disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
                    Button("Cancel") { isNaming = false }
                }
                .controlSize(.small)
            }
        }
    }

    private func save() {
        model.saveTextStyle(from: title, name: newName)
        isNaming = false
    }
}
