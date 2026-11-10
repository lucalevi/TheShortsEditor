import AVFoundation
import EditorCore
import RenderEngine
import SwiftUI
import UniformTypeIdentifiers

/// iMovie's editing grammar: skimming, ranges, putting media in with E/W or by dropping it on a
/// clip, copying and resetting settings, loop and full-screen playback, and one-time tips.
extension EditorModel {
    // MARK: Skimming

    /// The pointer is over the timeline at `time` (nil: it left). The viewer shows that moment;
    /// the playhead stays where it is. Ignored while playing.
    func skim(to time: CMTime?) {
        guard let time else {
            guard skimTime != nil else { return }
            skimTime = nil
            stopSkimBlip()
            chaseSeek(to: currentTime)
            return
        }
        guard skimsTimeline, !isPlaying || isSkimBlip, voiceOver == nil, !project.timeline.clips.isEmpty else { return }
        let frame = time.snappedToFrame().clamped(.zero, max(.zero, duration - .oneFrame))
        guard frame != skimTime else { return }
        skimTime = frame
        chaseSeek(to: frame)
    }

    /// While an edge of a main clip is dragged by `delta`: the viewer shows the frame at that
    /// edge (the last one kept, for the end). The storyline isn't changed yet, so the frame comes
    /// from the clip's file. Nil `delta`: the drag ended.
    func showEdgeFrame(ofClip clipID: Clip.ID, edge: ClipEdge, delta: CMTime?) {
        guard let clip = project.anyClip(id: clipID) else { return }
        guard let delta, project.asset(id: clip.assetID)?.isImage != true else {
            skimMedia(clip.assetID, at: nil)
            return
        }
        let offset = edge == .start ? delta : clip.duration + delta - .oneFrame
        skimMedia(clip.assetID, at: clip.sourceTime(atOffset: offset))
    }

    /// Seeks the player to `time`, dropping in-between targets while a seek is under way, so
    /// skimming stays smooth however fast the pointer moves.
    func chaseSeek(to time: CMTime) {
        chaseTarget = time
        guard !isChasing, player.currentItem != nil else { return }
        isChasing = true
        Task {
            while let target = chaseTarget {
                chaseTarget = nil
                if isSkimBlip { player.pause() }
                _ = await player.seek(to: target, toleranceBefore: .zero, toleranceAfter: .zero)
            }
            isChasing = false
            if skimsAudio, skimTime != nil { playSkimBlip() }
        }
    }

    /// A tenth of a second of sound at the skimmer.
    private func playSkimBlip() {
        skimBlipTask?.cancel()
        isSkimBlip = true
        player.rate = 1
        skimBlipTask = Task {
            try? await Task.sleep(for: .milliseconds(110))
            guard !Task.isCancelled else { return }
            stopSkimBlip()
        }
    }

    private func stopSkimBlip() {
        skimBlipTask?.cancel()
        guard isSkimBlip else { return }
        player.pause()
        isSkimBlip = false
    }

    /// The pointer is over a file in Media at `time` of it (nil: it left): the viewer shows it.
    func skimMedia(_ assetID: MediaAsset.ID, at time: CMTime?) {
        guard let time, skimsTimeline, !isPlaying, let asset = project.asset(id: assetID) else {
            mediaSkim = nil
            mediaSkimImage = nil
            mediaSkimTarget = nil
            return
        }
        if asset.isImage {
            mediaSkim = (assetID, .zero)
            mediaSkimImage = thumbnails[assetID]
            return
        }
        mediaSkim = (assetID, time)
        mediaSkimTarget = (assetID, time)
        guard mediaSkimTask == nil else { return }
        mediaSkimTask = Task {
            defer { mediaSkimTask = nil }
            while let target = mediaSkimTarget {
                mediaSkimTarget = nil
                guard let media = project.asset(id: target.assetID), !missingAssets.contains(media.id) else { return }
                if let image = try? await MediaProbe.frame(of: media.url, at: target.time), mediaSkim?.assetID == target.assetID {
                    mediaSkimImage = image
                }
            }
        }
    }

    // MARK: Ranges

    /// Picks a stretch of the storyline (dragging with R held).
    func setTimelineRange(from a: CMTime, to b: CMTime) {
        let range = Project.frameRange(CMTimeRange(start: min(a, b), end: max(a, b)), within: duration)
        timelineRange = range.duration > .zero ? range : nil
    }

    /// X: the whole clip under the skimmer (or the playhead) becomes the range.
    func selectClipRange() {
        timelineRange = project.clipRange(at: skimTime ?? currentTime)
    }

    func clearRanges() {
        timelineRange = nil
        mediaRange = nil
    }

    func deleteRange() {
        guard let range = timelineRange else { return }
        player.pause()
        apply("Delete Range") { $0.removeRange(range) }
        seek(to: range.start)
        selection = nil
    }

    /// Keeps only the range of the clips it touches (Trim to Range, ⌥/).
    func trimToRange() {
        guard let range = timelineRange else { return }
        player.pause()
        apply("Trim to Range") { $0.trimToRange(range) }
        // The kept part starts where the first touched clip used to start.
        seek(to: project.clipRange(at: range.start)?.start ?? range.start)
    }

    func setSpeedInRange(_ speed: Double) {
        guard let range = timelineRange else { return }
        apply("Change Speed") { $0.setSpeed(speed, in: range) }
    }

    func setVolumeInRange(_ volume: Double, muted: Bool = false) {
        guard let range = timelineRange else { return }
        apply(muted ? "Mute Range" : "Change Volume") { $0.setVolume(volume, muted: muted, in: range) }
    }

    /// The part of a file chosen in Media, if `assetID` is the one it was chosen in.
    func mediaPart(of assetID: MediaAsset.ID) -> CMTimeRange? {
        mediaRange?.assetID == assetID ? mediaRange?.range : nil
    }

    // MARK: Putting media in (E, W, the + button)

    /// E: the selected file (or the part chosen of it) goes to the end of the storyline.
    func appendSelectedMedia() {
        guard let id = selectedAssetID else { return }
        appendMedia(id)
    }

    func appendMedia(_ id: MediaAsset.ID) {
        guard let asset = project.asset(id: id) else { return }
        guard asset.hasVideo else { useAsMusic(id); return }
        let part = mediaPart(of: id)
        var newID: Clip.ID?
        apply("Add to Timeline") { newID = $0.appendClip(of: id, part: part) }
        if newID == nil { NSSound.beep() }
    }

    /// W: the selected file goes into the storyline at the playhead, cutting the clip there.
    func insertSelectedMedia() {
        guard let id = selectedAssetID, let asset = project.asset(id: id), asset.hasVideo else { NSSound.beep(); return }
        player.pause()
        let part = mediaPart(of: id)
        let time = currentTime
        var newID: Clip.ID?
        apply("Insert Clip") { newID = $0.insertClip(of: id, part: part, at: time) }
        if let newID, let range = project.timeline.range(of: newID) { seek(to: range.end) } else { NSSound.beep() }
    }

    /// Files dropped on main clip `clipID` at `time`, doing what the user picked from the menu.
    func dropFiles(_ urls: [URL], on clipID: Clip.ID, at time: CMTime, action: DropAction) {
        let parts = Dictionary(project.assets.compactMap { asset in mediaPart(of: asset.id).map { (asset.url.standardizedFileURL, $0) } }) { a, _ in a }
        let urlParts = urls.map { parts[$0.standardizedFileURL] }
        importFiles(urls, to: .media, actionName: action.displayName) { project, ids in
            var at = time
            var replaced = false
            for (index, id) in ids.enumerated() {
                guard project.asset(id: id)?.hasVideo == true else { continue }
                let part = index < urlParts.count ? urlParts[index] : nil
                switch action {
                case .replace, .replaceFromStart, .replaceFromEnd, .insert:
                    // Several files: the first replaces the clip, the others go in after it.
                    if action != .insert, !replaced {
                        replaced = true
                        if let newID = project.replaceClip(clipID, with: id, part: part, mode: action), let range = project.timeline.range(of: newID) {
                            at = range.end
                        }
                    } else if let newID = project.insertClip(of: id, part: part, at: at), let range = project.timeline.range(of: newID) { at = range.end }
                case .overClips, .splitScreen, .pictureInPicture:
                    if let newID = project.addOverlay(of: id, part: part, at: at, as: action), let overlay = project.overlay(id: newID) { at = overlay.end }
                }
            }
        }
    }

    /// Files dropped on a cut between clips (or at the end): put in there.
    func dropFiles(_ urls: [URL], insertingAt time: CMTime) {
        let parts = Dictionary(project.assets.compactMap { asset in mediaPart(of: asset.id).map { (asset.url.standardizedFileURL, $0) } }) { a, _ in a }
        let urlParts = urls.map { parts[$0.standardizedFileURL] }
        importFiles(urls, to: .media, actionName: "Insert Clip") { project, ids in
            var at = time
            for (index, id) in ids.enumerated() where project.asset(id: id)?.hasVideo == true {
                if let newID = project.insertClip(of: id, part: index < urlParts.count ? urlParts[index] : nil, at: at),
                   let range = project.timeline.range(of: newID) { at = range.end }
            }
        }
    }

    /// The menu shown where files are dropped on a clip: replace it, put them in, or over it.
    func showDropMenu(for urls: [URL], on clipID: Clip.ID, at time: CMTime) {
        let menu = NSMenu()
        let header = NSMenuItem(title: urls.count == 1 ? "Drop “\(urls[0].deletingPathExtension().lastPathComponent)”:" : "Drop \(urls.count) files:", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        for action in DropAction.allCases {
            if action == .overClips { menu.addItem(.separator()) }
            menu.addItem(ActionMenuItem(title: action.displayName) { [weak self] in
                self?.dropFiles(urls, on: clipID, at: time, action: action)
            })
        }
        menu.addItem(.separator())
        menu.addItem(ActionMenuItem(title: "Cancel") {})
        menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }

    // MARK: Copy, paste and reset settings

    /// The clip or title Copy Settings works on.
    var settingsSource: (clip: Clip?, title: TextOverlay?) {
        switch selection {
        case .clip(let id)?, .overlay(let id)?, .sound(let id)?: (project.anyClip(id: id), nil)
        case .title(let id)?: (nil, project.title(id: id))
        default: (nil, nil)
        }
    }

    func copySettings() {
        let source = settingsSource
        if let clip = source.clip {
            copiedClip = clip
            copiedTitle = nil
        } else if let title = source.title {
            copiedTitle = title
            copiedClip = nil
        } else {
            NSSound.beep()
        }
    }

    /// The selected clips (main, B-roll, sounds) and titles, for pasting onto.
    private var selectedClipIDs: [Clip.ID] {
        timelineSelection.items.compactMap { item -> Clip.ID? in
            switch item {
            case .clip(let id), .overlay(let id), .sound(let id): id
            default: nil
            }
        }
    }

    private var selectedTitleIDs: [TextOverlay.ID] {
        timelineSelection.items.compactMap { if case .title(let id) = $0 { id } else { nil } }
    }

    var canPasteSettings: Bool {
        (copiedClip != nil && !selectedClipIDs.isEmpty) || (copiedTitle != nil && !selectedTitleIDs.isEmpty)
    }

    /// Pastes the copied clip's `kinds` of settings onto every selected clip.
    func pasteSettings(_ kinds: Set<SettingsKind>) {
        guard let source = copiedClip, !selectedClipIDs.isEmpty else { NSSound.beep(); return }
        let ids = selectedClipIDs
        let name = kinds.count == SettingsKind.allCases.count ? "Paste Settings" : "Paste \(kinds.first?.displayName ?? "") Settings"
        apply(name) { project in
            for id in ids where id != source.id { project.pasteSettings(kinds, from: source, to: id) }
        }
    }

    func pasteTitleDesign() {
        guard let source = copiedTitle, !selectedTitleIDs.isEmpty else { NSSound.beep(); return }
        let ids = selectedTitleIDs
        apply("Paste Title Design") { project in
            for id in ids where id != source.id { project.pasteTitleDesign(from: source, to: id) }
        }
    }

    /// Paste Settings ▸ All: everything for clips, the design for titles.
    func pasteAllSettings() {
        if copiedTitle != nil, !selectedTitleIDs.isEmpty { pasteTitleDesign() }
        if copiedClip != nil, !selectedClipIDs.isEmpty { pasteSettings(Set(SettingsKind.allCases)) }
    }

    func resetSettings(_ kinds: Set<SettingsKind>, of ids: [Clip.ID]) {
        let name = kinds.count == SettingsKind.allCases.count ? "Reset All" : "Reset \(kinds.first?.displayName ?? "")"
        apply(name) { project in
            for id in ids { project.resetSettings(kinds, of: id) }
        }
    }

    /// Reset All for the selection (Clip menu).
    func resetSelectedClips() {
        guard !selectedClipIDs.isEmpty else { NSSound.beep(); return }
        resetSettings(Set(SettingsKind.allCases), of: selectedClipIDs)
    }

    func setFollowsClip(_ follows: Bool, for item: TimelineItem) {
        apply(follows ? "Move with Clip" : "Stay at Its Time") { $0.setFollowsClip(follows, for: item) }
    }

    // MARK: Playback

    func playerReachedEnd() {
        guard loopsPlayback, playRange == nil, player.currentItem != nil else { return }
        seek(to: .zero)
        player.play()
    }

    /// Reached the end of the stretch being played: again from its start (loop), or stop there.
    func playRangeEnded(_ range: CMTimeRange) {
        if loopsPlayback {
            seek(to: range.start)
        } else {
            player.pause()
            playRange = nil
            seek(to: range.end)
        }
    }

    /// /: plays the range, or the selected item, once (or over and over with loop on).
    func playSelection() {
        let range: CMTimeRange? = timelineRange ?? {
            switch selection {
            case .clip(let id)?: project.timeline.range(of: id)
            case .title(let id)?: project.title(id: id)?.visibleRange(in: project)
            case .overlay(let id)?: project.overlay(id: id)?.visibleRange(in: project)
            case .sound(let id)?: project.sound(id: id)?.audibleRange(in: project)
            default: nil
            }
        }()
        guard let range, range.duration > .zero else { NSSound.beep(); return }
        skimTime = nil
        seek(to: range.start)
        playRange = range
        player.play()
    }

    /// \: plays from the start of the Short.
    func playFromStart() {
        skimTime = nil
        playRange = nil
        seek(to: .zero)
        player.play()
    }

    /// ; and ': the playhead to the previous or next cut or item edge.
    func goToEdit(forward: Bool) {
        player.pause()
        if let time = project.editPoint(from: currentTime, forward: forward) { seek(to: time) } else { NSSound.beep() }
    }

    /// ⇧⌘F: the Short full screen inside a phone, as it will look on YouTube.
    func toggleFullScreenPreview() {
        guard !project.timeline.clips.isEmpty || isFullScreenPreview else { return }
        isFullScreenPreview.toggle()
        let window = self.window ?? NSApp.keyWindow ?? NSApp.mainWindow
        if isFullScreenPreview {
            windowWasFullScreen = window?.styleMask.contains(.fullScreen) == true
            if !windowWasFullScreen { window?.toggleFullScreen(nil) }
            skimTime = nil
            if currentTime >= duration - .oneFrame { seek(to: .zero) }
            player.play()
        } else {
            player.pause()
            if !windowWasFullScreen, window?.styleMask.contains(.fullScreen) == true { window?.toggleFullScreen(nil) }
        }
    }

    // MARK: Tips

    /// Shows a tip the first time its moment comes (never again after).
    func showTip(_ tip: EditorTip) {
        guard screen == .editor, self.tip == nil, !EditorTip.wasShown(tip) else { return }
        EditorTip.markShown(tip)
        self.tip = tip
        tipTask?.cancel()
        tipTask = Task {
            try? await Task.sleep(for: .seconds(14))
            guard !Task.isCancelled else { return }
            if self.tip == tip { self.tip = nil }
        }
    }

    func dismissTip() {
        tipTask?.cancel()
        tip = nil
    }
}

/// A hint shown once, the first time it would help (like iMovie's "Press the R key…").
enum EditorTip: String, CaseIterable {
    case skimming, range, mediaKeys, follow, dropOnClip, transitions, freezeFrame

    var text: String {
        switch self {
        case .skimming: "Move the pointer over the timeline to look through your Short. Press Space to play from the pointer."
        case .range: "Hold R and drag across your clips to pick part of them. Then delete it, keep only it, speed it up or change its volume."
        case .mediaKeys: "Press E to add this file to the end, or W to put it in at the playhead. Drag across the bar under it to use only part of it."
        case .follow: "Titles, B-roll and sounds move with the clip under their start (the thin line shows which one). You can turn this off in the inspector."
        case .dropOnClip: "Drop on a cut to put it in there. Drop on a clip to replace it, or to show it over the clip."
        case .transitions: "The white square on the cut is the transition. Click it to choose another kind or change its length. Move the pointer across it to see it."
        case .freezeFrame: "The freeze frame holds this picture for three seconds. Drag its edges to make it shorter or longer."
        }
    }

    var systemImage: String {
        switch self {
        case .skimming: "cursorarrow.motionlines"
        case .range: "selection.pin.in.out"
        case .mediaKeys: "keyboard"
        case .follow: "pin"
        case .dropOnClip: "arrow.down.to.line"
        case .transitions: "circle.lefthalf.filled"
        case .freezeFrame: "snowflake"
        }
    }

    private static let key = "shownTips"

    static func wasShown(_ tip: EditorTip) -> Bool {
        (UserDefaults.standard.stringArray(forKey: key) ?? []).contains(tip.rawValue)
    }

    static func markShown(_ tip: EditorTip) {
        var shown = UserDefaults.standard.stringArray(forKey: key) ?? []
        if !shown.contains(tip.rawValue) { shown.append(tip.rawValue) }
        UserDefaults.standard.set(shown, forKey: key)
    }
}

/// Runs a closure when its menu item is chosen. The item keeps it alive (`representedObject`).
final class MenuAction: NSObject {
    private let handler: () -> Void

    init(_ handler: @escaping () -> Void) {
        self.handler = handler
    }

    @objc func run() { handler() }
}

/// A menu item that runs a closure.
func ActionMenuItem(title: String, handler: @escaping () -> Void) -> NSMenuItem {
    let action = MenuAction(handler)
    let item = NSMenuItem(title: title, action: #selector(MenuAction.run), keyEquivalent: "")
    item.target = action
    item.representedObject = action
    return item
}
