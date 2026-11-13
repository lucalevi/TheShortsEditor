import EditorCore
import RenderEngine
import SwiftUI

/// Making captions, choosing how they look, and fixing their words.
struct CaptionsView: View {
    @Bindable var model: EditorModel

    var body: some View {
        if let job = model.captionJob {
            CaptionProgress(job: job) { model.cancelCaptions() }
        } else if !model.project.hasCaptions {
            MakeCaptions(model: model)
        } else {
            VStack(spacing: 0) {
                // Scrolls on its own, so opening the design options never pushes the window around.
                ScrollView {
                    CaptionSettingsForm(model: model)
                }
                .frame(maxHeight: 330)
                .fixedSize(horizontal: false, vertical: false)
                Divider()
                CaptionList(model: model)
            }
        }
    }
}

/// The first step: pick the language and go.
private struct MakeCaptions: View {
    @Bindable var model: EditorModel

    var body: some View {
        ContentUnavailableView {
            Label("Add Captions", systemImage: "captions.bubble")
        } description: {
            Text(model.project.timeline.clips.isEmpty
                 ? "Put some clips on the timeline first. Captions are made from what is said in them."
                 : "Captions are written for you from what is said in your clips and voice-overs. It all happens on this Mac.")
        } actions: {
            VStack(spacing: 10) {
                LanguagePicker(model: model)
                Button("Make Captions") { model.makeCaptions() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(model.project.timeline.clips.isEmpty)
                Button("Import Subtitle File…") { model.importCaptionsFile() }
                    .buttonStyle(.link)
                    .disabled(model.project.timeline.clips.isEmpty)
                    .help("Use captions you already have, from an .srt file")
            }
        }
    }
}

private struct LanguagePicker: View {
    @Bindable var model: EditorModel

    var body: some View {
        Picker("Spoken language", selection: $model.captionLanguageChoice) {
            Text(CaptionLanguageChoice.automatic.displayName).tag(CaptionLanguageChoice.automatic)
            Divider()
            ForEach(CaptionLanguage.allCases) { Text($0.displayName).tag(CaptionLanguageChoice.language($0)) }
        }
        .fixedSize()
        .help("The language people speak in your clips")
    }
}

private struct CaptionProgress: View {
    let job: EditorModel.CaptionJob
    let cancel: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            switch job {
            case .detecting:
                ProgressView()
                Text("Listening for the language…")
            case .downloading(let fraction):
                ProgressView(value: fraction)
                Text("Getting the speech model ready…")
                Text("This happens once per language.").font(.caption).foregroundStyle(.secondary)
            case .listening(let index, let count):
                ProgressView()
                Text(count == 1 ? "Listening to your Short…" : "Listening to part \(index) of \(count)…")
            }
            Button("Cancel", action: cancel)
        }
        .multilineTextAlignment(.center)
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Show/hide, style and position.
private struct CaptionSettingsForm: View {
    @Bindable var model: EditorModel

    private var settings: CaptionSettings { model.project.captions }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle("Show captions", isOn: Binding(get: { settings.isVisible }, set: { model.setCaptionsVisible($0) }))
                .toggleStyle(.switch)
                .controlSize(.small)

            CaptionLookGrid(model: model, settings: settings)

            VStack(alignment: .leading, spacing: 6) {
                Text("Position").font(.subheadline.weight(.semibold))
                Picker("Position", selection: Binding(
                    get: { CaptionPlacement(settings.verticalPosition) },
                    set: { model.setCaptionPosition($0.verticalPosition) }
                )) {
                    ForEach(CaptionPlacement.allCases) { Text($0.displayName).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                Text("Or drag the caption up and down in the viewer.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            SecondLanguage(model: model, settings: settings)

            CaptionDesign(model: model, settings: settings)

            let missing = model.project.assetsNeedingTranscription(in: model.captionLanguageForNewCaptions)
            HStack {
                LanguagePicker(model: model).labelsHidden().controlSize(.small)
                Spacer()
                if !missing.isEmpty {
                    Button("Update Captions") { model.makeCaptions() }
                        .controlSize(.small)
                        .help("Make captions for clips and voice-overs that don't have them in this language yet")
                }
                CaptionsMoreMenu(model: model)
            }
        }
        .padding(12)
        .disabled(model.captionJob != nil)
    }
}

/// A style shown as it really looks, on a dark background. Used for captions and titles.
struct StyleChip: View {
    let name: String
    let isSelected: Bool
    let makeImage: () -> CGImage?
    let action: () -> Void

    @State private var image: CGImage?

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(white: 0.22))
                    .frame(height: 40)
                    .overlay {
                        if let image {
                            Image(decorative: image, scale: 1).resizable().scaledToFit().padding(4)
                        }
                    }
                Text(name).font(.caption)
            }
            .padding(4)
            .background(isSelected ? Color.accentColor.opacity(0.25) : .clear, in: RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(isSelected ? Color.accentColor : .clear, lineWidth: 2)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(name)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .task { image = makeImage() }
    }
}

/// Every caption, in order, with its words editable.
private struct CaptionList: View {
    @Bindable var model: EditorModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ScrollViewReader { proxy in
            List {
                ForEach(model.captionPages) { page in
                    CaptionRow(model: model, page: page, isCurrent: model.currentCaption?.id == page.id)
                        .id(page.id)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .onChange(of: model.currentCaption?.id) { _, id in
                if model.isPlaying, let id { proxy.scrollTo(id, anchor: .center) }
            }
            .onChange(of: model.focusedCaptionID) { _, id in
                if let id { withAnimation(reduceMotion ? nil : .default) { proxy.scrollTo(id, anchor: .center) } }
            }
            .safeAreaInset(edge: .bottom) {
                Text("Click a caption to fix it. ↩ splits it at the cursor, ⌘↩ starts a new line, ⌫ at the start joins it to the one before.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(8)
                    .frame(maxWidth: .infinity)
                    .background(Theme.header)
            }
        }
    }
}

private struct CaptionRow: View {
    let model: EditorModel
    let page: CaptionPage
    let isCurrent: Bool
    @State private var typing: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Button(TimeFormat.string(page.range.start)) {
                    model.pause()
                    model.seek(to: page.firstFrame)
                }
                .buttonStyle(.plain)
                .font(.caption.monospacedDigit())
                .foregroundStyle(isCurrent ? Color.accentColor : .secondary)
                .help("Go to this caption")
                switch page.source {
                case .sound:
                    Image(systemName: "mic").font(.caption2).foregroundStyle(.secondary).help("Heard in a voice-over or sound")
                case .broll:
                    Image(systemName: "rectangle.on.rectangle").font(.caption2).foregroundStyle(.secondary).help("Heard in a B-roll clip")
                case .clip:
                    EmptyView()
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                CaptionTextField(
                    text: page.text,
                    startsEditing: model.captionToEdit == page.id,
                    onBeginEditing: {
                        model.pause()
                        model.seek(to: page.firstFrame)
                    },
                    onCommit: { typed in
                        let text = typed.trimmingCharacters(in: .whitespacesAndNewlines)
                        if text != page.text { model.editCaption(page, text: text) }
                    },
                    onSplit: { text, offset in model.splitCaption(page, text: text, at: offset) },
                    onMerge: { text in model.mergeCaptionWithPrevious(page, text: text) },
                    cursor: model.captionEditCursor,
                    onStartedEditing: { if model.captionToEdit == page.id { model.captionToEdit = nil } },
                    onTextChange: { typing = $0 },
                    editingText: typing
                )
                if let translation = page.translation, model.project.captions.translationLanguage != nil {
                    Text(translation).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 3)
        .listRowBackground(
            (isCurrent || model.focusedCaptionID == page.id ? Color.accentColor.opacity(0.15) : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 6))
        )
    }
}

/// The caption looks, each drawn over a picture of this Short, with its word animation caught
/// mid-word.
private struct CaptionLookGrid: View {
    let model: EditorModel
    let settings: CaptionSettings
    /// A frame of the Short without its captions, as the chips' background.
    @State private var frame: CGImage?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Look").font(.subheadline.weight(.semibold))
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 74), spacing: 6)], spacing: 6) {
                ForEach(CaptionStyle.allCases) { style in
                    LookChip(style: style, settings: settings, frame: frame, isSelected: settings.style == style) {
                        model.setCaptionStyle(style)
                    }
                }
            }
        }
        // A new picture when the playhead stops somewhere else.
        .task(id: model.isPlaying ? -1 : Int(model.currentTime.seconds)) {
            guard !model.isPlaying, !model.project.timeline.clips.isEmpty else { return }
            var project = model.project
            project.captions.isVisible = false
            project.titles = []
            let time = model.currentTime
            frame = try? await ProjectPoster.frame(of: project, at: time, maxSize: CGSize(width: 240, height: 426))
        }
    }
}

private struct LookChip: View {
    let style: CaptionStyle
    let settings: CaptionSettings
    let frame: CGImage?
    let isSelected: Bool
    let action: () -> Void
    @State private var image: CGImage?

    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                ZStack {
                    RoundedRectangle(cornerRadius: 6).fill(Color(white: 0.22))
                    if let image {
                        Image(decorative: image, scale: 2).resizable().scaledToFill()
                    }
                }
                .frame(height: 46)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                Text(style.displayName).font(.caption).lineLimit(1)
            }
            .padding(3)
            .background(isSelected ? Color.accentColor.opacity(0.25) : .clear, in: RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8).strokeBorder(isSelected ? Color.accentColor : .clear, lineWidth: 2)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(style.displayName)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .help(Self.help(style))
        .task(id: Key(settings: settings, hasFrame: frame != nil, frameID: frame.map { ObjectIdentifier($0) })) {
            image = CaptionPreview.image(for: style, settings: settings, over: frame, size: CGSize(width: 160, height: 92))
        }
    }

    private struct Key: Hashable {
        var settings: CaptionSettings
        var hasFrame: Bool
        var frameID: ObjectIdentifier?
    }

    static func help(_ style: CaptionStyle) -> String {
        switch style {
        case .bold: "Big capitals; the spoken word turns yellow and grows"
        case .highlight: "The spoken word sits on a coloured box"
        case .oneWord: "One big word at a time"
        case .phrase: "Two to four words at a time, big and centred"
        case .karaoke: "Words fill with colour as they are spoken"
        case .glow: "Soft light around the letters; the spoken word shines"
        case .bounce: "The spoken word jumps up"
        case .typewriter: "Words appear one by one as they are spoken"
        case .outline: "Hollow letters; the spoken word fills in"
        case .classic: "White text on a dark box, like TV subtitles"
        case .minimal: "Plain white text with a soft shadow"
        }
    }
}

/// A translated second line under each caption.
private struct SecondLanguage: View {
    let model: EditorModel
    let settings: CaptionSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Second language").font(.subheadline.weight(.semibold))
                Spacer()
                Picker("Second language", selection: Binding(
                    get: { settings.translationLanguage },
                    set: { model.setTranslationLanguage($0) }
                )) {
                    Text("None").tag(String?.none)
                    Divider()
                    ForEach(EditorModel.translationLanguages.filter { $0 != model.project.captionLanguageInUse?.rawValue }, id: \.self) { code in
                        Text(EditorModel.languageName(code)).tag(Optional(code))
                    }
                }
                .labelsHidden()
                .fixedSize()
                .controlSize(.small)
            }
            if settings.translationLanguage != nil {
                if model.isTranslating || model.translationRequest != nil {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.small)
                        Text("Translating on this Mac…").font(.caption).foregroundStyle(.secondary)
                    }
                } else {
                    let missing = model.project.captionsNeedingTranslation().count
                    if missing > 0 {
                        Button(missing == 1 ? "Translate 1 Caption" : "Translate \(missing) Captions") { model.translateCaptions() }
                            .controlSize(.small)
                            .help("Captions you changed need translating again")
                    } else {
                        Text("Shown smaller, under each caption. Translated on this Mac.").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}

/// Subtitle files, caption breaks and starting over.
private struct CaptionsMoreMenu: View {
    let model: EditorModel

    var body: some View {
        Menu {
            Button("Import Subtitle File (.srt)…") { model.importCaptionsFile() }
            Button("Export Subtitle File (.srt)…") { model.exportCaptionsFile() }
            Divider()
            Button("Undo My Splits and Joins") { model.resetCaptionBreaks() }
                .help("Let the captions flow again on their own")
            Button("Delete All Captions") { model.removeAllCaptions() }
        } label: {
            Image(systemName: "ellipsis.circle")
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Subtitle files, caption breaks, delete captions")
        .accessibilityLabel("More caption actions")
    }
}

/// Font, size, colours, key words and emoji, folded away until wanted.
private struct CaptionDesign: View {
    let model: EditorModel
    let settings: CaptionSettings
    @State private var isOpen = false
    @State private var dragging: Double?

    var body: some View {
        DisclosureGroup("Design, key words & emoji", isExpanded: $isOpen) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    FontMenu(model: model, selection: settings.fontFamily) { family in
                        model.editCaptionLook("Change Caption Font") { $0.fontFamily = family }
                    }
                    if settings.isCustomized {
                        Button("Reset") {
                            model.editCaptionLook("Reset Caption Design") { captions in
                                captions.fontFamily = nil
                                captions.sizeScale = 1
                                captions.textColor = nil
                                captions.accentColor = nil
                            }
                        }
                    }
                }
                .controlSize(.small)
                HStack {
                    Text("Size").frame(width: 34, alignment: .leading)
                    Slider(value: Binding(get: { dragging ?? settings.sizeScale }, set: { dragging = $0 }), in: CaptionSettings.sizeRange) { editing in
                        if !editing, let value = dragging {
                            dragging = nil
                            model.editCaptionLook("Change Caption Size") { $0.sizeScale = (value * 20).rounded() / 20 }
                        }
                    }
                    .controlSize(.small)
                    Text("\(Int(((dragging ?? settings.sizeScale) * 100).rounded()))%").monospacedDigit().frame(width: 40, alignment: .trailing)
                }
                ColorRow(title: "Letters", selection: settings.textColor, allowsNone: true) { color in
                    model.editCaptionLook("Change Caption Colour") { $0.textColor = color }
                }
                ColorRow(title: "Accent (spoken word, key words)", selection: settings.accentColor, allowsNone: true) { color in
                    model.editCaptionLook("Change Accent Colour") { $0.accentColor = color }
                }
                Text("“None” keeps the style's own colour.").font(.caption).foregroundStyle(.secondary)

                Divider()
                Toggle("Highlight key words", isOn: Binding(get: { settings.showsKeywords }, set: { on in
                    model.editCaptionLook(on ? "Show Key Words" : "Hide Key Words") { $0.showsKeywords = on }
                }))
                HStack {
                    Button("Pick Key Words", systemImage: model.canUseWordModel ? "apple.intelligence" : "highlighter") { model.pickKeywords() }
                        .help(model.canUseWordModel
                              ? "Apple Intelligence reads your captions and highlights the words that matter, on this Mac"
                              : "Highlight numbers, names and strong words automatically, about one in seven words")
                        .disabled(model.wordModelJob != nil)
                    Button("Clear") { model.clearKeywords() }
                }
                .controlSize(.small)
                Toggle("Show emoji", isOn: Binding(get: { settings.showsEmoji }, set: { on in
                    model.editCaptionLook(on ? "Show Emoji" : "Hide Emoji") { $0.showsEmoji = on }
                }))
                HStack {
                    Button("Suggest Emoji", systemImage: model.canUseWordModel ? "apple.intelligence" : "face.smiling") { model.suggestEmoji() }
                        .help(model.canUseWordModel
                              ? "Apple Intelligence picks emoji that match what is said (at most one per caption), on this Mac"
                              : "Add an emoji above captions with words like money, love, fire, idea… (at most one per caption)")
                        .disabled(model.wordModelJob != nil)
                    if model.wordModelJob != nil { ProgressView().controlSize(.small) }
                    Button("Clear") { model.clearEmoji() }
                }
                .controlSize(.small)
                Text("Pick single words yourself in the Script panel.").font(.caption).foregroundStyle(.secondary)
            }
            .padding(.top, 6)
        }
        .font(.subheadline)
    }
}
