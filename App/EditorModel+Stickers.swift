import AVFoundation
import EditorCore
import RenderEngine
import SwiftUI

/// What the text-to-speech sheet is making: the words, and where the voice goes.
struct SpeechRequest: Identifiable {
    let id = UUID()
    var text: String
    /// Where on the timeline the voice starts.
    var start: CMTime
    /// The title it reads, if any.
    var titleID: TextOverlay.ID?
}

/// Text, stickers and voice (Stage H): stickers, text templates, titles and stickers that follow
/// something in the video, and text to speech.
extension EditorModel {
    // MARK: Stickers and templates

    func addSticker(_ sticker: Sticker) {
        guard !project.timeline.clips.isEmpty else { return }
        player.pause()
        var id: TextOverlay.ID?
        apply("Add Sticker") { id = $0.addSticker(sticker, at: currentTime) }
        if let id { selectTitle(id) }
    }

    func addTextTemplate(_ template: TextTemplate) {
        guard !project.timeline.clips.isEmpty else { return }
        player.pause()
        var ids: [TextOverlay.ID] = []
        apply("Add \(template.displayName)") { ids = $0.addTextTemplate(template, at: currentTime) }
        guard let first = ids.first else { return }
        selectTitle(first)
        wantsTitleTextFocus = true
    }

    /// Plays a title's first moments (or, with `end`, its last ones), to show its animation.
    func playTitle(_ id: TextOverlay.ID, end: Bool = false) {
        guard let title = project.title(id: id), let range = title.visibleRange(in: project) else { return }
        let length = CMTime(value: 2, timescale: 1)
        let part = end ? CMTimeRange(start: max(range.start, range.end - length), end: range.end) : CMTimeRange(start: range.start, duration: min(length, range.duration))
        skimTime = nil
        seek(to: part.start)
        playRange = part
        player.play()
    }

    // MARK: Following something in the video

    /// Makes a title or sticker follow what is under it at its first moment.
    func followInVideo(_ id: TextOverlay.ID) {
        guard tracking == nil, let title = project.title(id: id), let range = title.visibleRange(in: project) else { return }
        player.pause()
        tracking = (id, 0)
        let project = project
        Task {
            defer { tracking = nil }
            do {
                let path = try await SubjectTracker.track(project: project, at: (title.horizontalPosition, title.verticalPosition), during: range) { fraction in
                    Task { @MainActor in if self.tracking?.id == id { self.tracking = (id, fraction) } }
                }
                apply(title.isSticker ? "Follow in Video" : "Follow in Video") { $0.setTrack(path, for: id) }
                // Show it following.
                skimTime = nil
                seek(to: range.start)
                playRange = range
                player.play()
            } catch is CancellationError {
            } catch {
                Log.render.failure("followInVideo", error)
                alert = AlertMessage(title: "It couldn't follow anything there", message: error.localizedDescription)
            }
        }
    }

    func stopFollowing(_ id: TextOverlay.ID) {
        apply("Stop Following") { $0.setTrack(nil, for: id) }
    }

    // MARK: Text to speech

    /// Opens the text-to-speech sheet: for a title (its words, at its start), else for the words
    /// picked in the Script panel or the caption being looked at, at the playhead.
    func beginSpeech(for titleID: TextOverlay.ID? = nil) {
        if let titleID, let title = project.title(id: titleID), !title.isSticker {
            speechRequest = SpeechRequest(text: title.text, start: title.start, titleID: titleID)
            return
        }
        speechRequest = SpeechRequest(text: scriptSelectionText ?? "", start: currentTime, titleID: nil)
    }

    /// The words picked in the Script panel, in order, or nil.
    private var scriptSelectionText: String? {
        guard !scriptSelection.isEmpty else { return nil }
        let words = project.script.filter { scriptSelection.contains($0.ref) }.map(\.text)
        return words.isEmpty ? nil : words.joined(separator: " ")
    }

    /// The folder voices made from text are kept in.
    private var voicesFolder: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: "Shorts Editor/Voices", directoryHint: .isDirectory)
    }

    /// Makes the voice and places it as a voice-over (captioned when the Short has captions).
    func makeSpeech(_ request: SpeechRequest, voice: String?, rate: Double) {
        let text = request.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !makingSpeech else { return }
        makingSpeech = true
        Task {
            defer { makingSpeech = false }
            do {
                let url = try await SpeechMaker.makeFile(text, voice: voice, rate: rate, in: voicesFolder)
                let media = try await MediaProbe.probe(url)
                var id: Clip.ID?
                apply("Add Spoken Text") { project in
                    let assetID = project.addAsset(media)
                    id = project.addSound(of: assetID, at: request.start, isVoiceOver: true)
                }
                speechRequest = nil
                if let id { selection = .sound(id) }
                loadPreviewsIfNeeded(media)
                if !project.transcripts.isEmpty { makeCaptions(quietly: true) }
            } catch {
                Log.render.failure("makeSpeech", error)
                alert = AlertMessage(title: "The voice couldn't be made", message: error.localizedDescription)
            }
        }
    }
}
