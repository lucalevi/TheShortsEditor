import AppKit

extension EditorModel {
    /// Opening several files from Finder makes SwiftUI create extra windows that stay hidden and
    /// report themselves too, so a hidden window is passed over for a visible one.
    var undoManager: UndoManager? {
        if let ownUndoManager { return Self.limited(ownUndoManager) }
        let candidates = [window, NSApp.mainWindow].compactMap(\.self)
        return Self.limited((candidates.first(where: \.isVisible) ?? candidates.first)?.undoManager)
    }

    /// How many edits can be undone (F13). Each keeps the whole Short as it was; unchanged parts
    /// are shared, but big edits (Magic Short, captions) are not, and nothing was ever let go.
    static let undoLevels = 200

    private static func limited(_ manager: UndoManager?) -> UndoManager? {
        if let manager, manager.levelsOfUndo != undoLevels { manager.levelsOfUndo = undoLevels }
        return manager
    }
}
