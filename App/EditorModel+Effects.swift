import CoreMedia
import EditorCore
import SwiftUI

/// Effects on clips (Stage J): shake, flash, glitch and the rest, attached to a clip.
extension EditorModel {
    func addEffect(_ kind: EffectKind, to clipIDs: [Clip.ID]) {
        apply("Add \(kind.displayName)") { $0.addEffect(kind, to: clipIDs) }
        // Show it: play the part of the clip it is on.
        guard let id = clipIDs.first, let clip = project.anyClip(id: id), let start = project.timelineStart(ofClip: id),
            let effect = clip.effects.first(where: { $0.kind == kind })
        else { return }
        playEffect(effect, of: clip, at: start)
    }

    func updateEffect(_ effectID: ClipEffect.ID, on clipID: Clip.ID, _ actionName: String, _ change: @escaping (inout ClipEffect) -> Void) {
        apply(actionName) { $0.updateEffect(effectID, on: clipID, change) }
    }

    func removeEffect(_ effectID: ClipEffect.ID, from clipID: Clip.ID) {
        apply("Remove Effect") { $0.removeEffect(effectID, from: clipID) }
    }

    /// Plays the part of `clip` (starting at `start` on the timeline) that `effect` is on.
    func playEffect(_ effect: ClipEffect, of clip: Clip, at start: CMTime) {
        let length = min(effect.length, clip.duration)
        let range: CMTimeRange =
            switch effect.part {
            case .wholeClip: CMTimeRange(start: start, duration: min(clip.duration, CMTime(value: 3, timescale: 1)))
            case .start: CMTimeRange(start: start, duration: min(clip.duration, length + CMTime(value: 1, timescale: 2)))
            case .end: CMTimeRange(start: max(start, start + clip.duration - length - CMTime(value: 1, timescale: 2)), end: start + clip.duration)
            }
        play(range)
    }
}
