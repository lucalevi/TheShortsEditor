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

    static func write(_ project: Project, to url: URL, name: String? = nil, created: Date? = nil) throws {
        var saved: [MediaAsset.ID: Data] = [:]
        for asset in project.assets {
            if let data = bookmark(for: asset.url) { saved[asset.id] = data }
        }
        let data = try ProjectFile(project: project, bookmarks: saved, name: name, created: created).encoded()
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        do {
            try data.write(to: url, options: .atomic)
        } catch {
            // Writing atomically needs a temporary file next to it, which the sandbox may not
            // allow in a folder the user only gave us one file of.
            try data.write(to: url)
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
            guard let resolved = Log.file.attempt("Finding a Short's media file", {
                try URL(resolvingBookmarkData: data, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &stale)
            }) else {
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
        guard let data = Log.file.attempt("Making a bookmark for a media file", {
            try url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
        }) else { return nil }
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

    /// Every Short in the library, newest change first. Files that can't be read are left out.
    static func libraryEntries() -> [ShortEntry] {
        let files = (try? FileManager.default.contentsOfDirectory(at: libraryFolder, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        return files.compactMap { url -> ShortEntry? in
            guard url.pathExtension == ProjectFile.fileExtension,
                  let id = UUID(uuidString: url.deletingPathExtension().lastPathComponent),
                  let file = Log.file.attempt("Reading a Short for the home window", { try ProjectFile.decode(Data(contentsOf: url)) })
            else { return nil }
            let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .now
            return ShortEntry(id: id, name: file.name ?? ShortsLibrary.defaultName, created: file.created ?? modified,
                              modified: modified, duration: file.project.duration,
                              clipCount: file.project.timeline.clips.count)
        }
        .sorted { $0.modified > $1.modified }
    }

    /// The poster saved for a Short, if it is newer than the Short's last change.
    static func freshPoster(for entry: ShortEntry) -> URL? {
        let url = posterURL(for: entry.id)
        guard let date = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
              date >= entry.modified else { return nil }
        return url
    }

    static func writePoster(_ image: CGImage, for id: UUID) {
        let url = posterURL(for: id)
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil) else { return }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.8] as CFDictionary)
        CGImageDestinationFinalize(destination)
    }

    /// Removes a Short from the library: into the Trash when the sandbox allows it, so a mistake
    /// can be undone from Finder.
    static func delete(_ id: UUID) {
        let url = fileURL(for: id)
        if (try? FileManager.default.trashItem(at: url, resultingItemURL: nil)) == nil {
            // The sandbox may not allow the Trash: remove it instead.
            Log.file.attempt("Deleting a Short") { try FileManager.default.removeItem(at: url) }
        }
        Log.file.attempt("Deleting a Short's poster") { try FileManager.default.removeItem(at: posterURL(for: id)) }
    }

    /// Changes only the name saved in a Short's file.
    static func rename(_ id: UUID, to name: String) throws {
        let url = fileURL(for: id)
        var file = try ProjectFile.decode(Data(contentsOf: url))
        file.name = name
        try file.encoded().write(to: url, options: .atomic)
    }

    /// Copies a Short (file and poster) under a new id and name.
    static func duplicate(_ id: UUID, as name: String) throws -> UUID {
        var file = try ProjectFile.decode(Data(contentsOf: fileURL(for: id)))
        file.name = name
        file.created = .now
        let copy = UUID()
        try file.encoded().write(to: fileURL(for: copy), options: .atomic)
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
        try file.encoded().write(to: fileURL(for: id), options: .atomic)
        return id
    }

    /// Once, after updating from a version without the home window: the unnamed Short and the
    /// projects opened lately become Shorts in the library.
    static func moveOldProjectsIntoLibrary() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: "MovedIntoLibrary") else { return }
        defaults.set(true, forKey: "MovedIntoLibrary")
        var names = libraryEntries().map(\.name)
        let recents = (defaults.array(forKey: "RecentProjects") as? [Data] ?? []).compactMap(resolve)
        for url in recents {
            if let id = Log.file.attempt("Moving an old project into the library", { try importProject(at: url, existingNames: names) }) {
                names.append((try? ProjectFile.decode(Data(contentsOf: fileURL(for: id))))?.name ?? "")
            }
        }
        if FileManager.default.fileExists(atPath: legacyUntitledURL.path),
           (try? importProject(at: legacyUntitledURL, existingNames: names)) != nil {
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
struct ShortEntry: Identifiable, Equatable {
    let id: UUID
    var name: String
    var created: Date
    var modified: Date
    var duration: CMTime
    var clipCount: Int
}
