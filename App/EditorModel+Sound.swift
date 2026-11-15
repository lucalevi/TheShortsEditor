import AVFoundation
import EditorCore
import RenderEngine
import SwiftUI

/// Sound like iMovie's: the volume line and its points, fades, detaching a clip's sound, voice
/// effects and EQ.
extension EditorModel {
    // MARK: Volume line and fades

    /// Sets how long a clip's sound fades in (`.start`) or out (`.end`).
    func setFade(_ edge: ClipEdge, to length: CMTime, for clipIDs: [Clip.ID]) {
        let length = length.snappedToFrame().clamped(.zero, Clip.maxFade)
        apply(length == .zero ? "Remove Fade" : edge == .start ? "Fade In" : "Fade Out") { project in
            for id in clipIDs {
                project.updateAnyClip(id) { clip in
                    let other = edge == .start ? clip.fadeOut : clip.fadeIn
                    let fitted = min(length, max(clip.duration - other, .zero))
                    if edge == .start { clip.fadeIn = fitted } else { clip.fadeOut = fitted }
                }
            }
        }
    }

    /// Adds a point to a clip's volume line at `offset` into it (⌥-click on the line).
    func addVolumePoint(to clipID: Clip.ID, atOffset offset: CMTime) {
        apply("Add Volume Point") { project in
            project.updateAnyClip(clipID) { $0.addVolumeKey(atOffset: offset.snappedToFrame()) }
        }
    }

    /// Adds a point at the playhead to the selected main clip's volume line.
    func addVolumePointAtPlayhead() {
        guard let (index, offset) = project.timeline.locate(currentTime) else { return }
        addVolumePoint(to: project.timeline.clips[index].id, atOffset: offset)
    }

    func setVolumePoint(_ keyID: VolumeKey.ID, of clipID: Clip.ID, level: Double) {
        apply("Change Volume Point") { project in
            project.updateAnyClip(clipID) { clip in
                guard let index = clip.volumeKeys.firstIndex(where: { $0.id == keyID }) else { return }
                clip.volumeKeys[index].level = Clip.clampedLevel(level)
            }
        }
    }

    func removeVolumePoint(_ keyID: VolumeKey.ID, of clipID: Clip.ID) {
        apply("Remove Volume Point") { project in
            project.updateAnyClip(clipID) { $0.volumeKeys.removeAll { $0.id == keyID } }
        }
    }

    func removeVolumePoints(of clipIDs: [Clip.ID]) {
        apply("Remove Volume Points") { project in
            for id in clipIDs { project.updateAnyClip(id) { $0.volumeKeys = [] } }
        }
    }

    /// Where a clip's sound is loud enough to crackle, as offsets into the clip.
    func tooLoudRanges(of clip: Clip, limit: Float = AudioMix.distortionLevel) -> [CMTimeRange] {
        guard let levels = audioLevels[clip.assetID] else { return [] }
        return AudioMix.tooLoudRanges(of: clip, levels: levels, limit: limit)
    }

    // MARK: Detaching

    /// The main clips Detach Sound works on: the selected ones with sound still attached.
    var detachableClips: [Clip] {
        selectedClips.filter { clip in
            !clip.soundDetached && project.timeline.index(of: clip.id) != nil
                && project.asset(id: clip.assetID).map { $0.hasAudio && !$0.isImage } == true
        }
    }

    /// Puts the sound of the selected main clips on the sound row, where it can be trimmed and
    /// moved on its own: to start before the picture, or carry on after it.
    func detachSound(of clipIDs: [Clip.ID]? = nil) {
        let ids = clipIDs ?? detachableClips.map(\.id)
        guard !ids.isEmpty else { return }
        var made: Clip.ID?
        apply("Detach Sound") { project in
            for id in ids { made = project.detachSound(of: id) ?? made }
        }
        if ids.count == 1, let made { selection = .sound(made) }
    }

    func reattachSound(of clipID: Clip.ID) {
        apply("Bring Sound Back") { $0.reattachSound(of: clipID) }
    }

    // MARK: Voice effects and EQ

    /// Sets the voice effect of clips (nil for none). The effect is made first (on this Mac, in
    /// the background), then the change is made, so the sound is right as soon as it is heard.
    func setVoiceEffect(_ effect: VoiceEffect?, for clipIDs: [Clip.ID]) {
        changeProcessedSound(effect == nil ? "No Voice Effect" : "Voice Effect: \(effect!.displayName)", for: clipIDs) { $0.voiceEffect = effect }
    }

    func setEqualizer(_ eq: SoundEQ?, for clipIDs: [Clip.ID]) {
        changeProcessedSound(eq == nil ? "No EQ" : "EQ: \(eq!.displayName)", for: clipIDs) { $0.equalizer = eq }
    }

    private func changeProcessedSound(_ name: String, for clipIDs: [Clip.ID], _ change: @escaping (inout Clip) -> Void) {
        let changed: [(Clip, MediaAsset)] = clipIDs.compactMap { id in
            guard var clip = project.anyClip(id: id), let media = project.asset(id: clip.assetID) else { return nil }
            change(&clip)
            return (clip, media)
        }
        Task {
            for (clip, media) in changed where clip.needsProcessedSound {
                guard await makeProcessedSound(for: clip, media: media) else { return }
            }
            apply(name) { project in for id in clipIDs { project.updateAnyClip(id, change) } }
        }
    }

    /// Makes the processed sound `clip` needs (if it isn't made yet), showing progress on the
    /// clip. Returns false (after saying why) when it couldn't be made.
    @discardableResult
    func makeProcessedSound(for clip: Clip, media: MediaAsset) async -> Bool {
        let base = SoundProcessor.baseURL(for: clip, media: media)
        let recipe = SoundProcessor.Recipe(clip)
        guard media.hasAudio, !media.isImage, !recipe.isEmpty,
            SoundProcessor.existingProcessedURL(for: base, recipe: recipe) == nil
        else { return true }
        guard !tasks.isRunning(.processedSound(clip.id)) else { return false }
        do {
            _ = try await tasks.run(.processedSound(clip.id), title: "Making the sound of “\(media.name)”") { progress in
                try await SoundProcessor.process(base, recipe: recipe) { progress($0) }
            }
            return true
        } catch is CancellationError {
            return false
        } catch {
            Log.audio.failure("makeProcessedSound", error)
            alert = AlertMessage(title: "The sound effect couldn't be made", message: error.localizedDescription)
            return false
        }
    }

    /// Makes processed sounds that clips use but that aren't on this Mac (a Short opened from
    /// elsewhere, a cleared cache, voice clean-up switched on later), then plays them.
    func prepareMissingProcessedSounds() {
        var needed: [String: (Clip, MediaAsset)] = [:]
        for clip in project.timeline.clips + project.overlays.map(\.clip) + project.sounds.map(\.clip) where clip.needsProcessedSound {
            guard let media = project.asset(id: clip.assetID), media.hasAudio, !media.isImage, !missingAssets.contains(media.id) else { continue }
            let base = SoundProcessor.baseURL(for: clip, media: media)
            let recipe = SoundProcessor.Recipe(clip)
            guard SoundProcessor.existingProcessedURL(for: base, recipe: recipe) == nil else { continue }
            let key = SoundProcessor.processedURL(for: base, recipe: recipe).path
            if tasks.mayStart(.processedSound(clip.id)) { needed[key] = (clip, media) }
        }
        guard !needed.isEmpty else { return }
        Task {
            for (clip, media) in needed.values {
                await makeProcessedSound(for: clip, media: media)
            }
            refreshPlayback()
        }
    }

    // MARK: Sounds

    /// Puts a built-in sound effect at the playhead.
    func addSoundEffect(_ effect: SoundEffect) {
        guard !project.timeline.clips.isEmpty else { return }
        Task {
            do {
                let url = try effect.fileURL()
                var media = project.assets.first { $0.url.standardizedFileURL == url.standardizedFileURL }
                if media == nil { media = try await MediaProbe.probe(url) }
                guard let media else { return }
                var id: Clip.ID?
                apply("Add \(effect.displayName)") { project in
                    let assetID = project.addAsset(media)
                    id = project.addSound(of: assetID, at: currentTime)
                }
                if let id { selection = .sound(id) }
                loadPreviewsIfNeeded(media)
            } catch {
                Log.audio.failure("addSoundEffect", error)
                alert = AlertMessage(title: "The sound couldn't be made", message: error.localizedDescription)
            }
        }
    }

    /// Puts a sound file from Media at the playhead, as a sound effect.
    func addSound(_ assetID: MediaAsset.ID) {
        guard !project.timeline.clips.isEmpty else { return }
        var id: Clip.ID?
        apply("Add Sound") { id = $0.addSound(of: assetID, at: currentTime) }
        if let id { selection = .sound(id) }
    }

    func previewSoundEffect(_ effect: SoundEffect) {
        guard let url = try? effect.fileURL() else { return }
        effectPlayer = try? AVAudioPlayer(contentsOf: url)
        effectPlayer?.play()
    }

    func moveSound(_ id: Clip.ID, to start: CMTime) {
        apply("Move Sound") { $0.moveSound(id, to: start) }
    }

    func trimSound(_ id: Clip.ID, edge: ClipEdge, by delta: CMTime) {
        apply("Trim Sound") { $0.trimSound(id, edge: edge, by: delta) }
    }

    func selectSound(_ id: Clip.ID) {
        selection = .sound(id)
        guard let sound = project.sound(id: id), let range = sound.audibleRange(in: project) else { return }
        if !range.containsTime(currentTime) {
            playback.player.pause()
            playback.seek(to: range.start)
        }
    }

    var selectedSound: SoundClip? {
        if case .sound(let id)? = selection { project.sound(id: id) } else { nil }
    }
}
