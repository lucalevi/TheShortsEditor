import AppKit
import EditorCore

/// Moving main clips to another place in the storyline: by dragging (several selected clips move
/// together) or with Clip ▸ Move Clip Earlier / Later.
extension EditorModel {
    func moveClip(_ clipID: Clip.ID, to index: Int) {
        moveClips([clipID], to: index)
    }

    /// Moves main clips together so the first lands at `destination` among the others.
    func moveClips(_ ids: Set<Clip.ID>, to destination: Int) {
        guard project.timeline.reordered(moving: ids, to: destination).map(\.id) != project.timeline.clips.map(\.id) else { return }
        apply(ids.count > 1 ? "Move Clips" : "Move Clip") { $0.timeline.move(ids, to: destination) }
    }

    /// The main clips selected on the timeline.
    var selectedMainClipIDs: Set<Clip.ID> {
        Set(timelineSelection.items.compactMap { if case .clip(let id) = $0 { id } else { nil } })
    }

    /// What dragging (or right-clicking) `id` moves: every selected main clip when it is one of
    /// them, else just it.
    func clipsMovedWith(_ id: Clip.ID) -> Set<Clip.ID> {
        let selected = selectedMainClipIDs
        return selected.contains(id) ? selected : [id]
    }

    /// Clip ▸ Move Earlier / Move Later: the selected clips one place along.
    func moveSelectedClips(by step: Int) {
        moveClips(selectedMainClipIDs, by: step)
    }

    func moveClips(_ ids: Set<Clip.ID>, by step: Int) {
        guard let destination = project.timeline.stepDestination(moving: ids, by: step) else {
            NSSound.beep()
            return
        }
        moveClips(ids, to: destination)
    }

    func canMoveSelectedClips(by step: Int) -> Bool {
        canMoveClips(selectedMainClipIDs, by: step)
    }

    func canMoveClips(_ ids: Set<Clip.ID>, by step: Int) -> Bool {
        project.timeline.stepDestination(moving: ids, by: step) != nil
    }
}
