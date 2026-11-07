import SwiftUI

@main
struct TheShortsEditorApp: App {
    @State private var model = EditorModel()

    var body: some Scene {
        // One project at a time for now, so a single window rather than a document per window.
        Window("Shorts Editor", id: "editor") {
            ContentView(model: model)
                .frame(minWidth: 1000, minHeight: 680)
        }
        .defaultSize(width: 1400, height: 900)
        .commands { EditorCommands(model: model) }
    }
}
