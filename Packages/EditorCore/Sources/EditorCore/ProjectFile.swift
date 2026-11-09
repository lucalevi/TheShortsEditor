import CoreMedia
import Foundation

/// What a saved Short looks like on disk: the project, plus a way back to each media file.
///
/// The app is sandboxed, so a plain path isn't enough to open a file again after a restart: each
/// asset also carries a security-scoped bookmark, made while the app had access to it.
public struct ProjectFile: Codable, Equatable, Sendable {
    /// Bumped when the format changes in a way older versions can't read.
    /// 2: overlays (B-roll), pictures, placement and motion.
    public static let currentVersion = 2
    public static let fileExtension = "shortsproject"

    public var version: Int
    public var project: Project
    /// Per asset, bookmark data for its file (missing when it couldn't be made).
    public var bookmarks: [MediaAsset.ID: Data]

    public init(project: Project, bookmarks: [MediaAsset.ID: Data] = [:]) {
        version = Self.currentVersion
        self.project = project
        self.bookmarks = bookmarks
    }

    public enum ReadError: LocalizedError, Equatable {
        case newerVersion
        case unreadable

        public var errorDescription: String? {
            switch self {
            case .newerVersion: "This Short was saved by a newer version of Shorts Editor. Update the app to open it."
            case .unreadable: "This file isn't a Shorts Editor project, or it is damaged."
            }
        }
    }

    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(self)
    }

    public static func decode(_ data: Data) throws -> ProjectFile {
        struct Header: Decodable { var version: Int }
        guard let header = try? JSONDecoder().decode(Header.self, from: data) else { throw ReadError.unreadable }
        guard header.version <= currentVersion else { throw ReadError.newerVersion }
        do {
            return try JSONDecoder().decode(ProjectFile.self, from: data)
        } catch {
            throw ReadError.unreadable
        }
    }
}

public extension Project {
    /// The media the project uses (clips, overlays or music), in a stable order.
    var usedAssets: [MediaAsset] {
        var ids = Set(timeline.clips.map(\.assetID))
        ids.formUnion(overlays.map(\.clip.assetID))
        if let music { ids.insert(music.assetID) }
        return assets.filter { ids.contains($0.id) }
    }

    /// Points an asset at a new file, e.g. after it was moved. Its edits (clips, captions) stay.
    mutating func relink(_ assetID: MediaAsset.ID, to url: URL) {
        guard let index = assets.firstIndex(where: { $0.id == assetID }) else { return }
        assets[index].url = url
        assets[index].name = url.deletingPathExtension().lastPathComponent
    }

    /// For each missing asset, the file among `candidates` with the same name, if there is one.
    /// Used to find all the missing files in a folder the user points at.
    func relinkMatches(for missing: Set<MediaAsset.ID>, in candidates: [URL]) -> [MediaAsset.ID: URL] {
        var byName: [String: URL] = [:]
        for url in candidates { byName[url.lastPathComponent.lowercased()] = url }
        var matches: [MediaAsset.ID: URL] = [:]
        for asset in assets where missing.contains(asset.id) {
            if let url = byName[asset.url.lastPathComponent.lowercased()] { matches[asset.id] = url }
        }
        return matches
    }

    /// Whether a file chosen to replace `asset` looks like the same media: same kind and about
    /// the same length. Clips are cut by time, so a different file would play the wrong parts.
    static func isLikelySameMedia(_ asset: MediaAsset, as candidate: MediaAsset) -> Bool {
        guard asset.hasVideo == candidate.hasVideo, asset.isImage == candidate.isImage else { return false }
        if asset.isImage { return true }
        return abs(asset.duration.seconds - candidate.duration.seconds) <= 0.5
    }
}
