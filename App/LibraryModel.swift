import AppKit
import EditorCore
import ImageIO
import Observation
import RenderEngine

/// The home window's list of Shorts: reading the library, posters, and renaming, copying and
/// deleting Shorts that aren't open. Opening and saving the open Short is `EditorModel`'s.
@Observable
final class LibraryModel {
    /// Every Short in the library, newest change first.
    private(set) var shorts: [ShortEntry] = []
    /// Posters of the Shorts, made from their first second.
    private(set) var posters: [UUID: CGImage] = [:]
    /// Says something went wrong (a title and a message), as an alert.
    @ObservationIgnored var onProblem: ((String, String) -> Void)?
    /// The undo manager of the window, looked up at each change (see `EditorModel.undoManager`).
    @ObservationIgnored var undoManager: () -> UndoManager? = { nil }
    @ObservationIgnored private var posterTask: Task<Void, Never>?
    /// What has been measured about media files, shared with the editor.
    @ObservationIgnored private let analysis: MediaAnalysis

    init(analysis: MediaAnalysis) {
        self.analysis = analysis
    }

    var names: [String] { shorts.map(\.name) }

    /// The poster of a Short is made again next time (it was changed).
    func forgetPoster(of id: UUID) {
        posters[id] = nil
    }

    /// Reads the library again, and makes posters for Shorts that changed since theirs.
    func refresh() {
        posterTask?.cancel()
        posterTask = Task {
            // Read off the main thread, after any save still being written.
            let entries = await ProjectStore.loadLibrary()
            guard !Task.isCancelled else { return }
            shorts = entries
            for entry in entries {
                guard !Task.isCancelled else { return }
                if posters[entry.id] == nil, let url = ProjectStore.freshPoster(for: entry),
                    let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                    let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
                {
                    posters[entry.id] = image
                    continue
                }
                // The Short's media is open only while its poster is made.
                let media = MediaAccess()
                defer { media.close() }
                guard ProjectStore.freshPoster(for: entry) == nil, entry.clipCount > 0,
                    let project = try? ProjectStore.read(ProjectStore.fileURL(for: entry.id), media: media),
                    let image = try? await ProjectPoster.image(of: project, analysis: analysis)
                else { continue }
                guard !Task.isCancelled else { return }
                ProjectStore.writePoster(image, for: entry.id)
                posters[entry.id] = image
            }
        }
    }

    /// Renames a Short that isn't open.
    func rename(_ id: UUID, to name: String) {
        do {
            try ProjectStore.rename(id, to: name)
        } catch {
            Log.file.failure("renameShort", error)
            onProblem?("The Short couldn't be renamed", error.localizedDescription)
        }
        refresh()
    }

    func duplicate(_ id: UUID) {
        guard let entry = shorts.first(where: { $0.id == id }) else { return }
        do {
            _ = try ProjectStore.duplicate(id, as: ShortsLibrary.copyName(of: entry.name, existing: names))
        } catch {
            Log.file.failure("duplicateShort", error)
            onProblem?("The Short couldn't be copied", error.localizedDescription)
        }
        refresh()
    }

    /// Asks first, then moves the Shorts to the Trash, as one undoable step.
    func delete(_ ids: Set<UUID>) {
        let names = shorts.filter { ids.contains($0.id) }.map(\.name)
        guard !names.isEmpty else { return }
        let alert = NSAlert()
        alert.messageText = names.count == 1 ? "Delete “\(names[0])”?" : "Delete \(names.count) Shorts?"
        alert.informativeText = "Your videos, pictures and sounds stay where they are. Only the edit is deleted."
        alert.addButton(withTitle: "Delete").hasDestructiveAction = true
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let deleted = ids.compactMap { ProjectStore.delete($0) }
        refresh()
        guard !deleted.isEmpty else { return }
        let actionName = deleted.count == 1 ? "Delete Short" : "Delete \(deleted.count) Shorts"
        // Registered on the next turn of the main run loop: straight after the alert's modal run
        // loop, the undo manager's automatic grouping didn't close the step, so Undo stayed disabled.
        Task { @MainActor in
            undoManager()?.registerUndo(withTarget: self) { library in
                MainActor.assumeIsolated { library.restore(deleted, actionName: actionName) }
            }
            undoManager()?.setActionName(actionName)
        }
    }

    /// Undo of deleting Shorts: they come back, and Redo deletes them again.
    private func restore(_ deleted: [ProjectStore.DeletedShort], actionName: String) {
        for short in deleted {
            Log.file.attempt("Putting a deleted Short back") { try ProjectStore.restore(short) }
        }
        refresh()
        undoManager()?.registerUndo(withTarget: self) { library in
            MainActor.assumeIsolated {
                let again = deleted.compactMap { ProjectStore.delete($0.id) }
                library.refresh()
                library.undoManager()?.registerUndo(withTarget: library) { library in
                    MainActor.assumeIsolated { library.restore(again, actionName: actionName) }
                }
                library.undoManager()?.setActionName(actionName)
            }
        }
        undoManager()?.setActionName(actionName)
    }
}
