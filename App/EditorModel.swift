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
        let kind: TimelineSelection.ClickKind = modifiers.contains(.command) ? .toggle
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
    /// Export at YouTube's loudness. On unless the user turns it off in the Export sheet.
    var evensOutLoudness = true
    /// Asks the title inspector to put the cursor in the text (after adding a title). It resets it.
    var wantsTitleTextFocus = false
    var selectedAssetID: MediaAsset.ID? {
        didSet { if selectedAssetID != nil { showTip(.mediaKeys) } }
    }

    // MARK: State for iMovie's grammar (EditorModel+Grammar.swift)

    /// Hovering over the timeline shows that moment in the viewer (iMovie's skimming).
    var skimsTimeline = UserDefaults.standard.object(forKey: "skimming") as? Bool ?? true {
        didSet { UserDefaults.standard.set(skimsTimeline, forKey: "skimming"); if !skimsTimeline { skim(to: nil) } }
    }
    /// Skimming also plays a moment of sound (⇧S).
    var skimsAudio = UserDefaults.standard.bool(forKey: "audioSkimming") {
        didSet { UserDefaults.standard.set(skimsAudio, forKey: "audioSkimming") }
    }
    /// Where the pointer is skimming on the timeline (the white line), nil when it isn't.
    var skimTime: CMTime?
    /// A file in Media being skimmed: which one and where, with the frame shown in the viewer.
    var mediaSkim: (assetID: MediaAsset.ID, time: CMTime)?
    var mediaSkimImage: CGImage?
    /// A stretch of the storyline picked with R (or X), to delete, keep, speed up or change the volume of.
    var timelineRange: CMTimeRange?
    /// Part of a file picked in Media, used by E, W and dropping it on the timeline.
    var mediaRange: (assetID: MediaAsset.ID, range: CMTimeRange)?
    /// R is held down: dragging across clips picks a range instead of moving them.
    @ObservationIgnored var isRangeKeyDown = false
    /// Playing starts again from the beginning (or the range) at the end (⌘L).
    var loopsPlayback = UserDefaults.standard.bool(forKey: "loopPlayback") {
        didSet { UserDefaults.standard.set(loopsPlayback, forKey: "loopPlayback") }
    }
    /// Playing only this stretch (/), stopping or looping at its end.
    @ObservationIgnored var playRange: CMTimeRange?
    /// The Short shown full screen in a phone, with YouTube's buttons drawn over it (⇧⌘F).
    var isFullScreenPreview = false
    /// Settings copied with Copy Settings (⌥⌘C), for pasting onto other clips or titles.
    var copiedClip: Clip?
    var copiedTitle: TextOverlay?
    /// A one-time hint shown at the right moment.
    var tip: EditorTip?
    @ObservationIgnored var tipTask: Task<Void, Never>?
    @ObservationIgnored var chaseTarget: CMTime?
    @ObservationIgnored var isChasing = false
    /// A moment of sound playing while skimming: the player runs, but nothing should react.
    @ObservationIgnored var isSkimBlip = false
    @ObservationIgnored var skimBlipTask: Task<Void, Never>?
    @ObservationIgnored var mediaSkimTask: Task<Void, Never>?
    @ObservationIgnored var mediaSkimTarget: (assetID: MediaAsset.ID, time: CMTime)?
    @ObservationIgnored var windowWasFullScreen = false
    var showsSafeZone = true
    /// Timeline zoom, in points per second.
    var timelineZoom: CGFloat = 60
    private(set) var currentTime: CMTime = .zero
    private(set) var isPlaying = false
    private(set) var thumbnails: [MediaAsset.ID: CGImage] = [:]
    /// Stills along each file, drawn on its clips.
    private(set) var filmstrips: [MediaAsset.ID: Filmstrip] = [:]
    private(set) var isImporting = false
    /// Edges dragged on the timeline stick to cuts, other items and the playhead (S).
    var snapsToEdges = UserDefaults.standard.object(forKey: "snapsToEdges") as? Bool ?? true {
        didSet { UserDefaults.standard.set(snapsToEdges, forKey: "snapsToEdges") }
    }
    var alert: AlertMessage?

    /// Which list the left panel shows.
    var sidebar: Sidebar = .media
    /// Title looks the user saved, for every Short (their "brand kit").
    var savedTextStyles: [SavedTextStyle] = TextStyleStore.load() {
        didSet { TextStyleStore.save(savedTextStyles) }
    }
    /// Files whose voice is being cleaned up, with how far it has got (0…1).
    var voiceCleaning: [MediaAsset.ID: Double] = [:]
    /// Clips whose voice effect or EQ is being made, with how far it has got (0…1).
    var soundProcessing: [Clip.ID: Double] = [:]
    /// Clips being turned round: how far the backwards copy of their file is (0…1).
    var reversing: [Clip.ID: Double] = [:]
    /// The cut whose transition is being chosen (the clip before it), for the picker on the timeline.
    var transitionPickerCut: Clip.ID?
    /// Processed sounds being made in the background (`prepareMissingProcessedSounds`).
    @ObservationIgnored var preparingSounds: Set<String> = []
    /// A clip whose subject is being found for reframing, with how far it has got.
    var reframing: (clipID: Clip.ID, progress: Double)?
    /// Waiting for a click in the viewer to pick white or skin for a clip (see `EditorModel+Look`).
    var colorPick: ColorPick?
    /// Before/after: while on, the viewer shows every picture without its colour and filters.
    var showsOriginalLook = false {
        didSet {
            LivePreview.showsOriginal = showsOriginalLook
            // A seek to the same time doesn't always draw the paused frame again; a fresh item does.
            refreshPlayback()
        }
    }
    /// Files whose shake is being measured for Stabilize, with how far it has got (0…1).
    var steadying: [MediaAsset.ID: Double] = [:]
    /// Files whose shake couldn't be measured, so it isn't tried again after every rebuild.
    @ObservationIgnored var unsteadiable: Set<MediaAsset.ID> = []
    /// See-through copies being made for Remove Background (by file and subject), with how far they have got.
    var cuttingOut: [String: Double] = [:]
    /// Copies that couldn't be made, so they aren't tried again after every rebuild.
    @ObservationIgnored var uncuttable: Set<String> = []
    /// Clips being looked at for Enhance or Match Color.
    var analysingLook: Set<Clip.ID> = []
    /// Listening to the music for its beats.
    var findingBeats = false
    /// A title or sticker learning to follow something in the video, with how far it has got.
    var tracking: (id: TextOverlay.ID, progress: Double)?
    /// The sticker and ready-made text picker is open.
    var showsStickerPicker = false
    /// The text-to-speech sheet, when open.
    var speechRequest: SpeechRequest?
    /// Making a voice from text.
    var makingSpeech = false
    /// Smooth slow-motion copies being made, by clip, with how far they have got (0…1).
    var smoothing: [Clip.ID: Double] = [:]
    /// Copies that couldn't be made, so they aren't tried again after every rebuild.
    @ObservationIgnored var unsmoothable: Set<URL> = []
    /// The marker whose name is being typed (its pop-up on the ruler is open).
    var markerBeingRenamed: Marker.ID?
    /// The clip shown in the clip trimmer (⌘\), if it is open.
    var trimmerClipID: Clip.ID?
    /// Photos library items being copied in (downloaded from iCloud first if needed), by local identifier.
    var photoDownloads: [String: Double] = [:]
    /// While recording a voice-over: counting down, then recording from a time.
    var voiceOver: VoiceOverState?
    /// The style whose music is being made, while it is.
    var styleBeingMade: ShortStyle?
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
    var captionLanguage = CaptionLanguage.preferred()
    /// The spoken language is found by listening, rather than chosen.
    var findsCaptionLanguage = true
    /// What the language picker shows.
    var captionLanguageChoice: CaptionLanguageChoice {
        get { findsCaptionLanguage ? .automatic : .language(captionLanguage) }
        set {
            switch newValue {
            case .automatic: findsCaptionLanguage = true
            case .language(let language):
                findsCaptionLanguage = false
                captionLanguage = language
            }
        }
    }
    /// What the caption maker is doing, while it works.
    private(set) var captionJob: CaptionJob?
    /// The captions as they appear on the timeline. Updated with every edit.
    private(set) var captionPages: [CaptionPage] = []
    /// The caption the user last clicked on the timeline, so the Captions list can show it.
    var focusedCaptionID: CaptionPage.ID?
    /// A caption whose words should start being edited (after splitting one in two).
    var captionToEdit: CaptionPage.ID?
    /// Where the cursor goes in that caption, in characters.
    var captionEditCursor = 0
    /// What Apple Intelligence is reading the script for, while it works.
    var wordModelJob: WordModel.Task?
    /// Real words used as fillers ("like", "tipo"), found by Apple Intelligence in the Script panel.
    var modelFillers: Set<Word.ID> = []
    /// Set to start translating the captions (run by the editor's `translationTask`).
    var translationRequest: TranslationSession.Configuration?
    var isTranslating = false
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

    let player = AVPlayer()
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
    /// Opening several files from Finder makes SwiftUI create extra windows that stay hidden and
    /// report themselves too, so a hidden window is passed over for a visible one.
    private var undoManager: UndoManager? {
        let candidates = [window, NSApp.mainWindow].compactMap(\.self)
        return (candidates.first(where: \.isVisible) ?? candidates.first)?.undoManager
    }

    @ObservationIgnored private var rebuildTask: Task<Void, Never>?
    /// Set while a style is being applied, so its own motion isn't taken for hand-made motion.
    @ObservationIgnored var isRestyling = false
    @ObservationIgnored var magicTask: Task<Void, Never>?
    /// Music files made for styles, ready to use without waiting.
    @ObservationIgnored var preparedMusic: [MusicMood: MediaAsset] = [:]
    @ObservationIgnored private var captionTask: Task<Void, Never>?
    @ObservationIgnored var exportTask: Task<Void, Never>?
    @ObservationIgnored private var timeObserver: Any?
    @ObservationIgnored private var statusObservation: NSKeyValueObservation?

    static let zoomRange: ClosedRange<CGFloat> = 15...400

    enum VoiceOverState: Equatable {
        case countdown(Int)
        case recording(from: CMTime)
    }

    enum Sidebar: String, CaseIterable, Identifiable {
        case media = "Media"
        case photos = "Photos"
        case captions = "Captions"
        case script = "Script"
        case sounds = "Sounds"
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
        case failed(String)
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

    enum CaptionJob: Equatable {
        /// Listening to the start of the sound to find the language spoken.
        case detecting
        /// Downloading the language's speech model, the first time it is used.
        case downloading(Double)
        /// Listening to file `index` of `count`.
        case listening(index: Int, count: Int)
    }

    struct AlertMessage: Identifiable {
        let id = UUID()
        let title: String
        let message: String
    }

    init() {
        FontLibrary.registerImportedFonts()
        player.actionAtItemEnd = .pause
        timeObserver = player.addPeriodicTimeObserver(forInterval: .oneFrame, queue: .main) { [weak self] time in
            MainActor.assumeIsolated { self?.playheadMoved(to: time) }
        }
        statusObservation = player.observe(\.timeControlStatus) { [weak self] player, _ in
            let playing = player.timeControlStatus != .paused
            Task { @MainActor in
                guard let self, !self.isSkimBlip else { return }
                self.isPlaying = playing
            }
        }
        NotificationCenter.default.addObserver(forName: AVPlayerItem.didPlayToEndTimeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.playerReachedEnd() }
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
    func apply(_ actionName: String, _ edit: (inout Project) -> Void) {
        var updated = project
        // New clips start as Settings say (picture length and placement, slow motion).
        NewClipSettings.$current.withValue(newClipSettings) { edit(&updated) }
        // Titles, B-roll and sounds stay with the clip under them.
        updated.followClips(from: project)
        // A style's motion moved by hand becomes the user's own; style music ends on the beat.
        if !isRestyling { updated.claimHandMadeMotion(from: project) }
        updated.fitMoodMusic()
        if updated.timeline != project.timeline { timelineRange = nil }
        replaceProject(with: updated, actionName: actionName)
    }

    private func replaceProject(with new: Project, actionName: String) {
        guard new != project else { return }
        let old = project
        project = new
        undoManager?.registerUndo(withTarget: self) { model in
            MainActor.assumeIsolated { model.replaceProject(with: old, actionName: actionName) }
        }
        undoManager?.setActionName(actionName)
        projectDidChange()
    }

    /// Where imported files go.
    enum ImportDestination: Equatable {
        /// Only into Media.
        case media
        /// Also to the end of the timeline (a song becomes the music).
        case timelineEnd
        /// Also over the clips, starting at this time (videos and pictures).
        case overlay(at: CMTime)
        /// Sound files as sound effects, starting at this time.
        case sound(at: CMTime)
    }

    /// Reads the files, adds the usable ones to Media and, if asked, to the end of the timeline.
    func importFiles(_ urls: [URL], addToTimeline: Bool) {
        importFiles(urls, to: addToTimeline ? .timelineEnd : .media)
    }

    /// Reads the files, adds the usable ones to Media, and puts them where `destination` says.
    func importFiles(_ urls: [URL], to destination: ImportDestination, actionName customName: String? = nil,
                     then: ((inout Project, [MediaAsset.ID]) -> Void)? = nil) {
        let addToTimeline = destination == .timelineEnd
        // A project file dropped or opened opens that Short instead.
        if let projectFile = urls.first(where: { $0.pathExtension.lowercased() == ProjectFile.fileExtension }) {
            openProject(projectFile)
            return
        }
        guard !urls.isEmpty else { return }
        // Media opened or dropped on the home window starts a new Short with it.
        if screen == .home { newShort() }
        isImporting = true
        Task {
            var probed: [MediaAsset] = []
            var failures: [String] = []
            for url in urls {
                // Keep access to files the user handed us for as long as the app runs.
                _ = url.startAccessingSecurityScopedResource()
                if let existing = project.assets.first(where: { $0.url.standardizedFileURL == url.standardizedFileURL }) {
                    probed.append(existing)
                    continue
                }
                do {
                    probed.append(try await MediaProbe.probe(url))
                } catch {
                    Log.media.failure("Reading a file to add", error)
                    failures.append(url.lastPathComponent)
                }
            }
            isImporting = false

            let songs = probed.filter { !$0.hasVideo }
            var overlayIDs: [Clip.ID] = []
            let actionName = switch destination {
            case .media: "Import"
            case .timelineEnd: probed.allSatisfy { !$0.hasVideo } ? "Add Music" : "Add to Timeline"
            case .overlay: "Add Over Clips"
            case .sound: "Add Sound"
            }
            apply(customName ?? actionName) { project in
                var importedIDs: [MediaAsset.ID] = []
                defer { then?(&project, importedIDs) }
                var overlayStart: CMTime?
                if case .overlay(let time) = destination { overlayStart = time }
                for asset in probed {
                    let id = project.addAsset(asset)
                    importedIDs.append(id)
                    if addToTimeline, asset.hasVideo { project.appendClip(of: id) }
                    if case .sound(let time) = destination, !asset.hasVideo, let soundID = project.addSound(of: id, at: time) {
                        overlayIDs.append(soundID)
                    }
                    // Several dropped together go one after another.
                    if let start = overlayStart, asset.hasVideo, let overlayID = project.addOverlay(of: id, at: start) {
                        overlayIDs.append(overlayID)
                        overlayStart = project.overlay(id: overlayID)?.end
                    }
                }
                // A sound file dropped on the timeline or viewer becomes the music.
                if addToTimeline, let song = songs.first, let id = project.assets.first(where: { $0.url.standardizedFileURL == song.url.standardizedFileURL })?.id {
                    project.setMusic(id)
                }
            }
            if addToTimeline, !songs.isEmpty { selection = .music }
            if overlayIDs.count == 1 {
                if case .sound = destination { selection = .sound(overlayIDs[0]) } else { selection = .overlay(overlayIDs[0]) }
            }
            for asset in probed { loadPreviews(for: asset) }
            if !failures.isEmpty {
                alert = AlertMessage(
                    title: failures.count == 1 ? "This file can't be used" : "These files can't be used",
                    message: failures.joined(separator: "\n") + "\n\nOnly videos, pictures and sound files can be added."
                )
            }
        }
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

    func setClipsMuted(_ clipIDs: [Clip.ID], _ muted: Bool) {
        apply(muted ? "Mute Clips" : "Unmute Clips") { project in
            for id in clipIDs { project.updateAnyClip(id) { $0.isMuted = muted } }
        }
    }

    func moveClip(_ clipID: Clip.ID, to index: Int) {
        apply("Move Clip") { $0.timeline.move(clipID, to: index) }
    }

    // MARK: Sound

    func setClipVolume(_ clipID: Clip.ID, _ volume: Double) {
        apply("Change Volume") { project in
            project.updateAnyClip(clipID) { clip in
                clip.volume = min(max(volume, 0), Clip.maxVolume)
                clip.isMuted = false
            }
        }
    }

    func setClipMuted(_ clipID: Clip.ID, _ muted: Bool) {
        apply(muted ? "Mute Clip" : "Unmute Clip") { project in
            project.updateAnyClip(clipID) { $0.isMuted = muted }
        }
    }

    func useAsMusic(_ assetID: MediaAsset.ID) {
        apply("Add Music") { $0.setMusic(assetID) }
        if project.music?.assetID == assetID { selection = .music }
    }

    func removeMusic() {
        apply("Remove Music") { $0.music = nil }
        if selection == .music { selection = nil }
    }

    func editMusic(_ actionName: String, _ change: @escaping (inout BackgroundMusic) -> Void) {
        apply(actionName) { project in
            guard var music = project.music else { return }
            change(&music)
            project.music = music
        }
    }

    func setMusicStart(_ start: CMTime) {
        apply("Choose Part of Song") { $0.setMusicStart(start) }
    }

    var musicAsset: MediaAsset? {
        project.music.flatMap { project.asset(id: $0.assetID) }
    }

    // MARK: Titles

    /// Adds a title at the playhead, selects it and puts the cursor in its text.
    func addTitle() {
        guard !project.timeline.clips.isEmpty else { return }
        player.pause()
        var id: TextOverlay.ID?
        apply("Add Title") { id = $0.addTitle(at: currentTime, text: "Your title") }
        guard let id else { return }
        selectTitle(id)
        wantsTitleTextFocus = true
    }

    /// Selects a title and moves the playhead to where it is fully on screen.
    func selectTitle(_ id: TextOverlay.ID) {
        selectedTitleID = id
        guard let title = project.title(id: id), let range = title.visibleRange(in: project) else { return }
        player.pause()
        let settled = range.start + min(CMTime(value: 1, timescale: 2), CMTimeMultiplyByRatio(range.duration, multiplier: 1, divisor: 2))
        if !range.containsTime(currentTime) || currentTime < settled { seek(to: settled) }
    }

    func editTitle(_ id: TextOverlay.ID, _ actionName: String, _ change: @escaping (inout TextOverlay) -> Void) {
        apply(actionName) { $0.updateTitle(id, change) }
    }

    /// Shows a title's text in the viewer while it is typed, before it is saved (nil: its own).
    func previewTitleText(_ text: String?, for id: TextOverlay.ID) {
        LivePreview.setTitleText(text, for: id)
        typedTitle = text.map { (id, $0) }
        redrawCurrentFrame()
    }

    /// The title with the text being typed in it, if any (for the viewer's box around it).
    func withTypedText(_ title: TextOverlay) -> TextOverlay {
        guard let typedTitle, typedTitle.id == title.id else { return title }
        var typed = title
        typed.text = typedTitle.text
        return typed
    }

    func moveTitle(_ id: TextOverlay.ID, to start: CMTime) {
        apply("Move Title") { $0.moveTitle(id, to: start) }
    }

    func setTitleDuration(_ id: TextOverlay.ID, _ duration: CMTime) {
        apply("Change Title Length") { $0.setTitleDuration(id, duration) }
    }

    // MARK: Captions

    /// Transcribes what is heard in the Short (clips, B-roll with sound, voice-overs) that doesn't
    /// have captions in the chosen language yet, then shows the captions. The result is one
    /// undoable step. With "Find automatically", the language is the one the Short's captions are
    /// already in, or found by listening. `quietly` keeps the panel and doesn't complain when
    /// nothing is heard (used after recording a voice-over).
    func makeCaptions(quietly: Bool = false) {
        guard captionJob == nil, !project.timeline.clips.isEmpty else { return }
        if !quietly { sidebar = .captions }
        if findsCaptionLanguage, let inUse = project.captionLanguageInUse { captionLanguage = inUse }
        let detects = findsCaptionLanguage && project.captionLanguageInUse == nil
        guard detects || !project.assetsNeedingTranscription(in: captionLanguage).isEmpty else {
            if !quietly { apply("Show Captions") { $0.captions.isVisible = true } }
            return
        }
        captionJob = detects ? .detecting : .downloading(0)
        captionTask = Task {
            defer { captionJob = nil }
            do {
                var language = captionLanguage
                if detects, let first = project.assetsHeard().first {
                    language = try await Transcriber.detectLanguage(of: first.url, name: first.name, fallback: captionLanguage)
                    captionLanguage = language
                }
                captionJob = .downloading(0)
                try await Transcriber.prepare(language) { fraction in
                    if case .downloading = self.captionJob { self.captionJob = .downloading(fraction) }
                }
                let assets = project.assetsNeedingTranscription(in: language)
                var transcripts: [MediaAsset.ID: Transcript] = [:]
                for (index, asset) in assets.enumerated() {
                    try Task.checkCancellation()
                    captionJob = .listening(index: index + 1, count: assets.count)
                    transcripts[asset.id] = try await Transcriber.transcribe(asset.url, name: asset.name, language: language)
                }
                try Task.checkCancellation()
                apply(quietly ? "Make Voice-Over Captions" : "Make Captions") { project in
                    project.transcripts.merge(transcripts) { $1 }
                    project.captions.isVisible = true
                }
                if !project.hasCaptions, !quietly {
                    alert = AlertMessage(
                        title: "No speech found",
                        message: "No words in \(language.displayName) were heard in your Short. Check the language, or that the clips or voice-overs have someone talking."
                    )
                }
            } catch is CancellationError {
                // The user stopped it; nothing changes.
            } catch {
                Log.captions.failure("Making captions", error)
                if !quietly { alert = AlertMessage(title: "Captions couldn't be made", message: error.localizedDescription) }
            }
        }
    }

    func cancelCaptions() {
        captionTask?.cancel()
    }

    func setCaptionsVisible(_ visible: Bool) {
        apply(visible ? "Show Captions" : "Hide Captions") { $0.captions.isVisible = visible }
    }

    func setCaptionStyle(_ style: CaptionStyle) {
        apply("Change Caption Style") { $0.captions.style = style }
    }

    func setCaptionPosition(_ position: Double) {
        apply("Move Captions") { $0.captions.verticalPosition = position }
    }

    /// Replaces the words of a caption with what the user typed.
    func editCaption(_ page: CaptionPage, text: String) {
        guard text != page.text else { return }
        apply("Edit Caption") { $0.replaceWords(page.words.map(\.wordID), in: page.assetID, with: text) }
    }

    /// The caption on screen at the playhead.
    var currentCaption: CaptionPage? {
        CaptionLayout.page(at: currentTime, in: captionPages)
    }

    // MARK: Playback

    private func playheadMoved(to time: CMTime) {
        // While skimming, the player shows the skimmer's moment; the playhead stays put.
        if isSkimBlip || (skimTime != nil && !isPlaying) || isChasing { return }
        currentTime = time
        if let range = playRange, player.rate > 0, time.snappedToFrame() >= range.end {
            playRangeEnded(range)
            return
        }
        if case .recording = voiceOver, time >= duration - .oneFrame { stopVoiceOver() }
        // While previewing pause removal, jump over the parts that would be cut.
        // Compare whole frames: the player reports nanoseconds, and 3.233333333 s is a hair before
        // a cut ending at 97/30 s, which would otherwise jump to the same place forever.
        let frame = time.snappedToFrame()
        if let target = skipTarget, frame < target { return }
        skipTarget = nil
        if let cuts = silenceSession?.plan.timelineCuts, player.rate > 0,
           let cut = cuts.first(where: { $0.containsTime(frame) }) {
            skipTarget = cut.end
            seek(to: cut.end)
        }
    }

    func togglePlayback() {
        if isPlaying {
            player.pause()
            playRange = nil
        } else if let skim = skimTime {
            // Space while skimming plays from the skimmer, as in iMovie.
            skimTime = nil
            seek(to: skim)
            player.play()
        } else {
            if currentTime >= duration - .oneFrame { seek(to: .zero) }
            player.play()
        }
    }

    /// J/K/L shuttle: each press of L (or J) doubles the speed forwards (or backwards).
    func shuttle(forward: Bool) {
        let rate = player.rate
        if forward {
            player.rate = rate > 0 ? min(rate * 2, 8) : 1
        } else {
            player.rate = rate < 0 ? max(rate * 2, -8) : -1
        }
    }

    func pause() {
        player.pause()
        playRange = nil
    }

    func step(frames: Int) {
        player.pause()
        seek(to: currentTime + CMTime(value: Int64(frames), timescale: Project.frameRate))
    }

    func seek(to time: CMTime) {
        let clamped = CMTimeClampToRange(time.snappedToFrame(), range: CMTimeRange(start: .zero, duration: duration))
        currentTime = clamped
        player.seek(to: clamped, toleranceBefore: .zero, toleranceAfter: .zero)
    }

    // MARK: Timeline zoom

    func zoom(by factor: CGFloat) {
        timelineZoom = min(max(timelineZoom * factor, Self.zoomRange.lowerBound), Self.zoomRange.upperBound)
    }

    // MARK: The home window (EditorModel+Library.swift)

    enum Screen { case home, editor }

    /// The home window with every Short, or the editor with one of them.
    var screen: Screen = .home

    /// Every Short in the library, for the home window, newest change first.
    var shorts: [ShortEntry] = []
    /// Posters of the Shorts, made from their first second.
    var posters: [UUID: CGImage] = [:]
    @ObservationIgnored var posterTask: Task<Void, Never>?

    // MARK: Opening a Short

    /// Replaces the whole Short (opening another one): not an edit, so undo starts afresh.
    func load(_ opened: Project, name: String, created: Date) {
        autosaveTask?.cancel()
        hasUnsavedChanges = false
        captionTask?.cancel()
        silenceSession = nil
        player.pause()
        project = opened
        openShortName = name
        openShortCreated = created
        if let id = openShortID { posters[id] = nil }
        selection = nil
        selectedAssetID = nil
        focusedCaptionID = nil
        thumbnails = [:]
        filmstrips = [:]
        audioLevels = [:]
        voiceLevels = [:]
        LivePreview.clearAll()
        typedTitle = nil
        missingAssets = []
        currentTime = .zero
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
        captionPages = CaptionLayout.pages(in: project)
        timelineSelection.prune(to: project)
        if let settings = silenceSession?.settings { updateSilenceSettings(settings) }
        rebuildTask?.cancel()
        let project = project
        rebuildTask = Task {
            guard !project.timeline.clips.isEmpty else {
                player.replaceCurrentItem(with: nil)
                currentTime = .zero
                musicEnvelope = []
                missingAssets = []
                return
            }
            do {
                let built = try await CompositionBuilder.build(project)
                guard !Task.isCancelled else { return }
                let time = min(currentTime, project.duration)
                musicEnvelope = built.musicEnvelope
                missingAssets = built.missingAssets
                player.replaceCurrentItem(with: built.makePlayerItem())
                // The edit a drag in the viewer showed live is now in the composition itself.
                LivePreview.clearAll()
                typedTitle = nil
                seek(to: time)
                prepareMissingProcessedSounds()
                prepareMissingSteadiness()
                prepareMissingCutouts()
                prepareMissingSmoothSlowMotion()
                remakeMissingStyleMusic()
            } catch {
                guard !Task.isCancelled else { return }
                Log.render.failure("Building the Short for playback", error)
                alert = AlertMessage(title: "Playback problem", message: error.localizedDescription)
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
            if asset.hasAudio, audioLevels[asset.id] == nil, let levels = await LevelCache.levels(of: asset.url) {
                audioLevels[asset.id] = levels
            }
        }
    }
}
