import AVFoundation
import CoreText
import EditorCore
import RenderEngine
import SwiftUI

/// Speed, text design, caption extras, edit by text, sounds and voice-overs, voice clean-up,
/// following the subject, and split screen.
extension EditorModel {
    // MARK: Speed

    func setSpeed(_ speed: Double, for clipIDs: [Clip.ID]) {
        apply(speed == 1 ? "Normal Speed" : "Change Speed") { project in
            for id in clipIDs { project.setSpeed(speed, for: id) }
        }
    }

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
            for asset in assets where VoiceCleaner.existingCleanedURL(for: asset.url) == nil {
                voiceCleaning[asset.id] = 0
                do {
                    _ = try await VoiceCleaner.clean(asset.url) { fraction in
                        Task { @MainActor in self.voiceCleaning[asset.id] = fraction }
                    }
                } catch {
                    voiceCleaning[asset.id] = nil
                    alert = AlertMessage(title: "The voice couldn't be cleaned up", message: error.localizedDescription)
                    return
                }
                voiceCleaning[asset.id] = nil
            }
            apply("Clean Up Voice") { project in for id in clipIDs { project.updateAnyClip(id) { $0.cleansVoice = true } } }
        }
    }

    // MARK: Following the subject

    /// Makes a horizontal clip vertical by following its subject (a face, or what stands out):
    /// it fills the screen and glides to keep the subject in the middle.
    func followSubject(_ clipID: Clip.ID) {
        guard reframing == nil, let clip = project.anyClip(id: clipID), let media = project.asset(id: clip.assetID) else { return }
        player.pause()
        reframing = (clipID, 0)
        Task {
            defer { reframing = nil }
            do {
                let samples = try await Reframer.samples(for: clip, media: media) { fraction in
                    if self.reframing?.clipID == clipID { self.reframing?.progress = fraction }
                }
                var filled = clip
                filled.framing = .fill
                filled.placement = .identity
                let keyframes = Reframe.keyframes(for: filled, displaySize: media.displaySize, samples: samples)
                guard !keyframes.isEmpty else {
                    alert = AlertMessage(title: "Nothing to follow", message: "This clip already fills the screen across, so there's no room to move.")
                    return
                }
                apply("Follow the Subject") { project in
                    project.updateAnyClip(clipID) { clip in
                        clip.framing = .fill
                        clip.placement = keyframes.count == 1 ? keyframes[0].placement : .identity
                        clip.keyframes = keyframes.count == 1 ? [] : keyframes
                    }
                }
            } catch is CancellationError {
            } catch {
                alert = AlertMessage(title: "The subject couldn't be found", message: error.localizedDescription)
            }
        }
    }

    // MARK: Split screen and picture-in-picture

    func setLayout(_ layout: OverlayLayout, for overlayID: Clip.ID) {
        apply(layout == .free ? "Full Screen" : "Split Screen") { project in
            project.updateOverlay(overlayID) { overlay in
                overlay.layout = layout
                overlay.clip.framing = .fill
                overlay.clip.placement = .identity
                overlay.clip.keyframes = []
            }
        }
    }

    func putInCorner(_ corner: PictureCorner, overlayID: Clip.ID) {
        guard let overlay = project.overlay(id: overlayID), let media = project.asset(id: overlay.clip.assetID) else { return }
        let placement = Placement.pictureInPicture(corner, displaySize: media.displaySize, framing: overlay.clip.framing)
        apply("Picture in Picture") { project in
            project.updateOverlay(overlayID) { overlay in
                overlay.layout = .free
                overlay.clip.placement = placement
                overlay.clip.keyframes = []
            }
        }
    }

    // MARK: Title looks and fonts

    func editTitleLook(_ id: TextOverlay.ID, _ actionName: String, _ change: @escaping (inout TextLook) -> Void) {
        editTitle(id, actionName) { change(&$0.look) }
    }

    func saveTextStyle(from title: TextOverlay, name: String) {
        let name = name.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        savedTextStyles.removeAll { $0.name == name }
        savedTextStyles.append(SavedTextStyle(name: name, look: title.look, entrance: title.entrance))
    }

    func applySavedStyle(_ style: SavedTextStyle, to titleID: TextOverlay.ID) {
        editTitle(titleID, "Use Saved Style") { title in
            title.look = style.look
            title.entrance = style.entrance
        }
    }

    func deleteSavedStyle(_ id: SavedTextStyle.ID) {
        savedTextStyles.removeAll { $0.id == id }
    }

    /// Lets the user pick font files to use in titles and captions.
    func importFonts() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.font]
        panel.allowsMultipleSelection = true
        panel.prompt = "Add Fonts"
        panel.message = "Choose font files (.ttf, .otf) to use in your titles and captions"
        guard panel.runModal() == .OK else { return }
        let added = FontLibrary.importFonts(panel.urls)
        if added.isEmpty {
            alert = AlertMessage(title: "No fonts were added", message: "These files couldn't be read as fonts.")
        }
    }

    // MARK: Captions

    func editCaptionLook(_ actionName: String, _ change: @escaping (inout CaptionSettings) -> Void) {
        apply(actionName) { change(&$0.captions) }
    }

    /// Picks key words in all the captions (numbers, names, long meaningful words).
    func pickKeywords() {
        var count = 0
        apply("Highlight Key Words") { project in
            count = project.pickKeywords()
            project.captions.showsKeywords = true
        }
        if count == 0 { alert = AlertMessage(title: "No key words found", message: "Click a word in the Script panel to highlight it yourself.") }
    }

    func clearKeywords() {
        apply("Clear Key Words") { project in
            let ids = Set(project.transcripts.values.flatMap(\.words).map(\.id))
            project.updateWords(ids) { $0.isKeyword = false }
        }
    }

    func suggestEmoji() {
        var count = 0
        apply("Add Emoji") { project in
            count = project.suggestEmoji()
            project.captions.showsEmoji = true
        }
        if count == 0 { alert = AlertMessage(title: "No emoji found", message: "None of the words call for one. Add one to a word in the Script panel.") }
    }

    func clearEmoji() {
        apply("Remove Emoji") { project in
            let ids = Set(project.transcripts.values.flatMap(\.words).map(\.id))
            project.updateWords(ids) { $0.emoji = nil }
        }
    }

    func setKeyword(_ on: Bool, words: Set<Word.ID>) {
        apply(on ? "Highlight Words" : "Remove Highlight") { $0.updateWords(words) { $0.isKeyword = on } }
    }

    func setEmoji(_ emoji: String?, word: Word.ID) {
        apply(emoji == nil ? "Remove Emoji" : "Add Emoji") { $0.updateWords([word]) { $0.emoji = emoji } }
    }

    func setCaptionPositionByDragging(_ position: Double) {
        let range = SafeZone.captionRange
        apply("Move Captions") { $0.captions.verticalPosition = min(max(position, range.lowerBound), range.upperBound) }
    }

    // MARK: Edit by text

    /// Cuts the words (and the pause after each) out of the Short.
    func cutWords(_ words: Set<WordRef>) {
        guard !words.isEmpty else { return }
        let plan = project.cutPlan(removing: words)
        guard !plan.isEmpty else { return }
        player.pause()
        apply(words.count == 1 ? "Cut Word" : "Cut \(words.count) Words") { $0.apply(plan) }
        scriptSelection = []
    }

    /// The filler sounds and repeated words in the Short.
    var fillerWords: [WordRef] { project.fillerAndRepeatedWords() }

    func removeFillerWords() {
        let words = Set(fillerWords)
        guard !words.isEmpty else { return }
        player.pause()
        let plan = project.cutPlan(removing: words)
        apply("Remove Filler Words") { $0.apply(plan) }
        scriptSelection = []
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
            player.pause()
            seek(to: range.start)
        }
    }

    var selectedSound: SoundClip? {
        if case .sound(let id)? = selection { project.sound(id: id) } else { nil }
    }

    // MARK: Voice-over

    var isRecordingVoiceOver: Bool { voiceOver != nil }

    /// Counts down 3-2-1, then records from the microphone while the Short plays (silently) from
    /// the playhead. Stop with the button, Space, or at the end of the Short.
    func startVoiceOver() {
        guard voiceOver == nil, !project.timeline.clips.isEmpty else { return }
        player.pause()
        Task {
            guard await AVCaptureDevice.requestAccess(for: .audio) else {
                alert = AlertMessage(title: "The microphone is off for Shorts Editor",
                                     message: "Turn it on in System Settings ▸ Privacy & Security ▸ Microphone, then try again.")
                return
            }
            if currentTime >= duration - .oneFrame { seek(to: .zero) }
            for n in [3, 2, 1] {
                voiceOver = .countdown(n)
                try? await Task.sleep(for: .seconds(1))
                guard voiceOver == .countdown(n) else { return }
            }
            do {
                let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                    .appending(path: "Shorts Editor/Voice-overs", directoryHint: .isDirectory)
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                let stamp = Date.now.formatted(.iso8601.year().month().day().time(includingFractionalSeconds: false)).replacingOccurrences(of: ":", with: ".")
                let url = folder.appending(path: "Voice-over \(stamp).m4a")
                let recorder = try AVAudioRecorder(url: url, settings: [
                    AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 48_000, AVNumberOfChannelsKey: 1, AVEncoderBitRateKey: 192_000,
                ])
                guard recorder.record() else { throw CocoaError(.fileWriteUnknown) }
                self.recorder = recorder
                voiceOverURL = url
                voiceOver = .recording(from: currentTime.snappedToFrame())
                player.isMuted = true
                player.play()
            } catch {
                voiceOver = nil
                alert = AlertMessage(title: "Recording couldn't start", message: error.localizedDescription)
            }
        }
    }

    /// Stops recording (or the countdown) and puts the recording on the timeline as a voice-over.
    func stopVoiceOver() {
        guard let state = voiceOver else { return }
        voiceOver = nil
        player.pause()
        player.isMuted = false
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
        }
    }

    private func loadPreviewsIfNeeded(_ media: MediaAsset) {
        guard media.hasAudio, audioLevelsMissing(media.id) else { return }
        Task {
            if let levels = await LevelCache.levels(of: media.url) { setAudioLevels(levels, for: media.id) }
        }
    }
}

/// Saved title looks, kept for every Short in the app's preferences.
enum TextStyleStore {
    private static let key = "savedTextStyles"

    static func load() -> [SavedTextStyle] {
        guard let data = UserDefaults.standard.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([SavedTextStyle].self, from: data)) ?? []
    }

    static func save(_ styles: [SavedTextStyle]) {
        UserDefaults.standard.set(try? JSONEncoder().encode(styles), forKey: key)
    }
}

/// Fonts the user added: copied into the app's own folder and made available to it (only to
/// it, not to the rest of the Mac) at every launch.
enum FontLibrary {
    static var folder: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: "Shorts Editor/Fonts", directoryHint: .isDirectory)
    }

    static func registerImportedFonts() {
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        guard !files.isEmpty else { return }
        CTFontManagerRegisterFontURLs(files as CFArray, .process, true, nil)
    }

    /// Copies and registers the fonts; returns the family names that were added.
    @discardableResult
    static func importFonts(_ urls: [URL]) -> [String] {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var families: [String] = []
        for url in urls {
            _ = url.startAccessingSecurityScopedResource()
            defer { url.stopAccessingSecurityScopedResource() }
            guard let descriptors = CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor], !descriptors.isEmpty else { continue }
            let destination = folder.appending(path: url.lastPathComponent)
            try? FileManager.default.removeItem(at: destination)
            guard (try? FileManager.default.copyItem(at: url, to: destination)) != nil else { continue }
            CTFontManagerRegisterFontURLs([destination] as CFArray, .process, true, nil)
            families += descriptors.compactMap { CTFontDescriptorCopyAttribute($0, kCTFontFamilyNameAttribute) as? String }
        }
        return families
    }

    /// Every font family the app can use, by name.
    static var families: [String] {
        NSFontManager.shared.availableFontFamilies.filter { !$0.hasPrefix(".") }.sorted()
    }
}
