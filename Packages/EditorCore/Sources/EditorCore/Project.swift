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
    /// Text over the video, such as the hook title. Drawn in this order, so later ones are on top.
    public var titles: [TextOverlay] = []
    /// The background song, if any. One per Short.
    public var music: BackgroundMusic?
    /// Pictures over the main clips (B-roll, picture-in-picture). Drawn in this order, so later
    /// ones are on top.
    public var overlays: [Overlay] = []
    /// Sound effects and voice-overs.
    public var sounds: [SoundClip] = []
    /// A filter over the whole Short (on top of each clip's own look), if any.
    public var look: FilterChoice?
    /// Named points on the timeline (M), sorted by time.
    public var markers: [Marker] = []
    /// The ready-made style of the whole Short, if one was chosen (see `ShortStyles.swift`).
    public var style: ShortStyle?
    /// The shot list the Short is being filmed from, if it was started from one (see `Storyboards.swift`).
    public var storyboard: Storyboard?

    public init() {}

    private enum CodingKeys: String, CodingKey {
        case assets, timeline, transcripts, captions, titles, music, overlays, sounds, look, markers, style, storyboard
    }

    /// Reads what older versions saved too: anything they didn't have yet starts empty.
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        assets = try c.decode([MediaAsset].self, forKey: .assets)
        timeline = try c.decode(Timeline.self, forKey: .timeline)
        transcripts = try c.decodeIfPresent([MediaAsset.ID: Transcript].self, forKey: .transcripts) ?? [:]
        captions = try c.decodeIfPresent(CaptionSettings.self, forKey: .captions) ?? CaptionSettings()
        titles = try c.decodeIfPresent([TextOverlay].self, forKey: .titles) ?? []
        music = try c.decodeIfPresent(BackgroundMusic.self, forKey: .music)
        overlays = try c.decodeIfPresent([Overlay].self, forKey: .overlays) ?? []
        sounds = try c.decodeIfPresent([SoundClip].self, forKey: .sounds) ?? []
        look = try? c.decodeIfPresent(FilterChoice.self, forKey: .look)
        markers = try c.decodeIfPresent([Marker].self, forKey: .markers) ?? []
        style = try? c.decodeIfPresent(ShortStyle.self, forKey: .style)
        storyboard = try? c.decodeIfPresent(Storyboard.self, forKey: .storyboard)
    }

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
    /// False for sound files (music), which can't go on the timeline as clips.
    public var hasVideo: Bool
    /// A still picture (photo, screenshot). It has a picture (`hasVideo`) but no video track, and
    /// can be shown for any length up to `MediaAsset.imageDuration`.
    public var isImage: Bool
    /// Pictures per second of a video, when known. High numbers mean it was filmed for slow motion.
    public var frameRate: Double?
    /// Set on a copy of another file made to play backwards (see `TimeEffects.swift`).
    public var reversedFrom: ReversedSource?

    /// The longest a picture can be shown. Pictures are given this as their length, so trimming
    /// treats them like a very long video.
    public static let imageDuration = CMTime(value: 3600, timescale: 1)
    /// How long a picture stays when it is added.
    public static let imageClipDuration = CMTime(value: 3, timescale: 1)

    public init(id: UUID = UUID(), url: URL, name: String, duration: CMTime, displaySize: CGSize, hasAudio: Bool, hasVideo: Bool = true, isImage: Bool = false,
                frameRate: Double? = nil, reversedFrom: ReversedSource? = nil) {
        self.frameRate = frameRate
        self.reversedFrom = reversedFrom
        self.id = id
        self.url = url
        self.name = name
        self.duration = isImage ? Self.imageDuration : duration
        self.displaySize = displaySize
        self.hasAudio = isImage ? false : hasAudio
        self.hasVideo = hasVideo || isImage
        self.isImage = isImage
    }

    /// A picture file of `size` (as it is meant to be seen, i.e. upright).
    public static func image(url: URL, size: CGSize) -> MediaAsset {
        MediaAsset(url: url, name: url.deletingPathExtension().lastPathComponent, duration: imageDuration, displaySize: size, hasAudio: false, isImage: true)
    }

    /// How long a new clip of this media is: the whole video, or a few seconds of a picture.
    public var defaultClipDuration: CMTime { isImage ? Self.imageClipDuration : duration }

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
        appendClip(of: assetID, part: nil)
    }
}

extension MediaAsset {
    private enum CodingKeys: String, CodingKey {
        case id, url, name, duration, displaySize, hasAudio, hasVideo, isImage, frameRate, reversedFrom
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        url = try c.decode(URL.self, forKey: .url)
        name = try c.decode(String.self, forKey: .name)
        duration = try c.decodeTime(forKey: .duration)
        displaySize = try c.decode(CGSize.self, forKey: .displaySize)
        hasAudio = try c.decode(Bool.self, forKey: .hasAudio)
        hasVideo = try c.decodeIfPresent(Bool.self, forKey: .hasVideo) ?? true
        isImage = try c.decodeIfPresent(Bool.self, forKey: .isImage) ?? false
        frameRate = try c.decodeIfPresent(Double.self, forKey: .frameRate)
        reversedFrom = try? c.decodeIfPresent(ReversedSource.self, forKey: .reversedFrom)
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(url, forKey: .url)
        try c.encode(name, forKey: .name)
        try c.encode(time: duration, forKey: .duration)
        try c.encode(displaySize, forKey: .displaySize)
        try c.encode(hasAudio, forKey: .hasAudio)
        try c.encode(hasVideo, forKey: .hasVideo)
        try c.encode(isImage, forKey: .isImage)
        try c.encodeIfPresent(frameRate, forKey: .frameRate)
        try c.encodeIfPresent(reversedFrom, forKey: .reversedFrom)
    }
}
