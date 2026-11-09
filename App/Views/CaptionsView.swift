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
                CaptionSettingsForm(model: model)
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
                 : "Captions are written for you from what is said in your clips. It all happens on this Mac.")
        } actions: {
            VStack(spacing: 10) {
                LanguagePicker(model: model)
                Button("Make Captions") { model.makeCaptions() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(model.project.timeline.clips.isEmpty)
            }
        }
    }
}

private struct LanguagePicker: View {
    @Bindable var model: EditorModel

    var body: some View {
        Picker("Spoken language", selection: $model.captionLanguage) {
            ForEach(CaptionLanguage.allCases) { Text($0.displayName).tag($0) }
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
            case .downloading(let fraction):
                ProgressView(value: fraction)
                Text("Getting the speech model ready…")
                Text("This happens once per language.").font(.caption).foregroundStyle(.secondary)
            case .listening(let index, let count):
                ProgressView()
                Text(count == 1 ? "Listening to your clip…" : "Listening to clip \(index) of \(count)…")
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

            VStack(alignment: .leading, spacing: 6) {
                Text("Style").font(.subheadline.weight(.semibold))
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 6)], spacing: 6) {
                    ForEach(CaptionStyle.allCases) { style in
                        StyleChip(name: style.displayName, isSelected: settings.style == style, makeImage: { CaptionPreview.image(for: style) }) {
                            model.setCaptionStyle(style)
                        }
                    }
                }
            }

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
            }

            let missing = model.project.assetsNeedingTranscription(in: model.captionLanguage)
            HStack {
                LanguagePicker(model: model).labelsHidden().controlSize(.small)
                Spacer()
                if !missing.isEmpty {
                    Button("Update Captions") { model.makeCaptions() }
                        .controlSize(.small)
                        .help("Make captions for clips that don't have them in this language yet")
                }
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
                if let id { withAnimation { proxy.scrollTo(id, anchor: .center) } }
            }
            .safeAreaInset(edge: .bottom) {
                Text("Click a caption's words to fix them. Press Return when done.")
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

    /// What the user is typing. Outside editing the row always shows the project's words.
    @State private var draft = ""
    @FocusState private var isEditing: Bool

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Button(TimeFormat.string(page.range.start)) {
                model.pause()
                model.seek(to: page.firstFrame)
            }
            .buttonStyle(.plain)
            .font(.caption.monospacedDigit())
            .foregroundStyle(isCurrent ? Color.accentColor : .secondary)
            .help("Go to this caption")

            TextField("Caption", text: Binding(get: { isEditing ? draft : page.text }, set: { if isEditing { draft = $0 } }), axis: .vertical)
                .textFieldStyle(.plain)
                .focused($isEditing)
                // Return ends editing; the change is saved once, when editing ends.
                .onSubmit { isEditing = false }
                .onChange(of: isEditing) { _, editing in
                    if editing {
                        draft = page.text
                        model.pause()
                        model.seek(to: page.firstFrame)
                    } else {
                        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
                        if text != page.text { model.editCaption(page, text: text) }
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
