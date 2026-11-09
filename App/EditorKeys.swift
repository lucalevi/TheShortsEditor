import AppKit

/// Handles the single-key editing shortcuts (Space, J/K/L, B, arrows, Delete, Home/End).
///
/// Menu shortcuts alone aren't enough for keys without modifiers: whichever control has keyboard
/// focus gets them first (Space presses a focused button, arrows move a list selection). The menus
/// still list these keys so they can be discovered; this monitor makes sure they always work,
/// except while the user is typing text.
@MainActor
final class EditorKeys {
    private var monitor: Any?

    func install(for model: EditorModel) {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak model] event in
            guard let model, Self.handle(event, model) else { return event }
            return nil
        }
    }

    private static func handle(_ event: NSEvent, _ model: EditorModel) -> Bool {
        guard event.modifierFlags.intersection([.command, .control, .option]).isEmpty,
              !(event.window?.firstResponder is NSText)
        else { return false }

        switch event.keyCode {
        case 49: model.togglePlayback()            // Space
        case 38: model.shuttle(forward: false)     // J
        case 40: model.pause()                     // K
        case 37: model.shuttle(forward: true)      // L
        case 11: model.splitAtPlayhead()           // B
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
