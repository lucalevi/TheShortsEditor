import AppKit

/// Handles the single-key editing shortcuts (Space, J/K/L, B, Q/W, E, R, X, S, / \ ; ', arrows, Delete, Home/End).
///
/// Menu shortcuts alone aren't enough for keys without modifiers: whichever control has keyboard
/// focus gets them first (Space presses a focused button, arrows move a list selection). The menus
/// still list these keys so they can be discovered; this monitor makes sure they always work,
/// except while the user is typing text.
@MainActor
final class EditorKeys {
    private var monitor: Any?
    private var upMonitor: Any?
    private var clickMonitor: Any?

    func install(for model: EditorModel) {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak model] event in
            guard let model, Self.handle(event, model) else { return event }
            return nil
        }
        // A click anywhere else ends editing a caption, so the change is saved.
        clickMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { event in
            CaptionTextField.endEditingOnClickOutside(event)
            return event
        }
        // R is held while dragging a range: notice when it is let go.
        upMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyUp) { [weak model] event in
            if event.charactersIgnoringModifiers?.lowercased() == "r" { model?.isRangeKeyDown = false }
            return event
        }
    }

    /// Escape (below), or Return with a title selected: type its words on the picture, as Return
    /// renames a file in the Finder.
    private static func handleEscapeOrReturn(_ keyCode: UInt16, _ model: EditorModel) -> Bool {
        switch keyCode {
        case 53:
            return handleEscape(model)
        case 36, 76:
            guard let title = model.selectedTitle, !title.isSticker else { return false }
            model.editTitleTextInViewer()
            return true
        default:
            return false
        }
    }

    /// Escape stops what is under way, one thing at a time: picking white or skin in the viewer,
    /// the clip trimmer, a picked range, then what is selected (as in the Finder).
    private static func handleEscape(_ model: EditorModel) -> Bool {
        if model.colorPick != nil {
            model.colorPick = nil
        } else if model.trimmerClipID != nil {
            model.trimmerClipID = nil
        } else if model.timelineRange != nil || model.mediaRange != nil {
            model.clearRanges()
        } else if !model.timelineSelection.isEmpty || model.selectedAssetID != nil {
            model.selection = nil
            model.selectedAssetID = nil
        } else {
            return false
        }
        return true
    }

    /// The single letters, as in iMovie: J K L play, B splits, Q W trim to the playhead, S snapping,
    /// R (held) picks a range, X picks a clip's range, M a marker. E does nothing without a file.
    private static let letterKeys: [String: (EditorModel) -> Void] = [
        "j": { $0.playback.shuttle(forward: false) },
        "k": { $0.playback.pause() },
        "l": { $0.playback.shuttle(forward: true) },
        "b": { $0.splitAtPlayhead() },
        "q": { $0.trimToPlayhead(removing: .start) },
        "w": { $0.trimToPlayhead(removing: .end) },
        "s": { $0.snapsToEdges.toggle() },
        "r": { $0.isRangeKeyDown = true },
        "x": { $0.selectClipRange() },
        "m": { $0.addMarker() },
        "e": { _ in },
    ]

    private static func handle(_ event: NSEvent, _ model: EditorModel) -> Bool {
        // The home window has no timeline: its keys go to its own views.
        guard model.screen == .editor else { return false }
        // Other windows (Background Tasks, Settings) keep their keys.
        if let window = event.window, let editor = model.window, window !== editor { return false }
        if CaptionTextField.handleCommandReturn(event) { return true }
        // ⌘A outside a text field selects everything on the timeline (Edit ▸ Select All).
        if event.modifierFlags.intersection([.command, .control, .option, .shift]) == .command,
            event.charactersIgnoringModifiers == "a",
            !(event.window?.firstResponder is NSText)
        {
            model.selectAllOnTimeline()
            return true
        }
        // ⌘\ opens the clip trimmer; ⌃; and ⌃' jump between markers. Matched by character, as below.
        let modifiers = event.modifierFlags.intersection([.command, .control, .option, .shift])
        if !(event.window?.firstResponder is NSText) {
            let character = event.charactersIgnoringModifiers
            if modifiers.subtracting(.shift) == .command, character == "\\" {
                model.toggleClipTrimmer()
                return true
            }
            if modifiers.subtracting(.shift) == .control, character == ";" || character == "'" {
                model.goToMarker(forward: character == "'")
                return true
            }
        }
        guard event.modifierFlags.intersection([.command, .control, .option]).isEmpty,
            !(event.window?.firstResponder is NSText)
        else { return false }

        // Full-screen preview: Escape leaves it, Space plays and pauses.
        if model.isFullScreenPreview {
            switch event.keyCode {
            case 53: model.toggleFullScreenPreview()
            case 49: model.playback.togglePlayback()
            default: return false
            }
            return true
        }
        // Punctuation keys are matched by the character typed, not the key's place: on many
        // keyboards (Italian, German, French…) they need ⇧ or sit elsewhere.
        switch event.characters {
        case "/": model.playSelection(); return true
        case "\\": model.playback.playFromStart(); return true
        case ";": model.goToEdit(forward: false); return true
        case "'": model.goToEdit(forward: true); return true
        default: break
        }
        // ⇧S: hear the sound while skimming.
        if event.modifierFlags.contains(.shift) {
            guard event.keyCode == 1 else { return false }
            model.playback.skimsAudio.toggle()
            return true
        }
        // While recording a voice-over, Space (or Escape) stops it.
        if model.isRecordingVoiceOver, event.keyCode == 49 || event.keyCode == 53 {
            model.stopVoiceOver()
            return true
        }
        // In the Script panel, ⌫ cuts the selected words.
        if model.sidebar == .script, !model.scriptSelection.isEmpty, event.keyCode == 51 || event.keyCode == 117 {
            model.cutWords(model.scriptSelection)
            return true
        }
        if handleEscapeOrReturn(event.keyCode, model) { return true }
        // A picked range: ⌫ deletes it.
        if model.timelineRange != nil, event.keyCode == 51 || event.keyCode == 117 {
            model.deleteRange()
            return true
        }
        // Letters are matched by what the key types, so they work on every keyboard layout.
        let letter = event.charactersIgnoringModifiers?.lowercased() ?? ""
        // A file selected in Media: E adds it to the end, W puts it in at the playhead.
        if model.selectedAssetID != nil, model.sidebar == .media, letter == "e" || letter == "w" {
            if letter == "e" { model.appendSelectedMedia() } else { model.insertSelectedMedia() }
            return true
        }
        // In the Media panel, ⌫ removes the selected file.
        if model.sidebar == .media, let id = model.selectedAssetID, event.keyCode == 51 || event.keyCode == 117 {
            model.removeAssets([id])
            return true
        }
        // With ⇧ a letter is a menu's (⇧S audio skimming, ⇧Z zoom to fit), not the plain key's.
        if !event.modifierFlags.contains(.shift), let action = letterKeys[letter] {
            action(model)
            return true
        }
        switch event.keyCode {
        case 49: model.playback.togglePlayback() // Space
        case 123: model.playback.step(frames: -1) // ←
        case 124: model.playback.step(frames: 1) // →
        case 51, 117: model.deleteSelection() // ⌫, ⌦
        case 115: model.playback.seek(to: .zero) // Home
        case 119: model.playback.seek(to: model.duration) // End
        default: return false
        }
        return true
    }
}
