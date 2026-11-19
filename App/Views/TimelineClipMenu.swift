import CoreMedia
import EditorCore
import SwiftUI

extension TimelineView {
    /// A main clip's right-click menu.
    @ViewBuilder
    func clipMenu(_ clip: Clip, index: Int) -> some View {
        clipboardButtons(for: .clip(clip.id))
        Button("Split at Playhead") { model.splitAtPlayhead() }
        Button("Trim Start to Playhead") { model.trimToPlayhead(removing: .start) }
        Button("Trim End to Playhead") { model.trimToPlayhead(removing: .end) }
        Picker("Framing", selection: Binding(get: { clip.framing }, set: { model.setFraming($0, for: clip.id) })) {
            Text("Fill Screen").tag(Framing.fill)
            Text("Show All").tag(Framing.fit)
        }
        Button(model.isPunchedIn([clip]) ? "Remove Punch-In" : "Punch In") { model.togglePunchIn([clip.id]) }
            .disabled(clip.hasMotion)
        let moving = model.clipsMovedWith(clip.id)
        Button(moving.count > 1 ? "Move Clips Earlier" : "Move Earlier") { model.moveClips(moving, by: -1) }
            .disabled(!model.canMoveClips(moving, by: -1))
        Button(moving.count > 1 ? "Move Clips Later" : "Move Later") { model.moveClips(moving, by: 1) }
            .disabled(!model.canMoveClips(moving, by: 1))
        Divider()
        if index + 1 < model.project.timeline.clips.count {
            Menu("Transition into the Next Clip") {
                Button("None") { model.setTransition(nil, after: clip.id) }
                Divider()
                ForEach(TransitionKind.allCases) { kind in
                    Button(kind.displayName) { model.setTransition(kind, after: clip.id) }
                }
            }
        }
        Button("Add Freeze Frame at Playhead") { model.addFreezeFrame() }
        Button("Instant Replay") {
            model.selectedClipID = clip.id
            model.addInstantReplay()
        }
        if model.project.canReverse(clip) {
            Button(model.project.isReversed(clip) ? "Play Forwards" : "Play Backwards") { model.toggleBackwards(for: [clip.id]) }
        }
        Divider()
        if clip.isFrozen {
            // A freeze frame has no sound.
        } else if clip.soundDetached {
            Button("Bring Sound Back") { model.reattachSound(of: clip.id) }
        } else if model.audioLevels[clip.assetID] != nil {
            Button("Detach Sound") { model.detachSound(of: [clip.id]) }
            if !clip.volumeKeys.isEmpty { Button("Remove Volume Points") { model.removeVolumePoints(of: [clip.id]) } }
        }
        Divider()
        settingsMenuItems(for: .clip(clip.id), clipID: clip.id)
        if model.timelineRange != nil {
            Divider()
            rangeMenuItems
        }
        Divider()
        deleteButton(for: .clip(clip.id), single: "Delete Clip")
    }
}

extension TimelineView {
    /// Cut, Copy, Paste and Duplicate at the top of every item's right-click menu. They act on the
    /// selection when the item is part of it, otherwise on the item alone.
    @ViewBuilder
    func clipboardButtons(for item: EditorModel.Selection) -> some View {
        let select = { if !model.isSelected(item) { model.selection = item } }
        Button("Cut") {
            select()
            model.cutItems()
        }
        Button("Copy") {
            select()
            model.copyItems()
        }
        Button("Paste at Playhead") { model.pasteItems() }
            .disabled(!model.canPasteItems)
        Button("Duplicate") {
            select()
            model.duplicateItems()
        }
        Divider()
    }

    /// In a right-click menu: deletes all selected items when this one is among several selected,
    /// otherwise just this one.
    @ViewBuilder
    func deleteButton(for item: EditorModel.Selection, single: String) -> some View {
        let count = model.timelineSelection.count
        if model.isSelected(item), count > 1 {
            Button("Delete \(count) Selected Items", role: .destructive) { model.deleteSelection() }
        } else {
            Button(single, role: .destructive) {
                model.selection = item
                model.deleteSelection()
            }
        }
    }
}

// The timeline's drags, as they are under way.
extension TimelineView {
    struct BlockDrag {
        enum Kind { case move, start, end }
        var item: TimelineItem
        var kind: Kind
        /// How far it moved, already stuck to an edge when close to one.
        var delta: CMTime
    }

    struct Reorder {
        /// The main clips being moved.
        var ids: Set<Clip.ID>
        /// Where the drag started and where the pointer was last reported, in content coordinates.
        var startX: CGFloat
        var pointerX: CGFloat
        /// Where the timeline was scrolled when `pointerX` was reported.
        var scrollX: CGFloat
        /// Where they land: an index among the other clips.
        var destination: Int
        /// Escape was pressed: nothing happens when the mouse is let go.
        var isCancelled = false
    }

    struct ClipTrim {
        var id: Clip.ID
        var edge: ClipEdge
        var delta: CMTime
    }
}
