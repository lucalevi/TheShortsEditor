import CoreMedia
import Foundation

// Stage E (media and finishing): settings for new clips, markers, sliding a clip's footage in the
// clip trimmer, and how big an export will be.

// MARK: - Settings for new clips

/// How new clips start, set in Settings (like iMovie's). The app sets `current` around each edit;
/// everything that makes a clip reads it, so the settings don't have to be passed through.
public struct NewClipSettings: Equatable, Sendable {
    /// How a new picture (photo, screenshot) is put on screen.
    public enum PicturePlacement: String, CaseIterable, Identifiable, Sendable {
        /// Upright pictures fill the screen, wide ones are shown whole (as for videos).
        case automatic
        case fill
        case fit
        /// Fills the screen and slowly zooms in (iMovie's Ken Burns).
        case slowZoom

        public var id: String { rawValue }

        public var displayName: String {
            switch self {
            case .automatic: "Automatic"
            case .fill: "Fill screen"
            case .fit: "Show all"
            case .slowZoom: "Slow zoom"
            }
        }
    }

    /// How long a new picture stays on screen.
    public var pictureLength: CMTime
    public var picturePlacement: PicturePlacement
    /// Footage filmed for slow motion (100 fps and more) starts slowed down.
    public var slowsDownSlowMotion: Bool

    public init(pictureLength: CMTime = MediaAsset.imageClipDuration, picturePlacement: PicturePlacement = .automatic, slowsDownSlowMotion: Bool = true) {
        self.pictureLength = Self.allowedPictureLength(pictureLength)
        self.picturePlacement = picturePlacement
        self.slowsDownSlowMotion = slowsDownSlowMotion
    }

    /// The picture lengths Settings offers, in seconds.
    public static let pictureLengthRange: ClosedRange<Double> = 0.5...10

    /// `length` kept inside the range Settings offers, on a whole frame.
    public static func allowedPictureLength(_ length: CMTime) -> CMTime {
        let seconds = length.seconds.isFinite ? length.seconds : MediaAsset.imageClipDuration.seconds
        let kept = min(max(seconds, pictureLengthRange.lowerBound), pictureLengthRange.upperBound)
        return CMTime(seconds: kept, preferredTimescale: 600).snappedToFrame()
    }

    /// The settings in force for the edit being made.
    @TaskLocal public static var current = NewClipSettings()
}

extension MediaAsset {
    /// The framing a new clip of this media starts with, as Settings say for pictures.
    func newClipFraming(_ settings: NewClipSettings) -> Framing {
        guard isImage else { return defaultFraming }
        switch settings.picturePlacement {
        case .automatic: return defaultFraming
        case .fill, .slowZoom: return .fill
        case .fit: return .fit
        }
    }
}

// MARK: - Markers

/// A named point on the timeline (M), to find a moment again and for edges to snap to. Like
/// titles, it stays on the same moment of the clip under it when the clips change.
public struct Marker: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public var time: CMTime
    public var name: String
    public var followsClip: Bool

    public init(id: UUID = UUID(), time: CMTime, name: String, followsClip: Bool = true) {
        self.id = id
        self.time = time
        self.name = name
        self.followsClip = followsClip
    }

    private enum CodingKeys: String, CodingKey { case id, time, name, followsClip }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        time = try c.decodeTime(forKey: .time)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        followsClip = try c.decodeIfPresent(Bool.self, forKey: .followsClip) ?? true
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(time: time, forKey: .time)
        try c.encode(name, forKey: .name)
        if !followsClip { try c.encode(followsClip, forKey: .followsClip) }
    }
}

public extension Project {
    func marker(id: Marker.ID) -> Marker? {
        markers.first { $0.id == id }
    }

    /// Adds a marker at `time` (on a whole frame, inside the Short), named "Marker 1", "Marker 2"…
    /// unless `name` is given. On the time of an existing marker, nothing is added and that one is
    /// returned.
    @discardableResult
    mutating func addMarker(at time: CMTime, name: String? = nil) -> Marker.ID {
        let time = time.snappedToFrame().clamped(.zero, duration).snappedToFrame()
        if let existing = markers.first(where: { $0.time == time }) { return existing.id }
        let used = Set(markers.map(\.name))
        var number = markers.count + 1
        while used.contains("Marker \(number)") { number += 1 }
        let marker = Marker(time: time, name: name ?? "Marker \(number)")
        markers.append(marker)
        markers.sort { $0.time < $1.time }
        return marker.id
    }

    mutating func renameMarker(_ id: Marker.ID, to name: String) {
        guard let index = markers.firstIndex(where: { $0.id == id }) else { return }
        let tidy = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !tidy.isEmpty { markers[index].name = String(tidy.prefix(60)) }
    }

    mutating func moveMarker(_ id: Marker.ID, to time: CMTime) {
        guard let index = markers.firstIndex(where: { $0.id == id }) else { return }
        markers[index].time = time.snappedToFrame().clamped(.zero, duration).snappedToFrame()
        markers.sort { $0.time < $1.time }
    }

    mutating func removeMarker(_ id: Marker.ID) {
        markers.removeAll { $0.id == id }
    }

    /// The marker before (or after) `time`.
    func marker(from time: CMTime, forward: Bool) -> Marker? {
        let time = time.snappedToFrame()
        let shown = markers.filter { $0.time <= duration }
        return forward ? shown.first { $0.time > time } : shown.last { $0.time < time }
    }
}

// MARK: - Sliding the footage (clip trimmer)

public extension Project {
    /// Shows a different stretch of the same file in a clip without changing its length or place
    /// (sliding the bright part in the clip trimmer). `delta` is in the file's time; it stops at
    /// the file's start and end. Pictures and freeze frames have nothing to slide. Returns false
    /// when nothing changed.
    @discardableResult
    mutating func slipClip(_ id: Clip.ID, by delta: CMTime) -> Bool {
        guard let clip = anyClip(id: id), let media = asset(id: clip.assetID), !media.isImage, !clip.isFrozen else { return false }
        let latest = max(.zero, media.duration - clip.sourceDuration)
        let start = (clip.sourceStart + delta).snappedToFrame().clamped(.zero, latest).snappedToFrame()
        guard start != clip.sourceStart else { return false }
        let shift = start - clip.sourceStart
        updateAnyClip(id) { clip in
            clip.sourceStart = start
            // Motion and volume points are in the file's time: they move with the footage, so they
            // keep their place in the clip.
            for i in clip.keyframes.indices { clip.keyframes[i].time = clip.keyframes[i].time + shift }
            for i in clip.volumeKeys.indices { clip.volumeKeys[i].time = clip.volumeKeys[i].time + shift }
        }
        return true
    }

    /// How far the footage of a clip can slide either way (in the file's time).
    func slipLimits(of id: Clip.ID) -> CMTimeRange? {
        guard let clip = anyClip(id: id), let media = asset(id: clip.assetID), !media.isImage, !clip.isFrozen else { return nil }
        let latest = max(.zero, media.duration - clip.sourceDuration)
        return CMTimeRange(start: .zero - clip.sourceStart, end: latest - clip.sourceStart)
    }
}

// MARK: - Export size

public enum ExportEstimate {
    /// About how many bytes a Short of `duration` takes at these bit rates (bits per second),
    /// with a little for the file's own bookkeeping.
    public static func bytes(duration: CMTime, videoBitRate: Int, audioBitRate: Int) -> Int64 {
        let seconds = max(duration.seconds, 0)
        return Int64(Double(videoBitRate + audioBitRate) * seconds / 8 * 1.01)
    }

    /// "About 45 MB", rounded so it doesn't look more exact than it is.
    public static func description(bytes: Int64) -> String {
        let mb = Double(bytes) / 1_000_000
        if mb < 1 { return "under 1 MB" }
        if mb < 10 { return "about \(mb.formatted(.number.precision(.fractionLength(1)))) MB" }
        return "about \(Int((mb / 5).rounded() * 5)) MB"
    }
}
