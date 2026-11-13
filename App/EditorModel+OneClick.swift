import AppKit
import EditorCore
import RenderEngine
import SwiftUI
import Transcription
import UniformTypeIdentifiers

/// The Magic Short sheet: the choices, then the work, then what was done.
struct MagicSession {
    enum Phase: Equatable {
        case choosing
        /// What is being done, and how far it is (nil: can't tell).
        case working(String, Double?)
        case done(MagicReport)
    }

    var options: MagicOptions
    var language: CaptionLanguage
    var phase = Phase.choosing
}

/// One-click Shorts (stage F): styles, Magic Short and storyboards.
extension EditorModel {
    // MARK: Styles

    /// Gives the whole Short a style (nil takes it away). Its music is made first if needed
    /// (a few seconds, once per Mac), then everything changes in one undoable step.
    func setStyle(_ style: ShortStyle?) {
        guard styleBeingMade == nil else { return }
        guard let style else {
            restyle(nil, music: nil, actionName: "Remove Style")
            return
        }
        styleBeingMade = style
        Task {
            defer { styleBeingMade = nil }
            let music = await styleMusic(style.music)
            restyle(style, music: music, actionName: "Style: \(style.displayName)")
        }
    }

    private func restyle(_ style: ShortStyle?, music: MediaAsset?, actionName: String) {
        isRestyling = true
        apply(actionName) { $0.applyStyle(style, music: music) }
        isRestyling = false
        if let music { loadPreviewsIfNeeded(music) }
    }

    /// The music file for `mood`, made and read now if it isn't ready (nil if it can't be made).
    func styleMusic(_ mood: MusicMood) async -> MediaAsset? {
        if let ready = preparedMusic[mood] { return ready }
        do {
            let url = try await MusicLibrary.fileURL(for: mood)
            var asset = project.assets.first { $0.url.standardizedFileURL == url.standardizedFileURL }
            if asset == nil { asset = try await MediaProbe.probe(url) }
            guard let asset else { return nil }
            preparedMusic[mood] = asset
            return asset
        } catch {
            return nil
        }
    }

    /// Starts making a mood's music in the background, so it is ready when it is chosen.
    func prepareMusic(_ mood: MusicMood) {
        guard preparedMusic[mood] == nil else { return }
        Task { _ = await styleMusic(mood) }
    }

    // MARK: Magic Short

    /// Opens the Magic Short sheet for the clips on the timeline.
    func beginMagic() {
        guard magic == nil else { return }
        player.pause()
        let style = project.style ?? MagicShort.lastStyle
        magic = MagicSession(options: MagicOptions(style: style, length: MagicShort.lastLength), language: captionLanguage)
        prepareMusic(style.music)
    }

    /// The Magic Short tile and File ▸ New Magic Short…: choose clips, then a new Short opens
    /// with them and the Magic Short sheet.
    func newMagicShort() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.movie, .image]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.prompt = "Make Magic Short"
        panel.message = "Choose the clips for your Short: one long video, or several clips in the order they should play"
        guard panel.runModal() == .OK, !panel.urls.isEmpty else { return }
        newShort()
        importFiles(panel.urls, to: .timelineEnd, actionName: "Add Clips")
        beginMagic()
    }

    /// Chooses more clips from inside the sheet, when the Short has none yet.
    func addClipsForMagic() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.movie, .image]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.prompt = "Add Clips"
        guard panel.runModal() == .OK else { return }
        importFiles(panel.urls, to: .timelineEnd, actionName: "Add Clips")
    }

    func updateMagic(_ change: (inout MagicSession) -> Void) {
        guard var session = magic else { return }
        change(&session)
        if session.options.style != magic?.options.style { prepareMusic(session.options.style.music) }
        magic = session
    }

    /// Does the Magic Short: listens for speech, measures the sound, makes the music, then
    /// changes the Short in one undoable step.
    func runMagic() {
        guard let session = magic, session.phase == .choosing, !project.timeline.clips.isEmpty else { return }
        let options = session.options
        let language = session.language
        captionLanguage = language
        MagicShort.lastStyle = options.style
        MagicShort.lastLength = options.length
        magicTask = Task {
            @MainActor func show(_ text: String, _ fraction: Double? = nil) {
                guard magic != nil else { return }
                if case .done? = magic?.phase { return }
                magic?.phase = .working(text, fraction)
            }
            // 1. What is said: for cutting filler words, captions and the hook.
            var transcripts: [MediaAsset.ID: Transcript] = [:]
            let assets = project.assetsNeedingTranscription(in: language)
            if !assets.isEmpty {
                show("Getting ready to listen…")
                do {
                    try await Transcriber.prepare(language) { fraction in show("Getting ready to listen…", fraction) }
                    for (index, asset) in assets.enumerated() {
                        try Task.checkCancellation()
                        show(assets.count == 1 ? "Listening to your clip…" : "Listening to clip \(index + 1) of \(assets.count)…",
                             Double(index) / Double(assets.count))
                        transcripts[asset.id] = try? await Transcriber.transcribe(asset.url, name: asset.name, language: language)
                    }
                } catch is CancellationError {
                    return
                } catch {
                    // No speech model: carry on without captions.
                }
            }
            // 2. How loud each moment is: for finding the pauses.
            show("Finding the pauses…")
            for asset in Set(project.timeline.clips.map(\.assetID)).compactMap(project.asset(id:)) where asset.hasAudio && audioLevels[asset.id] == nil {
                if let levels = await LevelCache.levels(of: asset.url) { setAudioLevels(levels, for: asset.id) }
            }
            // 3. The style's music.
            var music: MediaAsset?
            if options.addsMusic {
                show("Making the music…")
                music = await styleMusic(options.style.music)
            }
            guard !Task.isCancelled, magic != nil else { return }
            var options = options
            let levels = audioLevels
            // 4. Cut to a length: the best moments, not just the start.
            var trial = project
            trial.transcripts.merge(transcripts) { $1 }
            if !trial.magicSentences(options, levels: levels).isEmpty {
                show(WordModel.isAvailable(for: language) ? "Finding the best moments with Apple Intelligence…" : "Finding the best moments…")
                if let moments = await bestMoments(in: trial, options: options, levels: levels, language: language) {
                    options.keptSentences = moments.kept
                    options.momentsByModel = moments.byModel
                }
            }
            guard !Task.isCancelled, magic != nil else { return }
            show("Putting it together…")
            var report = MagicReport()
            isRestyling = true
            apply("Magic Short") { project in
                project.transcripts.merge(transcripts) { $1 }
                report = project.makeMagic(options, levels: levels, music: music)
            }
            isRestyling = false
            if let music { loadPreviewsIfNeeded(music) }
            selection = nil
            seek(to: .zero)
            magic?.phase = .done(report)
        }
    }

    func cancelMagic() {
        magicTask?.cancel()
        magicTask = nil
        magic = nil
    }

    /// Closes the finished sheet. A hook title still to be written is selected, ready for typing.
    func finishMagic(play: Bool) {
        let report: MagicReport? = if case .done(let report)? = magic?.phase { report } else { nil }
        magic = nil
        if let report, report.hookNeedsText, let id = report.hookTitleID {
            selectTitle(id)
            wantsTitleTextFocus = true
        } else if play {
            seek(to: .zero)
            player.play()
        }
    }

    // MARK: Storyboards

    /// A new Short that starts from a storyboard, in the storyboard's style.
    func newShort(from kind: StoryboardKind) {
        choosesStoryboard = false
        // An empty Short open in the editor takes the storyboard; otherwise a new Short starts.
        if !(screen == .editor && project.timeline.clips.isEmpty) { newShort() }
        isRestyling = true
        apply("Start \(kind.displayName)") { project in
            project.startStoryboard(kind)
            project.applyStyle(kind.suggestedStyle)
        }
        isRestyling = false
        sidebar = .storyboard
        // The music goes in with the first clip; make it now so that is instant.
        prepareMusic(kind.suggestedStyle.music)
    }

    /// Fills a shot with a file from Media.
    func fill(_ slotID: Storyboard.Slot.ID, with assetID: MediaAsset.ID) {
        let music = project.style.flatMap { preparedMusic[$0.music] }
        var clipID: Clip.ID?
        apply("Fill Shot") { project in
            let wasEmpty = project.timeline.clips.isEmpty
            clipID = project.fill(slotID, with: assetID)
            if wasEmpty, clipID != nil, let music { project.addStyleMusic(music) }
        }
        if let clipID, let range = project.timeline.range(of: clipID) {
            selection = .clip(clipID)
            seek(to: range.start)
        }
    }

    /// Fills a shot with files dropped on it or chosen in the Open panel (the first one is used).
    func fill(_ slotID: Storyboard.Slot.ID, withFiles urls: [URL]) {
        guard let url = urls.first else { return }
        if let existing = project.assets.first(where: { $0.url.standardizedFileURL == url.standardizedFileURL }) {
            fill(slotID, with: existing.id)
            return
        }
        let music = project.style.flatMap { preparedMusic[$0.music] }
        importFiles([url], to: .media, actionName: "Fill Shot") { project, ids in
            guard let id = ids.first else { return }
            let wasEmpty = project.timeline.clips.isEmpty
            if project.fill(slotID, with: id) != nil, wasEmpty, let music { project.addStyleMusic(music) }
        }
    }

    /// The Open panel for filling a shot.
    func chooseFile(for slotID: Storyboard.Slot.ID) {
        guard let slot = project.storyboard?.slots.first(where: { $0.id == slotID }) else { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.movie, .image]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.prompt = "Use for \(slot.shot.name)"
        panel.message = slot.shot.direction
        guard panel.runModal() == .OK else { return }
        fill(slotID, withFiles: panel.urls)
    }

    func emptyShot(_ slotID: Storyboard.Slot.ID) {
        apply("Remove Shot") { $0.empty(slotID) }
    }

    /// Stops showing the storyboard; the clips stay.
    func closeStoryboard() {
        apply("Close Storyboard") { $0.storyboard = nil }
        if sidebar == .storyboard { sidebar = .media }
    }

    /// Selects the clip filling a shot and shows its start.
    func showShot(_ slot: Storyboard.Slot) {
        guard let clip = project.clip(filling: slot), let range = project.timeline.range(of: clip.id) else { return }
        selection = .clip(clip.id)
        seek(to: range.start)
    }
}

extension MagicShort {
    /// The choices made last time, offered again.
    static var lastStyle: ShortStyle {
        get { UserDefaults.standard.string(forKey: "magicStyle").flatMap(ShortStyle.init(rawValue:)) ?? .bold }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "magicStyle") }
    }

    static var lastLength: MagicLength {
        get { UserDefaults.standard.string(forKey: "magicLength").flatMap(MagicLength.init(rawValue:)) ?? .keepAll }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "magicLength") }
    }
}
