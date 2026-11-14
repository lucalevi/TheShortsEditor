import AVFoundation
import EditorCore
import ImageIO
import RenderEngine
import SwiftUI
import Transcription

/// The home window with every Short, opening and saving them, and finding missing media.
extension EditorModel {
    // MARK: The home window and saving

    /// The open Short's name, shown in the title bar. Renaming it there renames the Short.
    var shortName: String {
        get { openShortName }
        set { renameOpenShort(to: newValue) }
    }

    /// A Short with media in it, or a storyboard waiting to be filmed, is kept in the library.
    var isWorthKeeping: Bool { !project.assets.isEmpty || project.storyboard != nil }

    /// The name shown in the window's title.
    var documentName: String { screen == .home ? "Shorts" : openShortName }

    /// Writes the open Short to the library now, if anything changed. A Short with nothing in it
    /// isn't kept.
    func saveNow() {
        autosaveTask?.cancel()
        autosaveTask = nil
        guard hasUnsavedChanges, let id = openShortID else { return }
        if !isWorthKeeping {
            try? FileManager.default.removeItem(at: ProjectStore.fileURL(for: id))
            hasUnsavedChanges = false
            return
        }
        do {
            try ProjectStore.write(project, to: ProjectStore.fileURL(for: id), name: openShortName, created: openShortCreated)
            hasUnsavedChanges = false
            didReportSaveError = false
        } catch {
            Log.file.failure("Saving the open Short", error)
            // Say it once; keep trying with the next change.
            if !didReportSaveError {
                didReportSaveError = true
                alert = AlertMessage(title: "Your Short couldn't be saved", message: error.localizedDescription)
            }
        }
    }

    func scheduleAutosave() {
        hasUnsavedChanges = true
        autosaveTask?.cancel()
        autosaveTask = Task {
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            saveNow()
        }
    }

    /// File ▸ Save: everything is saved as you work; this just does it now.
    func save() {
        hasUnsavedChanges = true
        saveNow()
    }

    /// File ▸ Save a Copy…: writes the Short to a file anywhere, e.g. as a backup or for another
    /// Mac. The Short in the app stays as it is.
    func saveCopy() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.shortsProject]
        panel.nameFieldStringValue = "\(openShortName).\(ProjectFile.fileExtension)"
        panel.canCreateDirectories = true
        panel.message = "Save a copy of this Short as a file. Open it on another Mac with File ▸ Open…"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try ProjectStore.write(project, to: url, name: openShortName, created: openShortCreated)
        } catch {
            Log.file.failure("Saving a copy of the Short", error)
            alert = AlertMessage(title: "The copy couldn't be saved", message: error.localizedDescription)
        }
    }

    /// At launch: brings older projects into the library, then shows the home window.
    func restoreLastSession() {
        ProjectStore.moveOldProjectsIntoLibrary()
        // Before any Short is open, so nothing an undo might need is removed.
        ProjectStore.removeUnusedCopies()
        showHome()
    }

    /// Back to the home window (the "All Shorts" button): the open Short is saved first.
    func showHome() {
        player.pause()
        saveNow()
        if let id = openShortID, !isWorthKeeping {
            // A Short left empty isn't kept.
            try? FileManager.default.removeItem(at: ProjectStore.fileURL(for: id))
        }
        openShortID = nil
        load(Project(), name: "", created: .now)
        screen = .home
        refreshShorts()
    }

    /// File ▸ New Short, or the New Short tile: an empty Short, open in the editor.
    func newShort() {
        if screen == .editor { showHome() }
        openShortID = UUID()
        load(Project(), name: ShortsLibrary.newName(existing: shorts.map(\.name)), created: .now)
        screen = .editor
    }

    /// Opens a Short from the home window.
    func openShort(_ id: UUID) {
        let file: ProjectFile
        do {
            file = try ProjectStore.readFile(ProjectStore.fileURL(for: id))
        } catch {
            Log.file.failure("openShort", error)
            alert = AlertMessage(title: "This Short can't be opened", message: error.localizedDescription)
            return
        }
        if screen == .editor { showHome() }
        openShortID = id
        load(file.project, name: file.name ?? ShortsLibrary.defaultName, created: file.created ?? .now)
        screen = .editor
    }

    /// File ▸ Open…: a Short saved as a file is added to the library and opened.
    func openProjectPanel() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.shortsProject]
        panel.allowsMultipleSelection = false
        panel.message = "Choose a Short saved as a file. It will be added to your Shorts."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        openProject(url)
    }

    /// A project file opened from Finder, dropped, or chosen: it becomes a Short in the library.
    func openProject(_ url: URL) {
        if screen == .editor { showHome() }
        do {
            let id = try ProjectStore.importProject(at: url, existingNames: shorts.map(\.name))
            refreshShorts()
            openShort(id)
        } catch {
            Log.file.failure("openProject", error)
            alert = AlertMessage(title: "“\(url.deletingPathExtension().lastPathComponent)” can't be opened", message: error.localizedDescription)
        }
    }

    func renameShort(_ id: UUID, to typed: String) {
        guard let name = ShortsLibrary.cleanedName(typed) else { return }
        if id == openShortID {
            renameOpenShort(to: name)
            return
        }
        do {
            try ProjectStore.rename(id, to: name)
        } catch {
            Log.file.failure("renameShort", error)
            alert = AlertMessage(title: "The Short couldn't be renamed", message: error.localizedDescription)
        }
        refreshShorts()
    }

    private func renameOpenShort(to typed: String) {
        guard let name = ShortsLibrary.cleanedName(typed), name != openShortName else { return }
        openShortName = name
        if isWorthKeeping {
            hasUnsavedChanges = true
            saveNow()
        }
    }

    func duplicateShort(_ id: UUID) {
        guard let entry = shorts.first(where: { $0.id == id }) else { return }
        do {
            _ = try ProjectStore.duplicate(id, as: ShortsLibrary.copyName(of: entry.name, existing: shorts.map(\.name)))
        } catch {
            Log.file.failure("duplicateShort", error)
            alert = AlertMessage(title: "The Short couldn't be copied", message: error.localizedDescription)
        }
        refreshShorts()
    }

    /// Asks first, then moves the Shorts to the Trash.
    func deleteShorts(_ ids: Set<UUID>) {
        let names = shorts.filter { ids.contains($0.id) }.map(\.name)
        guard !names.isEmpty else { return }
        let alert = NSAlert()
        alert.messageText = names.count == 1 ? "Delete “\(names[0])”?" : "Delete \(names.count) Shorts?"
        alert.informativeText = "Your videos, pictures and sounds stay where they are. Only the edit is deleted."
        alert.addButton(withTitle: "Delete").hasDestructiveAction = true
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        for id in ids { ProjectStore.delete(id) }
        refreshShorts()
    }

    /// Reads the library again, and makes posters for Shorts that changed since theirs.
    func refreshShorts() {
        shorts = ProjectStore.libraryEntries()
        posterTask?.cancel()
        let entries = shorts
        posterTask = Task {
            for entry in entries {
                guard !Task.isCancelled else { return }
                if posters[entry.id] == nil, let url = ProjectStore.freshPoster(for: entry),
                    let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                    let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
                {
                    posters[entry.id] = image
                    continue
                }
                guard ProjectStore.freshPoster(for: entry) == nil, entry.clipCount > 0,
                    let project = try? ProjectStore.read(ProjectStore.fileURL(for: entry.id)),
                    let image = try? await ProjectPoster.image(of: project)
                else { continue }
                guard !Task.isCancelled else { return }
                ProjectStore.writePoster(image, for: entry.id)
                posters[entry.id] = image
            }
        }
    }

    // MARK: Missing media

    var missingAssetList: [MediaAsset] {
        project.assets.filter { missingAssets.contains($0.id) }
    }

    /// Asks where the missing files are now: one file, or a folder (every missing file with the
    /// same name in it is found). Files are checked to be the same kind and length before use.
    func findMissingFiles() {
        let missing = missingAssetList
        guard let first = missing.first else { return }
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        // Folders must be listed too: with only file types allowed, a folder can't be chosen.
        panel.allowedContentTypes = [.movie, .audio, .image, .folder]
        panel.prompt = "Use"
        panel.message =
            missing.count == 1
            ? "Where is “\(first.url.lastPathComponent)” now? Choose the file, or the folder it is in."
            : "Where are the \(missing.count) missing files now? Choose the folder they are in, or one of the files."
        guard panel.runModal() == .OK, let chosen = panel.url else { return }
        // Kept for as long as the app runs, so the files (and the bookmarks saved for them) work.
        _ = chosen.startAccessingSecurityScopedResource()

        var candidates: [MediaAsset.ID: URL] = [:]
        if (try? chosen.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
            let contents = (try? FileManager.default.contentsOfDirectory(at: chosen, includingPropertiesForKeys: nil)) ?? []
            candidates = project.relinkMatches(for: missingAssets, in: contents)
        } else if let match = missing.first(where: { $0.url.lastPathComponent.lowercased() == chosen.lastPathComponent.lowercased() })
            ?? (missing.count == 1 ? first : nil)
        {
            candidates = [match.id: chosen]
        }
        guard !candidates.isEmpty else {
            alert = AlertMessage(
                title: "No missing files there",
                message: "None of the files there has the name of a missing one (\(missing.map(\.url.lastPathComponent).joined(separator: ", "))).")
            return
        }
        Task {
            var accepted: [MediaAsset.ID: URL] = [:]
            var rejected: [String] = []
            for (id, url) in candidates {
                guard let asset = project.asset(id: id) else { continue }
                if let found = try? await MediaProbe.probe(url), Project.isLikelySameMedia(asset, as: found) {
                    accepted[id] = url
                } else {
                    rejected.append(url.lastPathComponent)
                }
            }
            if !accepted.isEmpty {
                apply(accepted.count == 1 ? "Find Missing File" : "Find Missing Files") { project in
                    for (id, url) in accepted { project.relink(id, to: url) }
                }
                for id in accepted.keys {
                    if let asset = project.asset(id: id) { loadPreviews(for: asset, again: true) }
                }
            }
            if !rejected.isEmpty {
                alert = AlertMessage(
                    title: rejected.count == 1 ? "This file doesn't match" : "These files don't match",
                    message: rejected.joined(separator: "\n")
                        + "\n\nThey have a different length or kind than the missing media, so your cuts would land in the wrong places."
                )
            }
        }
    }
}
