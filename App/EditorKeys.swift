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

    func install(for model: EditorModel) {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak model] event in
            guard let model, Self.handle(event, model) else { return event }
            return nil
        }
        // R is held while dragging a range: notice when it is let go.
        upMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyUp) { [weak model] event in
            if event.keyCode == 15 { model?.isRangeKeyDown = false }
            return event
        }
    }

    private static func handle(_ event: NSEvent, _ model: EditorModel) -> Bool {
        // The home window has no timeline: its keys go to its own views.
        guard model.screen == .editor else { return false }
        // ⌘A outside a text field selects everything on the timeline (Edit ▸ Select All).
        if event.modifierFlags.intersection([.command, .control, .option, .shift]) == .command,
           event.charactersIgnoringModifiers == "a",
           !(event.window?.firstResponder is NSText) {
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
            case 49: model.togglePlayback()
            default: return false
            }
            return true
        }
        // Punctuation keys are matched by the character typed, not the key's place: on many
        // keyboards (Italian, German, French…) they need ⇧ or sit elsewhere.
        switch event.characters {
        case "/": model.playSelection(); return true
        case "\\": model.playFromStart(); return true
        case ";": model.goToEdit(forward: false); return true
        case "'": model.goToEdit(forward: true); return true
        default: break
        }
        // ⇧S: hear the sound while skimming.
        if event.modifierFlags.contains(.shift) {
            guard event.keyCode == 1 else { return false }
            model.skimsAudio.toggle()
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
        // Picking white or skin in the viewer: Escape stops.
        if event.keyCode == 53, model.colorPick != nil {
            model.colorPick = nil
            return true
        }
        // A picked range: ⌫ deletes it, Escape lets go of it.
        if model.timelineRange != nil, event.keyCode == 51 || event.keyCode == 117 {
            model.deleteRange()
            return true
        }
        if event.keyCode == 53, model.trimmerClipID != nil {
            model.trimmerClipID = nil
            return true
        }
        if event.keyCode == 53, model.timelineRange != nil || model.mediaRange != nil {
            model.clearRanges()
            return true
        }
        // A file selected in Media: E adds it to the end, W puts it in at the playhead.
        if model.selectedAssetID != nil, model.sidebar == .media, event.keyCode == 14 || event.keyCode == 13 {
            if event.keyCode == 14 { model.appendSelectedMedia() } else { model.insertSelectedMedia() }
            return true
        }
        // In the Media panel, ⌫ removes the selected file.
        if model.sidebar == .media, let id = model.selectedAssetID, event.keyCode == 51 || event.keyCode == 117 {
            model.removeAssets([id])
            return true
        }
        switch event.keyCode {
        case 49: model.togglePlayback()            // Space
        case 38: model.shuttle(forward: false)     // J
        case 40: model.pause()                     // K
        case 37: model.shuttle(forward: true)      // L
        case 11: model.splitAtPlayhead()           // B
        case 12: model.trimToPlayhead(removing: .start)  // Q
        case 13: model.trimToPlayhead(removing: .end)    // W
        case 1: model.snapsToEdges.toggle()        // S
        case 15: model.isRangeKeyDown = true       // R (held while dragging a range)
        case 7: model.selectClipRange()            // X
        case 46: model.addMarker()                 // M
        case 14: break                             // E without a file selected
        case 123: model.step(frames: -1)           // ←
        case 124: model.step(frames: 1)            // →
        case 51, 117: model.deleteSelection()      // ⌫, ⌦
        case 115: model.seek(to: .zero)            // Home
        case 119: model.seek(to: model.duration)   // End
        default: return false
        }
        return true
    }
}
