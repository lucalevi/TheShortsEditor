import EditorCore
import RenderEngine
import SwiftUI

/// Where a title's words are typed: in the details on the right, or on the picture itself.
///
/// The viewer shows the words as they are typed. They are saved a moment after each pause, so
/// nothing is lost if the app quits while typing, and when editing ends; all of it is one undo
/// step ("Edit Title").
struct TitleTextField: View {
    let model: EditorModel
    let title: TextOverlay
    /// Takes the cursor when `model.wantsTitleTextFocus` asks (the details on the right).
    var answersFocusRequests = false
    /// Takes the cursor as soon as it is shown (on the picture).
    var startsFocused = false
    /// Editing ended (Return, or a click elsewhere).
    var onEnd: () -> Void = {}

    /// What is being typed. Only written while editing: as focus leaves, the field hands back the
    /// project's text, which must not replace what was typed.
    @State private var draft = ""
    /// Whether this round of typing has been saved once already (it then has its undo step).
    @State private var hasSaved = false
    @State private var pause: Task<Void, Never>?
    @FocusState private var isEditing: Bool

    /// How long typing has to stop before what was typed is saved.
    static let saveAfter: Duration = .milliseconds(800)

    var body: some View {
        TextField("Your title", text: Binding(get: { isEditing ? draft : title.text }, set: { if isEditing { draft = $0 } }), axis: .vertical)
            .focused($isEditing)
            .onSubmit { isEditing = false }
            .onExitCommand { isEditing = false }
            .onChange(of: draft) { _, typed in
                guard isEditing else { return }
                let text = typed.trimmingCharacters(in: .whitespacesAndNewlines)
                model.previewTitleText(text.isEmpty ? nil : text, for: title.id)
                pause?.cancel()
                pause = Task {
                    try? await Task.sleep(for: Self.saveAfter)
                    if !Task.isCancelled { save(final: false) }
                }
            }
            .onChange(of: isEditing) { _, editing in
                if editing {
                    draft = title.text
                    hasSaved = false
                } else {
                    pause?.cancel()
                    save(final: true)
                    onEnd()
                }
            }
            .onChange(of: model.wantsTitleTextFocus) { focusIfAsked() }
            .onAppear(perform: focusIfAsked)
            .task {
                guard startsFocused else { return }
                draft = title.text
                isEditing = true
            }
            .onDisappear {
                guard isEditing else { return }
                pause?.cancel()
                save(final: true)
            }
    }

    private func focusIfAsked() {
        guard answersFocusRequests, model.wantsTitleTextFocus else { return }
        model.wantsTitleTextFocus = false
        draft = title.text
        isEditing = true
    }

    private func save(final: Bool) {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        let saved = model.project.title(id: title.id)?.text
        guard !text.isEmpty, text != saved else {
            if final { model.previewTitleText(nil, for: title.id) }
            return
        }
        // The typed text stays shown until the rebuilt Short (which has it) arrives.
        model.editTitle(title.id, "Edit Title", registersUndo: !hasSaved) { $0.text = text }
        hasSaved = true
    }
}

/// Typing a title's words on the picture: a box just under the title (above it near the bottom),
/// so the title itself stays in sight and changes as it is typed.
struct ViewerTitleEditor: View {
    let model: EditorModel
    let title: TextOverlay
    /// The title's box in the viewer, in points.
    let box: CGRect
    /// The viewer's size, in points.
    let viewer: CGSize

    var body: some View {
        let width = min(max(box.width, 220), viewer.width - 16)
        let height: CGFloat = 64
        let below = box.maxY + 6 + height <= viewer.height
        TitleTextField(model: model, title: title, startsFocused: true) { model.titleEditedInViewer = nil }
            .textFieldStyle(.plain)
            .font(.title3.weight(.semibold))
            .multilineTextAlignment(.center)
            .lineLimit(1...3)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .frame(width: width)
            .background(.black.opacity(0.8), in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.yellow, lineWidth: 2))
            .foregroundStyle(.white)
            .help("Type the title's words. Return when done.")
            .offset(
                x: min(max(box.midX - width / 2, 8), viewer.width - width - 8),
                y: below ? box.maxY + 6 : max(box.minY - height - 6, 0))
    }
}
