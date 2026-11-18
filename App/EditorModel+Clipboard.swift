import AppKit
import CoreMedia
import EditorCore
import Observation

/// What Cut, Copy and Paste hold: timeline items, shared by every window so they can be pasted
/// into another Short. (Text being typed uses the system pasteboard as usual.)
@Observable
final class TimelineClipboardStore {
    var contents: TimelineClipboard?
}

// Cut, Copy, Paste and Duplicate of timeline items (⌘X, ⌘C, ⌘V, ⌘D), as in iMovie and CapCut.
extension EditorModel {
    /// The selection without the music, which can't be copied (a Short has one song).
    private var copyableItems: Set<TimelineItem> {
        timelineSelection.items.filter { $0 != .music }
    }

    var canCopyItems: Bool { screen == .editor && !copyableItems.isEmpty }

    var canPasteItems: Bool {
        guard screen == .editor, let board = clipboard.contents, !board.isEmpty else { return false }
        // Titles, B-roll and sounds need clips to sit over.
        return !board.clips.isEmpty || !project.timeline.clips.isEmpty
    }

    func copyItems() {
        let board = project.copy(copyableItems)
        guard !board.isEmpty else { return NSSound.beep() }
        clipboard.contents = board
    }

    func cutItems() {
        let items = copyableItems
        let board = project.copy(items)
        guard !board.isEmpty else { return NSSound.beep() }
        clipboard.contents = board
        apply("Cut \(Self.itemsName(board))") { $0.remove(items) }
        timelineSelection = TimelineSelection()
    }

    /// Pastes at the playhead and selects what was pasted.
    func pasteItems() {
        guard canPasteItems, let board = clipboard.contents else { return NSSound.beep() }
        // Files from another Short: this one needs its own access to them, to save bookmarks.
        for asset in board.assets where project.asset(id: asset.id) == nil { media.open(asset.url) }
        let known = Set(project.assets.map(\.id))
        playback.player.pause()
        var pasted: Set<TimelineItem> = []
        let time = currentTime
        apply("Paste \(Self.itemsName(board))") { pasted = $0.paste(board, at: time) }
        for asset in project.assets where !known.contains(asset.id) { loadPreviews(for: asset) }
        select(pasted)
    }

    /// A copy of the selection right after it, selected (⌘D).
    func duplicateItems() {
        let items = copyableItems
        let board = project.copy(items)
        guard !board.isEmpty else { return NSSound.beep() }
        var pasted: Set<TimelineItem> = []
        apply("Duplicate \(Self.itemsName(board))") { pasted = $0.duplicate(items) }
        select(pasted)
    }

    /// A copy of one item at `time` (⌥-drag on the timeline), selected.
    func duplicate(_ item: TimelineItem, at time: CMTime) {
        let board = project.copy([item])
        guard !board.isEmpty else { return }
        var pasted: Set<TimelineItem> = []
        apply("Copy \(Self.itemsName(board))") { pasted = $0.paste(board, at: time) }
        select(pasted)
    }

    /// Selects what was pasted; a single title is also shown fully on screen, as when one is added.
    private func select(_ pasted: Set<TimelineItem>) {
        if pasted.count == 1, case .title(let id)? = pasted.first {
            selectTitle(id)
        } else {
            timelineSelection = TimelineSelection(pasted)
        }
    }

    /// "Title", "Clip", "3 Items"… for the Undo menu.
    static func itemsName(_ board: TimelineClipboard) -> String {
        guard board.count == 1 else { return "\(board.count) Items" }
        if !board.clips.isEmpty { return "Clip" }
        if let title = board.titles.first { return title.sticker != nil ? "Sticker" : "Title" }
        if !board.overlays.isEmpty { return "B-roll" }
        return "Sound"
    }
}
