import AVFoundation
import EditorCore
import ImageIO
import Observation
import RenderEngine
import SwiftUI
import Transcription
@preconcurrency import Translation

/// The state of the open Short and everything the views can do to it.
///
/// Every change to the project goes through `apply(_:_:)`, which registers undo and rebuilds what
/// the player shows. Views never touch the project or the player in any other way.
@Observable
final class EditorModel {
    private(set) var project = Project()
    /// The Short open in the editor (its file in the library), nil on the home window. Every
    /// change is saved to it a moment after it is made.
    @ObservationIgnored var openShortID: UUID?
    var openShortName = ""
    @ObservationIgnored var openShortCreated = Date.now
    /// Media used in the Short whose files can't be found (moved, renamed elsewhere, deleted).
    private(set) var missingAssets: Set<MediaAsset.ID> = []
    /// What is selected on the timeline: any mix of clips, titles and the music.
    var timelineSelection = TimelineSelection() {
        // Only one place has the selection: picking something on the timeline unselects the media.
        didSet {
            if !timelineSelection.isEmpty { selectedAssetID = nil }
            switch timelineSelection.single {
            case .clip?: showTip(.range)
            case .title?, .overlay?, .sound?: showTip(.follow)
            default: break
            }
        }
    }

    typealias Selection = TimelineItem

    /// The selected item when exactly one is selected (the inspector shows its details). Setting it
    /// selects only that item; setting nil clears the selection.
    var selection: Selection? {
        get { timelineSelection.single }
        set { timelineSelection = TimelineSelection(newValue.map { [$0] } ?? []) }
    }

    func isSelected(_ item: Selection) -> Bool { timelineSelection.contains(item) }

    /// A click on a timeline item, with ⌘ (add/remove) or ⇧ (add the clips in between) as held.
    func click(_ item: Selection, modifiers: NSEvent.ModifierFlags) {
        let kind: TimelineSelection.ClickKind =
            modifiers.contains(.command)
            ? .toggle
            : modifiers.contains(.shift) ? .extend : .replace
        timelineSelection.click(item, kind, in: project.timeline)
    }

    /// Selects every clip, title and the music (⌘A on the timeline).
    func selectAllOnTimeline() {
        timelineSelection = TimelineSelection(project.allTimelineItems)
    }

    var selectedClipID: Clip.ID? {
        get { if case .clip(let id) = selection { id } else { nil } }
        set { if let newValue { selection = .clip(newValue) } else if selectedClipID != nil { selection = nil } }
    }
    var selectedTitleID: TextOverlay.ID? {
        get { if case .title(let id) = selection { id } else { nil } }
        set { if let newValue { selection = .title(newValue) } else if selectedTitleID != nil { selection = nil } }
    }
    /// The music's volume over the timeline, as built, for drawing it.
    private(set) var musicEnvelope: [VolumePoint] = []
    /// The Export sheet's choices (loudness, HDR).
    var exportOptions = ExportOptions()
    /// Asks the title inspector to put the cursor in the text. It resets it.
    var wantsTitleTextFocus = false
    /// The title whose words are being typed on the picture (`ViewerTitleEditor`).
    var titleEditedInViewer: TextOverlay.ID?
    var selectedAssetID: MediaAsset.ID? {
        didSet { if selectedAssetID != nil { showTip(.mediaKeys) } }
    }

    // MARK: State for iMovie's grammar (EditorModel+Grammar.swift)

    /// A file in Media being skimmed: which one and where, with the frame shown in the viewer.
    var mediaSkim: (assetID: MediaAsset.ID, time: CMTime)?
    var mediaSkimImage: CGImage?
    /// A stretch of the storyline picked with R (or X), to delete, keep, speed up or change the volume of.
    var timelineRange: CMTimeRange?
    /// Part of a file picked in Media, used by E, W and dropping it on the timeline.
    var mediaRange: (assetID: MediaAsset.ID, range: CMTimeRange)?
    /// R is held down: dragging across clips picks a range instead of moving them.
    @ObservationIgnored var isRangeKeyDown = false
    /// The Short shown full screen in a phone, with YouTube's buttons drawn over it (⇧⌘F).
    var isFullScreenPreview = false
    /// Settings copied with Copy Settings (⌥⌘C), for pasting onto other clips or titles.
    var copiedClip: Clip?
    var copiedTitle: TextOverlay?
    /// A one-time hint shown at the right moment.
    var tip: EditorTip?
    @ObservationIgnored var tipTask: Task<Void, Never>?
    @ObservationIgnored var mediaSkimTask: Task<Void, Never>?
    @ObservationIgnored var mediaSkimTarget: (assetID: MediaAsset.ID, time: CMTime)?
    @ObservationIgnored var windowWasFullScreen = false
    var showsSafeZone = true
    /// Timeline zoom, in points per second.
    var timelineZoom: CGFloat = 60
    private(set) var thumbnails: [MediaAsset.ID: CGImage] = [:]
    /// Stills along each file, drawn on its clips.
    private(set) var filmstrips: [MediaAsset.ID: Filmstrip] = [:]
    /// Files being read to be added.
    var isImporting: Bool { tasks.isRunning(kind: .importing) }
    /// Edges dragged on the timeline stick to cuts, other items and the playhead (S).
    var snapsToEdges = AppEnvironment.defaults.object(forKey: "snapsToEdges") as? Bool ?? true {
        didSet { AppEnvironment.defaults.set(snapsToEdges, forKey: "snapsToEdges") }
    }
    var alert: AlertMessage?

    /// Which list the left panel shows.
    var sidebar: Sidebar = .media
    /// Title looks the user saved, for every Short (their "brand kit").
    var savedTextStyles: [SavedTextStyle] = TextStyleStore.load() {
        didSet { TextStyleStore.save(savedTextStyles) }
    }
    /// The cut whose transition is being chosen (the clip before it), for the picker on the timeline.
    var transitionPickerCut: Clip.ID?
    /// Waiting for a click in the viewer to pick white or skin for a clip (see `EditorModel+Look`).
    var colorPick: ColorPick?
    /// Before/after: while on, the viewer shows every picture without its colour and filters.
    var showsOriginalLook = false {
        didSet {
            livePreview.showsOriginal = showsOriginalLook
            // A seek to the same time doesn't always draw the paused frame again; a fresh item does.
            refreshPlayback()
        }
    }
    /// The text-to-speech sheet, when open.
    var speechRequest: SpeechRequest?
    /// The marker whose name is being typed (its pop-up on the ruler is open).
    var markerBeingRenamed: Marker.ID?
    /// The clip shown in the clip trimmer (⌘\), if it is open.
    var trimmerClipID: Clip.ID?
    /// While recording a voice-over: counting down, then recording from a time.
    var voiceOver: VoiceOverState?
    /// The voice-over just recorded, offered for Listen / Retake / Delete / Keep while it is selected.
    var voiceOverTake: VoiceOverTake?
    /// The style whose music is being made, while it is.
    var styleBeingMade: ShortStyle? {
        tasks.jobs.lazy.compactMap { job -> ShortStyle? in if case .style(let style) = job.key { style } else { nil } }.first
    }
    /// The Magic Short sheet, when it is open.
    var magic: MagicSession?
    /// The storyboard chooser sheet is open.
    var choosesStoryboard = false
    /// The template chooser sheet is open.
    var choosesTemplate = false
    /// The cover being made (the cover sheet is open while it is set).
    var coverDraft: ShortCover?
    /// Words selected in the Script panel.
    var scriptSelection: Set<WordRef> = []
    @ObservationIgnored var effectPlayer: AVAudioPlayer?
    @ObservationIgnored var recorder: AVAudioRecorder?
    @ObservationIgnored var voiceOverURL: URL?
    /// Set while recording a retake: the take it replaces once the new one is made.
    @ObservationIgnored var retakeOf: Clip.ID?
    /// Set while the Export sheet is open.
    var exportPhase: ExportPhase?
    /// Set while the user is choosing which pauses to remove.
    var silenceSession: SilenceSession?
    /// Sound levels of the files, for Remove Pauses and the waveforms on clips (measured by `LevelCache`).
    var audioLevels: [MediaAsset.ID: AudioLevels] = [:]
    /// Sound levels of the files' voices alone (music and noise removed), for Remove Pauses.
    @ObservationIgnored var voiceLevels: [MediaAsset.ID: AudioLevels] = [:]
    /// Where a preview skip is heading, so it isn't started again while the seek lands.
    @ObservationIgnored private var skipTarget: CMTime?

    /// The open Short's access to its media files (and their bookmarks), closed with it.
    @ObservationIgnored private(set) var media = MediaAccess()
    /// The player, the playhead and skimming.
    let playback = PlaybackController()
    /// What the viewer shows while something is dragged, before the edit is made. Only this
    /// editor's player sees it (not exports or thumbnails).
    let livePreview = LivePreview()
    /// Every long job running in the background (Window ▸ Background Tasks).
    let tasks = BackgroundTasks()
    /// The editor window, set by the main view whenever its window becomes active. Undo goes to
    /// that window's undo manager, the one Edit ▸ Undo and ⌘Z use. (Opening files from Finder can
    /// briefly create a second window that then closes, so the first window seen isn't reliable,
    /// and neither is SwiftUI's environment undo manager.)
    @ObservationIgnored weak var window: NSWindow?
    /// A title's text while it is typed, before it is saved (see `previewTitleText`).
    var typedTitle: (id: TextOverlay.ID, text: String)?
    @ObservationIgnored var autosaveTask: Task<Void, Never>?
    @ObservationIgnored var hasUnsavedChanges = false
    @ObservationIgnored var didReportSaveError = false
    /// The open Short's backups, newest first (File ▸ Revert To).
    var backups: [ProjectStore.Backup] = []
    /// An undo manager of its own instead of the window's (the app tests, which have no window).
    @ObservationIgnored var ownUndoManager: UndoManager?

    @ObservationIgnored private var rebuildTask: Task<Void, Never>?
    /// Set while a style is being applied, so its own motion isn't taken for hand-made motion.
    @ObservationIgnored var isRestyling = false
    @ObservationIgnored var magicTask: Task<Void, Never>?
    /// Music files made for styles, ready to use without waiting.
    @ObservationIgnored var preparedMusic: [MusicMood: MediaAsset] = [:]
    @ObservationIgnored var exportTask: Task<Void, Never>?

    static let zoomRange: ClosedRange<CGFloat> = 15...400

    enum Sidebar: String, CaseIterable, Identifiable {
        case media = "Media"
        /// Inside the Media tab: the Photos library.
        case photos = "Photos"
        case audio = "Audio"
        case text = "Text"
        case transitions = "Transitions"
        case effects = "Effects"
        case captions = "Captions"
        /// Inside the Captions tab: edit by text.
        case script = "Script"
        /// Only while the Short has a storyboard.
        case storyboard = "Shots"
        var id: String { rawValue }
    }

    enum ExportPhase: Equatable {
        /// Running the checks before export.
        case checking
        /// Showing what the checks found; the user decides whether to go on.
        case review([ExportIssue])
        case exporting(Double)
        case finished(URL)
        case failed(ExportFailure)
    }

    struct SilenceSession {
        var isMeasuring = true
        var settings = SilenceSettings()
        var plan = SilencePlan(sourceCuts: [:], timelineCuts: [])
        /// Pauses are measured on the voice alone (cleaned of music and noise), not the whole sound.
        var listensToVoiceOnly = false
        /// While the voice is being separated: how far along, 0…1.
        var separating: Double?
    }

    /// One editor per window. `app` shares the library and what was measured about media between
    /// windows; without it (the app tests) the editor has its own.
    init(app: AppState? = nil) {
        let analysis = app?.analysis ?? MediaAnalysis()
        self.analysis = analysis
        library = app?.library ?? LibraryModel(analysis: analysis)
        clipboard = app?.clipboard ?? TimelineClipboardStore()
        self.app = app
        FontLibrary.registerImportedFonts()
        playback.onPlayheadMove = { [weak self] time in self?.playheadMoved(to: time) }
        if app == nil {
            library.onProblem = { [weak self] title, error in self?.alert = AlertMessage(title, error: error) }
            library.undoManager = { [weak self] in self?.undoManager }
        }
    }

    // MARK: Lookups

    var selectedClip: Clip? {
        selectedClipID.flatMap { id in project.timeline.clips.first { $0.id == id } }
    }

    var duration: CMTime { project.duration }

    var selectedTitle: TextOverlay? {
        selectedTitleID.flatMap(project.title(id:))
    }

    // MARK: Editing

    /// Applies an edit as one undoable step.
    /// `registersUndo: false` folds the change into the last undo step (more typing in a title).
    func apply(_ actionName: String, registersUndo: Bool = true, _ edit: (inout Project) -> Void) {
        var updated = project
        // New clips start as Settings say (picture length and placement, slow motion).
        NewClipSettings.$current.withValue(newClipSettings) { edit(&updated) }
        // Titles, B-roll and sounds stay with the clip under them.
        updated.followClips(from: project)
        // A style's motion moved by hand becomes the user's own; style music ends on the beat.
        if !isRestyling { updated.claimHandMadeMotion(from: project) }
        updated.fitMoodMusic()
        if updated.timeline != project.timeline { timelineRange = nil }
        replaceProject(with: updated, actionName: actionName, registersUndo: registersUndo)
    }

    /// Replaces the project as one undoable step, as it is (no following of clips): `apply`, and
    /// reverting to a backup.
    func replaceProject(with new: Project, actionName: String, registersUndo: Bool = true) {
        guard new != project else { return }
        let old = project
        project = new
        if registersUndo {
            undoManager?.registerUndo(withTarget: self) { model in
                MainActor.assumeIsolated { model.replaceProject(with: old, actionName: actionName) }
            }
            undoManager?.setActionName(actionName)
        }
        projectDidChange()
    }

    /// Puts a video at the end of the timeline, or uses a sound file as the music.
    func appendToTimeline(_ assetID: MediaAsset.ID) {
        if project.asset(id: assetID)?.hasVideo == false {
            useAsMusic(assetID)
        } else {
            apply("Add to Timeline") { $0.appendClip(of: assetID) }
        }
    }

    /// Cuts the selected overlay at the playhead when it is on screen there, otherwise the main clip (B).
    func splitAtPlayhead() {
        var newID: Clip.ID?
        if case .overlay(let id)? = selection, project.overlay(id: id)?.range.containsTime(currentTime) == true {
            apply("Split Clip") { newID = $0.splitOverlay(id, at: currentTime) }
            if let newID { selection = .overlay(newID) } else { NSSound.beep() }
            return
        }
        if case .sound(let id)? = selection, project.sound(id: id)?.range.containsTime(currentTime) == true {
            apply("Split Sound") { newID = $0.splitSound(id, at: currentTime) }
            if let newID { selection = .sound(newID) } else { NSSound.beep() }
            return
        }
        apply("Split Clip") { newID = $0.timeline.split(at: currentTime) }
        if let newID { selectedClipID = newID } else { NSSound.beep() }
    }

    /// Removes files from the media panel, and from the timeline where they are used.
    func removeAssets(_ ids: Set<MediaAsset.ID>) {
        let ids = ids.filter { project.asset(id: $0) != nil }
        guard !ids.isEmpty else { return }
        apply(ids.count == 1 ? "Remove Media" : "Remove \(ids.count) Media") { project in
            ids.forEach { project.removeAsset($0) }
        }
        selection = nil
        selectedAssetID = nil
    }

    func deleteSelectedClip() {
        guard let id = selectedClipID else { return }
        apply("Delete Clip") { $0.timeline.remove(id) }
        selectedClipID = nil
    }

    /// Deletes what is selected: a title, the music, a clip, or several of them at once (⌫).
    func deleteSelection() {
        if timelineSelection.count > 1 {
            let items = timelineSelection.items
            apply("Delete \(items.count) Items") { $0.remove(items) }
            selection = nil
        } else if selection == .music {
            removeMusic()
        } else if let id = selectedTitleID {
            apply("Delete Title") { $0.removeTitle(id) }
            selectedTitleID = nil
        } else if case .overlay(let id)? = selection {
            apply("Delete Clip") { $0.removeOverlay(id) }
            selection = nil
        } else if case .sound(let id)? = selection {
            apply("Delete Sound") { $0.removeSound(id) }
            selection = nil
        } else {
            deleteSelectedClip()
        }
    }

    func setFraming(_ framing: Framing, for clipID: Clip.ID) {
        setFraming(framing, for: [clipID])
    }

    func setFraming(_ framing: Framing, for clipIDs: [Clip.ID]) {
        apply("Change Framing") { project in
            for id in clipIDs { project.updateAnyClip(id) { $0.framing = framing } }
        }
    }

    func moveClip(_ clipID: Clip.ID, to index: Int) {
        apply("Move Clip") { $0.timeline.move(clipID, to: index) }
    }

    // MARK: Playback

    /// The current time, for the many edits made at the playhead.
    var currentTime: CMTime { playback.currentTime }

    /// While playing: stops a voice-over at the end, and jumps over the pauses being previewed.
    private func playheadMoved(to time: CMTime) {
        if case .recording = voiceOver, time >= duration - .oneFrame { stopVoiceOver() }
        // Compare whole frames: the player reports nanoseconds, and 3.233333333 s is a hair before
        // a cut ending at 97/30 s, which would otherwise jump to the same place forever.
        let frame = time.snappedToFrame()
        if let target = skipTarget, frame < target { return }
        skipTarget = nil
        if let cuts = silenceSession?.plan.timelineCuts, playback.player.rate > 0,
            let cut = cuts.first(where: { $0.containsTime(frame) })
        {
            skipTarget = cut.end
            playback.seek(to: cut.end)
        }
    }

    // MARK: Timeline zoom

    func zoom(by factor: CGFloat) {
        timelineZoom = min(max(timelineZoom * factor, Self.zoomRange.lowerBound), Self.zoomRange.upperBound)
    }

    // MARK: The home window (EditorModel+Library.swift)

    enum Screen { case home, editor }

    /// The home window with every Short, or the editor with one of them.
    var screen: Screen = .home

    /// What has been measured about the media files (sound levels, shake), shared with the
    /// library's posters and everything that builds the Short.
    let analysis: MediaAnalysis
    /// Every Short in the library, for the home window.
    let library: LibraryModel
    @ObservationIgnored weak var app: AppState? // every window's editor (nil in the app tests)
    /// Cut, Copy and Paste of timeline items, shared with the other windows (EditorModel+Clipboard).
    @ObservationIgnored let clipboard: TimelineClipboardStore
    /// Making, laying out and translating captions.
    @ObservationIgnored lazy var captioning = CaptionsModel(editor: self)

    // MARK: Opening a Short

    /// Replaces the whole Short (opening another one): not an edit, so undo starts afresh.
    func load(_ opened: Project, name: String, created: Date, media: MediaAccess = MediaAccess()) {
        autosaveTask?.cancel()
        hasUnsavedChanges = false
        captioning.cancel()
        silenceSession = nil
        playback.reset()
        // The Short closed gives up its media; the one opened brings its own.
        if media !== self.media {
            self.media.close()
            self.media = media
        }
        project = opened
        openShortName = name
        openShortCreated = created
        if let id = openShortID { library.forgetPoster(of: id) }
        selection = nil
        selectedAssetID = nil
        captioning.focusedID = nil
        thumbnails = [:]
        filmstrips = [:]
        audioLevels = [:]
        voiceLevels = [:]
        livePreview.clearAll()
        typedTitle = nil
        missingAssets = []
        backups = []
        tasks.forgetFailures()
        undoManager?.removeAllActions()
        for asset in project.assets { loadPreviews(for: asset) }
        sidebar = project.storyboard != nil ? .storyboard : sidebar == .storyboard ? .media : sidebar
        projectDidChange(autosave: false)
    }

    // MARK: Private

    /// Rebuilds the player's content from the project, keeping the playhead where it was, and
    /// saves the change a moment later.
    private func projectDidChange(autosave: Bool = true) {
        if autosave { scheduleAutosave() }
        captioning.update(for: project)
        timelineSelection.prune(to: project)
        if let settings = silenceSession?.settings { updateSilenceSettings(settings) }
        rebuildTask?.cancel()
        // Seeks made before the rebuild lands already reach the new end.
        playback.duration = project.timeline.clips.isEmpty ? .zero : project.duration
        let project = project
        rebuildTask = Task {
            guard !project.timeline.clips.isEmpty else {
                playback.show(nil, duration: .zero)
                musicEnvelope = []
                missingAssets = []
                return
            }
            do {
                let built = try await CompositionBuilder.build(project, live: livePreview, analysis: analysis)
                guard !Task.isCancelled else { return }
                musicEnvelope = built.musicEnvelope
                missingAssets = built.missingAssets
                playback.show(built.makePlayerItem(), duration: project.duration)
                // The edit a drag in the viewer showed live is now in the composition itself.
                livePreview.clearAll()
                typedTitle = nil
                prepareMissingProcessedSounds()
                prepareMissingSteadiness()
                prepareMissingCutouts()
                prepareMissingSmoothSlowMotion()
                remakeMissingStyleMusic()
            } catch {
                guard !Task.isCancelled else { return }
                Log.render.failure("Building the Short for playback", error)
                alert = AlertMessage("Playback problem", error: error, retry: { self.refreshPlayback() })
            }
        }
    }

    /// Music made by the app for a style can be made again (on another Mac, or after its folder
    /// was cleared): it is remade and the Short points at the new file, without an undo step.
    private func remakeMissingStyleMusic() {
        guard let music = project.music, let mood = music.mood, missingAssets.contains(music.assetID) else { return }
        Task {
            guard let url = try? await MusicLibrary.fileURL(for: mood), project.music?.assetID == music.assetID else { return }
            project.relink(music.assetID, to: url)
            preparedMusic[mood] = nil
            projectDidChange()
        }
    }

    /// Rebuilds the player (e.g. once a processed sound is ready) without saving.
    func refreshPlayback() { projectDidChange(autosave: false) }

    /// Waits until the player shows the project as it is now (the rebuild after the last change).
    func waitUntilBuilt() async {
        while let task = rebuildTask {
            await task.value
            if task == rebuildTask { return }
        }
    }

    /// The main clips, B-roll and sounds selected on the timeline.
    var selectedClips: [Clip] {
        timelineSelection.items.compactMap { item -> Clip? in
            switch item {
            case .clip(let id), .overlay(let id), .sound(let id): project.anyClip(id: id)
            default: nil
            }
        }
    }

    func audioLevelsMissing(_ id: MediaAsset.ID) -> Bool { audioLevels[id] == nil }
    func setAudioLevels(_ levels: AudioLevels, for id: MediaAsset.ID) { audioLevels[id] = levels }

    /// Makes what is drawn for a file: its thumbnail, the stills along it, and its sound levels.
    /// `again` makes them anew, e.g. after the file was found somewhere else.
    func loadPreviews(for asset: MediaAsset, again: Bool = false) {
        if again {
            thumbnails[asset.id] = nil
            filmstrips[asset.id] = nil
        }
        Task {
            if asset.hasVideo, thumbnails[asset.id] == nil, let image = try? await MediaProbe.thumbnail(for: asset) {
                thumbnails[asset.id] = image
            }
            if asset.hasVideo, filmstrips[asset.id] == nil, let strip = try? await MediaProbe.filmstrip(for: asset) {
                filmstrips[asset.id] = strip
            }
            if asset.hasAudio, audioLevels[asset.id] == nil, let levels = await analysis.levels(of: asset.url) {
                audioLevels[asset.id] = levels
            }
        }
    }
}
