import AppKit
import SwiftUI

/// A caption's words, edited like text: ↩ splits the caption at the cursor, ⌘↩ (or ⌥↩) starts a
/// new line in it, ⌫ at the very start joins it to the caption before, Escape undoes the typing.
/// AppKit, because SwiftUI's text field doesn't tell where the cursor is when Return is pressed.
struct CaptionTextField: NSViewRepresentable {
    /// The caption's words as saved.
    let text: String
    /// Start editing (the caption was just made by a split or a join).
    let startsEditing: Bool
    var onBeginEditing: () -> Void = {}
    /// Editing ended normally: save the text.
    var onCommit: (String) -> Void
    /// ↩ at `offset` characters into the text. Return true when the caption was split.
    var onSplit: (String, Int) -> Bool
    /// ⌫ at the start. Return true when the caption was joined to the one before.
    var onMerge: (String) -> Bool
    /// Where the cursor goes when editing starts by request, in characters.
    var cursor: Int = 0
    /// The request to start editing has been taken.
    var onStartedEditing: () -> Void = {}
    /// The text as it is typed, so the row can grow with new lines.
    var onTextChange: (String?) -> Void = { _ in }
    /// What is being typed, when editing (measured instead of `text`).
    var editingText: String?

    /// ⌘↩ while a caption is being edited adds a new line. Called from the app's key monitor,
    /// because the list around the field never passes it key equivalents.
    static func endEditingOnClickOutside(_ event: NSEvent) {
        guard let window = event.window,
              let editor = window.firstResponder as? NSTextView,
              let field = editor.delegate as? Field
        else { return }
        let point = field.convert(event.locationInWindow, from: nil)
        if !field.bounds.contains(point) { window.makeFirstResponder(nil) }
    }

    static func handleCommandReturn(_ event: NSEvent) -> Bool {
        guard event.keyCode == 36 || event.keyCode == 76,
              event.modifierFlags.intersection([.command, .control, .option, .shift]) == .command,
              let editor = event.window?.firstResponder as? NSTextView,
              editor.delegate is Field
        else { return false }
        editor.insertText("\n", replacementRange: editor.selectedRange())
        // insertText doesn't always tell the delegate; make sure the row grows.
        NotificationCenter.default.post(name: NSControl.textDidChangeNotification, object: editor.delegate, userInfo: ["NSFieldEditor": editor])
        return true
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> Field {
        let field = Field()
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.isEditable = true
        field.isSelectable = true
        field.usesSingleLineMode = false
        field.lineBreakMode = .byWordWrapping
        field.cell?.wraps = true
        field.cell?.isScrollable = false
        field.maximumNumberOfLines = 0
        field.font = .systemFont(ofSize: NSFont.systemFontSize)
        field.placeholderString = "Caption"
        field.delegate = context.coordinator
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        field.stringValue = text
        return field
    }

    func updateNSView(_ field: Field, context: Context) {
        context.coordinator.parent = self
        if field.currentEditor() == nil, field.stringValue != text {
            field.stringValue = text
        }
        if startsEditing, field.currentEditor() == nil {
            DispatchQueue.main.async {
                guard let window = field.window else { return }
                if window.makeFirstResponder(field) {
                    let text = field.stringValue
                    let index = text.index(text.startIndex, offsetBy: min(cursor, text.count))
                    field.currentEditor()?.selectedRange = NSRange(location: text.utf16.distance(from: text.utf16.startIndex, to: index.samePosition(in: text.utf16) ?? text.utf16.endIndex), length: 0)
                }
                onStartedEditing()
            }
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView field: Field, context: Context) -> CGSize? {
        let width = proposal.width ?? 200
        guard width > 0, width.isFinite else { return nil }
        guard let cell = field.cell?.copy() as? NSCell else { return nil }
        let measured = editingText ?? text
        // An empty last line still takes room while typing.
        cell.stringValue = measured.hasSuffix("\n") || measured.isEmpty ? measured + " " : measured
        let height = cell.cellSize(forBounds: NSRect(x: 0, y: 0, width: width, height: 10_000)).height
        return CGSize(width: width, height: max(ceil(height) + 2, 18))
    }

    final class Field: NSTextField {}

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: CaptionTextField
        /// The text when editing started, for Escape.
        private var original = ""
        /// Editing ended by a split, join or Escape: nothing more to save.
        private var handled = false

        init(_ parent: CaptionTextField) { self.parent = parent }

        func controlTextDidBeginEditing(_ notification: Notification) {
            original = (notification.object as? NSTextField)?.stringValue ?? ""
            handled = false
            parent.onBeginEditing()
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let editor = notification.userInfo?["NSFieldEditor"] as? NSTextView else { return }
            parent.onTextChange(editor.string)
        }

        func controlTextDidEndEditing(_ notification: Notification) {
            parent.onTextChange(nil)
            guard let field = notification.object as? NSTextField else { return }
            if handled {
                handled = false
                return
            }
            parent.onCommit(field.stringValue)
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            switch selector {
            case #selector(NSResponder.insertNewline(_:)):
                let text = textView.string
                let offset = characterOffset(of: textView.selectedRange().location, in: text)
                if parent.onSplit(text, offset) {
                    finish(control)
                } else {
                    control.window?.makeFirstResponder(nil)
                }
                return true
            case #selector(NSResponder.insertNewlineIgnoringFieldEditor(_:)):
                textView.insertText("\n", replacementRange: textView.selectedRange())
                parent.onTextChange(textView.string)
                return true
            case #selector(NSResponder.deleteBackward(_:)):
                let selection = textView.selectedRange()
                guard selection.location == 0, selection.length == 0 else { return false }
                if parent.onMerge(textView.string) { finish(control) }
                return true
            case #selector(NSResponder.cancelOperation(_:)):
                (control as? NSTextField)?.stringValue = original
                textView.string = original
                finish(control)
                return true
            default:
                return false
            }
        }

        /// Ends editing without saving again (the edit was already made).
        private func finish(_ control: NSControl) {
            handled = true
            control.window?.makeFirstResponder(nil)
        }

        /// A UTF-16 offset (AppKit's) as a count of characters (Swift's).
        private func characterOffset(of utf16Offset: Int, in text: String) -> Int {
            let index = String.Index(utf16Offset: min(utf16Offset, text.utf16.count), in: text)
            return text.distance(from: text.startIndex, to: index)
        }
    }
}
