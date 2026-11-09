import EditorCore
import SwiftUI

/// Menu bar commands. Every keyboard shortcut lives here so it is also discoverable in a menu.
struct EditorCommands: Commands {
    let model: EditorModel

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Short") { model.newShort() }
                .keyboardShortcut("n")
            Button("Open…") { model.openProjectPanel() }
                .keyboardShortcut("o")
            Menu("Open Recent") {
                ForEach(model.recentProjects, id: \.self) { url in
                    Button(url.deletingPathExtension().lastPathComponent) { model.openProject(url) }
                }
                if !model.recentProjects.isEmpty {
                    Divider()
                    Button("Clear Menu") { model.clearRecentProjects() }
                }
            }
            .disabled(model.recentProjects.isEmpty)
        }

        CommandGroup(replacing: .saveItem) {
            Button("Save") { model.save() }
                .keyboardShortcut("s")
            Button("Save As…") { model.saveAs() }
                .keyboardShortcut("s", modifiers: [.command, .shift])
            Divider()
            Button("Import Media…") { MediaImportPanel.run(model: model, addToTimeline: false) }
                .keyboardShortcut("i")
            Button("Find Missing Files…") { model.findMissingFiles() }
                .disabled(model.missingAssets.isEmpty)
            Divider()
            Button("Export Short…") { model.beginExport() }
                .keyboardShortcut("e")
                .disabled(model.project.timeline.clips.isEmpty || model.exportPhase != nil)
        }

        CommandGroup(after: .pasteboard) {
            // ⌘A (Edit ▸ Select All) selects everything on the timeline when no text is being
            // edited; EditorKeys handles that, since the standard item only reaches text fields.
            Button("Deselect All") { model.selection = nil }
                .keyboardShortcut("a", modifiers: [.command, .shift])
                .disabled(model.timelineSelection.isEmpty)
        }

        CommandMenu("Clip") {
            Button("Split at Playhead") { model.splitAtPlayhead() }
                .keyboardShortcut("b", modifiers: [])
                .disabled(model.project.timeline.clips.isEmpty)
            Button(model.timelineSelection.count > 1 ? "Delete \(model.timelineSelection.count) Items"
                   : model.selection == .music ? "Remove Music" : model.selectedTitleID != nil ? "Delete Title" : "Delete Clip") { model.deleteSelection() }
                .keyboardShortcut(.delete, modifiers: [])
                .disabled(model.timelineSelection.isEmpty)
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

        CommandMenu("Sound") {
            Button("Add Music…") { MusicImportPanel.run(model: model) }
                .disabled(model.project.timeline.clips.isEmpty)
            Button("Remove Music") { model.removeMusic() }
                .disabled(model.project.music == nil)
            Toggle("Lower Music While People Talk", isOn: Binding(
                get: { model.project.music?.lowersUnderSpeech ?? false },
                set: { on in model.editMusic(on ? "Lower Music Under Speech" : "Keep Music Level") { $0.lowersUnderSpeech = on } }
            ))
            .disabled(model.project.music == nil)
            Divider()
            if let clip = model.selectedClip {
                Toggle("Mute Clip", isOn: Binding(get: { clip.isMuted }, set: { model.setClipMuted(clip.id, $0) }))
            } else {
                Button("Mute Clip") {}.disabled(true)
            }
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

/// The standard Open panel, filtered to video and sound files.
enum MediaImportPanel {
    static func run(model: EditorModel, addToTimeline: Bool) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.movie, .audio]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.prompt = addToTimeline ? "Add to Timeline" : "Import"
        panel.message = "Choose the videos (or music) for your Short"
        guard panel.runModal() == .OK else { return }
        model.importFiles(panel.urls, addToTimeline: addToTimeline)
    }
}

/// The Open panel for choosing a song. It becomes the music straight away.
enum MusicImportPanel {
    static func run(model: EditorModel) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.audio]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.prompt = "Use as Music"
        panel.message = "Choose a song to play under your Short"
        guard panel.runModal() == .OK else { return }
        model.importFiles(panel.urls, addToTimeline: true)
    }
}
