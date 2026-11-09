import AVFoundation
import EditorCore
import ImageIO
import Observation
import RenderEngine
import SwiftUI
import Transcription

/// The state of the open Short and everything the views can do to it.
///
/// Every change to the project goes through `apply(_:_:)`, which registers undo and rebuilds what
/// the player shows. Views never touch the project or the player in any other way.
@Observable
final class EditorModel {
    private(set) var project = Project()
    /// The Short open in the editor (its file in the library), nil on the home window. Every
    /// change is saved to it a moment after it is made.
    @ObservationIgnored private var openShortID: UUID?
    private var openShortName = ""
    @ObservationIgnored private var openShortCreated = Date.now
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
    /// Processed sounds being made in the background (`prepareMissingProcessedSounds`).
    @ObservationIgnored var preparingSounds: Set<String> = []
    /// A clip whose subject is being found for reframing, with how far it has got.
    var reframing: (clipID: Clip.ID, progress: Double)?
    /// While recording a voice-over: counting down, then recording from a time.
    var voiceOver: VoiceOverState?
    /// Words selected in the Script panel.
    var scriptSelection: Set<WordRef> = []
    @ObservationIgnored var effectPlayer: AVAudioPlayer?
    @ObservationIgnored var recorder: AVAudioRecorder?
    @ObservationIgnored var voiceOverURL: URL?
    var captionLanguage = CaptionLanguage.preferred()
    /// What the caption maker is doing, while it works.
    private(set) var captionJob: CaptionJob?
    /// The captions as they appear on the timeline. Updated with every edit.
    private(set) var captionPages: [CaptionPage] = []
    /// The caption the user last clicked on the timeline, so the Captions list can show it.
    var focusedCaptionID: CaptionPage.ID?
    /// Set while the Export sheet is open.
    var exportPhase: ExportPhase?
    /// Set while the user is choosing which pauses to remove.
    private(set) var silenceSession: SilenceSession?
    /// Sound levels of the files, for Remove Pauses and the waveforms on clips (measured by `LevelCache`).
    private(set) var audioLevels: [MediaAsset.ID: AudioLevels] = [:]
    /// Where a preview skip is heading, so it isn't started again while the seek lands.
    @ObservationIgnored private var skipTarget: CMTime?

    let player = AVPlayer()
    /// The editor window, set by the main view whenever its window becomes active. Undo goes to
    /// that window's undo manager, the one Edit ▸ Undo and ⌘Z use. (Opening files from Finder can
    /// briefly create a second window that then closes, so the first window seen isn't reliable,
    /// and neither is SwiftUI's environment undo manager.)
    @ObservationIgnored weak var window: NSWindow?
    @ObservationIgnored private var autosaveTask: Task<Void, Never>?
    @ObservationIgnored private var hasUnsavedChanges = false
    @ObservationIgnored private var didReportSaveError = false
    private var undoManager: UndoManager? { (window ?? NSApp.mainWindow)?.undoManager }

    @ObservationIgnored private var rebuildTask: Task<Void, Never>?
    @ObservationIgnored private var captionTask: Task<Void, Never>?
    @ObservationIgnored private var exportTask: Task<Void, Never>?
    @ObservationIgnored private var timeObserver: Any?
    @ObservationIgnored private var statusObservation: NSKeyValueObservation?

    static let zoomRange: ClosedRange<CGFloat> = 15...400

    enum VoiceOverState: Equatable {
        case countdown(Int)
        case recording(from: CMTime)
    }

    enum Sidebar: String, CaseIterable, Identifiable {
        case media = "Media"
        case captions = "Captions"
        case script = "Script"
        case sounds = "Sounds"
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
    }

    enum CaptionJob: Equatable {
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
        edit(&updated)
        // Titles, B-roll and sounds stay with the clip under them.
        updated.followClips(from: project)
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

    func moveTitle(_ id: TextOverlay.ID, to start: CMTime) {
        apply("Move Title") { $0.moveTitle(id, to: start) }
    }

    func setTitleDuration(_ id: TextOverlay.ID, _ duration: CMTime) {
        apply("Change Title Length") { $0.setTitleDuration(id, duration) }
    }

    // MARK: Captions

    /// Transcribes the clips on the timeline that don't have captions in the chosen language yet,
    /// then shows the captions. The result is one undoable step.
    func makeCaptions() {
        guard captionJob == nil else { return }
        let language = captionLanguage
        let assets = project.assetsNeedingTranscription(in: language)
        guard !project.timeline.clips.isEmpty else { return }
        sidebar = .captions
        guard !assets.isEmpty else {
            apply("Show Captions") { $0.captions.isVisible = true }
            return
        }
        captionJob = .downloading(0)
        captionTask = Task {
            defer { captionJob = nil }
            do {
                try await Transcriber.prepare(language) { fraction in
                    if case .downloading = self.captionJob { self.captionJob = .downloading(fraction) }
                }
                var transcripts: [MediaAsset.ID: Transcript] = [:]
                for (index, asset) in assets.enumerated() {
                    try Task.checkCancellation()
                    captionJob = .listening(index: index + 1, count: assets.count)
                    transcripts[asset.id] = try await Transcriber.transcribe(asset.url, name: asset.name, language: language)
                }
                try Task.checkCancellation()
                apply("Make Captions") { project in
                    project.transcripts.merge(transcripts) { $1 }
                    project.captions.isVisible = true
                }
                if !project.hasCaptions {
                    alert = AlertMessage(
                        title: "No speech found",
                        message: "No words in \(language.displayName) were heard in your clips. Check the language, or that the clips have someone talking."
                    )
                }
            } catch is CancellationError {
                // The user stopped it; nothing changes.
            } catch {
                alert = AlertMessage(title: "Captions couldn't be made", message: error.localizedDescription)
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

    // MARK: Export

    /// Opens the Export sheet and runs the checks.
    func beginExport() {
        guard !project.timeline.clips.isEmpty, exportPhase == nil else { return }
        player.pause()
        exportPhase = .checking
        let project = project
        exportTask = Task {
            let firstSecond = CMTimeRange(start: .zero, duration: min(CMTime(value: 1, timescale: 1), project.duration))
            let peak: Float?
            do {
                peak = try await AudioProbe.peak(of: project, in: firstSecond)
            } catch {
                peak = 1  // Couldn't measure: skip that check rather than claim silence.
            }
            guard exportPhase == .checking else { return }
            exportPhase = .review(ExportReview.issues(for: project, openingPeak: peak, titleFrames: TitlePreview.frames(in: project), missing: missingAssets))
        }
    }

    /// Writes the Short to `url`, showing progress in the Export sheet.
    func export(to url: URL) {
        let project = project
        exportPhase = .exporting(0)
        exportTask = Task {
            do {
                try await Exporter.export(project, to: url, evenOutLoudness: evensOutLoudness) { fraction in
                    if case .exporting = self.exportPhase { self.exportPhase = .exporting(fraction) }
                }
                exportPhase = .finished(url)
            } catch is CancellationError {
                exportPhase = nil
            } catch {
                exportPhase = .failed(error.localizedDescription)
            }
        }
    }

    /// Stops a running export (removing the partial file) or closes the sheet.
    func endExport() {
        exportTask?.cancel()
        exportTask = nil
        exportPhase = nil
    }

    /// A file name for the export, from the first clip's name.
    var suggestedExportName: String {
        let base = project.timeline.clips.first.flatMap { project.asset(id: $0.assetID)?.name } ?? "My"
        return "\(base) Short.mp4"
    }

    // MARK: Removing pauses

    /// Opens the Remove Pauses panel: measures the sound of the clips (once per file) and plans
    /// the cuts with settings suggested from the sound itself. Nothing changes until `applySilenceRemoval`.
    func beginRemovingSilences() {
        guard silenceSession == nil, !project.timeline.clips.isEmpty else { return }
        player.pause()
        silenceSession = SilenceSession()
        let assets = Dictionary(project.timeline.clips.compactMap { project.asset(id: $0.assetID) }.map { ($0.id, $0) }) { a, _ in a }
        Task {
            for asset in assets.values where asset.hasAudio && audioLevels[asset.id] == nil {
                if let levels = await LevelCache.levels(of: asset.url) {
                    audioLevels[asset.id] = levels
                }
            }
            guard silenceSession != nil else { return }
            var settings = SilenceSettings()
            // Suggest from the file used most on the timeline.
            let main = project.timeline.clips.max { $0.duration < $1.duration }?.assetID
            if let main, let levels = audioLevels[main] { settings.threshold = levels.suggestedThreshold.rounded() }
            silenceSession?.isMeasuring = false
            updateSilenceSettings(settings)
        }
    }

    func updateSilenceSettings(_ settings: SilenceSettings) {
        guard silenceSession != nil else { return }
        silenceSession?.settings = settings
        silenceSession?.plan = SilencePlan.make(for: project, levels: audioLevels, settings: settings)
    }

    func applySilenceRemoval() {
        guard let plan = silenceSession?.plan, !plan.isEmpty else { return }
        silenceSession = nil
        apply("Remove Pauses") { $0.apply(plan) }
    }

    func cancelSilenceRemoval() {
        silenceSession = nil
    }

    /// Plays from the start, skipping the parts that would be cut.
    func previewSilenceRemoval() {
        seek(to: .zero)
        player.play()
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

    // MARK: The home window and saving

    enum Screen { case home, editor }

    /// The home window with every Short, or the editor with one of them.
    private(set) var screen: Screen = .home

    /// Every Short in the library, for the home window, newest change first.
    private(set) var shorts: [ShortEntry] = []
    /// Posters of the Shorts, made from their first second.
    private(set) var posters: [UUID: CGImage] = [:]
    @ObservationIgnored private var posterTask: Task<Void, Never>?

    /// The open Short's name, shown in the title bar. Renaming it there renames the Short.
    var shortName: String {
        get { openShortName }
        set { renameOpenShort(to: newValue) }
    }

    /// The name shown in the window's title.
    var documentName: String { screen == .home ? "Shorts" : openShortName }

    /// Writes the open Short to the library now, if anything changed. A Short with nothing in it
    /// isn't kept.
    func saveNow() {
        autosaveTask?.cancel()
        autosaveTask = nil
        guard hasUnsavedChanges, let id = openShortID else { return }
        if project.assets.isEmpty {
            try? FileManager.default.removeItem(at: ProjectStore.fileURL(for: id))
            hasUnsavedChanges = false
            return
        }
        do {
            try ProjectStore.write(project, to: ProjectStore.fileURL(for: id), name: openShortName, created: openShortCreated)
            hasUnsavedChanges = false
            didReportSaveError = false
        } catch {
            // Say it once; keep trying with the next change.
            if !didReportSaveError {
                didReportSaveError = true
                alert = AlertMessage(title: "Your Short couldn't be saved", message: error.localizedDescription)
            }
        }
    }

    private func scheduleAutosave() {
        hasUnsavedChanges = true
        autosaveTask?.cancel()
        autosaveTask = Task {
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            saveNow()
        }
    }

    /// File ▸ Save: everything is saved as you work; this just does it now.
    func save() {
        hasUnsavedChanges = true
        saveNow()
    }

    /// File ▸ Save a Copy…: writes the Short to a file anywhere, e.g. as a backup or for another
    /// Mac. The Short in the app stays as it is.
    func saveCopy() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.shortsProject]
        panel.nameFieldStringValue = "\(openShortName).\(ProjectFile.fileExtension)"
        panel.canCreateDirectories = true
        panel.message = "Save a copy of this Short as a file. Open it on another Mac with File ▸ Open…"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try ProjectStore.write(project, to: url, name: openShortName, created: openShortCreated)
        } catch {
            alert = AlertMessage(title: "The copy couldn't be saved", message: error.localizedDescription)
        }
    }

    /// At launch: brings older projects into the library, then shows the home window.
    func restoreLastSession() {
        ProjectStore.moveOldProjectsIntoLibrary()
        showHome()
    }

    /// Back to the home window (the "All Shorts" button): the open Short is saved first.
    func showHome() {
        player.pause()
        saveNow()
        if let id = openShortID, project.assets.isEmpty {
            // A Short left empty isn't kept.
            try? FileManager.default.removeItem(at: ProjectStore.fileURL(for: id))
        }
        openShortID = nil
        load(Project(), name: "", created: .now)
        screen = .home
        refreshShorts()
    }

    /// File ▸ New Short, or the New Short tile: an empty Short, open in the editor.
    func newShort() {
        if screen == .editor { showHome() }
        openShortID = UUID()
        load(Project(), name: ShortsLibrary.newName(existing: shorts.map(\.name)), created: .now)
        screen = .editor
    }

    /// Opens a Short from the home window.
    func openShort(_ id: UUID) {
        let file: ProjectFile
        do {
            file = try ProjectStore.readFile(ProjectStore.fileURL(for: id))
        } catch {
            alert = AlertMessage(title: "This Short can't be opened", message: error.localizedDescription)
            return
        }
        if screen == .editor { showHome() }
        openShortID = id
        load(file.project, name: file.name ?? ShortsLibrary.defaultName, created: file.created ?? .now)
        screen = .editor
    }

    /// File ▸ Open…: a Short saved as a file is added to the library and opened.
    func openProjectPanel() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.shortsProject]
        panel.allowsMultipleSelection = false
        panel.message = "Choose a Short saved as a file. It will be added to your Shorts."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        openProject(url)
    }

    /// A project file opened from Finder, dropped, or chosen: it becomes a Short in the library.
    func openProject(_ url: URL) {
        if screen == .editor { showHome() }
        do {
            let id = try ProjectStore.importProject(at: url, existingNames: shorts.map(\.name))
            refreshShorts()
            openShort(id)
        } catch {
            alert = AlertMessage(title: "“\(url.deletingPathExtension().lastPathComponent)” can't be opened", message: error.localizedDescription)
        }
    }

    func renameShort(_ id: UUID, to typed: String) {
        guard let name = ShortsLibrary.cleanedName(typed) else { return }
        if id == openShortID {
            renameOpenShort(to: name)
            return
        }
        do {
            try ProjectStore.rename(id, to: name)
        } catch {
            alert = AlertMessage(title: "The Short couldn't be renamed", message: error.localizedDescription)
        }
        refreshShorts()
    }

    private func renameOpenShort(to typed: String) {
        guard let name = ShortsLibrary.cleanedName(typed), name != openShortName else { return }
        openShortName = name
        if !project.assets.isEmpty {
            hasUnsavedChanges = true
            saveNow()
        }
    }

    func duplicateShort(_ id: UUID) {
        guard let entry = shorts.first(where: { $0.id == id }) else { return }
        do {
            _ = try ProjectStore.duplicate(id, as: ShortsLibrary.copyName(of: entry.name, existing: shorts.map(\.name)))
        } catch {
            alert = AlertMessage(title: "The Short couldn't be copied", message: error.localizedDescription)
        }
        refreshShorts()
    }

    /// Asks first, then moves the Shorts to the Trash.
    func deleteShorts(_ ids: Set<UUID>) {
        let names = shorts.filter { ids.contains($0.id) }.map(\.name)
        guard !names.isEmpty else { return }
        let alert = NSAlert()
        alert.messageText = names.count == 1 ? "Delete “\(names[0])”?" : "Delete \(names.count) Shorts?"
        alert.informativeText = "Your videos, pictures and sounds stay where they are. Only the edit is deleted."
        alert.addButton(withTitle: "Delete").hasDestructiveAction = true
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        for id in ids { ProjectStore.delete(id) }
        refreshShorts()
    }

    /// Reads the library again, and makes posters for Shorts that changed since theirs.
    func refreshShorts() {
        shorts = ProjectStore.libraryEntries()
        posterTask?.cancel()
        let entries = shorts
        posterTask = Task {
            for entry in entries {
                guard !Task.isCancelled else { return }
                if posters[entry.id] == nil, let url = ProjectStore.freshPoster(for: entry),
                   let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                   let image = CGImageSourceCreateImageAtIndex(source, 0, nil) {
                    posters[entry.id] = image
                    continue
                }
                guard ProjectStore.freshPoster(for: entry) == nil, entry.clipCount > 0,
                      let project = try? ProjectStore.read(ProjectStore.fileURL(for: entry.id)),
                      let image = try? await ProjectPoster.image(of: project) else { continue }
                guard !Task.isCancelled else { return }
                ProjectStore.writePoster(image, for: entry.id)
                posters[entry.id] = image
            }
        }
    }

    /// Replaces the whole Short (opening another one): not an edit, so undo starts afresh.
    private func load(_ opened: Project, name: String, created: Date) {
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
        LivePreview.clearAll()
        missingAssets = []
        currentTime = .zero
        undoManager?.removeAllActions()
        for asset in project.assets { loadPreviews(for: asset) }
        projectDidChange(autosave: false)
    }

    // MARK: Missing media

    var missingAssetList: [MediaAsset] {
        project.assets.filter { missingAssets.contains($0.id) }
    }

    /// Asks where the missing files are now: one file, or a folder (every missing file with the
    /// same name in it is found). Files are checked to be the same kind and length before use.
    func findMissingFiles() {
        let missing = missingAssetList
        guard let first = missing.first else { return }
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        // Folders must be listed too: with only file types allowed, a folder can't be chosen.
        panel.allowedContentTypes = [.movie, .audio, .image, .folder]
        panel.prompt = "Use"
        panel.message = missing.count == 1
            ? "Where is “\(first.url.lastPathComponent)” now? Choose the file, or the folder it is in."
            : "Where are the \(missing.count) missing files now? Choose the folder they are in, or one of the files."
        guard panel.runModal() == .OK, let chosen = panel.url else { return }
        // Kept for as long as the app runs, so the files (and the bookmarks saved for them) work.
        _ = chosen.startAccessingSecurityScopedResource()

        var candidates: [MediaAsset.ID: URL] = [:]
        if (try? chosen.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
            let contents = (try? FileManager.default.contentsOfDirectory(at: chosen, includingPropertiesForKeys: nil)) ?? []
            candidates = project.relinkMatches(for: missingAssets, in: contents)
        } else if let match = missing.first(where: { $0.url.lastPathComponent.lowercased() == chosen.lastPathComponent.lowercased() })
                    ?? (missing.count == 1 ? first : nil) {
            candidates = [match.id: chosen]
        }
        guard !candidates.isEmpty else {
            alert = AlertMessage(title: "No missing files there",
                                 message: "None of the files there has the name of a missing one (\(missing.map(\.url.lastPathComponent).joined(separator: ", "))).")
            return
        }
        Task {
            var accepted: [MediaAsset.ID: URL] = [:]
            var rejected: [String] = []
            for (id, url) in candidates {
                guard let asset = project.asset(id: id) else { continue }
                if let found = try? await MediaProbe.probe(url), Project.isLikelySameMedia(asset, as: found) {
                    accepted[id] = url
                } else {
                    rejected.append(url.lastPathComponent)
                }
            }
            if !accepted.isEmpty {
                apply(accepted.count == 1 ? "Find Missing File" : "Find Missing Files") { project in
                    for (id, url) in accepted { project.relink(id, to: url) }
                }
                for id in accepted.keys {
                    if let asset = project.asset(id: id) { loadPreviews(for: asset, again: true) }
                }
            }
            if !rejected.isEmpty {
                alert = AlertMessage(
                    title: rejected.count == 1 ? "This file doesn't match" : "These files don't match",
                    message: rejected.joined(separator: "\n") + "\n\nThey have a different length or kind than the missing media, so your cuts would land in the wrong places."
                )
            }
        }
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
                seek(to: time)
                prepareMissingProcessedSounds()
            } catch {
                guard !Task.isCancelled else { return }
                alert = AlertMessage(title: "Playback problem", message: error.localizedDescription)
            }
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
    private func loadPreviews(for asset: MediaAsset, again: Bool = false) {
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
