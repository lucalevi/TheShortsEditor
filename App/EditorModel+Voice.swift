import AVFoundation
import EditorCore
import RenderEngine
import SwiftUI

/// Cleaning up a voice, and recording a voice-over.
extension EditorModel {
    // MARK: Voice clean-up

    /// Turns voice clean-up on or off for clips. Turning it on cleans each file once (on this
    /// Mac, in the background) before the change is made.
    func setCleansVoice(_ on: Bool, for clipIDs: [Clip.ID]) {
        guard on else {
            apply("Original Sound") { project in for id in clipIDs { project.updateAnyClip(id) { $0.cleansVoice = false } } }
            return
        }
        guard VoiceCleaner.isAvailable else {
            alert = AlertMessage(title: "Voice clean-up isn't available", message: "This Mac doesn't have Apple's voice isolation.")
            return
        }
        let assets = Set(clipIDs.compactMap { project.anyClip(id: $0)?.assetID }).compactMap(project.asset(id:)).filter(\.hasAudio)
        Task {
            for asset in assets where VoiceCleaner.existingCleanedURL(for: asset.url) == nil && !tasks.isRunning(.voiceCleanUp(asset.id)) {
                do {
                    _ = try await tasks.run(.voiceCleanUp(asset.id), title: "Cleaning up the voice of “\(asset.name)”") { progress in
                        try await VoiceCleaner.clean(asset.url) { progress($0) }
                    }
                } catch is CancellationError {
                    return
                } catch {
                    Log.audio.failure("setCleansVoice", error)
                    alert = AlertMessage("The voice couldn't be cleaned up", error: error, retry: { self.setCleansVoice(on, for: clipIDs) })
                    return
                }
            }
            apply("Clean Up Voice") { project in for id in clipIDs { project.updateAnyClip(id) { $0.cleansVoice = true } } }
        }
    }

    // MARK: Voice-over

    /// While recording a voice-over: counting down, then recording from a time.
    enum VoiceOverState: Equatable {
        case countdown(Int)
        case recording(from: CMTime)
    }

    /// A voice-over that was just recorded.
    struct VoiceOverTake: Equatable {
        var soundID: Clip.ID
        /// The microphone heard almost nothing (wrong microphone, or muted).
        var isQuiet = false
    }

    var isRecordingVoiceOver: Bool { voiceOver != nil }

    /// The take offered for Listen / Retake / Delete / Keep: the one just recorded, while it is
    /// still on the timeline and selected (clicking anything else keeps it).
    var reviewedVoiceOver: (take: VoiceOverTake, sound: SoundClip)? {
        guard voiceOver == nil, let take = voiceOverTake, selection == .sound(take.soundID), let sound = project.sound(id: take.soundID) else { return nil }
        return (take, sound)
    }

    /// Counts down 3-2-1, then records from the microphone while the Short plays (silently) from
    /// the playhead. Stop with the button, Space, or at the end of the Short.
    func startVoiceOver() {
        voiceOverTake = nil
        record()
    }

    /// Records the take under review again, from where it starts. The old take stays until the new
    /// one is made, and is then replaced in one undo step.
    func retakeVoiceOver() {
        guard let (take, sound) = reviewedVoiceOver else { return }
        retakeOf = take.soundID
        playback.seek(to: sound.start)
        record()
    }

    /// Plays the Short over the take, with its sound.
    func listenToVoiceOver() {
        guard let (_, sound) = reviewedVoiceOver else { return }
        playback.play(CMTimeRange(start: sound.start, duration: sound.duration))
    }

    /// Takes the take under review off the timeline, and its file out of the Short.
    func deleteVoiceOver() {
        guard let (take, sound) = reviewedVoiceOver else { return }
        playback.pause()
        apply("Delete Voice-Over") { project in project.removeTake(take.soundID, assetID: sound.clip.assetID) }
        voiceOverTake = nil
        selection = nil
    }

    /// Done reviewing: the take stays as it is.
    func keepVoiceOver() {
        voiceOverTake = nil
    }

    /// How loud the microphone is right now, 0 (silence) to 1, while recording.
    func microphoneLevel() -> Double {
        guard let recorder, recorder.isRecording else { return 0 }
        recorder.updateMeters()
        return Double(min(max((recorder.averagePower(forChannel: 0) + 55) / 55, 0), 1))
    }

    private func record() {
        guard voiceOver == nil, !project.timeline.clips.isEmpty else { return }
        playback.pause()
        Task {
            guard await AVCaptureDevice.requestAccess(for: .audio) else {
                retakeOf = nil
                alert = AlertMessage(
                    title: "The microphone is off for Shorts Editor",
                    message: "Turn it on in System Settings ▸ Privacy & Security ▸ Microphone, then try again.", kind: .privacy(.microphone))
                return
            }
            if currentTime >= duration - .oneFrame { playback.seek(to: .zero) }
            for n in [3, 2, 1] {
                voiceOver = .countdown(n)
                try? await Task.sleep(for: .seconds(1))
                guard voiceOver == .countdown(n) else { return }
            }
            do {
                let folder = AppEnvironment.appFolder.appending(path: "Voice-overs", directoryHint: .isDirectory)
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                let stamp = Date.now.formatted(.iso8601.year().month().day().time(includingFractionalSeconds: false)).replacingOccurrences(of: ":", with: ".")
                let url = folder.appending(path: "Voice-over \(stamp).m4a")
                let recorder = try AVAudioRecorder(
                    url: url,
                    settings: [
                        AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 48_000, AVNumberOfChannelsKey: 1, AVEncoderBitRateKey: 192_000,
                    ])
                recorder.isMeteringEnabled = true
                guard recorder.record() else { throw CocoaError(.fileWriteUnknown) }
                self.recorder = recorder
                voiceOverURL = url
                voiceOver = .recording(from: currentTime.snappedToFrame())
                playback.player.isMuted = true
                playback.player.play()
            } catch {
                Log.audio.failure("startVoiceOver", error)
                voiceOver = nil
                retakeOf = nil
                alert = AlertMessage("Recording couldn't start", error: error)
            }
        }
    }

    /// Stops recording (or the countdown) and puts the recording on the timeline as a voice-over.
    func stopVoiceOver() {
        guard let state = voiceOver else { return }
        voiceOver = nil
        playback.player.pause()
        playback.player.isMuted = false
        let replaced = retakeOf
        retakeOf = nil
        guard case .recording(let start) = state, let recorder, let url = voiceOverURL else { return }
        recorder.stop()
        self.recorder = nil
        voiceOverURL = nil
        // The new take is offered once it is on the timeline (not the old one meanwhile).
        voiceOverTake = nil
        Task { await placeVoiceOver(url, at: start, replacing: replaced) }
    }

    /// Puts a recorded file on the timeline at `start` as a voice-over (in place of the take
    /// `replacing`, for a retake), selects it for review, and says when it is nearly silent.
    func placeVoiceOver(_ url: URL, at start: CMTime, replacing replaced: Clip.ID? = nil) async {
        guard var media = try? await MediaProbe.probe(url), media.hasAudio else {
            alert = AlertMessage(title: "Nothing was recorded", message: "Check that the right microphone is chosen in System Settings ▸ Sound.")
            return
        }
        let old = replaced.flatMap(project.sound(id:))
        media.name = old.flatMap { project.asset(id: $0.clip.assetID)?.name } ?? project.nextVoiceOverName
        var id: Clip.ID?
        apply(old == nil ? "Record Voice-Over" : "Retake Voice-Over") { project in
            if let old { project.removeTake(old.id, assetID: old.clip.assetID) }
            let assetID = project.addAsset(media)
            id = project.addSound(of: assetID, at: start, isVoiceOver: true)
        }
        guard let id else { return }
        selection = .sound(id)
        voiceOverTake = VoiceOverTake(soundID: id)
        if let levels = await analysis.levels(of: media.url) {
            setAudioLevels(levels, for: media.id)
            if voiceOverTake?.soundID == id { voiceOverTake?.isQuiet = levels.isNearlySilent }
        }
        // Record, and the captions appear: a Short that has captions gets the voice-over's too.
        if !project.transcripts.isEmpty { captioning.make(quietly: true) }
    }

    func loadPreviewsIfNeeded(_ media: MediaAsset) {
        guard media.hasAudio, audioLevelsMissing(media.id) else { return }
        Task {
            if let levels = await analysis.levels(of: media.url) { setAudioLevels(levels, for: media.id) }
        }
    }
}
