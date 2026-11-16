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
                    alert = AlertMessage(title: "The voice couldn't be cleaned up", message: error.localizedDescription)
                    return
                }
            }
            apply("Clean Up Voice") { project in for id in clipIDs { project.updateAnyClip(id) { $0.cleansVoice = true } } }
        }
    }

    // MARK: Voice-over

    var isRecordingVoiceOver: Bool { voiceOver != nil }

    /// Counts down 3-2-1, then records from the microphone while the Short plays (silently) from
    /// the playhead. Stop with the button, Space, or at the end of the Short.
    func startVoiceOver() {
        guard voiceOver == nil, !project.timeline.clips.isEmpty else { return }
        playback.player.pause()
        Task {
            guard await AVCaptureDevice.requestAccess(for: .audio) else {
                alert = AlertMessage(
                    title: "The microphone is off for Shorts Editor",
                    message: "Turn it on in System Settings ▸ Privacy & Security ▸ Microphone, then try again.")
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
                guard recorder.record() else { throw CocoaError(.fileWriteUnknown) }
                self.recorder = recorder
                voiceOverURL = url
                voiceOver = .recording(from: currentTime.snappedToFrame())
                playback.player.isMuted = true
                playback.player.play()
            } catch {
                Log.audio.failure("startVoiceOver", error)
                voiceOver = nil
                alert = AlertMessage(title: "Recording couldn't start", message: error.localizedDescription)
            }
        }
    }

    /// Stops recording (or the countdown) and puts the recording on the timeline as a voice-over.
    func stopVoiceOver() {
        guard let state = voiceOver else { return }
        voiceOver = nil
        playback.player.pause()
        playback.player.isMuted = false
        guard case .recording(let start) = state, let recorder, let url = voiceOverURL else { return }
        recorder.stop()
        self.recorder = nil
        voiceOverURL = nil
        Task {
            guard let media = try? await MediaProbe.probe(url) else {
                alert = AlertMessage(title: "Nothing was recorded", message: "Check that the right microphone is chosen in System Settings ▸ Sound.")
                return
            }
            var id: Clip.ID?
            apply("Record Voice-Over") { project in
                let assetID = project.addAsset(media)
                id = project.addSound(of: assetID, at: start, isVoiceOver: true)
            }
            if let id { selection = .sound(id) }
            loadPreviewsIfNeeded(media)
            // Record, and the captions appear: a Short that has captions gets the voice-over's too.
            if !project.transcripts.isEmpty { captioning.make(quietly: true) }
        }
    }

    func loadPreviewsIfNeeded(_ media: MediaAsset) {
        guard media.hasAudio, audioLevelsMissing(media.id) else { return }
        Task {
            if let levels = await analysis.levels(of: media.url) { setAudioLevels(levels, for: media.id) }
        }
    }
}
