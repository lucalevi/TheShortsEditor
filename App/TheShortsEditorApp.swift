import EditorCore
import SwiftUI

@main
struct TheShortsEditorApp: App {
    @NSApplicationDelegateAdaptor private var appDelegate: AppDelegate
    @State private var model = EditorModel()

    var body: some Scene {
        // One project at a time for now. A WindowGroup rather than a single Window because only a
        // WindowGroup gets created when the app is launched by opening videos from Finder; "New
        // Window" is removed so there is never more than one.
        WindowGroup("Shorts Editor", id: "editor") {
            ContentView(model: model)
                .frame(minWidth: 1000, minHeight: 680)
                .onAppear { appDelegate.connect(model) }
                // Send opened files to this window instead of making a new one per file…
                .handlesExternalEvents(preferring: ["*"], allowing: ["*"])
        }
        // …while still creating it when opening files is what launched the app. The files
        // themselves are imported by the app delegate.
        .handlesExternalEvents(matching: ["*"])
        .defaultSize(width: 1400, height: 900)
        .commands {
            EditorCommands(model: model)
            UndoCommands()
        }

        Settings {
            SettingsView(model: model)
        }
    }
}

/// Reopens the last Short at launch, saves on quit, and receives files opened with the app from
/// Finder or the Dock: projects are opened, videos go onto the timeline, a song becomes the music.
/// (SwiftUI's onOpenURL drops files when several are opened at once; this gets them all together.)
final class AppDelegate: NSObject, NSApplicationDelegate {
    private weak var model: EditorModel?
    /// Files that arrive before the window exists, when opening them is what launched the app.
    private var pending: [URL] = []

    func connect(_ model: EditorModel) {
        guard self.model !== model else { return }
        self.model = model
        // Opening a project from Finder is what launched the app: open that one instead.
        if !pending.contains(where: { $0.pathExtension.lowercased() == ProjectFile.fileExtension }) {
            model.restoreLastSession()
        }
        if !pending.isEmpty {
            model.importFiles(pending, addToTimeline: true)
            pending = []
        }
    }

    func applicationWillFinishLaunching(_ notification: Notification) {
        // A video editor looks like one: dark greys around the picture, whatever the Mac's setting.
        NSApp.appearance = NSAppearance(named: .darkAqua)
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        if let model {
            model.importFiles(urls, addToTimeline: true)
        } else {
            pending += urls
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        model?.saveNow()
    }

    /// There is only one window, so closing it means being done; this also avoids a running app
    /// with no window and no obvious way back.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
