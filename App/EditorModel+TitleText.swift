import EditorCore
import RenderEngine

// A title's words: editing them, and showing them in the viewer while they are typed.
extension EditorModel {
    /// Adds a title at the playhead (in `style`, else the Short's), selects it and puts the
    /// cursor in its words on the picture.
    func addTitle(style: TitleStyle? = nil) {
        guard !project.timeline.clips.isEmpty else { return }
        playback.player.pause()
        var id: TextOverlay.ID?
        let time = currentTime
        apply("Add Title") { project in
            let added = project.addTitle(at: time, text: "Your title")
            if let style { project.updateTitle(added) { $0.applyStyle(style) } }
            id = added
        }
        guard let id else { return }
        selectTitle(id)
        titleEditedInViewer = id
    }

    func editTitle(_ id: TextOverlay.ID, _ actionName: String, registersUndo: Bool = true, _ change: @escaping (inout TextOverlay) -> Void) {
        apply(actionName, registersUndo: registersUndo) { $0.updateTitle(id, change) }
    }

    /// Shows a title's text in the viewer while it is typed, before it is saved (nil: its own).
    func previewTitleText(_ text: String?, for id: TextOverlay.ID) {
        livePreview.setTitleText(text, for: id)
        typedTitle = text.map { (id, $0) }
        redrawCurrentFrame()
    }

    /// The title with the text being typed in it, if any (for the viewer's box around it).
    func withTypedText(_ title: TextOverlay) -> TextOverlay {
        guard let typedTitle, typedTitle.id == title.id else { return title }
        var typed = title
        typed.text = typedTitle.text
        return typed
    }

    /// Types the selected title's words on the picture (double-click it, or Return).
    func editTitleTextInViewer() {
        guard let title = selectedTitle, !title.isSticker else { return }
        selectTitle(title.id)
        titleEditedInViewer = title.id
    }
}
