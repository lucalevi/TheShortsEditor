import SwiftUI
@preconcurrency import Translation

/// The app's one window: the home window with every Short, or the editor with one of them.
struct ContentView: View {
    @Bindable var model: EditorModel
    @State private var keys = EditorKeys()

    var body: some View {
        Group {
            switch model.screen {
            case .home: HomeView(model: model)
            case .editor: EditorView(model: model)
            }
        }
        .overlay {
            if model.isFullScreenPreview, model.screen == .editor {
                FullScreenPreview(model: model)
            }
        }
        .onAppear {
            keys.install(for: model)
        }
        .background {
            // Edits are undone through the window's own undo manager (see EditorModel.window).
            WindowReader { window in
                // A hidden extra window (several files opened from Finder) mustn't take over.
                if window.isVisible || !(model.window?.isVisible ?? false) { model.window = window }
            }
        }
        .sheet(isPresented: Binding(get: { model.exportPhase != nil }, set: { if !$0 { model.endExport() } })) {
            ExportSheet(model: model)
        }
        .sheet(isPresented: Binding(get: { model.magic != nil }, set: { if !$0 { model.cancelMagic() } })) {
            MagicShortSheet(model: model)
                .interactiveDismissDisabled()
        }
        .sheet(isPresented: $model.choosesStoryboard) {
            StoryboardChooser(model: model)
        }
        .sheet(isPresented: $model.choosesTemplate) {
            TemplateChooser(model: model)
        }
        .sheet(isPresented: Binding(get: { model.coverDraft != nil }, set: { if !$0 { model.coverDraft = nil } })) {
            if let cover = model.coverDraft { CoverSheet(model: model, cover: cover) }
        }
        .sheet(item: $model.speechRequest) { request in
            SpeechSheet(model: model, request: request)
        }
        .alert(item: $model.alert) { alert in
            Alert(title: Text(alert.title), message: Text(alert.message))
        }
    }
}

/// The editor: media on the left, the vertical viewer in the middle, details on the right, and
/// the timeline across the bottom.
struct EditorView: View {
    @Bindable var model: EditorModel

    var body: some View {
        VSplitView {
            HSplitView {
                SidebarView(model: model)
                    .frame(minWidth: 220, idealWidth: 260, maxWidth: 340)
                ViewerView(model: model)
                    .frame(minWidth: 320, maxWidth: .infinity)
                InspectorView(model: model)
                    .frame(minWidth: 220, idealWidth: 260, maxWidth: 320)
            }
            .frame(minHeight: 380, maxHeight: .infinity)
            // A single storyline needs little height; the viewer gets the rest.
            TimelineView(model: model)
                .frame(minHeight: 230, idealHeight: 255, maxHeight: 330)
        }
        // Captions in a second language, translated on this Mac (it asks to download languages once).
        .translationTask(model.translationRequest) { session in
            await model.runTranslation(session)
        }
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button("All Shorts", systemImage: "chevron.backward") { model.showHome() }
                    .labelStyle(.titleAndIcon)
                    .help("Back to all your Shorts. This one is saved (⇧⌘0)")
            }
            ToolbarItem(placement: .navigation) {
                ShortNameField(model: model)
            }
            ToolbarSpacer(.flexible)
            ToolbarItemGroup {
                Button("Import", systemImage: "square.and.arrow.down") {
                    MediaImportPanel.run(model: model, addToTimeline: false)
                }
                .help("Import videos and pictures into Media (⌘I)")
                Button("Split", systemImage: "scissors") { model.splitAtPlayhead() }
                    .help("Cut the clip at the playhead (B)")
                    .disabled(model.project.timeline.clips.isEmpty)
                Button("Delete", systemImage: "trash") { model.deleteSelection() }
                    .help("Remove the selected clips, titles or music (⌫)")
                    .disabled(model.timelineSelection.isEmpty)
            }
            ToolbarItem {
                Button("B-roll", systemImage: "rectangle.on.rectangle") { OverlayImportPanel.run(model: model) }
                    .help("Show videos or pictures over your clips, starting at the playhead")
                    .disabled(model.project.timeline.clips.isEmpty)
            }
            ToolbarItem {
                Button("Transition", systemImage: "circle.lefthalf.filled") {
                    model.chooseTransition()
                }
                .help("Put a transition on the cut nearest the playhead (⌥T), then choose its kind")
                .disabled(model.project.timeline.clips.count < 2)
            }
            ToolbarItem {
                Button("Remove Pauses", systemImage: "waveform.path.badge.minus") { model.beginRemovingSilences() }
                    .help("Cut out the quiet parts between sentences")
                    .disabled(model.project.timeline.clips.isEmpty || model.silenceSession != nil)
            }
            ToolbarItem {
                Button("Title", systemImage: "textformat") { model.addTitle() }
                    .help("Add text over the video at the playhead, like a hook (⌘T)")
                    .disabled(model.project.timeline.clips.isEmpty)
            }
            ToolbarItem {
                Button("Stickers", systemImage: "face.smiling") { model.showsStickerPicker = true }
                    .help("Add a sticker (emoji, arrow, shape) or a ready-made text at the playhead")
                    .disabled(model.project.timeline.clips.isEmpty)
                    .popover(isPresented: $model.showsStickerPicker, arrowEdge: .bottom) {
                        StickerPicker(model: model)
                    }
            }
            ToolbarItem {
                Group {
                    if model.project.music != nil {
                        Button("Music", systemImage: "music.note") { model.selection = .music }
                            .help("Change the music's volume and settings")
                    } else {
                        Menu {
                            MusicChoices(model: model)
                        } label: {
                            Label("Music", systemImage: "music.note")
                        }
                        .menuIndicator(.hidden)
                        .help("Add music to play under your Short: the app's own, or a song from a file")
                    }
                }
                .disabled(model.project.timeline.clips.isEmpty)
            }
            ToolbarItem {
                Button("Captions", systemImage: "captions.bubble") { model.sidebar = .captions }
                    .help("Make captions from what is said, and change how they look")
            }
            ToolbarItem {
                Toggle("Overlay Areas", systemImage: "rectangle.dashed", isOn: $model.showsSafeZone)
                    .help("Show where YouTube's buttons and captions cover your video (⌘')")
            }
            ToolbarItem {
                Button("Export", systemImage: "square.and.arrow.up") { model.beginExport() }
                    .help("Save your Short as a video file, ready for YouTube (⌘E)")
                    .disabled(model.project.timeline.clips.isEmpty)
            }
        }
        .navigationTitle(model.shortName)
        // The name is shown (and renamed) by ShortNameField instead.
        .toolbar(removing: .title)
    }
}

/// The open Short's name in the toolbar. Click it to rename the Short; Return or clicking away
/// keeps the new name, Escape goes back to the old one.
private struct ShortNameField: View {
    @Bindable var model: EditorModel
    @State private var typed = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            TextField("Name", text: $typed)
                .textFieldStyle(.plain)
                .font(.headline)
                .focused($focused)
                .frame(width: 200)
                .onSubmit { commit() }
                .onExitCommand {
                    typed = model.shortName
                    focused = false
                }
                .onChange(of: focused) { if !focused { commit() } }
                .help("Click to rename this Short")
                .accessibilityLabel("Short name")
            Text(model.project.assets.isEmpty ? "Add videos to start" : "Saved as you work")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.leading, 6)
        .onAppear { typed = model.shortName }
        .onChange(of: model.shortName) { if !focused { typed = model.shortName } }
    }

    private func commit() {
        // Text fields hand their old value back as focus leaves; only take what was typed while focused.
        model.shortName = typed
        typed = model.shortName
    }
}

/// Hands over the AppKit window this view is in, when it gets one and each time it becomes active.
private struct WindowReader: NSViewRepresentable {
    let onWindow: (NSWindow) -> Void

    func makeNSView(context: Context) -> NSView { WindowReaderView(onWindow: onWindow) }
    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class WindowReaderView: NSView {
        let onWindow: (NSWindow) -> Void

        init(onWindow: @escaping (NSWindow) -> Void) {
            self.onWindow = onWindow
            super.init(frame: .zero)
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

        private var observer: NSObjectProtocol?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let observer { NotificationCenter.default.removeObserver(observer) }
            observer = nil
            guard let window else { return }
            onWindow(window)
            observer = NotificationCenter.default.addObserver(forName: NSWindow.didBecomeKeyNotification, object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    if let self, let window = self.window { self.onWindow(window) }
                }
            }
        }
    }
}
