import SwiftUI

/// The editor window: media on the left, the vertical viewer in the middle, details on the right,
/// and the timeline across the bottom.
struct ContentView: View {
    @Bindable var model: EditorModel
    @State private var keys = EditorKeys()

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
        .toolbar {
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
                Button("Music", systemImage: "music.note") {
                    if model.project.music != nil { model.selection = .music } else { MusicImportPanel.run(model: model) }
                }
                .help(model.project.music != nil ? "Change the music's volume and settings" : "Add a song to play under your Short")
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
        .navigationTitle(model.documentName)
        .navigationSubtitle(model.documentURL == nil && !model.project.assets.isEmpty ? "Kept on this Mac · ⌘S to name it" : "")
        .onAppear {
            keys.install(for: model)
        }
        .background {
            // Edits are undone through the window's own undo manager (see EditorModel.window).
            WindowReader { window in model.window = window }
        }
        .sheet(isPresented: Binding(get: { model.exportPhase != nil }, set: { if !$0 { model.endExport() } })) {
            ExportSheet(model: model)
        }
        .alert(item: $model.alert) { alert in
            Alert(title: Text(alert.title), message: Text(alert.message))
        }
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
