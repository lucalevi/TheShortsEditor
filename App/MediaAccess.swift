import EditorCore
import Foundation

/// A Short's way into its media files. The app is sandboxed: it may open only files the user
/// handed it (dropped, chosen in a panel) or that it found again through a security-scoped
/// bookmark saved in the Short. Access to each of them is started once, here, and stopped when
/// the Short is closed (`close()`), so starts and stops always balance.
///
/// It also keeps the Short's bookmarks by file location, so saving doesn't make them anew each time
/// and a missing file keeps the bookmark it had.
final class MediaAccess {
    private var bookmarks: [URL: Data] = [:]
    /// Files and folders whose access this started (and will stop).
    private(set) var opened: Set<URL> = []

    /// Starts access to a file or folder, for as long as this lasts. Opening the same one again
    /// does nothing.
    func open(_ url: URL) {
        guard !opened.contains(url), url.startAccessingSecurityScopedResource() else { return }
        opened.insert(url)
    }

    /// Stops every access started (the Short is closed).
    func close() {
        for url in opened { url.stopAccessingSecurityScopedResource() }
        opened = []
    }

    isolated deinit {
        close()
    }

    /// A bookmark for a media file, made the first time (while access to it is on).
    func bookmark(for url: URL) -> Data? {
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

    /// The bookmarks of the project's media, to save with it.
    func bookmarks(for project: Project) -> [MediaAsset.ID: Data] {
        var saved: [MediaAsset.ID: Data] = [:]
        for asset in project.assets {
            if let data = bookmark(for: asset.url) { saved[asset.id] = data }
        }
        return saved
    }

    /// Finds a read project's media through its saved bookmarks, opening each file found and
    /// following files that were renamed or moved on the same disk.
    func resolve(_ file: ProjectFile) -> ProjectFile {
        var file = file
        for asset in file.project.assets {
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
            open(resolved)
            if resolved.standardizedFileURL != asset.url.standardizedFileURL {
                file.project.relink(asset.id, to: resolved)
            }
            if !stale { bookmarks[resolved] = data }
        }
        return file
    }
}
