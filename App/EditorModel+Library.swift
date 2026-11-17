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
    ///
    /// The Short is written in the background (`ProjectStore.save`), from a snapshot taken now;
    /// `ProjectStore.finishSaving()` waits for it (at quit).
    func saveNow() {
        autosaveTask?.cancel()
        autosaveTask = nil
        rememberSession()
        guard hasUnsavedChanges, let id = openShortID else { return }
        hasUnsavedChanges = false
        if !isWorthKeeping {
            ProjectStore.removeFromLibrary(id)
            return
        }
        ProjectStore.save(ProjectStore.file(for: project, name: openShortName, created: openShortCreated, media: media), id: id) { [weak self] error in
            guard let self else { return }
            guard let error else {
                didReportSaveError = false
                if openShortID == id { backups = ProjectStore.backups(for: id) }
                return
            }
            Log.file.failure("Saving the open Short", error)
            // Try again with the next change (or now, if this is still the open Short); say it once.
            if openShortID == id { hasUnsavedChanges = true }
            if !didReportSaveError {
                didReportSaveError = true
                alert = AlertMessage("Your Short couldn't be saved", error: error, retry: { self.saveNow() })
            }
        }
    }

    // MARK: Backups

    /// File ▸ Revert To: the open Short goes back to a backup, as one undoable step. The Short as
    /// it is now is backed up first, so reverting can be undone after quitting, too.
    func revert(to backup: ProjectStore.Backup) {
        guard let id = openShortID else { return }
        saveNow()
        let reverted: ProjectFile
        do {
            reverted = try ProjectStore.readFile(backup.url, media: media)
        } catch {
            Log.file.failure("Reading a backup", error)
            alert = AlertMessage("This backup can't be opened", error: error)
            return
        }
        ProjectStore.backUp(id, when: .always) { [weak self] in
            guard let self, openShortID == id else { return }
            backups = ProjectStore.backups(for: id)
        }
        replaceProject(with: reverted.project, actionName: "Revert to \(backup.title)")
        for asset in project.assets { loadPreviews(for: asset) }
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
            try ProjectStore.write(project, to: url, name: openShortName, created: openShortCreated, media: media)
        } catch {
            Log.file.failure("Saving a copy of the Short", error)
            alert = AlertMessage("The copy couldn't be saved", error: error)
        }
    }

    /// At launch: brings older projects into the library, then shows the home window, or the Short
    /// that was open when the app was quit when `reopening` (not when files opened from Finder
    /// launched the app: they start a new Short).
    func restoreLastSession(reopening: Bool = true) {
        let session = reopening ? EditingSession.saved : nil
        // Under tests the library is a test run's own, but the made copies (Caches) are shared
        // with the real app: cleaning them up there could remove copies the user's Shorts use.
        if !AppEnvironment.isTesting {
            ProjectStore.moveOldProjectsIntoLibrary()
            // Before any Short is open, so nothing an undo might need is removed.
            ProjectStore.removeUnusedCopies()
        }
        ProjectStore.removeOrphanedBackups()
        showHome()
        if let session { reopen(session) }
    }

    /// Back to the home window (the "All Shorts" button): the open Short is saved first.
    func showHome() {
        playback.player.pause()
        saveNow()
        if let id = openShortID, !isWorthKeeping {
            // A Short left empty isn't kept.
            ProjectStore.removeFromLibrary(id)
        }
        openShortID = nil
        load(Project(), name: "", created: .now)
        screen = .home
        rememberSession()
        library.refresh()
    }

    /// The window is closing: its Short is saved and the player stops.
    func closeWindow() {
        showHome()
        playback.player.replaceCurrentItem(with: nil)
    }

    /// File ▸ New Short, or the New Short tile: an empty Short, open in the editor.
    func newShort() {
        if screen == .editor { showHome() }
        openShortID = UUID()
        load(Project(), name: ShortsLibrary.newName(existing: library.names), created: .now)
        screen = .editor
    }

    /// Opens a Short from the home window.
    func openShort(_ id: UUID) {
        // Already open in another window: that window comes forward instead.
        if let other = app?.editor(showing: id), other !== self {
            other.window?.makeKeyAndOrderFront(nil)
            return
        }
        let file: ProjectFile
        let access = MediaAccess()
        do {
            file = try ProjectStore.readFile(ProjectStore.fileURL(for: id), media: access)
        } catch {
            Log.file.failure("openShort", error)
            alert = AlertMessage("This Short can't be opened", error: error)
            return
        }
        if screen == .editor { showHome() }
        openShortID = id
        load(file.project, name: file.name ?? ShortsLibrary.defaultName, created: file.created ?? .now, media: access)
        screen = .editor
        // How it was before this session, for File ▸ Revert To.
        backups = ProjectStore.backups(for: id)
        ProjectStore.backUp(id, when: .changed) { [weak self] in
            guard let self, openShortID == id else { return }
            backups = ProjectStore.backups(for: id)
        }
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
            let id = try ProjectStore.importProject(at: url, existingNames: library.names)
            library.refresh()
            openShort(id)
        } catch {
            Log.file.failure("openProject", error)
            alert = AlertMessage("“\(url.deletingPathExtension().lastPathComponent)” can't be opened", error: error)
        }
    }

    func renameShort(_ id: UUID, to typed: String) {
        guard let name = ShortsLibrary.cleanedName(typed) else { return }
        if id == openShortID {
            renameOpenShort(to: name)
        } else if let other = app?.editor(showing: id) {
            // Open in another window: renamed there, so its next save keeps the name.
            other.renameShort(id, to: name)
            library.refresh()
        } else {
            library.rename(id, to: name)
        }
    }

    private func renameOpenShort(to typed: String) {
        guard let name = ShortsLibrary.cleanedName(typed), name != openShortName else { return }
        openShortName = name
        if isWorthKeeping {
            hasUnsavedChanges = true
            saveNow()
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
        // Kept while the Short is open, so the files (and the bookmarks saved for them) work.
        media.open(chosen)

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
