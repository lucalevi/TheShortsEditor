import CoreMedia
import Foundation

/// Items copied from the timeline with Copy or Cut (⌘C, ⌘X), with every setting they have, ready
/// to be pasted (⌘V) at the playhead of this Short or another one, as many times as wanted.
///
/// Titles, B-roll and sounds keep their distance from the earliest copied item, so a group pastes
/// the way it was laid out. Main clips are pasted one after another, starting at the playhead.
/// The music isn't copied: a Short has one song.
public struct TimelineClipboard: Equatable, Sendable {
    /// Main clips, in the order they play.
    public internal(set) var clips: [Clip] = []
    /// Titles, B-roll and sounds, each starting this long after the earliest copied item.
    public internal(set) var titles: [TextOverlay] = []
    public internal(set) var overlays: [Overlay] = []
    public internal(set) var sounds: [SoundClip] = []
    /// The files the items use, with what was heard in them, so they can be pasted into a Short
    /// that doesn't have them yet.
    public internal(set) var assets: [MediaAsset] = []
    var transcripts: [MediaAsset.ID: Transcript] = [:]

    public var count: Int { clips.count + titles.count + overlays.count + sounds.count }
    public var isEmpty: Bool { clips.isEmpty && titles.isEmpty && overlays.isEmpty && sounds.isEmpty }
}

extension Project {
    /// The items as a clipboard (the music, if among them, is left out).
    public func copy(_ items: Set<TimelineItem>) -> TimelineClipboard {
        var board = TimelineClipboard()
        let starts = timeline.clipStarts
        var earliest: CMTime?
        func note(_ time: CMTime) { earliest = earliest.map { min($0, time) } ?? time }

        for (index, clip) in timeline.clips.enumerated() where items.contains(.clip(clip.id)) {
            board.clips.append(clip)
            note(starts[index])
        }
        for title in titles where items.contains(.title(title.id)) {
            board.titles.append(title)
            note(title.start)
        }
        for overlay in overlays where items.contains(.overlay(overlay.id)) {
            board.overlays.append(overlay)
            note(overlay.start)
        }
        for sound in sounds where items.contains(.sound(sound.id)) {
            board.sounds.append(sound)
            note(sound.start)
        }
        let origin = earliest ?? .zero
        for i in board.titles.indices { board.titles[i].start = board.titles[i].start - origin }
        for i in board.overlays.indices { board.overlays[i].start = board.overlays[i].start - origin }
        for i in board.sounds.indices { board.sounds[i].start = board.sounds[i].start - origin }

        // A clip whose sound was detached plays its own sound again when that sound isn't copied
        // with it; a detached sound copied without its clip becomes an ordinary sound.
        let copiedClips = Set(board.clips.map(\.id))
        let copiedDetached = Set(board.sounds.compactMap(\.detachedFrom))
        for i in board.clips.indices where board.clips[i].soundDetached && !copiedDetached.contains(board.clips[i].id) {
            board.clips[i].soundDetached = false
        }
        for i in board.sounds.indices where board.sounds[i].detachedFrom.map({ !copiedClips.contains($0) }) ?? false {
            board.sounds[i].detachedFrom = nil
        }

        let used =
            Set(board.clips.map(\.assetID)).union(board.overlays.map(\.clip.assetID)).union(board.sounds.map(\.clip.assetID))
        board.assets = assets.filter { used.contains($0.id) }
        board.transcripts = transcripts.filter { used.contains($0.key) }
        return board
    }

    /// Pastes the clipboard at `time`: main clips are put in there (a clip under the playhead is
    /// split), the other items keep their places relative to it. Every pasted item is new (its
    /// own id), so it can be pasted again. Returns the pasted items, to select them.
    @discardableResult
    public mutating func paste(_ board: TimelineClipboard, at time: CMTime) -> Set<TimelineItem> {
        guard !board.isEmpty else { return [] }
        let time = time.snappedToFrame().clamped(.zero, duration)
        let assetIDs = adopt(board)
        var pasted: Set<TimelineItem> = []

        // New ids, with detached sounds still pointing at their (new) clip.
        var newClipIDs: [Clip.ID: Clip.ID] = [:]
        let clips = board.clips.map { clip in
            var copy = clip
            copy.id = UUID()
            copy.assetID = assetIDs[clip.assetID] ?? clip.assetID
            newClipIDs[clip.id] = copy.id
            return copy
        }
        if !clips.isEmpty {
            timeline.split(at: time)
            let index = timeline.locate(time)?.index ?? timeline.clips.count
            timeline.clips.insert(contentsOf: clips, at: index)
            pasted.formUnion(clips.map { .clip($0.id) })
        }
        for title in board.titles {
            var copy = title
            copy.id = UUID()
            titles.append(copy)
            moveTitle(copy.id, to: time + title.start)
            pasted.insert(.title(copy.id))
        }
        for overlay in board.overlays {
            var copy = overlay
            copy.clip.id = UUID()
            copy.clip.assetID = assetIDs[overlay.clip.assetID] ?? overlay.clip.assetID
            overlays.append(copy)
            moveOverlay(copy.id, to: time + overlay.start)
            pasted.insert(.overlay(copy.id))
        }
        for sound in board.sounds {
            var copy = sound
            copy.clip.id = UUID()
            copy.clip.assetID = assetIDs[sound.clip.assetID] ?? sound.clip.assetID
            copy.detachedFrom = sound.detachedFrom.flatMap { newClipIDs[$0] }
            sounds.append(copy)
            moveSound(copy.id, to: time + sound.start)
            pasted.insert(.sound(copy.id))
        }
        return pasted
    }

    /// Copies the items and pastes the copy right after them: clips after the last selected clip,
    /// the other items where the selection ends (⌘D). Returns the copies, to select them.
    @discardableResult
    public mutating func duplicate(_ items: Set<TimelineItem>) -> Set<TimelineItem> {
        let board = copy(items)
        guard !board.isEmpty else { return [] }
        let starts = timeline.clipStarts
        var end = CMTime.zero
        for (index, clip) in timeline.clips.enumerated() where items.contains(.clip(clip.id)) {
            end = max(end, starts[index] + clip.duration)
        }
        if board.clips.isEmpty {
            for title in titles where items.contains(.title(title.id)) { end = max(end, title.start + title.duration) }
            for overlay in overlays where items.contains(.overlay(overlay.id)) { end = max(end, overlay.start + overlay.duration) }
            for sound in sounds where items.contains(.sound(sound.id)) { end = max(end, sound.end) }
        }
        return paste(board, at: end)
    }

    /// Adds the clipboard's files this Short doesn't have yet (a file it already has, found by its
    /// place on disk, is used as it is). Returns the clipboard's file ids mapped to this Short's.
    private mutating func adopt(_ board: TimelineClipboard) -> [MediaAsset.ID: MediaAsset.ID] {
        var map: [MediaAsset.ID: MediaAsset.ID] = [:]
        for asset in board.assets {
            if let own = assets.first(where: { $0.id == asset.id || $0.url.standardizedFileURL == asset.url.standardizedFileURL }) {
                map[asset.id] = own.id
            } else {
                assets.append(asset)
                map[asset.id] = asset.id
                if transcripts[asset.id] == nil, let transcript = board.transcripts[asset.id] { transcripts[asset.id] = transcript }
            }
        }
        return map
    }
}

extension Timeline {
    /// Where each clip starts on the timeline.
    var clipStarts: [CMTime] {
        var starts: [CMTime] = []
        var cursor = CMTime.zero
        for clip in clips {
            starts.append(cursor)
            cursor = cursor + clip.duration
        }
        return starts
    }
}
