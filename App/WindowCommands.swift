import SwiftUI

/// The app's windows (F27): a new one, Background Tasks and Help.
struct WindowCommands: Commands {
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(after: .appInfo) {
            Button("Check for Updates…") { UpdateChecker.shared.check() }
                .disabled(UpdateChecker.shared.isChecking)
        }
        CommandGroup(after: .newItem) {
            Button("New Window") { openWindow(id: EditorWindow.id, value: EditorWindow.Value()) }
                .keyboardShortcut("n", modifiers: [.command, .shift])
        }
        CommandGroup(before: .windowList) {
            Button("Background Tasks") { openWindow(id: BackgroundTasksView.windowID) }
                .keyboardShortcut("9")
            Divider()
        }
        CommandGroup(replacing: .help) {
            Button("Shorts Editor Help") { openWindow(id: HelpView.windowID) }
                .keyboardShortcut("?", modifiers: .command)
        }
    }
}
