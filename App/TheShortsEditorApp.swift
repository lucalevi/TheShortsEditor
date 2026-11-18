import EditorCore
import SwiftUI

@main
struct TheShortsEditorApp: App {
    @NSApplicationDelegateAdaptor private var appDelegate: AppDelegate
    @State private var app = AppState()

    var body: some Scene {
        // A window per Short (F27), each with its own editor (`AppState`): File ▸ New Window, or
        // Open in New Window on a Short in All Shorts. A WindowGroup also because only a
        // WindowGroup gets created when the app is launched by opening videos from Finder.
        WindowGroup("Shorts Editor", id: EditorWindow.id, for: EditorWindow.Value.self) { $value in
            EditorWindow(app: app, value: value, delegate: appDelegate)
                // Send opened files to an open window instead of making a new one per file…
                .handlesExternalEvents(preferring: ["*"], allowing: ["*"])
        } defaultValue: {
            EditorWindow.Value()
        }
        // …while still creating one when opening files is what launched the app. The files
        // themselves are imported by the app delegate.
        .handlesExternalEvents(matching: ["*"])
        .defaultSize(width: 1400, height: 900)
        .commands {
            EditorCommands(app: app)
            TimelineViewCommands()
            WindowCommands()
            UndoCommands()
        }

        // Window ▸ Background Tasks (⌘9): the long jobs of the window in front, with Stop.
        Window("Background Tasks", id: BackgroundTasksView.windowID) {
            if let editor = app.current {
                BackgroundTasksView()
                    .environment(editor.tasks)
            }
        }
        .defaultSize(width: 420, height: 320)
        .restorationBehavior(.disabled)
        // Its menu item and ⌘9 are in EditorCommands, like every other shortcut.
        .commandsRemoved()

        // Help ▸ Shorts Editor Help (⌘?).
        Window("Shorts Editor Help", id: HelpView.windowID) {
            HelpView()
        }
        .defaultSize(width: 860, height: 600)
        .commandsRemoved()

        Settings {
            if let editor = app.current {
                SettingsView(model: editor)
                    // @AppStorage reads and writes the app's preferences (a test run's own under tests).
                    .defaultAppStorage(AppEnvironment.defaults)
            }
        }
    }
}

/// One window: All Shorts or the editor, with an editor model of its own.
struct EditorWindow: View {
    static let id = "editor"

    /// What a window is opened with: its own id, and a Short to open in it.
    struct Value: Codable, Hashable {
        var id = UUID()
        var shortID: UUID?
    }

    let app: AppState
    let value: Value
    let delegate: AppDelegate
    /// The window's editor and the id it is kept under, made once when the window first shows (the
    /// window's content is built many times; its value isn't guaranteed to stay the same).
    @State private var editor: (id: UUID, model: EditorModel)?

    var body: some View {
        Group {
            if let editor {
                window(editor.model)
                    .onDisappear { app.close(editor.id) }
            } else {
                Color.clear
                    .onAppear {
                        let id = app.editor(showingWindow: value.id) == nil ? value.id : UUID()
                        let model = app.editor(for: id)
                        editor = (id, model)
                        app.didFocus(model)
                        delegate.connect(app, window: model)
                        if let short = value.shortID, model.openShortID == nil { model.openShort(short) }
                    }
            }
        }
        .frame(minWidth: 1000, minHeight: 680)
    }

    private func window(_ model: EditorModel) -> some View {
        ContentView(model: model)
            .defaultAppStorage(AppEnvironment.defaults)
            .focusedSceneValue(\.editor, model)
            .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { note in
                if let window = note.object as? NSWindow, window === model.window { app.didFocus(model) }
            }
            .navigationTitle(model.screen == .editor ? model.openShortName : "Shorts Editor")
    }
}

extension FocusedValues {
    /// The editor of the window in front (menus act on it).
    @Entry var editor: EditorModel?
}

/// Reopens the last Short at launch, saves every window on quit, and receives files opened with
/// the app from Finder or the Dock: projects are opened, videos go onto the timeline, a song
/// becomes the music. (SwiftUI's onOpenURL drops files when several are opened at once; this gets
/// them all together.)
final class AppDelegate: NSObject, NSApplicationDelegate {
    private weak var app: AppState?
    /// Files that arrive before the window exists, when opening them is what launched the app.
    private var pending: [URL] = []

    /// A window showed. The first one restores where the user was and takes files that launched the app.
    func connect(_ app: AppState, window model: EditorModel) {
        guard self.app == nil else { return }
        self.app = app
        // Opening a project from Finder is what launched the app: open that one instead.
        if !pending.contains(where: { $0.pathExtension.lowercased() == ProjectFile.fileExtension }) {
            model.restoreLastSession(reopening: pending.isEmpty)
        }
        if !pending.isEmpty {
            model.importFiles(pending, addToTimeline: true)
            pending = []
        }
        UITestMedia.prepare(model)
    }

    func applicationWillFinishLaunching(_ notification: Notification) {
        // A video editor looks like one: dark greys around the picture, whatever the Mac's setting.
        NSApp.appearance = NSAppearance(named: .darkAqua)
        // Windows, not tabs: no "Show Tab Bar" or "Show All Tabs" in the menus.
        NSWindow.allowsAutomaticWindowTabbing = false
        HangReports.shared.start()
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        if let editor = app?.current {
            editor.importFiles(urls, addToTimeline: true)
        } else {
            pending += urls
        }
    }

    /// Before any window closes for the quit (SwiftUI closes them, which would otherwise take each
    /// back to All Shorts and forget where the user was).
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        app?.prepareToQuit()
        return .terminateNow
    }

    func applicationWillTerminate(_ notification: Notification) {
        if app?.isQuitting == false { app?.prepareToQuit() }
        // Saves are written in the background: wait for them before the app goes.
        ProjectStore.finishSaving()
    }

    /// Closing the last window means being done; this also avoids a running app with no window
    /// and no obvious way back.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
