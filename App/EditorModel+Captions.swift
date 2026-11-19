import AppKit
import CoreMedia
import EditorCore
import RenderEngine
import Transcription
@preconcurrency import Translation
import UniformTypeIdentifiers

/// Stage G: captions edited like text, their timing, SRT files, a translated second line, and
/// smarter key words, emoji and fillers with Apple Intelligence.
extension EditorModel {
    // MARK: Editing like text

    /// Splits a caption at `offset` characters into `text` (↩ while editing it). Returns whether it
    /// was split; at the very start or end only the text is saved.
    @discardableResult
    func splitCaption(_ page: CaptionPage, text: String, at offset: Int) -> Bool {
        var newFirst: Word.ID?
        apply("Split Caption") { newFirst = $0.splitCaption(page.words.map(\.wordID), in: page.assetID, text: text, at: offset) }
        guard let newFirst else { return false }
        let id = captioning.pages.first { $0.words.first?.wordID == newFirst }?.id
        captioning.focusedID = id
        captioning.editCursor = 0
        captioning.toEdit = id
        return true
    }

    /// The caption before `page`, when the two can be joined (same clip).
    func captionBefore(_ page: CaptionPage) -> CaptionPage? {
        guard let index = captioning.pages.firstIndex(where: { $0.id == page.id }), index > 0 else { return nil }
        let previous = captioning.pages[index - 1]
        return previous.clipID == page.clipID ? previous : nil
    }

    /// Joins a caption to the one before it (⌫ at the start while editing it).
    @discardableResult
    func mergeCaptionWithPrevious(_ page: CaptionPage, text: String) -> Bool {
        guard let previous = captionBefore(page) else { return false }
        apply("Join Captions") { $0.mergeCaptionWithPrevious(page.words.map(\.wordID), in: page.assetID, text: text, previousFirst: previous.words[0].wordID) }
        let id = captioning.pages.first { $0.words.first?.wordID == previous.words.first?.wordID }?.id
        captioning.focusedID = id
        // The cursor where the two were joined.
        captioning.editCursor = previous.text.count + (text.isEmpty ? 0 : 1)
        captioning.toEdit = id
        return true
    }

    /// Moves a caption's start or end on the timeline (dragging its edge in the captions lane).
    func moveCaptionEdge(_ page: CaptionPage, _ edge: CaptionEdge, to time: CMTime) {
        apply(edge == .start ? "Move Caption Start" : "Move Caption End") { $0.moveCaptionEdge(page, edge, to: time) }
    }

    func resetCaptionBreaks() {
        apply("Reset Caption Breaks") { $0.resetCaptionBreaks() }
    }

    func removeAllCaptions() {
        captioning.modelFillers = []
        apply("Delete Captions") { $0.removeAllCaptions() }
    }

    // MARK: SRT files

    func exportCaptionsFile() {
        guard !captioning.pages.isEmpty else {
            NSSound.beep()
            return
        }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [Self.srtType]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = "\(documentName.isEmpty ? "Short" : documentName).srt"
        panel.message = "Save the captions as a subtitle file (.srt), for YouTube or another editor."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let text = SRT.text(for: captioning.pages)
        do {
            try text.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            Log.captions.failure("exportCaptionsFile", error)
            alert = AlertMessage("The captions couldn't be saved", error: error)
        }
    }

    func importCaptionsFile() {
        guard !project.timeline.clips.isEmpty else {
            NSSound.beep()
            return
        }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [Self.srtType]
        panel.allowsOtherFileTypes = true
        panel.message =
            project.hasCaptions
            ? "Choose a subtitle file (.srt). Its captions replace the ones you have now."
            : "Choose a subtitle file (.srt). Its captions are placed at their times on the timeline."
        panel.prompt = "Import"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let data = try Data(contentsOf: url)
            let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .windowsCP1252) ?? ""
            let cues = try SRT.cues(from: text)
            var placed = 0
            let language = captioning.findsLanguage ? (project.captionLanguageInUse ?? captioning.spokenLanguage) : captioning.spokenLanguage
            apply("Import Captions") { project in
                placed = project.importCaptions(cues, language: language)
                project.captions.isVisible = true
            }
            sidebar = .captions
            captioning.modelFillers = []
            if placed < cues.count {
                alert = AlertMessage(
                    title: placed == 0 ? "No captions were placed" : "Some captions were left out",
                    message: "\(cues.count - placed) of the \(cues.count) captions are after the end of your Short."
                )
            }
        } catch {
            Log.captions.failure("importCaptionsFile", error)
            alert = AlertMessage("The subtitle file couldn't be read", error: error)
        }
    }

    /// macOS has no registered type for .srt: use the extension's own (dynamic) type.
    static var srtType: UTType { UTType(filenameExtension: "srt") ?? .data }

    // MARK: A second language

    /// The languages offered for the second line (codes), in the order shown.
    static let translationLanguages = ["en", "it", "de", "fr", "es", "pt", "nl", "pl", "sv", "tr", "ru", "uk", "ar", "hi", "ja", "ko", "zh"]

    /// A language's own name ("Italiano", "Deutsch").
    static func languageName(_ code: String) -> String {
        Locale(identifier: code).localizedString(forLanguageCode: code)?.capitalized(with: Locale(identifier: code)) ?? code
    }

    /// Shows the captions in a second language too (nil for none), translating them on this Mac.
    func setTranslationLanguage(_ code: String?) {
        let old = project.captions.translationLanguage
        guard code != old else { return }
        apply(code == nil ? "Remove Second Language" : "Show Second Language") { project in
            project.captions.translationLanguage = code
            project.clearTranslations()
        }
        if code != nil { captioning.translate() }
    }

    // MARK: Caption looks, key words and emoji

    func editCaptionLook(_ actionName: String, _ change: @escaping (inout CaptionSettings) -> Void) {
        apply(actionName) { change(&$0.captions) }
    }

    func clearKeywords() {
        apply("Clear Key Words") { project in
            let ids = Set(project.transcripts.values.flatMap(\.words).map(\.id))
            project.updateWords(ids) { $0.isKeyword = false }
        }
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
}

extension EditorModel {
    // MARK: Captions

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
        CaptionLayout.page(at: currentTime, in: captioning.pages)
    }
}
