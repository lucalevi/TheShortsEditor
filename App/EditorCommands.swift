import EditorCore
import SwiftUI

/// Menu bar commands. Every keyboard shortcut lives here so it is also discoverable in a menu.
struct EditorCommands: Commands {
    let model: EditorModel

    var body: some Commands {
        CommandGroup(after: .newItem) {
            Button("Import Media…") { MediaImportPanel.run(model: model, addToTimeline: false) }
                .keyboardShortcut("i")
            Divider()
            Button("Export Short…") { model.beginExport() }
                .keyboardShortcut("e")
                .disabled(model.project.timeline.clips.isEmpty || model.exportPhase != nil)
        }

        CommandMenu("Clip") {
            Button("Split at Playhead") { model.splitAtPlayhead() }
                .keyboardShortcut("b", modifiers: [])
                .disabled(model.project.timeline.clips.isEmpty)
            Button(model.selectedTitleID != nil ? "Delete Title" : "Delete Clip") { model.deleteSelection() }
                .keyboardShortcut(.delete, modifiers: [])
                .disabled(model.selectedClipID == nil && model.selectedTitleID == nil)
            Divider()
            Button("Remove Pauses…") { model.beginRemovingSilences() }
                .disabled(model.project.timeline.clips.isEmpty || model.silenceSession != nil)
        }

        CommandMenu("Text") {
            Button("Add Title") { model.addTitle() }
                .keyboardShortcut("t")
                .disabled(model.project.timeline.clips.isEmpty)
            Divider()
            Button("Make Captions") { model.makeCaptions() }
                .disabled(model.project.timeline.clips.isEmpty || model.captionJob != nil)
            Toggle("Show Captions", isOn: Binding(
                get: { model.project.captions.isVisible },
                set: { model.setCaptionsVisible($0) }
            ))
            .disabled(!model.project.hasCaptions)
            Picker("Caption Style", selection: Binding(get: { model.project.captions.style }, set: { model.setCaptionStyle($0) })) {
                ForEach(CaptionStyle.allCases) { Text($0.displayName).tag($0) }
            }
            .disabled(!model.project.hasCaptions)
        }

        CommandMenu("Playback") {
            Button(model.isPlaying ? "Pause" : "Play") { model.togglePlayback() }
                .keyboardShortcut(.space, modifiers: [])
            Divider()
            Button("Play Backwards / Faster Backwards") { model.shuttle(forward: false) }
                .keyboardShortcut("j", modifiers: [])
            Button("Stop") { model.pause() }
                .keyboardShortcut("k", modifiers: [])
            Button("Play Forwards / Faster Forwards") { model.shuttle(forward: true) }
                .keyboardShortcut("l", modifiers: [])
            Divider()
            Button("Previous Frame") { model.step(frames: -1) }
                .keyboardShortcut(.leftArrow, modifiers: [])
            Button("Next Frame") { model.step(frames: 1) }
                .keyboardShortcut(.rightArrow, modifiers: [])
            Button("Go to Start") { model.seek(to: .zero) }
                .keyboardShortcut(.home, modifiers: [])
            Button("Go to End") { model.seek(to: model.duration) }
                .keyboardShortcut(.end, modifiers: [])
        }

        CommandGroup(before: .toolbar) {
            Toggle("Show YouTube Overlay Areas", isOn: Binding(get: { model.showsSafeZone }, set: { model.showsSafeZone = $0 }))
                .keyboardShortcut("'", modifiers: .command)
            Button("Zoom In Timeline") { model.zoom(by: 1.5) }
                .keyboardShortcut("+", modifiers: .command)
            Button("Zoom Out Timeline") { model.zoom(by: 1 / 1.5) }
                .keyboardShortcut("-", modifiers: .command)
            Divider()
        }
    }
}

/// The standard Open panel, filtered to video files.
enum MediaImportPanel {
    static func run(model: EditorModel, addToTimeline: Bool) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.movie]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.prompt = addToTimeline ? "Add to Timeline" : "Import"
        panel.message = "Choose the videos for your Short"
        guard panel.runModal() == .OK else { return }
        model.importFiles(panel.urls, addToTimeline: addToTimeline)
    }
}
