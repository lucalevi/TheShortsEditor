import EditorCore
import Foundation

/// Finds the files the app made that no Short uses any more.
///
/// Two kinds: copies in Caches (cleaned voices, processed sound, smooth slow motion, cut-outs,
/// shake measurements), which the app can make again and are removed by themselves at launch;
/// and older versions of the app's own music.
public enum StorageCleaner {
    /// The Caches folders the app writes copies into.
    public static var cacheFolders: [URL] {
        [VoiceCleaner.folder, SoundProcessor.folder, FrameInterpolator.folder, CutoutCache.folder, ShakeCache.folder]
    }

    /// Every made copy `projects` read, whether made yet or not (and their own media).
    /// File names depend on each file's size and date, so call this while the media can be read.
    public static func filesInUse(by projects: [Project]) -> Set<URL> {
        var used = Set<URL>()
        for project in projects {
            let clips = project.timeline.clips + project.overlays.map(\.clip) + project.sounds.map(\.clip)
            for asset in project.assets { used.insert(asset.url.standardizedFileURL) }
            for clip in clips {
                guard let media = project.asset(id: clip.assetID) else { continue }
                if clip.cleansVoice { used.insert(VoiceCleaner.cleanedURL(for: media.url)) }
                let recipe = SoundProcessor.Recipe(clip)
                if !recipe.isEmpty {
                    // From the cleaned sound or the file itself, whichever the clip ends up using.
                    used.insert(SoundProcessor.processedURL(for: media.url, recipe: recipe))
                    if clip.cleansVoice { used.insert(SoundProcessor.processedURL(for: VoiceCleaner.cleanedURL(for: media.url), recipe: recipe)) }
                }
                if let recipe = FrameInterpolator.recipe(for: clip, media: media) {
                    used.insert(FrameInterpolator.copyURL(for: media.url, recipe: recipe))
                }
                if let subject = clip.cutout.removeBackground {
                    used.insert(CutoutCache.copyURL(for: media.url, subject: subject, isImage: media.isImage))
                }
                if clip.steadiness > 0 { used.insert(ShakeCache.fileURL(for: media.url)) }
            }
        }
        return Set(used.map(\.standardizedFileURL))
    }

    /// Files directly in `folders` that aren't in `inUse` and haven't changed since `before`.
    public static func unusedFiles(in folders: [URL], inUse: Set<URL>, before: Date) -> [URL] {
        let keys: [URLResourceKey] = [.contentModificationDateKey, .isRegularFileKey]
        return folders.flatMap { folder in
            (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: keys)) ?? []
        }.filter { file in
            guard let values = try? file.resourceValues(forKeys: Set(keys)), values.isRegularFile == true else { return false }
            return !inUse.contains(file.standardizedFileURL) && (values.contentModificationDate ?? .distantPast) < before
        }
    }

    /// Folders of music made by older versions of the app (it makes and relinks the current ones).
    public static var oldMusicFolders: [URL] {
        let parent = MusicLibrary.folder.deletingLastPathComponent()
        let current = MusicLibrary.folder.standardizedFileURL.lastPathComponent
        let folders = (try? FileManager.default.contentsOfDirectory(at: parent, includingPropertiesForKeys: nil)) ?? []
        return folders.filter { $0.lastPathComponent != current && $0.hasDirectoryPath }
    }

    /// How much space `files` take, in bytes (folders counted with everything in them).
    public static func size(of files: [URL]) -> Int64 {
        files.reduce(0) { total, url in
            if url.hasDirectoryPath {
                let inside = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.totalFileAllocatedSizeKey])?.allObjects as? [URL] ?? []
                return total + size(of: inside.filter { !$0.hasDirectoryPath })
            }
            let values = try? url.resourceValues(forKeys: [.totalFileAllocatedSizeKey, .fileSizeKey])
            return total + Int64(values?.totalFileAllocatedSize ?? values?.fileSize ?? 0)
        }
    }

    /// Removes the made copies no Short in `projects` uses, untouched for `days` days (so a Short
    /// whose media is on a disk that isn't plugged in doesn't lose its copies straight away), and
    /// old music. Returns the bytes freed. Run before a Short is opened, so no undo needs them.
    @discardableResult
    public static func removeUnusedCopies(keepingFor projects: [Project], days: Double = 7, now: Date = Date()) -> Int64 {
        let cutoff = now.addingTimeInterval(-days * 24 * 3600)
        let stale = unusedFiles(in: cacheFolders, inUse: filesInUse(by: projects), before: cutoff) + oldMusicFolders
        let bytes = size(of: stale)
        for file in stale { Log.storage.attempt("Removing an unused copy") { try FileManager.default.removeItem(at: file) } }
        return bytes
    }
}
