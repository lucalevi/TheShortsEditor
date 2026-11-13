import AppKit
import Observation
import SwiftUI

/// Edit ▸ Undo and Redo with the name of what they undo ("Undo Split Clip").
///
/// SwiftUI's own Undo item reads the scene's environment undo manager, which is not the one edits
/// go to (see `EditorModel.window`), so it always said plain "Undo". These items read the key
/// window's undo manager instead and are refreshed whenever any undo manager changes.
@MainActor @Observable
final class UndoMenu {
    static let shared = UndoMenu()

    private(set) var undoTitle = "Undo"
    private(set) var redoTitle = "Redo"
    private(set) var canUndo = false
    private(set) var canRedo = false

    @ObservationIgnored private var observers: [NSObjectProtocol] = []

    private init() {
        let names: [Notification.Name] = [
            .NSUndoManagerDidCloseUndoGroup, .NSUndoManagerDidUndoChange, .NSUndoManagerDidRedoChange,
            .NSUndoManagerCheckpoint, NSWindow.didBecomeKeyNotification,
        ]
        observers = names.map { name in
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { UndoMenu.shared.refresh() }
            }
        }
    }

    private var undoManager: UndoManager? {
        (NSApp.keyWindow ?? NSApp.mainWindow)?.undoManager
    }

    func refresh() {
        let manager = undoManager
        let undo = manager?.canUndo == true ? manager!.undoMenuItemTitle : "Undo"
        let redo = manager?.canRedo == true ? manager!.redoMenuItemTitle : "Redo"
        // Only assign changes, so menus aren't rebuilt on every keystroke's checkpoint.
        if undo != undoTitle { undoTitle = undo }
        if redo != redoTitle { redoTitle = redo }
        if (manager?.canUndo ?? false) != canUndo { canUndo.toggle() }
        if (manager?.canRedo ?? false) != canRedo { canRedo.toggle() }
    }

    /// Sent along the responder chain, so a text field being edited undoes its typing first.
    func undo() { NSApp.sendAction(Selector(("undo:")), to: nil, from: nil) }
    func redo() { NSApp.sendAction(Selector(("redo:")), to: nil, from: nil) }
}

/// Replaces SwiftUI's Undo/Redo items.
struct UndoCommands: Commands {
    let menu = UndoMenu.shared

    var body: some Commands {
        CommandGroup(replacing: .undoRedo) {
            Button(menu.undoTitle) { menu.undo() }
                .keyboardShortcut("z")
                .disabled(!menu.canUndo)
            Button(menu.redoTitle) { menu.redo() }
                .keyboardShortcut("z", modifiers: [.command, .shift])
                .disabled(!menu.canRedo)
        }
    }
}
