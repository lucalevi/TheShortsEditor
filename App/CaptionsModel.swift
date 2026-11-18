import CoreMedia
import EditorCore
import Observation
import Transcription
@preconcurrency import Translation

/// Captions' own state and long work: the spoken language, making captions (speech to text, on
/// this Mac), the captions as laid out on the timeline, translating them, and asking Apple
/// Intelligence for key words, emoji and fillers. The captions themselves are in the project;
/// every change to them goes through the editor's `apply`, like any other edit.
@Observable
final class CaptionsModel {

    /// The editor of the open Short, whose project the captions are in.
    @ObservationIgnored unowned let editor: EditorModel

    init(editor: EditorModel) {
        self.editor = editor
    }

    // MARK: The editor

    private var project: Project { editor.project }
    private var tasks: BackgroundTasks { editor.tasks }
    private var sidebar: EditorModel.Sidebar {
        get { editor.sidebar }
        set { editor.sidebar = newValue }
    }
    private var alert: AlertMessage? {
        get { editor.alert }
        set { editor.alert = newValue }
    }
    private func apply(_ actionName: String, _ edit: (inout Project) -> Void) {
        editor.apply(actionName, edit)
    }

    /// Lays the captions out again after an edit.
    func update(for project: Project) {
        pages = CaptionLayout.pages(in: project)
    }

    // MARK: State

    var spokenLanguage = CaptionLanguage.preferred()
    /// The spoken language is found by listening, rather than chosen.
    var findsLanguage = true
    /// What the language picker shows.
    var languageChoice: CaptionLanguageChoice {
        get { findsLanguage ? .automatic : .language(spokenLanguage) }
        set {
            switch newValue {
            case .automatic: findsLanguage = true
            case .language(let language):
                findsLanguage = false
                spokenLanguage = language
            }
        }
    }
    /// What the caption maker is doing, while it works.
    private(set) var job: Job?
    /// The captions as they appear on the timeline. Updated with every edit.
    private(set) var pages: [CaptionPage] = []
    /// The caption the user last clicked on the timeline, so the Captions list can show it.
    var focusedID: CaptionPage.ID?
    /// A caption whose words should start being edited (after splitting one in two).
    var toEdit: CaptionPage.ID?
    /// Where the cursor goes in that caption, in characters.
    var editCursor = 0
    /// What Apple Intelligence is reading the script for, while it works.
    var wordModelJob: WordModel.Task?
    /// Real words used as fillers ("like", "tipo"), found by Apple Intelligence in the Script panel.
    var modelFillers: Set<Word.ID> = []
    /// Set to start translating the captions (run by the editor's `translationTask`).
    var translationRequest: TranslationSession.Configuration?
    var isTranslating = false
    @ObservationIgnored private var task: Task<Void, Never>?

    enum Job: Equatable {
        /// Listening to the start of the sound to find the language spoken.
        case detecting
        /// Downloading the language's speech model, the first time it is used.
        case downloading(Double)
        /// Listening to file `index` of `count`.
        case listening(index: Int, count: Int)
    }

    /// The language new captions are made in: the Short's own when the language is found
    /// automatically and captions exist, else the chosen one.
    var languageForNewCaptions: CaptionLanguage {
        findsLanguage ? (project.captionLanguageInUse ?? spokenLanguage) : spokenLanguage
    }

    // MARK: Making captions

    /// Transcribes what is heard in the Short (clips, B-roll with sound, voice-overs) that doesn't
    /// have captions in the chosen language yet, then shows the captions. The result is one
    /// undoable step. With "Find automatically", the language is the one the Short's captions are
    /// already in, or found by listening. `quietly` keeps the panel and doesn't complain when
    /// nothing is heard (used after recording a voice-over).
    func make(quietly: Bool = false) {
        guard job == nil, !project.timeline.clips.isEmpty else { return }
        if !quietly { sidebar = .captions }
        if findsLanguage, let inUse = project.captionLanguageInUse { spokenLanguage = inUse }
        let detects = findsLanguage && project.captionLanguageInUse == nil
        guard detects || !project.assetsNeedingTranscription(in: spokenLanguage).isEmpty else {
            if !quietly { apply("Show Captions") { $0.captions.isVisible = true } }
            return
        }
        job = detects ? .detecting : .downloading(0)
        task = Task {
            defer { job = nil }
            do {
                let (language, transcripts) = try await tasks.run(.captions, title: "Making captions") { [self] progress in
                    var language = spokenLanguage
                    if detects, let first = project.assetsHeard().first {
                        progress.detail("Finding the language spoken")
                        language = try await Transcriber.detectLanguage(of: first.url, name: first.name, fallback: spokenLanguage)
                        spokenLanguage = language
                    }
                    job = .downloading(0)
                    progress.detail("Getting \(language.displayName) ready")
                    try await Transcriber.prepare(language) { fraction in
                        if case .downloading = self.job { self.job = .downloading(fraction) }
                    }
                    let assets = project.assetsNeedingTranscription(in: language)
                    var transcripts: [MediaAsset.ID: Transcript] = [:]
                    for (index, asset) in assets.enumerated() {
                        try Task.checkCancellation()
                        job = .listening(index: index + 1, count: assets.count)
                        progress.detail("Listening to “\(asset.name)”")
                        progress(Double(index) / Double(assets.count))
                        transcripts[asset.id] = try await Transcriber.transcribe(asset.url, name: asset.name, language: language)
                    }
                    try Task.checkCancellation()
                    return (language, transcripts)
                }
                apply(quietly ? "Make Voice-Over Captions" : "Make Captions") { project in
                    project.transcripts.merge(transcripts) { $1 }
                    project.captions.isVisible = true
                }
                if !project.hasCaptions, !quietly {
                    alert = AlertMessage(
                        title: "No speech found",
                        message:
                            "No words in \(language.displayName) were heard in your Short. "
                            + "Check the language, or that the clips or voice-overs have someone talking."
                    )
                }
            } catch is CancellationError {
                // The user stopped it; nothing changes.
            } catch {
                Log.captions.failure("Making captions", error)
                if !quietly { alert = AlertMessage("Captions couldn't be made", error: error, retry: { self.make() }) }
            }
        }
    }

    func cancel() {
        task?.cancel()
    }

    // MARK: A second language

    /// Translates the captions that have no up-to-date translation. Apple's Translation asks to
    /// download the languages the first time.
    func translate() {
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
            Log.captions.failure("runTranslation", error)
            alert = AlertMessage("The captions couldn't be translated", error: error)
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
        let language = project.captionLanguageInUse
        Task {
            defer { wordModelJob = nil }
            guard
                let picks = try? await tasks.run(
                    .wordModel, title: "Apple Intelligence is reading the script",
                    { _ in try await WordModel.picks(for: words, language: language, task: .keywords) }),
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
        if count == 0 { alert = AlertMessage(title: "No key words found", message: "Click a word in Captions ▸ Script to highlight it yourself.") }
    }

    /// Adds emoji to captions whose words call for one: chosen by Apple Intelligence when it is
    /// available, else from the built-in list.
    func suggestEmoji() {
        let words = project.script
        guard !words.isEmpty, wordModelJob == nil else { return }
        guard canUseWordModel else { return suggestEmojiByRules() }
        wordModelJob = .emoji
        let language = project.captionLanguageInUse
        Task {
            defer { wordModelJob = nil }
            guard
                let picks = try? await tasks.run(
                    .wordModel, title: "Apple Intelligence is reading the script",
                    { _ in try await WordModel.picks(for: words, language: language, task: .emoji) }),
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
        if count == 0 { alert = AlertMessage(title: "No emoji found", message: "None of the words call for one. Add one to a word in Captions ▸ Script.") }
    }

    /// Asks Apple Intelligence for real words used as fillers ("like", "tipo", "allora"); they join
    /// the filler sounds in the Script panel, ready to remove.
    func findMoreFillers() {
        let words = project.script.filter { $0.source == .clip }
        guard !words.isEmpty, wordModelJob == nil, canUseWordModel else { return }
        wordModelJob = .fillers
        let language = project.captionLanguageInUse
        Task {
            defer { wordModelJob = nil }
            do {
                let picks = try await tasks.run(
                    .wordModel, title: "Apple Intelligence is reading the script",
                    { _ in try await WordModel.picks(for: words, language: language, task: .fillers) })
                modelFillers = picks.fillers
                if picks.fillers.isEmpty {
                    alert = AlertMessage(
                        title: "No other fillers found", message: "Apple Intelligence didn't find words like “like” or “tipo” used as fillers.")
                }
            } catch {
                Log.captions.failure("findMoreFillers", error)
                alert = AlertMessage("Fillers couldn't be found", error: error)
            }
        }
    }
}
