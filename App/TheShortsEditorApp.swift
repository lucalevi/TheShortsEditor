import SwiftUI

@main
struct TheShortsEditorApp: App {
    @NSApplicationDelegateAdaptor private var appDelegate: AppDelegate
    @State private var model = EditorModel()

    var body: some Scene {
        // One project at a time for now, so a single window rather than a document per window.
        Window("Shorts Editor", id: "editor") {
            ContentView(model: model)
                .frame(minWidth: 1000, minHeight: 680)
                .onAppear { appDelegate.connect(model) }
        }
        .defaultSize(width: 1400, height: 900)
        .commands { EditorCommands(model: model) }
    }
}

/// Receives videos opened with the app from Finder or the Dock and puts them on the timeline.
final class AppDelegate: NSObject, NSApplicationDelegate {
    private weak var model: EditorModel?
    /// Files that arrive before the model exists (when the app is launched by opening them).
    private var pending: [URL] = []

    func connect(_ model: EditorModel) {
        guard self.model !== model else { return }
        self.model = model
        if !pending.isEmpty {
            model.importFiles(pending, addToTimeline: true)
            pending = []
        }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        if let model {
            model.importFiles(urls, addToTimeline: true)
        } else {
            pending += urls
        }
    }
}
