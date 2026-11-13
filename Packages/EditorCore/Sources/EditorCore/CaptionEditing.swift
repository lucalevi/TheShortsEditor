import CoreMedia
import Foundation

// Editing captions like text (split, merge, line breaks, timing), SRT files, translations and
// the on-device language model's word picks. Everything is stored on the words of each file's
// transcript, so it follows the clips like the rest of the captions.

/// A caption's text broken into words, remembering where the user put a new line.
public enum CaptionText {
    public struct Token: Equatable, Sendable {
        public var text: String
        public var lineBreakAfter: Bool

        public init(_ text: String, lineBreakAfter: Bool = false) {
            self.text = text
            self.lineBreakAfter = lineBreakAfter
        }
    }

    public static func tokens(_ text: String) -> [Token] {
        var tokens: [Token] = []
        var current = ""
        var sawNewline = false
        func finish() {
            guard !current.isEmpty else { return }
            if sawNewline, !tokens.isEmpty { tokens[tokens.count - 1].lineBreakAfter = true }
            tokens.append(Token(current))
            current = ""
            sawNewline = false
        }
        for character in text {
            if character.isNewline {
                finish()
                sawNewline = true
            } else if character.isWhitespace {
                finish()
            } else {
                current.append(character)
            }
        }
        finish()
        return tokens
    }

    /// Tokens back into text, with a new line where one was chosen.
    public static func string(_ tokens: [Token]) -> String {
        var result = ""
        for (index, token) in tokens.enumerated() {
            if index > 0 { result += tokens[index - 1].lineBreakAfter ? "\n" : " " }
            result += token.text
        }
        return result
    }
}

/// Which edge of a caption is being dragged on the timeline.
public enum CaptionEdge: Sendable {
    case start, end
}

public extension Project {
    // MARK: Split, merge, line breaks

    /// Splits a caption in two at `offset` characters into `text` (what the field shows, edits
    /// included). The second half becomes a caption of its own; the captions after it stay as they
    /// were. Returns the first word of the new caption, or nil when there was nothing to split
    /// (the cursor at the very start or end), in which case only the text is saved.
    @discardableResult
    mutating func splitCaption(_ wordIDs: [Word.ID], in assetID: MediaAsset.ID, text: String, at offset: Int) -> Word.ID? {
        let offset = min(max(offset, 0), text.count)
        var left = CaptionText.tokens(String(text.prefix(offset)))
        let right = CaptionText.tokens(String(text.dropFirst(offset)))
        guard !left.isEmpty, !right.isEmpty else {
            replaceWords(wordIDs, in: assetID, with: text)
            return nil
        }
        left[left.count - 1].lineBreakAfter = false
        let ids = replaceWords(wordIDs, in: assetID, with: CaptionText.string(left + right))
        guard ids.count == left.count + right.count else { return nil }
        let newFirst = ids[left.count]
        updateWords([newFirst]) { $0.captionBreak = .newCaption }
        // Both halves keep their shape in every look.
        pinCaptionStart(ids[0])
        // The second half ends where the old caption did.
        if let last = ids.last { keepCaptionStarting(after: last, in: assetID) }
        return newFirst
    }

    /// Joins a caption to the one before it (in the same clip, starting with `previousFirst`),
    /// saving `text` first. The joined caption keeps its shape in every look.
    mutating func mergeCaptionWithPrevious(_ wordIDs: [Word.ID], in assetID: MediaAsset.ID, text: String, previousFirst: Word.ID? = nil) {
        let ids = replaceWords(wordIDs, in: assetID, with: text)
        guard let last = ids.last else { return }
        updateWords(Set(ids)) { $0.captionBreak = .joined }
        if let previousFirst { pinCaptionStart(previousFirst) }
        keepCaptionStarting(after: last, in: assetID)
    }

    /// Makes a caption start at this word in every look, unless the user chose otherwise.
    private mutating func pinCaptionStart(_ wordID: Word.ID) {
        updateWords([wordID]) { if $0.captionBreak == nil { $0.captionBreak = .newCaption } }
    }

    /// Makes the word after `wordID` start a caption, unless the user already chose otherwise, so
    /// splitting or joining one caption never reflows the ones after it.
    private mutating func keepCaptionStarting(after wordID: Word.ID, in assetID: MediaAsset.ID) {
        guard var transcript = transcripts[assetID],
              let index = transcript.words.firstIndex(where: { $0.id == wordID }),
              index + 1 < transcript.words.count,
              transcript.words[index + 1].captionBreak == nil
        else { return }
        transcript.words[index + 1].captionBreak = .newCaption
        transcripts[assetID] = transcript
    }

    // MARK: Timing

    /// Moves the start or end of a caption to `time` on the timeline, by changing when its first
    /// or last word is said. A caption whose end was moved ends exactly there. Words never cross
    /// the words next to them, and each keeps at least one frame.
    mutating func moveCaptionEdge(_ page: CaptionPage, _ edge: CaptionEdge, to time: CMTime) {
        guard let (clip, clipStart) = anyClip(page.clipID), var transcript = transcripts[page.assetID] else { return }
        let offset = (time - clipStart).clamped(.zero, clip.duration)
        let sourceTime = clip.sourceTime(atOffset: offset).snappedToFrame()
        let wordID = edge == .start ? page.words[0].wordID : page.words[page.words.count - 1].wordID
        guard let index = transcript.words.firstIndex(where: { $0.id == wordID }) else { return }
        var word = transcript.words[index]
        switch edge {
        case .start:
            let earliest = max(index > 0 ? transcript.words[index - 1].end : .zero, clip.sourceStart)
            let start = sourceTime.clamped(earliest, word.end - .oneFrame)
            word.duration = word.end - start
            word.start = start
        case .end:
            let next = index + 1 < transcript.words.count ? transcript.words[index + 1].start : clip.sourceRange.end
            let latest = min(next, clip.sourceRange.end)
            let end = sourceTime.clamped(word.start + .oneFrame, max(latest, word.start + .oneFrame))
            word.duration = end - word.start
            word.endsExactly = true
        }
        transcript.words[index] = word
        transcripts[page.assetID] = transcript
    }

    /// Lets the captions flow again: removes every split, join and exact end the user made.
    mutating func resetCaptionBreaks() {
        let ids = Set(transcripts.values.flatMap(\.words).map(\.id))
        updateWords(ids) { word in
            word.captionBreak = nil
            word.endsExactly = false
        }
    }

    /// The language the Short's captions are in: the one most of its heard words are in, or nil
    /// before any captions are made.
    var captionLanguageInUse: CaptionLanguage? {
        var counts: [CaptionLanguage: Int] = [:]
        for asset in assetsHeard() {
            guard let transcript = transcripts[asset.id] else { continue }
            counts[transcript.language, default: 0] += max(transcript.words.count, 1)
        }
        return counts.max { $0.value < $1.value || ($0.value == $1.value && $0.key.rawValue > $1.key.rawValue) }?.key
    }

    /// Removes every caption, so they can be made again from scratch.
    mutating func removeAllCaptions() {
        transcripts = [:]
    }

    // MARK: Translations

    /// Stores translations of captions (keyed by each caption's first word).
    mutating func setTranslations(_ translations: [Word.ID: CaptionTranslation]) {
        updateWords(Set(translations.keys)) { $0.translation = translations[$0.id] }
    }

    mutating func clearTranslations() {
        let ids = Set(transcripts.values.flatMap(\.words).filter { $0.translation != nil }.map(\.id))
        updateWords(ids) { $0.translation = nil }
    }

    /// The captions that have no up-to-date translation yet.
    func captionsNeedingTranslation() -> [CaptionPage] {
        CaptionLayout.pages(in: self).filter { $0.translation == nil }
    }

    /// The sentences (runs of captions, see `CaptionSentences`) with a caption that has no
    /// up-to-date translation. A whole sentence is translated again, so its pieces fit together.
    func sentencesNeedingTranslation() -> [[CaptionPage]] {
        CaptionSentences.groups(CaptionLayout.pages(in: self)).filter { $0.contains { $0.translation == nil } }
    }

    /// Stores the translation of a whole sentence, shared out over its captions.
    mutating func setTranslation(_ translated: String, of sentence: [CaptionPage]) {
        let pieces = CaptionSentences.distribute(translated, over: sentence)
        var translations: [Word.ID: CaptionTranslation] = [:]
        for (page, piece) in zip(sentence, pieces) {
            translations[page.words[0].wordID] = CaptionTranslation(source: page.plainText, text: piece)
        }
        setTranslations(translations)
    }

    // MARK: SRT

    /// Replaces the captions with the cues of a subtitle file, timed on the timeline. Each word goes
    /// to what is heard at its moment (a voice-over first, then the main clip), and each cue
    /// becomes one caption ending when the cue does. Returns how many cues were placed.
    @discardableResult
    mutating func importCaptions(_ cues: [CaptionCue], language: CaptionLanguage) -> Int {
        var placed: [MediaAsset.ID: [Word]] = [:]
        var cueCount = 0
        let length = duration
        for cue in cues {
            let start = cue.start.snappedToFrame(), end = min(cue.end, length).snappedToFrame()
            let tokens = CaptionText.tokens(cue.text)
            guard end > start, !tokens.isEmpty else { continue }
            let total = end - start
            let weights = tokens.map { Double($0.text.count) + 1 }
            let sum = weights.reduce(0, +)
            var cursor = start
            var accumulated = 0.0
            var placedAny = false
            var lastWord: (asset: MediaAsset.ID, id: Word.ID)?
            for (index, token) in tokens.enumerated() {
                accumulated += weights[index]
                let wordEnd = index == tokens.count - 1 ? end : start + CMTimeMultiplyByFloat64(total, multiplier: accumulated / sum)
                defer { cursor = wordEnd }
                let middle = cursor + CMTimeMultiplyByRatio(wordEnd - cursor, multiplier: 1, divisor: 2)
                guard let (clip, clipStart) = captionTarget(at: middle) else { continue }
                let clipRange = CMTimeRange(start: clipStart, duration: clip.duration)
                let from = max(cursor, clipRange.start), to = min(wordEnd, clipRange.end)
                guard to > from else { continue }
                let sourceStart = clip.sourceTime(atOffset: from - clipStart)
                let sourceEnd = max(clip.sourceTime(atOffset: to - clipStart), sourceStart + CMTime(value: 1, timescale: 600))
                var word = Word(text: token.text, start: sourceStart, duration: sourceEnd - sourceStart, lineBreakAfter: token.lineBreakAfter)
                if !placedAny { word.captionBreak = .newCaption } else { word.captionBreak = .joined }
                placed[clip.assetID, default: []].append(word)
                lastWord = (clip.assetID, word.id)
                placedAny = true
            }
            if let lastWord, let index = placed[lastWord.asset]?.lastIndex(where: { $0.id == lastWord.id }) {
                placed[lastWord.asset]?[index].endsExactly = true
                placed[lastWord.asset]?[index].lineBreakAfter = false
            }
            if placedAny { cueCount += 1 }
        }
        transcripts = [:]
        for asset in assetsHeard() { transcripts[asset.id] = Transcript(language: language, words: [], isTyped: true) }
        for (assetID, words) in placed {
            // The same moment of a file used twice gets its words once. Words that only touch
            // (rounding at a cue's edge) are kept, starting where the one before ends.
            var kept: [Word] = []
            for var word in words.sorted(by: { $0.start < $1.start }) {
                if let last = kept.last, word.start < last.end {
                    let overlap = last.end - word.start
                    guard overlap < CMTimeMultiplyByRatio(word.duration, multiplier: 1, divisor: 2) else { continue }
                    word.duration = word.end - last.end
                    word.start = last.end
                }
                kept.append(word)
            }
            transcripts[assetID] = Transcript(language: language, words: kept, isTyped: true)
        }
        return cueCount
    }

    /// What typed captions at `time` belong to: a voice-over or other sound item, else the main clip.
    private func captionTarget(at time: CMTime) -> (Clip, CMTime)? {
        let heard = sounds.filter { sound in
            sound.clip.effectiveVolume > 0 && sound.range.containsTime(time) && asset(id: sound.clip.assetID).map { !$0.isBuiltInSound } == true
        }
        if let sound = heard.first(where: \.isVoiceOver) ?? heard.first { return (sound.clip, sound.start) }
        guard let (index, _) = timeline.locate(time) else { return nil }
        let clip = timeline.clips[index]
        if clip.soundDetached, let sound = sounds.first(where: { $0.detachedFrom == clip.id }), sound.range.containsTime(time) {
            return (sound.clip, sound.start)
        }
        return (clip, timeline.startTime(ofClipAt: index))
    }
}

// MARK: - SRT files

/// One subtitle of a subtitle file: its text, on the timeline from `start` to `end`.
public struct CaptionCue: Equatable, Sendable {
    public var start: CMTime
    public var end: CMTime
    public var text: String

    public init(start: CMTime, end: CMTime, text: String) {
        self.start = start
        self.end = end
        self.text = text
    }
}

/// SubRip (.srt), the subtitle file YouTube and every editor read.
public enum SRT {
    public enum ReadError: LocalizedError, Equatable {
        case noSubtitles

        public var errorDescription: String? {
            "No subtitles were found in this file. It should be an .srt file, with times like 00:00:01,000 --> 00:00:02,500."
        }
    }

    /// The captions as an SRT file. With `includeTranslation`, each caption's translation (when it
    /// has one) is a second line, as on screen.
    public static func text(for pages: [CaptionPage], includeTranslation: Bool = false) -> String {
        var lines: [String] = []
        for (index, page) in pages.enumerated() {
            lines.append("\(index + 1)")
            lines.append("\(timestamp(page.range.start)) --> \(timestamp(page.range.end))")
            lines.append(page.text)
            if includeTranslation, let translation = page.translation { lines.append(translation) }
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }

    public static func cues(from text: String) throws -> [CaptionCue] {
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
            .trimmingCharacters(in: CharacterSet(charactersIn: "\u{FEFF}"))
        var cues: [CaptionCue] = []
        var current: (start: CMTime, end: CMTime, lines: [String])?
        func finish() {
            if let cue = current {
                let body = cue.lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
                if !body.isEmpty, cue.end > cue.start { cues.append(CaptionCue(start: cue.start, end: cue.end, text: stripTags(body))) }
            }
            current = nil
        }
        for raw in normalized.components(separatedBy: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.contains("-->") {
                finish()
                let parts = line.components(separatedBy: "-->")
                if parts.count == 2, let start = time(parts[0]), let end = time(parts[1].split(separator: " ", omittingEmptySubsequences: true).first.map(String.init) ?? "") {
                    current = (start, end, [])
                }
            } else if line.isEmpty {
                finish()
            } else if current != nil {
                current?.lines.append(line)
            }
            // A line before any time (the cue's number) is skipped.
        }
        finish()
        guard !cues.isEmpty else { throw ReadError.noSubtitles }
        return cues.sorted { $0.start < $1.start }
    }

    /// "00:01:02,500" (or with a dot) as a time.
    static func time(_ text: String) -> CMTime? {
        let parts = text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ".", with: ",").split(separator: ",")
        guard let clock = parts.first else { return nil }
        let fields = clock.split(separator: ":").compactMap { Int($0) }
        guard (2...3).contains(fields.count) else { return nil }
        let seconds = fields.reduce(0) { $0 * 60 + $1 }
        var millis = 0
        if parts.count > 1 {
            let digits = String(parts[1].prefix(3))
            guard let value = Int(digits) else { return nil }
            millis = value * Int(pow(10, Double(3 - digits.count)))
        }
        return CMTime(value: CMTimeValue(seconds * 1000 + millis), timescale: 1000)
    }

    static func timestamp(_ time: CMTime) -> String {
        let millis = max(Int((time.seconds * 1000).rounded()), 0)
        return String(format: "%02d:%02d:%02d,%03d", millis / 3_600_000, millis / 60_000 % 60, millis / 1000 % 60, millis % 1000)
    }

    /// Removes the simple formatting tags some files have (<i>, <b>, <font …>, {\an8}).
    private static func stripTags(_ text: String) -> String {
        text.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "\\{\\\\[^}]*\\}", with: "", options: .regularExpression)
    }
}

// MARK: - Smarter words

/// What the on-device language model picked in the script: key words, emoji, and filler words that
/// are real words used as fillers ("like", "tipo", "allora"). The rules in `Keywords`,
/// `EmojiSuggestions` and `FillerWords` are used when the model isn't available.
public struct SmartWordPicks: Equatable, Sendable {
    public var keywords: Set<Word.ID> = []
    public var emoji: [Word.ID: String] = [:]
    public var fillers: Set<Word.ID> = []

    public init(keywords: Set<Word.ID> = [], emoji: [Word.ID: String] = [:], fillers: Set<Word.ID> = []) {
        self.keywords = keywords
        self.emoji = emoji
        self.fillers = fillers
    }

    public mutating func merge(_ other: SmartWordPicks) {
        keywords.formUnion(other.keywords)
        emoji.merge(other.emoji) { $1 }
        fillers.formUnion(other.fillers)
    }
}

public enum SmartWords {
    /// The script in pieces small enough for the model, each with its words numbered from 1.
    public static func chunks(of words: [TimedWord], size: Int = 120) -> [[TimedWord]] {
        stride(from: 0, to: words.count, by: max(size, 1)).map { Array(words[$0..<min($0 + size, words.count)]) }
    }

    /// "1 Hello 2 everyone 3 um …", the words as the model reads them.
    public static func numbered(_ words: [TimedWord]) -> String {
        words.enumerated().map { "[\($0.offset + 1)] \($0.element.text)" }.joined(separator: " ")
    }

    /// The model's answer for one chunk, as numbers into it, turned into picks. Numbers out of range
    /// are dropped, and so are emoji that aren't one emoji, and fillers that carry a number.
    public static func picks(in chunk: [TimedWord], keywords: [Int], fillers: [Int], emoji: [(Int, String)]) -> SmartWordPicks {
        func word(_ number: Int) -> TimedWord? { chunk.indices.contains(number - 1) ? chunk[number - 1] : nil }
        var picks = SmartWordPicks()
        for number in keywords { if let word = word(number), Keywords.score(word.text, startsSentence: false) > 0 || word.text.contains(where: \.isNumber) { picks.keywords.insert(word.wordID) } }
        for number in fillers {
            if let word = word(number), !word.text.contains(where: \.isNumber), WordText.normalized(word.text).count <= 12 {
                picks.fillers.insert(word.wordID)
            }
        }
        for (number, value) in emoji {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            if let word = word(number), EmojiSuggestions.isSingleEmoji(trimmed) { picks.emoji[word.wordID] = trimmed }
        }
        return picks
    }
}

public extension EmojiSuggestions {
    /// Whether `text` is exactly one emoji (flags, skin tones and families included).
    static func isSingleEmoji(_ text: String) -> Bool {
        guard text.count == 1, let character = text.first else { return false }
        let scalars = character.unicodeScalars
        return scalars.contains { $0.properties.isEmojiPresentation } || (scalars.count > 1 && scalars.contains { $0.properties.isEmoji })
    }
}

public extension Project {
    /// Marks the model's key words, replacing earlier picks. Returns how many.
    @discardableResult
    mutating func setKeywords(_ picked: Set<Word.ID>) -> Int {
        let ids = Set(transcripts.values.flatMap(\.words).map(\.id))
        updateWords(ids) { $0.isKeyword = picked.contains($0.id) }
        return picked.intersection(ids).count
    }

    /// Gives words the emoji in `choices`, at most one in each caption, replacing earlier ones.
    /// Returns how many.
    @discardableResult
    mutating func setEmoji(_ choices: [Word.ID: String]) -> Int {
        suggestEmoji { choices[$0.wordID] }
    }
}

// MARK: - Finding the spoken language

/// How well a sample was understood in one language, for picking the spoken language. A model
/// listening in the wrong language hears fewer words and is less sure of them.
public enum LanguageGuess {
    /// The speech model's confidence in each word it heard (nil when it gave none), summed and
    /// divided by at least `fewWords`, so a couple of lucky words don't win.
    public static func score(confidences: [Double?], fewWords: Int = 8) -> Double {
        guard !confidences.isEmpty else { return 0 }
        let sum = confidences.reduce(0) { $0 + ($1 ?? 0.5) }
        return sum / Double(max(confidences.count, fewWords))
    }
}

/// Captions are translated a sentence at a time: a short caption alone ("tipo il trucco più") is
/// translated without what it means, so the sentence is translated whole and its translation
/// shared out over its captions.
public enum CaptionSentences {
    /// A sentence never spans more captions than this (long talk without full stops).
    public static let maxPages = 8
    /// A pause this long between captions ends a sentence too.
    public static let pause = CMTime(value: 1, timescale: 1)

    /// The captions in runs that each make one sentence: a run ends after a caption that ends a
    /// sentence (. ! ? …), before a pause or a caption heard from another file, or at `maxPages`.
    public static func groups(_ pages: [CaptionPage]) -> [[CaptionPage]] {
        var groups: [[CaptionPage]] = []
        var current: [CaptionPage] = []
        for page in pages {
            if let last = current.last, last.source != page.source || page.range.start - last.range.end >= pause || current.count >= maxPages {
                groups.append(current)
                current = []
            }
            current.append(page)
            if endsSentence(page.plainText) {
                groups.append(current)
                current = []
            }
        }
        if !current.isEmpty { groups.append(current) }
        return groups
    }

    static func endsSentence(_ text: String) -> Bool {
        var trimmed = text.trimmingCharacters(in: .whitespaces)
        // Closing quotes and brackets after the stop.
        while let last = trimmed.last, "\"'”’»)]".contains(last) { trimmed.removeLast() }
        return trimmed.last.map { ".!?…。！？".contains($0) } ?? false
    }

    /// Shares a translated sentence out over its captions, each getting a part as long as its
    /// own words are (in characters), with at least one word each when there are enough. Languages
    /// written without spaces are shared out by characters.
    public static func distribute(_ translated: String, over pages: [CaptionPage]) -> [String] {
        let text = translated.trimmingCharacters(in: .whitespacesAndNewlines)
        guard pages.count > 1 else { return pages.isEmpty ? [] : [text] }
        let words = text.split(whereSeparator: \.isWhitespace).map(String.init)
        let bySpaces = words.count >= pages.count || text.contains(" ")
        let tokens = bySpaces ? words : text.map(String.init)
        let separator = bySpaces ? " " : ""
        let weights = pages.map { max(Double($0.plainText.count), 1) }
        let total = weights.reduce(0, +)
        var pieces: [String] = []
        var taken = 0
        var sum = 0.0
        for (index, weight) in weights.enumerated() {
            sum += weight
            let remainingPages = pages.count - index - 1
            var end = index == pages.count - 1 ? tokens.count : Int((Double(tokens.count) * sum / total).rounded())
            if tokens.count >= pages.count {
                // At least one each: leave enough for the captions still to come.
                end = min(max(end, taken + 1), tokens.count - remainingPages)
            }
            end = min(max(end, taken), tokens.count)
            pieces.append(tokens[taken..<end].joined(separator: separator))
            taken = end
        }
        return pieces
    }
}
