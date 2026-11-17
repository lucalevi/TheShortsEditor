import EditorCore
import SwiftUI

extension TimelineView {
    /// A main clip's right-click menu.
    @ViewBuilder
    func clipMenu(_ clip: Clip, index: Int) -> some View {
        Button("Split at Playhead") { model.splitAtPlayhead() }
        Button("Trim Start to Playhead") { model.trimToPlayhead(removing: .start) }
        Button("Trim End to Playhead") { model.trimToPlayhead(removing: .end) }
        Picker("Framing", selection: Binding(get: { clip.framing }, set: { model.setFraming($0, for: clip.id) })) {
            Text("Fill Screen").tag(Framing.fill)
            Text("Show All").tag(Framing.fit)
        }
        Button(model.isPunchedIn([clip]) ? "Remove Punch-In" : "Punch In") { model.togglePunchIn([clip.id]) }
            .disabled(clip.hasMotion)
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
