import CoreMedia
import EditorCore
import Foundation
import ImageIO
import UniformTypeIdentifiers

extension UTType {
    /// A saved Short (`.shortsproject`), declared in project.yml.
    static let shortsProject = UTType(exportedAs: "com.lucalevi.shortseditor.project")
}

/// Reads and writes project files, and keeps the library of Shorts shown on the home window.
///
/// The app is sandboxed: it may only open files the user handed it. To open media (and recent
/// projects) again after a restart, it keeps security-scoped bookmarks, made while it had access.
@MainActor
enum ProjectStore {
    /// The app's own folder in its container.
    static var appFolder: URL {
        let folder = URL.applicationSupportDirectory.appending(path: "Shorts Editor", directoryHint: .isDirectory)
        Log.file.attempt("Making the app's folder") { try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true) }
        return folder
    }

    /// Where the unnamed Short was kept before the home window existed (moved into the library).
    private static var legacyUntitledURL: URL {
        appFolder.appending(path: "Untitled.\(ProjectFile.fileExtension)")
    }

    /// Bookmarks already made or read, by file location, so saving doesn't remake them each time
    /// and a missing file keeps the bookmark it had.
    private static var bookmarks: [URL: Data] = [:]

    // MARK: Reading and writing

    /// The file for `project` as it would be saved, with a bookmark for each media file.
    static func file(for project: Project, name: String?, created: Date?) -> ProjectFile {
        var saved: [MediaAsset.ID: Data] = [:]
        for asset in project.assets {
            if let data = bookmark(for: asset.url) { saved[asset.id] = data }
        }
        return ProjectFile(project: project, bookmarks: saved, name: name, created: created)
    }

    /// Writes a Short to a file the user chose (Save a Copy), never leaving it half written.
    static func write(_ project: Project, to url: URL, name: String? = nil, created: Date? = nil) throws {
        let data = try file(for: project, name: name, created: created).encoded()
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        try safelyWrite(data, to: url)
    }

    /// Writes `data` so that `url` holds either its old content or the new, never a mix: atomically
    /// (a temporary file beside it, then swapped in). In a folder the user only gave us one file of,
    /// the sandbox may not allow that temporary file; then it is written in the folder the system
    /// gives for replacing that file, and swapped in from there. A new file has nothing to lose, so
    /// it is written directly.
    nonisolated static func safelyWrite(_ data: Data, to url: URL) throws {
        do {
            try data.write(to: url, options: .atomic)
        } catch {
            let manager = FileManager.default
            guard manager.fileExists(atPath: url.path) else { return try data.write(to: url) }
            let folder = try manager.url(for: .itemReplacementDirectory, in: .userDomainMask, appropriateFor: url, create: true)
            defer { try? manager.removeItem(at: folder) }
            let temporary = folder.appending(path: url.lastPathComponent)
            try data.write(to: temporary)
            _ = try manager.replaceItemAt(url, withItemAt: temporary)
        }
    }

    /// Reads a project, finding its media through the saved bookmarks (and following files that
    /// were renamed or moved on the same disk).
    static func read(_ url: URL) throws -> Project {
        try readFile(url).project
    }

    /// Reads a project file with its name and date, its media found through the saved bookmarks.
    static func readFile(_ url: URL) throws -> ProjectFile {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        var file = try ProjectFile.decode(Data(contentsOf: url))
        var project = file.project
        for asset in project.assets {
            guard let data = file.bookmarks[asset.id] else { continue }
            var stale = false
            guard
                let resolved = Log.file.attempt(
                    "Finding a Short's media file",
                    {
                        try URL(resolvingBookmarkData: data, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &stale)
                    })
            else {
                bookmarks[asset.url] = data
                continue
            }
            // Keep access for as long as the app runs, like files imported in this session.
            _ = resolved.startAccessingSecurityScopedResource()
            if resolved.standardizedFileURL != asset.url.standardizedFileURL {
                project.relink(asset.id, to: resolved)
            }
            if !stale { bookmarks[resolved] = data }
        }
        file.project = project
        return file
    }

    private static func bookmark(for url: URL) -> Data? {
        if let known = bookmarks[url] { return known }
        guard
            let data = Log.file.attempt(
                "Making a bookmark for a media file",
                {
                    try url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
                })
        else { return nil }
        bookmarks[url] = data
        return data
    }

    // MARK: The library (every Short, shown on the home window)

    /// Where every Short is kept: one project file per Short, named by its id, and its poster.
    static var libraryFolder: URL {
        let folder = appFolder.appending(path: "Shorts", directoryHint: .isDirectory)
        Log.file.attempt("Making the library folder") { try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true) }
        return folder
    }

    static func fileURL(for id: UUID) -> URL {
        libraryFolder.appending(path: "\(id.uuidString).\(ProjectFile.fileExtension)")
    }

    static func posterURL(for id: UUID) -> URL {
        libraryFolder.appending(path: "\(id.uuidString).jpg")
    }

    /// Every Short in the library, newest change first, read from each file's summary (without
    /// building the project). Files that can't be read are left out (and logged).
    nonisolated static func libraryEntries(in folder: URL) -> [ShortEntry] {
        let keys: [URLResourceKey] = [.contentModificationDateKey]
        let files = Log.file.attempt("Listing the library") { try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: keys) } ?? []
        return files.compactMap { url -> ShortEntry? in
            guard url.pathExtension == ProjectFile.fileExtension,
                let id = UUID(uuidString: url.deletingPathExtension().lastPathComponent),
                let listing = Log.file.attempt("Reading a Short for the home window", { try ProjectFile.readListing(Data(contentsOf: url)) })
            else { return nil }
            let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .now
            return ShortEntry(
                id: id, name: listing.name ?? ShortsLibrary.defaultName, created: listing.created ?? modified,
                modified: modified, duration: listing.summary.duration, clipCount: listing.summary.clipCount)
        }
        .sorted { $0.modified > $1.modified }
    }

    /// `libraryEntries(in:)`, off the main thread and after every save waiting to be written.
    static func loadLibrary() async -> [ShortEntry] {
        let folder = libraryFolder
        return await withCheckedContinuation { continuation in
            saveQueue.async { continuation.resume(returning: libraryEntries(in: folder)) }
        }
    }

    // MARK: Saving the library's Shorts, in the background

    /// Saves, backups and removals of the library's Shorts run here, one after another, off the
    /// main thread. In order: a later save never lands before an earlier one, and a removal is never
    /// undone by a save still waiting.
    nonisolated private static let saveQueue = DispatchQueue(label: "com.lucalevi.shortseditor.saving", qos: .userInitiated)

    /// Saves a Short into the library in the background: the version on disk is backed up first
    /// when a backup is due. The snapshot is taken now, so later edits don't change what is written;
    /// `done` is called on the main actor with the error, if any.
    static func save(_ project: Project, id: UUID, name: String, created: Date, done: @escaping @MainActor (Error?) -> Void) {
        let file = file(for: project, name: name, created: created)
        let url = fileURL(for: id), backups = backupsFolder(for: id)
        saveQueue.async {
            var failure: Error?
            do {
                backUp(url, into: backups, when: .due)
                try file.encoded(compact: true).write(to: url, options: .atomic)
            } catch {
                failure = error
            }
            Task { @MainActor [failure] in done(failure) }
        }
    }

    /// Removes a Short's file from the library (a Short left empty), after any save waiting.
    static func removeFromLibrary(_ id: UUID) {
        let url = fileURL(for: id)
        saveQueue.async {
            guard FileManager.default.fileExists(atPath: url.path) else { return }
            Log.file.attempt("Removing an empty Short") { try FileManager.default.removeItem(at: url) }
        }
    }

    /// Waits until every save waiting has been written (before quitting, or reading a Short's file).
    static func finishSaving() {
        saveQueue.sync {}
    }

    // MARK: Backups (File ▸ Revert To)

    struct Backup: Identifiable, Equatable {
        let date: Date
        let url: URL
        var id: URL { url }

        /// "Today at 08:44", "Yesterday at 17:10", "12 Nov 2026 at 09:30" (stays true while the menu is open).
        var title: String { Self.formatter.string(from: date) }

        private static let formatter: DateFormatter = {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .short
            formatter.doesRelativeDateFormatting = true
            return formatter
        }()
    }

    enum BackupRule {
        /// When the newest backup is older than `BackupPolicy.interval` (before saving).
        case due
        /// When the file changed since its newest backup (on opening a Short).
        case changed
        /// Always (before reverting).
        case always
    }

    static var backupsRoot: URL { appFolder.appending(path: "Backups", directoryHint: .isDirectory) }

    static func backupsFolder(for id: UUID) -> URL {
        backupsRoot.appending(path: id.uuidString, directoryHint: .isDirectory)
    }

    /// A Short's backups, newest first.
    static func backups(for id: UUID) -> [Backup] {
        backupFiles(in: backupsFolder(for: id))
    }

    nonisolated private static func backupFiles(in folder: URL) -> [Backup] {
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        return files.compactMap { url in BackupPolicy.date(fromFileName: url.lastPathComponent).map { Backup(date: $0, url: url) } }
            .sorted { $0.date > $1.date }
    }

    /// Backs up a Short's file in the background (on opening it, or before reverting), after any save waiting.
    static func backUp(_ id: UUID, when rule: BackupRule, done: @escaping @MainActor () -> Void = {}) {
        let url = fileURL(for: id), folder = backupsFolder(for: id)
        saveQueue.async {
            backUp(url, into: folder, when: rule)
            Task { @MainActor in done() }
        }
    }

    /// Copies `file` into `folder` as a backup when `rule` says so, then removes backups the
    /// policy no longer keeps. Failures are logged: a missed backup never stops a save.
    nonisolated private static func backUp(_ file: URL, into folder: URL, when rule: BackupRule, now: Date = .now) {
        let manager = FileManager.default
        guard manager.fileExists(atPath: file.path) else { return }
        let existing = backupFiles(in: folder)
        switch rule {
        case .due:
            guard BackupPolicy.isDue(newest: existing.first?.date, now: now) else { return }
        case .changed:
            let modified = (try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? now
            if let newest = existing.first?.date, newest >= modified { return }
        case .always:
            break
        }
        let made: Void? = Log.file.attempt("Backing up a Short") {
            try manager.createDirectory(at: folder, withIntermediateDirectories: true)
            try manager.copyItem(at: file, to: folder.appending(path: BackupPolicy.fileName(for: now)))
        }
        guard made != nil else { return }
        let all = existing + [Backup(date: now, url: folder.appending(path: BackupPolicy.fileName(for: now)))]
        let kept = BackupPolicy.kept(all.map(\.date), now: now)
        for backup in all where !kept.contains(backup.date) {
            Log.file.attempt("Removing an old backup") { try manager.removeItem(at: backup.url) }
        }
    }

    /// At launch: backups of Shorts no longer in the library go once their newest is a month old.
    static func removeOrphanedBackups(now: Date = .now) {
        let library = libraryFolder
        let folders = (try? FileManager.default.contentsOfDirectory(at: backupsRoot, includingPropertiesForKeys: nil)) ?? []
        for folder in folders {
            guard let id = UUID(uuidString: folder.lastPathComponent),
                !FileManager.default.fileExists(atPath: library.appending(path: "\(id.uuidString).\(ProjectFile.fileExtension)").path)
            else { continue }
            let newest = backupFiles(in: folder).first?.date ?? .distantPast
            if now.timeIntervalSince(newest) > BackupPolicy.orphanLifetime {
                Log.file.attempt("Removing backups of a deleted Short") { try FileManager.default.removeItem(at: folder) }
            }
        }
    }

    /// The poster saved for a Short, if it is newer than the Short's last change.
    static func freshPoster(for entry: ShortEntry) -> URL? {
        let url = posterURL(for: entry.id)
        guard let date = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
            date >= entry.modified
        else { return nil }
        return url
    }

    static func writePoster(_ image: CGImage, for id: UUID) {
        let url = posterURL(for: id)
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil) else { return }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.8] as CFDictionary)
        CGImageDestinationFinalize(destination)
    }

    /// A deleted Short's file and poster, kept in memory so Edit ▸ Undo can put it back.
    struct DeletedShort {
        let id: UUID
        let file: Data
        let poster: Data?
    }

    /// Removes a Short from the library: into the Trash when the sandbox allows it. Returns its
    /// content, for undo. Its backups stay (removed a month later, see `removeOrphanedBackups`).
    static func delete(_ id: UUID) -> DeletedShort? {
        finishSaving()
        let url = fileURL(for: id)
        guard let data = Log.file.attempt("Reading a Short before deleting it", { try Data(contentsOf: url) }) else { return nil }
        let deleted = DeletedShort(id: id, file: data, poster: try? Data(contentsOf: posterURL(for: id)))
        if (try? FileManager.default.trashItem(at: url, resultingItemURL: nil)) == nil {
            // The sandbox may not allow the Trash: remove it instead.
            Log.file.attempt("Deleting a Short") { try FileManager.default.removeItem(at: url) }
        }
        Log.file.attempt("Deleting a Short's poster") { try FileManager.default.removeItem(at: posterURL(for: id)) }
        return deleted
    }

    /// Puts a deleted Short back (Edit ▸ Undo Delete).
    static func restore(_ deleted: DeletedShort) throws {
        try deleted.file.write(to: fileURL(for: deleted.id), options: .atomic)
        if let poster = deleted.poster {
            Log.file.attempt("Putting a Short's poster back") { try poster.write(to: posterURL(for: deleted.id), options: .atomic) }
        }
    }

    /// Changes only the name saved in a Short's file.
    static func rename(_ id: UUID, to name: String) throws {
        finishSaving()
        let url = fileURL(for: id)
        var file = try ProjectFile.decode(Data(contentsOf: url))
        file.name = name
        try file.encoded(compact: true).write(to: url, options: .atomic)
    }

    /// Copies a Short (file and poster) under a new id and name.
    static func duplicate(_ id: UUID, as name: String) throws -> UUID {
        finishSaving()
        var file = try ProjectFile.decode(Data(contentsOf: fileURL(for: id)))
        file.name = name
        file.created = .now
        let copy = UUID()
        try file.encoded(compact: true).write(to: fileURL(for: copy), options: .atomic)
        Log.file.attempt("Copying a Short's poster") { try FileManager.default.copyItem(at: posterURL(for: id), to: posterURL(for: copy)) }
        return copy
    }

    /// Brings a project file from elsewhere (Finder, the Open panel) into the library as a new
    /// Short. Its media bookmarks are kept, so the media opens as before.
    static func importProject(at url: URL, existingNames: [String]) throws -> UUID {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        var file = try ProjectFile.decode(Data(contentsOf: url))
        let base = file.name ?? url.deletingPathExtension().lastPathComponent
        file.name = ShortsLibrary.newName(base: base, existing: existingNames)
        file.created = file.created ?? .now
        let id = UUID()
        try file.encoded(compact: true).write(to: fileURL(for: id), options: .atomic)
        return id
    }

    /// Once, after updating from a version without the home window: the unnamed Short and the
    /// projects opened lately become Shorts in the library.
    static func moveOldProjectsIntoLibrary() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: "MovedIntoLibrary") else { return }
        defaults.set(true, forKey: "MovedIntoLibrary")
        var names = libraryEntries(in: libraryFolder).map(\.name)
        let recents = (defaults.array(forKey: "RecentProjects") as? [Data] ?? []).compactMap(resolve)
        for url in recents {
            if let id = Log.file.attempt("Moving an old project into the library", { try importProject(at: url, existingNames: names) }) {
                names.append((try? ProjectFile.decode(Data(contentsOf: fileURL(for: id))))?.name ?? "")
            }
        }
        if FileManager.default.fileExists(atPath: legacyUntitledURL.path),
            (try? importProject(at: legacyUntitledURL, existingNames: names)) != nil
        {
            try? FileManager.default.removeItem(at: legacyUntitledURL)
        }
        defaults.removeObject(forKey: "RecentProjects")
        defaults.removeObject(forKey: "OpenProject")
    }

    private static func resolve(_ data: Data) -> URL? {
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: data, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &stale) else { return nil }
        // Outside its folder the sandbox hides the file, even from this check, until access is on.
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }
}

/// A Short as listed on the home window.
struct ShortEntry: Identifiable, Equatable, Sendable {
    let id: UUID
    var name: String
    var created: Date
    var modified: Date
    var duration: CMTime
    var clipCount: Int
}
