import CoreMedia
import Foundation

/// What a saved Short looks like on disk: the project, plus a way back to each media file.
///
/// The app is sandboxed, so a plain path isn't enough to open a file again after a restart: each
/// asset also carries a security-scoped bookmark, made while the app had access to it.
public struct ProjectFile: Codable, Equatable, Sendable {
    /// Bumped when the format changes in a way older versions can't read.
    /// 2: overlays (B-roll), pictures, placement and motion.
    /// 3: speed, title looks, key words and emoji, sound effects and voice-overs, layouts.
    /// 4: transitions, freeze frames, clips played backwards, see-through B-roll.
    /// 5: colour, filters (per clip and for the whole Short), Stabilize.
    /// 6: markers.
    /// 7: styles, app-made music, storyboards.
    /// 8: speed curves, clip animations, smooth slow motion, beats, music placed later or looped.
    public static let currentVersion = 8
    public static let fileExtension = "shortsproject"

    public var version: Int
    public var project: Project
    /// Per asset, bookmark data for its file (missing when it couldn't be made).
    public var bookmarks: [MediaAsset.ID: Data]
    /// The Short's name, shown on the home window. Files saved before the home window have none
    /// (their file name is used).
    public var name: String?
    /// When the Short was first made.
    public var created: Date?
    /// What the home window shows about the Short, so it can list Shorts without reading whole
    /// projects (`readListing`). Written with every save; files saved before 2026-11-14 have none.
    public var summary: Summary?

    public struct Summary: Codable, Equatable, Sendable {
        public var duration: CMTime
        public var clipCount: Int

        public init(of project: Project) {
            duration = project.duration
            clipCount = project.timeline.clips.count
        }

        private enum CodingKeys: String, CodingKey { case duration, clipCount }

        public init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            duration = try c.decodeTime(forKey: .duration)
            clipCount = try c.decode(Int.self, forKey: .clipCount)
        }

        public func encode(to encoder: any Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(time: duration, forKey: .duration)
            try c.encode(clipCount, forKey: .clipCount)
        }
    }

    public init(project: Project, bookmarks: [MediaAsset.ID: Data] = [:], name: String? = nil, created: Date? = nil) {
        version = Self.currentVersion
        self.project = project
        self.bookmarks = bookmarks
        self.name = name
        self.created = created
        summary = Summary(of: project)
    }

    /// Why a file couldn't be opened. Nothing is ever written over a file that couldn't be read, so
    /// refusing to open it is always safe: the file stays as it was.
    public enum ReadError: LocalizedError, Equatable {
        case newerVersion
        /// Not a Shorts Editor project at all (not JSON, or no version).
        case unreadable
        /// A Shorts Editor project with a value this version doesn't know (a new filter, style or
        /// effect), so made by a newer version of the app. `detail` says where, for the log.
        case unknownValue(detail: String)
        /// A Shorts Editor project with a part missing or of the wrong kind. `detail` says where.
        case damaged(detail: String)

        public var errorDescription: String? {
            switch self {
            case .newerVersion: "This Short was saved by a newer version of Shorts Editor. Update the app to open it."
            case .unreadable: "This file isn't a Shorts Editor project, or it is damaged."
            case .unknownValue:
                "This Short uses something this version of Shorts Editor doesn't know, so it was probably made with a newer version. "
                    + "Update the app to open it. The file wasn't changed."
            case .damaged: "Part of this Short's file is damaged, so it wasn't opened. The file wasn't changed."
            }
        }

        /// Where in the file the problem is (e.g. "project.timeline.clips.3.look"), and what it is.
        public var detail: String? {
            switch self {
            case .unknownValue(let detail), .damaged(let detail): detail
            case .newerVersion, .unreadable: nil
            }
        }

        init(_ error: DecodingError) {
            func path(_ context: DecodingError.Context) -> String {
                context.codingPath.map { $0.intValue.map(String.init) ?? $0.stringValue }.joined(separator: ".")
            }
            switch error {
            case .dataCorrupted(let context):
                // A raw value that isn't one of an enum's cases: a newer app's filter, style, effect…
                self = .unknownValue(detail: "\(path(context)): \(context.debugDescription)")
            case .keyNotFound(let key, let context):
                let parent = path(context)
                self = .damaged(detail: "\(parent.isEmpty ? "" : parent + ".")\(key.stringValue) is missing")
            case .typeMismatch(_, let context), .valueNotFound(_, let context):
                self = .damaged(detail: "\(path(context)): \(context.debugDescription)")
            @unknown default:
                self = .damaged(detail: String(describing: error))
            }
        }
    }

    /// The file's bytes. `compact` leaves out line breaks and indentation (the library's own files,
    /// written often); files the user saves somewhere are indented, easier to read.
    public func encoded(compact: Bool = false) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = compact ? [.sortedKeys] : [.prettyPrinted, .sortedKeys]
        return try encoder.encode(self)
    }

    private struct Header: Decodable {
        var version: Int
    }

    public static func decode(_ data: Data) throws -> ProjectFile {
        try checkVersion(data)
        do {
            return try JSONDecoder().decode(ProjectFile.self, from: data)
        } catch let error as DecodingError {
            let readError = ReadError(error)
            Log.file.error("A Short couldn't be read: \(readError.detail ?? "", privacy: .public)")
            throw readError
        } catch {
            throw ReadError.unreadable
        }
    }

    private static func checkVersion(_ data: Data) throws {
        guard let header = try? JSONDecoder().decode(Header.self, from: data) else { throw ReadError.unreadable }
        guard header.version <= currentVersion else { throw ReadError.newerVersion }
    }

    /// What the home window lists about a Short, read without building the project. Files without a
    /// summary (saved before summaries existed) are read in full once; their next save adds one.
    public struct Listing: Equatable, Sendable {
        public var name: String?
        public var created: Date?
        public var summary: Summary
    }

    public static func readListing(_ data: Data) throws -> Listing {
        struct Head: Decodable {
            var name: String?
            var created: Date?
            var summary: Summary?
        }
        try checkVersion(data)
        if let head = try? JSONDecoder().decode(Head.self, from: data), let summary = head.summary {
            return Listing(name: head.name, created: head.created, summary: summary)
        }
        let file = try decode(data)
        return Listing(name: file.name, created: file.created, summary: Summary(of: file.project))
    }
}

public extension Project {
    /// The media the project uses (clips, overlays or music), in a stable order.
    var usedAssets: [MediaAsset] {
        var ids = Set(timeline.clips.map(\.assetID))
        ids.formUnion(overlays.map(\.clip.assetID))
        ids.formUnion(sounds.map(\.clip.assetID))
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
