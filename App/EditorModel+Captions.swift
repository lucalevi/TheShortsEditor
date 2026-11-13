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
    /// The language new captions are made in: the Short's own when the language is found
    /// automatically and captions exist, else the chosen one.
    var captionLanguageForNewCaptions: CaptionLanguage {
        findsCaptionLanguage ? (project.captionLanguageInUse ?? captionLanguage) : captionLanguage
    }

    // MARK: Editing like text

    /// Splits a caption at `offset` characters into `text` (↩ while editing it). Returns whether it
    /// was split; at the very start or end only the text is saved.
    @discardableResult
    func splitCaption(_ page: CaptionPage, text: String, at offset: Int) -> Bool {
        var newFirst: Word.ID?
        apply("Split Caption") { newFirst = $0.splitCaption(page.words.map(\.wordID), in: page.assetID, text: text, at: offset) }
        guard let newFirst else { return false }
        let id = captionPages.first { $0.words.first?.wordID == newFirst }?.id
        focusedCaptionID = id
        captionEditCursor = 0
        captionToEdit = id
        return true
    }

    /// The caption before `page`, when the two can be joined (same clip).
    func captionBefore(_ page: CaptionPage) -> CaptionPage? {
        guard let index = captionPages.firstIndex(where: { $0.id == page.id }), index > 0 else { return nil }
        let previous = captionPages[index - 1]
        return previous.clipID == page.clipID ? previous : nil
    }

    /// Joins a caption to the one before it (⌫ at the start while editing it).
    @discardableResult
    func mergeCaptionWithPrevious(_ page: CaptionPage, text: String) -> Bool {
        guard let previous = captionBefore(page) else { return false }
        apply("Join Captions") { $0.mergeCaptionWithPrevious(page.words.map(\.wordID), in: page.assetID, text: text, previousFirst: previous.words[0].wordID) }
        let id = captionPages.first { $0.words.first?.wordID == previous.words.first?.wordID }?.id
        focusedCaptionID = id
        // The cursor where the two were joined.
        captionEditCursor = previous.text.count + (text.isEmpty ? 0 : 1)
        captionToEdit = id
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
        modelFillers = []
        apply("Delete Captions") { $0.removeAllCaptions() }
    }

    // MARK: SRT files

    func exportCaptionsFile() {
        guard !captionPages.isEmpty else {
            NSSound.beep()
            return
        }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [Self.srtType]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = "\(documentName.isEmpty ? "Short" : documentName).srt"
        panel.message = "Save the captions as a subtitle file (.srt), for YouTube or another editor."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let text = SRT.text(for: captionPages)
        do {
            try text.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            alert = AlertMessage(title: "The captions couldn't be saved", message: error.localizedDescription)
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
        panel.message = project.hasCaptions
            ? "Choose a subtitle file (.srt). Its captions replace the ones you have now."
            : "Choose a subtitle file (.srt). Its captions are placed at their times on the timeline."
        panel.prompt = "Import"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let data = try Data(contentsOf: url)
            let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .windowsCP1252) ?? ""
            let cues = try SRT.cues(from: text)
            var placed = 0
            let language = findsCaptionLanguage ? (project.captionLanguageInUse ?? captionLanguage) : captionLanguage
            apply("Import Captions") { project in
                placed = project.importCaptions(cues, language: language)
                project.captions.isVisible = true
            }
            sidebar = .captions
            modelFillers = []
            if placed < cues.count {
                alert = AlertMessage(
                    title: placed == 0 ? "No captions were placed" : "Some captions were left out",
                    message: "\(cues.count - placed) of the \(cues.count) captions are after the end of your Short."
                )
            }
        } catch {
            alert = AlertMessage(title: "The subtitle file couldn't be read", message: error.localizedDescription)
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
        if code != nil { translateCaptions() }
    }

    /// Translates the captions that have no up-to-date translation. Apple's Translation asks to
    /// download the languages the first time.
    func translateCaptions() {
        guard let target = project.captions.translationLanguage, !isTranslating else { return }
        let source = project.captionLanguageInUse.map { Locale.Language(identifier: $0.rawValue) }
        translationRequest = TranslationSession.Configuration(source: source, target: Locale.Language(identifier: target))
    }

    /// Run by the editor view's `translationTask` with a ready session.
    func runTranslation(_ session: TranslationSession) async {
        defer {
            isTranslating = false
            translationRequest = nil
        }
        // Whole sentences, so a short caption is translated with the words around it.
        let sentences = project.sentencesNeedingTranslation()
        guard !sentences.isEmpty, let target = project.captions.translationLanguage else { return }
        isTranslating = true
        do {
            try await session.prepareTranslation()
            let requests = sentences.map { ($0.map(\.plainText).joined(separator: " "), $0[0].words[0].wordID.uuidString) }
            let responses = try await session.translations(from: Self.translationRequests(requests))
            let byID = Dictionary(sentences.map { ($0[0].words[0].wordID, $0) }, uniquingKeysWith: { first, _ in first })
            var translated: [(sentence: [CaptionPage], text: String)] = []
            for response in responses {
                guard let id = response.clientIdentifier.flatMap(UUID.init(uuidString:)), let sentence = byID[id] else { continue }
                translated.append((sentence, response.targetText))
            }
            // Only if the user didn't pick another language meanwhile.
            guard project.captions.translationLanguage == target else { return }
            apply("Translate Captions") { project in
                for (sentence, text) in translated { project.setTranslation(text, of: sentence) }
            }
        } catch is CancellationError {
        } catch {
            alert = AlertMessage(title: "The captions couldn't be translated", message: error.localizedDescription)
        }
    }

    /// Made outside the main actor, so they can be handed to the translation session.
    nonisolated private static func translationRequests(_ items: [(text: String, id: String)]) -> sending [TranslationSession.Request] {
        items.map { TranslationSession.Request(sourceText: $0.text, clientIdentifier: $0.id) }
    }

    // MARK: Smarter words

    /// Whether Apple Intelligence can read this Short's captions.
    var canUseWordModel: Bool { WordModel.isAvailable(for: project.captionLanguageInUse) }

    /// Picks key words: with Apple Intelligence when it is available, else by the rules (numbers,
    /// names, long meaningful words).
    func pickKeywords() {
        let words = project.script
        guard !words.isEmpty, wordModelJob == nil else { return }
        guard canUseWordModel else { return pickKeywordsByRules() }
        wordModelJob = .keywords
        Task {
            defer { wordModelJob = nil }
            guard let picks = try? await WordModel.picks(for: words, language: project.captionLanguageInUse, task: .keywords),
                  !picks.keywords.isEmpty
            else { return pickKeywordsByRules() }
            apply("Highlight Key Words") { project in
                project.setKeywords(picks.keywords)
                project.captions.showsKeywords = true
            }
        }
    }

    private func pickKeywordsByRules() {
        var count = 0
        apply("Highlight Key Words") { project in
            count = project.pickKeywords()
            project.captions.showsKeywords = true
        }
        if count == 0 { alert = AlertMessage(title: "No key words found", message: "Click a word in the Script panel to highlight it yourself.") }
    }

    /// Adds emoji to captions whose words call for one: chosen by Apple Intelligence when it is
    /// available, else from the built-in list.
    func suggestEmoji() {
        let words = project.script
        guard !words.isEmpty, wordModelJob == nil else { return }
        guard canUseWordModel else { return suggestEmojiByRules() }
        wordModelJob = .emoji
        Task {
            defer { wordModelJob = nil }
            guard let picks = try? await WordModel.picks(for: words, language: project.captionLanguageInUse, task: .emoji),
                  !picks.emoji.isEmpty
            else { return suggestEmojiByRules() }
            apply("Add Emoji") { project in
                project.setEmoji(picks.emoji)
                project.captions.showsEmoji = true
            }
        }
    }

    private func suggestEmojiByRules() {
        var count = 0
        apply("Add Emoji") { project in
            count = project.suggestEmoji()
            project.captions.showsEmoji = true
        }
        if count == 0 { alert = AlertMessage(title: "No emoji found", message: "None of the words call for one. Add one to a word in the Script panel.") }
    }

    /// Asks Apple Intelligence for real words used as fillers ("like", "tipo", "allora"); they join
    /// the filler sounds in the Script panel, ready to remove.
    func findMoreFillers() {
        let words = project.script.filter { $0.source == .clip }
        guard !words.isEmpty, wordModelJob == nil, canUseWordModel else { return }
        wordModelJob = .fillers
        Task {
            defer { wordModelJob = nil }
            do {
                let picks = try await WordModel.picks(for: words, language: project.captionLanguageInUse, task: .fillers)
                modelFillers = picks.fillers
                if picks.fillers.isEmpty {
                    alert = AlertMessage(title: "No other fillers found", message: "Apple Intelligence didn't find words like “like” or “tipo” used as fillers.")
                }
            } catch {
                alert = AlertMessage(title: "Fillers couldn't be found", message: error.localizedDescription)
            }
        }
    }
}
