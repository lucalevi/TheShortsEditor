import EditorCore
import Foundation
import UniformTypeIdentifiers

extension UTType {
    /// A saved Short (`.shortsproject`), declared in project.yml.
    static let shortsProject = UTType(exportedAs: "com.lucalevi.shortseditor.project")
}

/// Reads and writes project files, and remembers which ones were open.
///
/// The app is sandboxed: it may only open files the user handed it. To open media (and recent
/// projects) again after a restart, it keeps security-scoped bookmarks, made while it had access.
@MainActor
enum ProjectStore {
    /// Where a Short that hasn't been given a name is kept, so quitting never loses it.
    static var untitledURL: URL {
        let folder = URL.applicationSupportDirectory.appending(path: "Shorts Editor", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appending(path: "Untitled.\(ProjectFile.fileExtension)")
    }

    static var hasUntitled: Bool { FileManager.default.fileExists(atPath: untitledURL.path) }

    /// Bookmarks already made or read, by file location, so saving doesn't remake them each time
    /// and a missing file keeps the bookmark it had.
    private static var bookmarks: [URL: Data] = [:]

    // MARK: Reading and writing

    static func write(_ project: Project, to url: URL) throws {
        var saved: [MediaAsset.ID: Data] = [:]
        for asset in project.assets {
            if let data = bookmark(for: asset.url) { saved[asset.id] = data }
        }
        let data = try ProjectFile(project: project, bookmarks: saved).encoded()
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
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        let file = try ProjectFile.decode(Data(contentsOf: url))
        var project = file.project
        for asset in project.assets {
            guard let data = file.bookmarks[asset.id] else { continue }
            var stale = false
            guard let resolved = try? URL(resolvingBookmarkData: data, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &stale) else {
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
        return project
    }

    private static func bookmark(for url: URL) -> Data? {
        if let known = bookmarks[url] { return known }
        guard let data = try? url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil) else { return nil }
        bookmarks[url] = data
        return data
    }

    // MARK: Recent projects

    private static let recentsKey = "RecentProjects"
    private static let openKey = "OpenProject"
    private static let recentLimit = 8

    /// Named projects opened lately, newest first, that can still be found.
    static var recentProjects: [URL] {
        (UserDefaults.standard.array(forKey: recentsKey) as? [Data] ?? []).compactMap(resolve)
    }

    /// Remembers a named project as open (to reopen at the next launch) and recent.
    static func noteOpened(_ url: URL) {
        guard let data = try? url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil) else { return }
        UserDefaults.standard.set(data, forKey: openKey)
        var recents = (UserDefaults.standard.array(forKey: recentsKey) as? [Data] ?? []).filter {
            resolve($0)?.standardizedFileURL != url.standardizedFileURL
        }
        recents.insert(data, at: 0)
        UserDefaults.standard.set(Array(recents.prefix(recentLimit)), forKey: recentsKey)
    }

    /// The unnamed Short is open: next launch reopens that instead.
    static func noteUntitledOpen() {
        UserDefaults.standard.removeObject(forKey: openKey)
    }

    /// The named project that was open when the app last quit, if it can still be found.
    static var lastOpenProject: URL? {
        (UserDefaults.standard.data(forKey: openKey)).flatMap(resolve)
    }

    static func clearRecents() {
        UserDefaults.standard.removeObject(forKey: recentsKey)
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
