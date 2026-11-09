import CoreMedia

/// Something that can be selected on the timeline.
public enum TimelineItem: Hashable, Sendable {
    case clip(Clip.ID)
    case title(TextOverlay.ID)
    /// A clip over the main clips (B-roll, picture-in-picture).
    case overlay(Clip.ID)
    /// A sound effect or voice-over.
    case sound(Clip.ID)
    case music
}

/// The rows of the timeline, top to bottom, for picking items with a rectangle.
public enum TimelineLane: Hashable, Sendable, CaseIterable {
    case titles, overlays, clips, sounds, music
}

/// What is selected on the timeline: any mix of clips, titles and the music.
///
/// Clicking follows the Finder and Final Cut Pro: a plain click selects one item, ⌘-click adds or
/// removes one, and ⇧-click adds every clip between the last clicked clip and this one.
public struct TimelineSelection: Equatable, Sendable {
    public private(set) var items: Set<TimelineItem> = []
    /// Where a ⇧-click range starts: the item last clicked without ⇧.
    public private(set) var anchor: TimelineItem?

    public enum ClickKind: Sendable {
        /// Select only this item.
        case replace
        /// ⌘: add it, or remove it if it was selected.
        case toggle
        /// ⇧: add the clips from the anchor to this one (other items are just added).
        case extend
    }

    public init(_ items: Set<TimelineItem> = []) {
        self.items = items
        anchor = items.count == 1 ? items.first : nil
    }

    public var isEmpty: Bool { items.isEmpty }
    public var count: Int { items.count }
    public func contains(_ item: TimelineItem) -> Bool { items.contains(item) }

    /// The item when exactly one is selected.
    public var single: TimelineItem? { items.count == 1 ? items.first : nil }

    public mutating func click(_ item: TimelineItem, _ kind: ClickKind, in timeline: Timeline) {
        switch kind {
        case .replace:
            items = [item]
            anchor = item
        case .toggle:
            if items.remove(item) == nil { items.insert(item) }
            anchor = item
        case .extend:
            guard case .clip(let to) = item, case .clip(let from)? = anchor,
                  let a = timeline.index(of: from), let b = timeline.index(of: to)
            else {
                items.insert(item)
                if anchor == nil { anchor = item }
                return
            }
            for clip in timeline.clips[min(a, b)...max(a, b)] { items.insert(.clip(clip.id)) }
        }
    }

    /// Selects what a rectangle covers, adding to the current selection when `adding` (⌘ or ⇧ held).
    public mutating func select(_ covered: Set<TimelineItem>, adding: Bool) {
        items = adding ? items.union(covered) : covered
        if !adding { anchor = covered.count == 1 ? covered.first : nil }
    }

    /// Drops items that no longer exist in the project (after an undo, a delete, a new project).
    public mutating func prune(to project: Project) {
        items = items.filter(project.contains)
        if let anchor, !project.contains(anchor) { self.anchor = nil }
    }
}

public extension Project {
    func contains(_ item: TimelineItem) -> Bool {
        switch item {
        case .clip(let id): timeline.index(of: id) != nil
        case .title(let id): title(id: id) != nil
        case .overlay(let id): overlay(id: id) != nil
        case .sound(let id): sound(id: id) != nil
        case .music: music != nil
        }
    }

    /// Every item on the timeline, for Select All.
    var allTimelineItems: Set<TimelineItem> {
        var items = Set(timeline.clips.map { TimelineItem.clip($0.id) })
        items.formUnion(titles.map { .title($0.id) })
        items.formUnion(overlays.map { .overlay($0.id) })
        items.formUnion(sounds.map { .sound($0.id) })
        if musicRange != nil { items.insert(.music) }
        return items
    }

    /// The items in the given lanes that overlap a stretch of time (a rectangle drawn on the timeline).
    func timelineItems(overlapping range: CMTimeRange, in lanes: Set<TimelineLane>) -> Set<TimelineItem> {
        func overlaps(_ start: CMTime, _ end: CMTime) -> Bool { start < range.end && end > range.start }
        var items: Set<TimelineItem> = []
        if lanes.contains(.clips) {
            var start = CMTime.zero
            for clip in timeline.clips {
                let end = start + clip.duration
                if overlaps(start, end) { items.insert(.clip(clip.id)) }
                start = end
            }
        }
        if lanes.contains(.titles) {
            for title in titles where overlaps(title.start, title.end) { items.insert(.title(title.id)) }
        }
        if lanes.contains(.overlays) {
            for overlay in overlays where overlaps(overlay.start, overlay.end) { items.insert(.overlay(overlay.id)) }
        }
        if lanes.contains(.sounds) {
            for sound in sounds where overlaps(sound.start, sound.end) { items.insert(.sound(sound.id)) }
        }
        if lanes.contains(.music), let music = musicRange, overlaps(music.start, music.end) {
            items.insert(.music)
        }
        return items
    }

    /// Removes clips (closing the gaps), overlays, titles and the music in one go.
    mutating func remove(_ items: Set<TimelineItem>) {
        for item in items {
            switch item {
            case .clip(let id): timeline.remove(id)
            case .title(let id): removeTitle(id)
            case .overlay(let id): removeOverlay(id)
            case .sound(let id): removeSound(id)
            case .music: music = nil
            }
        }
    }
}
