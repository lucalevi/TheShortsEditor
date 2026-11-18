import AppKit
import EditorCore
import Observation
import RenderEngine

/// What the app's windows share (F27: several Shorts in several windows): the library of Shorts,
/// what was measured about media files, and one editor per window, each with its own Short, undo,
/// player and background jobs. A Short is open in one window at most.
@Observable
final class AppState {
    let analysis = MediaAnalysis()
    let library: LibraryModel
    /// Timeline items copied with Cut or Copy, for pasting in any window.
    let clipboard = TimelineClipboardStore()
    /// The editor of each window, by the window's id. Not observed: windows make theirs while they
    /// are drawn.
    @ObservationIgnored private(set) var editors: [UUID: EditorModel] = [:]
    /// The editor of the window last in front: menus act on it, files opened from Finder go to it.
    private(set) var current: EditorModel?

    init() {
        library = LibraryModel(analysis: analysis)
        library.onProblem = { [weak self] title, error in self?.current?.alert = AlertMessage(title, error: error) }
        library.undoManager = { NSApp.keyWindow?.undoManager ?? NSApp.mainWindow?.undoManager }
        library.openShortIDs = { [weak self] in Set(self?.editors.values.compactMap(\.openShortID) ?? []) }
    }

    /// The editor of the window with `id`, made when the window first shows.
    func editor(for id: UUID) -> EditorModel {
        if let editor = editors[id] { return editor }
        let editor = EditorModel(app: self)
        editors[id] = editor
        return editor
    }

    /// The editor already made for the window `id`, if any (a restored window can come back with
    /// the value of one that is still open).
    func editor(showingWindow id: UUID) -> EditorModel? { editors[id] }

    /// The window in front is showing `editor`.
    func didFocus(_ editor: EditorModel) {
        if current !== editor { current = editor }
    }

    /// Set when the app is quitting: windows then close only to be saved, so the app reopens as it
    /// was (closing a window yourself goes back to All Shorts and is forgotten).
    @ObservationIgnored var isQuitting = false

    /// A window closed: its Short is saved and its editor let go.
    func close(_ id: UUID) {
        guard let editor = editors.removeValue(forKey: id) else { return }
        if isQuitting {
            editor.saveNow()
        } else {
            editor.closeWindow()
        }
        if current === editor { current = editors.values.first }
    }

    /// The app is about to quit: every window's Short is saved, the one in front last, so it is
    /// the one the app reopens.
    func prepareToQuit() {
        isQuitting = true
        for editor in allEditors where editor !== current { editor.saveNow() }
        current?.saveNow()
    }

    /// The editor that has the Short `id` open, if any.
    func editor(showing id: UUID) -> EditorModel? {
        editors.values.first { $0.openShortID == id }
    }

    var allEditors: [EditorModel] { Array(editors.values) }

    /// What menus act on before the first window shows (never seen).
    @ObservationIgnored private(set) lazy var standIn = EditorModel(app: self)
}
