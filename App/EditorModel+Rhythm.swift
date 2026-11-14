import AVFoundation
import EditorCore
import RenderEngine
import SwiftUI

/// Rhythm (Stage I): the music's beats, Cut to the Beat, speed curves, smooth slow motion, clip
/// animations, and music that starts later or loops.
extension EditorModel {
    // MARK: Beats

    /// Shows the music's beats (and lets cuts snap to them). The first time, for a song that isn't
    /// the app's own, it listens for them.
    func setShowsBeats(_ on: Bool) {
        guard on else {
            editMusic("Hide Beats") { $0.showsBeats = false }
            return
        }
        withBeats { self.editMusic("Show Beats") { $0.showsBeats = true } }
    }

    /// Listens to the song again, replacing beats found before or set by hand.
    func findBeatsAgain() {
        guard project.music != nil else { return }
        findBeats(replacing: true) { self.editMusic("Find Beats") { $0.showsBeats = true } }
    }

    /// Runs `then` once the music's beats are known, finding them first when needed.
    private func withBeats(_ then: @escaping () -> Void) {
        guard project.music != nil else { return }
        if project.hasBeats { then() } else { findBeats(replacing: false, then: then) }
    }

    private func findBeats(replacing: Bool, then: @escaping () -> Void) {
        guard !findingBeats, let music = project.music, let song = project.asset(id: music.assetID) else { return }
        if replacing, music.mood != nil {
            // The app's own music: its beats are exact.
            apply("Find Beats") { $0.resetBeats() }
            then()
            return
        }
        findingBeats = true
        Task {
            let beats = await BeatDetector.beats(of: song.url)
            findingBeats = false
            guard project.music?.assetID == music.assetID else { return }
            guard !beats.isEmpty else {
                alert = AlertMessage(
                    title: "No steady beat found",
                    message:
                        "“\(song.name)” has no beat that can be followed. You can still add beats by hand: put the playhead on a beat and choose Sound ▸ Add Beat at Playhead."
                )
                return
            }
            apply("Find Beats") { $0.music?.beats = beats }
            then()
        }
    }

    func addBeatAtPlayhead() {
        var added = false
        apply("Add Beat") { added = $0.addBeat(atTimeline: currentTime) }
        if !added { NSSound.beep() }
    }

    func removeBeatAtPlayhead() {
        var removed = false
        apply("Remove Beat") { removed = $0.removeBeat(nearTimeline: currentTime) }
        if !removed { NSSound.beep() }
    }

    /// Whether a beat is near the playhead (for "Remove Beat at Playhead").
    var beatNearPlayhead: Bool {
        project.timelineBeats.contains { abs(($0.time - currentTime).seconds) <= 4.0 / Double(Project.frameRate) }
    }

    /// Trims the clips so every cut lands on a beat (finding the beats first when needed).
    func cutToBeat(_ spacing: BeatSpacing) {
        guard project.music != nil else {
            alert = AlertMessage(title: "Cut to the Beat needs music", message: "Add music first (Sound ▸ Add Music), then cut to its beat.")
            return
        }
        withBeats {
            var moved = 0
            self.apply("Cut to the Beat") { project in
                moved = project.cutToBeat(spacing)
                project.music?.showsBeats = true
            }
            if moved == 0 {
                self.alert = AlertMessage(
                    title: "The cuts are already on the beat",
                    message: "No cut could move to a beat: they are on one already, or the clips have no more footage to reach the nearest.")
            }
        }
    }

    // MARK: Music placement

    func setMusicTimelineStart(_ start: CMTime) {
        apply("Move Music") { $0.setMusicTimelineStart(start) }
    }

    func setMusicLoops(_ on: Bool) {
        editMusic(on ? "Loop Music" : "Play Music Once") { $0.loops = on }
    }

    // MARK: Speed curves

    func setSpeedCurve(_ shape: SpeedCurveShape?, for clipIDs: [Clip.ID]) {
        apply(shape.map { "Speed Curve: \($0.displayName)" } ?? "Remove Speed Curve") { project in
            for id in clipIDs { project.setSpeedCurve(shape, for: id) }
        }
        if shape != nil, let id = clipIDs.first, let range = project.timeline.range(of: id) { play(range) }
    }

    // MARK: Smooth slow motion

    func setSmoothSlowMotion(_ on: Bool, for clipIDs: [Clip.ID]) {
        apply(on ? "Smooth Slow Motion" : "Plain Slow Motion") { project in
            for id in clipIDs { project.updateAnyClip(id) { $0.smoothSlowMotion = on } }
        }
    }

    /// Whether a clip plays slower than its file has pictures for (so smoothing it would help).
    func canSmooth(_ clip: Clip) -> Bool {
        guard let media = project.asset(id: clip.assetID), media.hasVideo, !media.isImage, !clip.isFrozen else { return false }
        var probe = clip
        probe.smoothSlowMotion = true
        return FrameInterpolator.recipe(for: probe, media: media) != nil
    }

    /// Makes the smooth slow-motion copies the clips ask for and don't have yet, then rebuilds.
    func prepareMissingSmoothSlowMotion() {
        let clips = project.timeline.clips + project.overlays.map(\.clip)
        var needed: [(clip: Clip.ID, url: URL, recipe: FrameInterpolator.Recipe)] = []
        for clip in clips where clip.smoothSlowMotion && smoothing[clip.id] == nil {
            guard let media = project.asset(id: clip.assetID), !missingAssets.contains(media.id),
                let recipe = FrameInterpolator.recipe(for: clip, media: media),
                FrameInterpolator.existingCopy(for: clip, media: media) == nil
            else { continue }
            let copy = FrameInterpolator.copyURL(for: media.url, recipe: recipe)
            guard !unsmoothable.contains(copy), !needed.contains(where: { FrameInterpolator.copyURL(for: $0.url, recipe: $0.recipe) == copy }) else { continue }
            needed.append((clip.id, media.url, recipe))
        }
        guard !needed.isEmpty else { return }
        for item in needed { smoothing[item.clip] = 0 }
        Task {
            for item in needed {
                do {
                    _ = try await FrameInterpolator.makeCopy(of: item.url, recipe: item.recipe) { fraction in
                        Task { @MainActor in if self.smoothing[item.clip] != nil { self.smoothing[item.clip] = fraction } }
                    }
                } catch {
                    Log.audio.failure("prepareMissingSmoothSlowMotion", error)
                    unsmoothable.insert(FrameInterpolator.copyURL(for: item.url, recipe: item.recipe))
                    alert = AlertMessage(title: "The slow motion couldn't be smoothed", message: error.localizedDescription)
                }
                smoothing[item.clip] = nil
            }
            refreshPlayback()
        }
    }

    // MARK: Clip animations

    func setAnimation(_ kind: MotionAnimation?, entering: Bool, for clipIDs: [Clip.ID]) {
        apply(kind.map { "\(entering ? "Comes In" : "Goes Out"): \($0.displayName)" } ?? (entering ? "No Animation In" : "No Animation Out")) { project in
            for id in clipIDs {
                let current = project.anyClip(id: id).flatMap { entering ? $0.animationIn : $0.animationOut }
                project.setAnimation(kind.map { ClipAnimation($0, duration: current?.duration ?? ClipAnimation.defaultDuration) }, entering: entering, for: id)
            }
        }
        // Show it: play the clip's start or end.
        if kind != nil, let id = clipIDs.first, let start = project.timelineStart(ofClip: id), let clip = project.anyClip(id: id) {
            let length = CMTime(value: 3, timescale: 2)
            play(
                entering
                    ? CMTimeRange(start: start, duration: min(length, clip.duration))
                    : CMTimeRange(start: max(start, start + clip.duration - length), end: start + clip.duration))
        }
    }

    /// Plays `range` once, then stops.
    func play(_ range: CMTimeRange) {
        skimTime = nil
        seek(to: range.start)
        playRange = range
        player.play()
    }

    func setAnimationLength(_ length: CMTime, entering: Bool, for clipID: Clip.ID) {
        guard let clip = project.anyClip(id: clipID), var animation = entering ? clip.animationIn : clip.animationOut else { return }
        animation.duration = length
        apply("Animation Length") { $0.setAnimation(animation, entering: entering, for: clipID) }
    }
}
