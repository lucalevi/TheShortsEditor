import CoreMedia
import Foundation

/// A piece of a source file placed on the timeline.
public struct Clip: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public var assetID: MediaAsset.ID
    /// Where in the source file this clip begins.
    public var sourceStart: CMTime
    public var duration: CMTime
    public var framing: Framing

    public init(id: UUID = UUID(), assetID: MediaAsset.ID, sourceStart: CMTime, duration: CMTime, framing: Framing = .fill) {
        self.id = id
        self.assetID = assetID
        self.sourceStart = sourceStart
        self.duration = duration
        self.framing = framing
    }

    public var sourceRange: CMTimeRange { CMTimeRange(start: sourceStart, duration: duration) }
}

/// The main storyline: clips play back to back with no gaps ("magnetic"), so removing a clip
/// closes the hole and moving one shifts the others.
public struct Timeline: Codable, Equatable, Sendable {
    public var clips: [Clip] = []

    public init(clips: [Clip] = []) {
        self.clips = clips
    }

    public var duration: CMTime {
        clips.reduce(.zero) { $0 + $1.duration }
    }

    public func index(of id: Clip.ID) -> Int? {
        clips.firstIndex { $0.id == id }
    }

    public func startTime(ofClipAt index: Int) -> CMTime {
        clips[..<index].reduce(.zero) { $0 + $1.duration }
    }

    /// Where the clip sits on the timeline.
    public func range(of id: Clip.ID) -> CMTimeRange? {
        guard let index = index(of: id) else { return nil }
        return CMTimeRange(start: startTime(ofClipAt: index), duration: clips[index].duration)
    }

    /// The clip playing at `time` and how far into it `time` is. A time exactly on a cut belongs
    /// to the clip that starts there.
    public func locate(_ time: CMTime) -> (index: Int, offset: CMTime)? {
        guard time >= .zero else { return nil }
        var start = CMTime.zero
        for (index, clip) in clips.enumerated() {
            let end = start + clip.duration
            if time < end { return (index, time - start) }
            start = end
        }
        return nil
    }

    /// Removes a clip and closes the gap.
    public mutating func remove(_ id: Clip.ID) {
        clips.removeAll { $0.id == id }
    }

    /// Moves a clip so it ends up at `destination` (an index into the timeline after removal).
    public mutating func move(_ id: Clip.ID, to destination: Int) {
        guard let from = index(of: id) else { return }
        let clip = clips.remove(at: from)
        clips.insert(clip, at: min(max(destination, 0), clips.count))
    }

    /// Cuts the clip under `time` in two, at the nearest frame. Returns the id of the new second
    /// half, or nil when `time` is on an existing cut or outside the timeline.
    @discardableResult
    public mutating func split(at time: CMTime) -> Clip.ID? {
        let time = time.snappedToFrame()
        guard let (index, offset) = locate(time), offset > .zero else { return nil }
        var first = clips[index]
        guard offset < first.duration else { return nil }
        let second = Clip(
            assetID: first.assetID,
            sourceStart: first.sourceStart + offset,
            duration: first.duration - offset,
            framing: first.framing
        )
        first.duration = offset
        clips[index] = first
        clips.insert(second, at: index + 1)
        return second.id
    }
}

extension Clip {
    private enum CodingKeys: String, CodingKey {
        case id, assetID, sourceStart, duration, framing
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        assetID = try c.decode(UUID.self, forKey: .assetID)
        sourceStart = try c.decodeTime(forKey: .sourceStart)
        duration = try c.decodeTime(forKey: .duration)
        framing = try c.decode(Framing.self, forKey: .framing)
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(assetID, forKey: .assetID)
        try c.encode(time: sourceStart, forKey: .sourceStart)
        try c.encode(time: duration, forKey: .duration)
        try c.encode(framing, forKey: .framing)
    }
}
