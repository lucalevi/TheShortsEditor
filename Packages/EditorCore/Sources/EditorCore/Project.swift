import CoreGraphics
import CoreMedia
import Foundation

/// Everything about one Short.
///
/// A plain value type: every edit produces a new `Project`, so undo is just restoring the previous
/// value, and the AVFoundation objects used for playback are always rebuilt from it — never edited
/// directly.
public struct Project: Codable, Equatable, Sendable {
    /// Shorts are always 9:16 at 1080×1920, so the canvas is fixed rather than a setting.
    public static let canvasSize = CGSize(width: 1080, height: 1920)
    public static let frameRate: Int32 = 30
    /// YouTube's maximum Short length (uploads since 2024-10-15).
    public static let maxDuration = CMTime(value: 180, timescale: 1)

    public var assets: [MediaAsset] = []
    public var timeline = Timeline()
    /// What is said in each source file, for captions. Kept per file, in the file's own time.
    public var transcripts: [MediaAsset.ID: Transcript] = [:]
    public var captions = CaptionSettings()

    public init() {}

    public var duration: CMTime { timeline.duration }
    public var isOverMaxDuration: Bool { duration > Self.maxDuration }

    public func asset(id: MediaAsset.ID) -> MediaAsset? {
        assets.first { $0.id == id }
    }
}

/// A source file the user imported. Clips on the timeline point at one of these.
public struct MediaAsset: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public var url: URL
    public var name: String
    public var duration: CMTime
    /// Size as the video is meant to be seen, i.e. after the track's rotation is applied.
    public var displaySize: CGSize
    public var hasAudio: Bool

    public init(id: UUID = UUID(), url: URL, name: String, duration: CMTime, displaySize: CGSize, hasAudio: Bool) {
        self.id = id
        self.url = url
        self.name = name
        self.duration = duration
        self.displaySize = displaySize
        self.hasAudio = hasAudio
    }

    /// The framing a newcomer most likely wants: vertical footage fills the screen, while
    /// horizontal footage is shown whole instead of losing two thirds of the picture.
    public var defaultFraming: Framing {
        guard displaySize.width > 0 else { return .fill }
        let aspect = displaySize.height / displaySize.width
        let vertical = Project.canvasSize.height / Project.canvasSize.width
        return aspect >= vertical * 0.75 ? .fill : .fit
    }
}

/// How a clip's picture is placed on the 9:16 canvas.
public enum Framing: String, Codable, CaseIterable, Sendable {
    /// Scale until the canvas is covered; the edges that don't fit are cropped.
    case fill
    /// Scale until the whole picture is visible; the rest of the canvas stays black.
    case fit
}

public extension Project {
    /// Adds `asset` unless a file at the same location is already imported.
    /// Returns the id of the asset that is now in the project.
    @discardableResult
    mutating func addAsset(_ asset: MediaAsset) -> MediaAsset.ID {
        if let existing = assets.first(where: { $0.url.standardizedFileURL == asset.url.standardizedFileURL }) {
            return existing.id
        }
        assets.append(asset)
        return asset.id
    }

    /// Appends a clip covering the whole of the asset to the end of the timeline.
    @discardableResult
    mutating func appendClip(of assetID: MediaAsset.ID) -> Clip.ID? {
        guard let asset = asset(id: assetID), asset.duration > .zero else { return nil }
        let clip = Clip(assetID: assetID, sourceStart: .zero, duration: asset.duration, framing: asset.defaultFraming)
        timeline.clips.append(clip)
        return clip.id
    }
}

extension MediaAsset {
    private enum CodingKeys: String, CodingKey {
        case id, url, name, duration, displaySize, hasAudio
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        url = try c.decode(URL.self, forKey: .url)
        name = try c.decode(String.self, forKey: .name)
        duration = try c.decodeTime(forKey: .duration)
        displaySize = try c.decode(CGSize.self, forKey: .displaySize)
        hasAudio = try c.decode(Bool.self, forKey: .hasAudio)
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(url, forKey: .url)
        try c.encode(name, forKey: .name)
        try c.encode(time: duration, forKey: .duration)
        try c.encode(displaySize, forKey: .displaySize)
        try c.encode(hasAudio, forKey: .hasAudio)
    }
}
