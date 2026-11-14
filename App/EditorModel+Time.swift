import AVFoundation
import EditorCore
import RenderEngine
import SwiftUI

/// Transitions between clips and playing with time: freeze frames, instant replay, backwards,
/// speed that changes gradually, and see-through B-roll.
extension EditorModel {
    // MARK: Transitions

    /// The transition last chosen, used by "Add Transition" (⌥T) and for new cuts.
    var preferredTransition: ClipTransition {
        let kind = UserDefaults.standard.string(forKey: "transitionKind").flatMap(TransitionKind.init(rawValue:)) ?? .dissolve
        let frames = UserDefaults.standard.integer(forKey: "transitionFrames")
        return ClipTransition(kind: kind, duration: frames > 0 ? CMTime(value: CMTimeValue(frames), timescale: Project.frameRate) : ClipTransition.defaultDuration)
    }

    private func remember(_ transition: ClipTransition) {
        UserDefaults.standard.set(transition.kind.rawValue, forKey: "transitionKind")
        UserDefaults.standard.set(Int(transition.duration.value), forKey: "transitionFrames")
    }

    /// The cut a transition command works on: after the selected main clip when one is selected
    /// and a clip follows it, otherwise the cut nearest the playhead.
    var transitionCut: Clip.ID? {
        if let id = selectedClipID, let index = project.timeline.index(of: id), index + 1 < project.timeline.clips.count,
           project.timeline.clips.count == 2 || timelineSelection.count == 1 {
            // With one clip selected, the nearer of its two cuts to the playhead.
            let range = project.timeline.range(of: id)
            if let range, index > 0, abs((currentTime - range.start).seconds) < abs((currentTime - range.end).seconds) {
                return project.timeline.clips[index - 1].id
            }
            return id
        }
        return project.timeline.clipBeforeCut(nearest: currentTime)
    }

    /// Puts `kind` on the cut after `clipID` (keeping the length already there, or the last one used).
    func setTransition(_ kind: TransitionKind?, after clipID: Clip.ID) {
        guard let kind else {
            apply("Remove Transition") { $0.setTransition(nil, after: clipID) }
            return
        }
        let length = project.transition(after: clipID)?.duration ?? preferredTransition.duration
        let transition = ClipTransition(kind: kind, duration: length)
        remember(transition)
        apply("Transition: \(kind.displayName)") { $0.setTransition(transition, after: clipID) }
    }

    func setTransitionLength(_ length: CMTime, after clipID: Clip.ID) {
        guard var transition = project.transition(after: clipID) else { return }
        transition.duration = ClipTransition.allowed(length)
        remember(transition)
        apply("Transition Length") { $0.setTransition(transition, after: clipID) }
    }

    /// ⌥T: the last transition used (a dissolve to begin with) on the cut nearest the playhead.
    func addTransition(_ kind: TransitionKind? = nil) {
        guard let cut = transitionCut else {
            alert = AlertMessage(title: "A transition needs two clips", message: "Transitions go between two clips. Add another clip, or split this one (B), then try again.")
            return
        }
        setTransition(kind ?? project.style?.transition?.kind ?? preferredTransition.kind, after: cut)
        showTip(.transitions)
    }

    /// The toolbar button: a transition on the nearest cut if it has none yet, then its picker.
    func chooseTransition() {
        guard let cut = transitionCut else {
            addTransition()
            return
        }
        if project.transition(after: cut) == nil { addTransition() }
        // The cut's marker has to be on screen before its pop-up can open from it.
        Task {
            try? await Task.sleep(for: .milliseconds(150))
            if project.transition(after: cut) != nil { transitionPickerCut = cut }
        }
    }

    func removeTransitionAtPlayhead() {
        guard let cut = transitionCut else { return }
        setTransition(nil, after: cut)
    }

    /// The same transition on every cut, or none anywhere.
    func setTransitionOnEveryCut(_ transition: ClipTransition?) {
        apply(transition == nil ? "Remove All Transitions" : "Transition on Every Cut") { $0.setTransitionOnEveryCut(transition) }
    }

    /// Plays from a second before the cut after `clipID` to a second after it.
    func playTransition(after clipID: Clip.ID) {
        guard let range = project.timeline.range(of: clipID) else { return }
        let second = CMTime(value: 1, timescale: 1)
        let around = CMTimeRange(start: max(.zero, range.end - second), end: min(duration, range.end + second))
        skimTime = nil
        seek(to: around.start)
        playRange = around
        player.play()
    }

    // MARK: Freeze frame and replay

    /// ⌥F: holds the picture at the playhead for three seconds.
    func addFreezeFrame() {
        var made: Clip.ID?
        apply("Add Freeze Frame") { made = $0.addFreezeFrame(at: currentTime) }
        guard let made else {
            NSSound.beep()
            return
        }
        selectedClipID = made
        showTip(.freezeFrame)
    }

    func setFreezeLength(_ length: CMTime, for clipID: Clip.ID) {
        guard let clip = project.anyClip(id: clipID), clip.isFrozen else { return }
        apply("Freeze Frame Length") { $0.trimClip(clipID, edge: .end, by: length.snappedToFrame() - clip.duration) }
    }

    /// The part "Instant Replay" works on: the picked range, the selected main clips, or the clip
    /// under the playhead.
    var replayRange: CMTimeRange? {
        if let range = timelineRange { return range }
        let ranges = timelineSelection.items.compactMap { item -> CMTimeRange? in
            if case .clip(let id) = item { project.timeline.range(of: id) } else { nil }
        }
        if let first = ranges.min(by: { $0.start < $1.start }), let last = ranges.max(by: { $0.end < $1.end }) {
            return CMTimeRange(start: first.start, end: last.end)
        }
        return project.clipRange(at: currentTime)
    }

    /// Shows the part once more straight after itself, at half speed.
    func addInstantReplay() {
        guard let range = replayRange else {
            NSSound.beep()
            return
        }
        var made: [Clip.ID] = []
        apply("Instant Replay") { made = $0.addInstantReplay(of: range) }
        guard let first = made.first else { return }
        timelineSelection = TimelineSelection(Set(made.map { TimelineItem.clip($0) }))
        if let start = project.timeline.range(of: first)?.start { seek(to: start) }
    }

    // MARK: Speed

    func setSmoothSpeed(_ on: Bool, for clipIDs: [Clip.ID]) {
        apply(on ? "Change Speed Gradually" : "Change Speed at Once") { project in
            for id in clipIDs { project.updateAnyClip(id) { $0.smoothSpeed = on } }
        }
    }

    /// Whether a main clip's speed changes gradually into a neighbour's (or would, switched on).
    func speedRampState(of clipID: Clip.ID) -> (applies: Bool, isOn: Bool) {
        guard let index = project.timeline.index(of: clipID) else { return (false, false) }
        let isOn = project.timeline.hasSpeedRamp(atClip: index)
        var smoothed = project.timeline
        for i in [index - 1, index, index + 1] where smoothed.clips.indices.contains(i) { smoothed.clips[i].smoothSpeed = true }
        return (smoothed.hasSpeedRamp(atClip: index), isOn)
    }

    // MARK: Backwards

    /// Turns clips round. A clip plays backwards from a backwards copy of its file, which is made
    /// first (on this Mac, in the background) when there isn't one yet; turning back is at once.
    func toggleBackwards(for clipIDs: [Clip.ID]) {
        let clips = clipIDs.compactMap { project.anyClip(id: $0) }.filter { project.canReverse($0) && reversing[$0.id] == nil }
        guard !clips.isEmpty else {
            NSSound.beep()
            return
        }
        let backwards = !clips.allSatisfy { project.isReversed($0) }
        let turning = clips.filter { project.isReversed($0) != backwards }
        Task {
            var copies: [MediaAsset] = []
            for clip in turning where project.counterpart(for: clip) == nil && !copies.contains(where: { covers($0, clip) }) {
                guard let copy = await makeBackwardsCopy(for: clip) else { return }
                copies.append(copy)
            }
            apply(backwards ? "Play Backwards" : "Play Forwards") { project in
                for copy in copies { project.addAsset(copy) }
                for clip in turning { project.flipDirection(of: clip.id) }
            }
            for copy in copies { loadPreviews(for: copy) }
        }
    }

    private func covers(_ copy: MediaAsset, _ clip: Clip) -> Bool {
        guard let from = copy.reversedFrom, from.assetID == clip.assetID else { return false }
        return from.range.start <= clip.sourceStart + .oneFrame && from.range.end >= clip.sourceRange.end - .oneFrame
    }

    /// Makes the backwards copy a clip needs, showing progress on the clip. Nil (after saying
    /// why) when it couldn't be made.
    private func makeBackwardsCopy(for clip: Clip) async -> MediaAsset? {
        guard let media = project.asset(id: clip.assetID), let part = project.partToReverse(for: clip) else { return nil }
        let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: "Shorts Editor/Backwards", directoryHint: .isDirectory)
        let url = folder.appending(path: "\(UUID().uuidString).mov")
        reversing[clip.id] = 0
        defer { reversing[clip.id] = nil }
        do {
            let id = clip.id
            try await Reverser.reverse(media.url, range: part, to: url) { fraction in
                Task { @MainActor in if self.reversing[id] != nil { self.reversing[id] = fraction } }
            }
            var copy = try await MediaProbe.probe(url)
            copy.name = "\(media.name) (backwards)"
            copy.reversedFrom = ReversedSource(assetID: media.id, range: part)
            return copy
        } catch is CancellationError {
            return nil
        } catch {
            Log.render.failure("makeBackwardsCopy", error)
            alert = AlertMessage(title: "The clip couldn't be turned round", message: error.localizedDescription)
            return nil
        }
    }

    // MARK: See-through pictures

    /// Sets how long a clip's picture takes to appear (`.start`) or to go (`.end`).
    func setPictureFade(_ edge: ClipEdge, to length: CMTime, for clipID: Clip.ID) {
        let length = length.snappedToFrame().clamped(.zero, Clip.maxFade)
        apply(length == .zero ? "Remove Picture Fade" : edge == .start ? "Fade Picture In" : "Fade Picture Out") { project in
            project.updateAnyClip(clipID) { clip in
                if edge == .start { clip.pictureFadeIn = length } else { clip.pictureFadeOut = length }
            }
        }
    }
}
