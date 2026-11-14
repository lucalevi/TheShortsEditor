import CoreMedia
import Foundation

/// A word as it is on the timeline: which clip plays it, and which word of its file it is.
public struct WordRef: Hashable, Sendable {
    public var clipID: Clip.ID
    public var wordID: Word.ID

    public init(clipID: Clip.ID, wordID: Word.ID) {
        self.clipID = clipID
        self.wordID = wordID
    }
}

public extension TimedWord {
    var ref: WordRef { WordRef(clipID: clipID, wordID: wordID) }
}

/// Words compared without case, accents or punctuation ("Ciao," and "ciao" are the same).
enum WordText {
    static func normalized(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .trimmingCharacters(in: .punctuationCharacters.union(.symbols).union(.whitespaces))
    }
}

// MARK: - Filler words and repeats

public enum FillerWords {
    /// Sounds that are never real words, in all four caption languages.
    static let sounds: Set<String> = [
        "um", "umm", "uh", "uhm", "uhh", "er", "erm", "hmm", "mm", "mmm", "ah", "eh", "ehm", "ehh",
        "äh", "ah", "ähm", "ahm", "öh", "euh", "heu", "bah", "beh", "boh",
    ]

    public static func isFiller(_ text: String) -> Bool {
        let word = WordText.normalized(text)
        return !word.isEmpty && (sounds.contains(word) || sounds.contains(text.lowercased().trimmingCharacters(in: .punctuationCharacters)))
    }
}

public extension Project {
    /// Every word on the timeline, in order (the script).
    var script: [TimedWord] { CaptionLayout.timelineWords(in: self) }

    /// The filler sounds ("um", "eh"…) on the timeline, words said twice in a row ("I I
    /// think", "so so"), keeping the second time, and the words in `fillers` (real words used as
    /// fillers, found by the language model). Only words of the main clips, which can be cut.
    func fillerAndRepeatedWords(also fillers: Set<Word.ID> = []) -> [WordRef] {
        let words = script.filter { $0.source == .clip }
        var found: [WordRef] = []
        var index = 0
        while index < words.count {
            let word = words[index]
            if FillerWords.isFiller(word.text) || fillers.contains(word.wordID) {
                found.append(word.ref)
                index += 1
                continue
            }
            // Two words said twice ("I think I think"): drop the first time.
            if index + 3 < words.count, same(words[index], words[index + 2]), same(words[index + 1], words[index + 3]),
                !same(words[index], words[index + 1])
            {
                found += [words[index].ref, words[index + 1].ref]
                index += 2
                continue
            }
            if index + 1 < words.count, same(word, words[index + 1]), !isNumber(word.text) {
                found.append(word.ref)
            }
            index += 1
        }
        return found
    }

    private func same(_ a: TimedWord, _ b: TimedWord) -> Bool {
        a.clipID == b.clipID && WordText.normalized(a.text) == WordText.normalized(b.text) && !WordText.normalized(a.text).isEmpty
    }

    private func isNumber(_ text: String) -> Bool { text.contains { $0.isNumber } }

    /// What cutting `words` out of the Short removes: each word and the pause after it (up to
    /// the next word, when that comes within a second). Ready for `apply(_:)`, like Remove Pauses.
    func cutPlan(removing words: Set<WordRef>) -> SilencePlan {
        let all = script
        var sourceWords: [Word.ID: Word] = [:]
        for transcript in transcripts.values { for word in transcript.words { sourceWords[word.id] = word } }
        var byClip: [Clip.ID: [CMTimeRange]] = [:]
        for (index, timed) in all.enumerated() where words.contains(timed.ref) {
            guard let word = sourceWords[timed.wordID], let clip = timeline.clips.first(where: { $0.id == timed.clipID }) else { continue }
            var end = word.end
            if index + 1 < all.count, all[index + 1].clipID == timed.clipID, let next = sourceWords[all[index + 1].wordID],
                next.start >= word.end, (next.start - word.end).seconds < 1
            {
                end = next.start
            }
            let range = CMTimeRange(start: word.start, end: end).intersection(clip.sourceRange)
            if range.duration > .zero { byClip[timed.clipID, default: []].append(range) }
        }
        var plan = SilencePlan()
        var clipStart = CMTime.zero
        for clip in timeline.clips {
            defer { clipStart = clipStart + clip.duration }
            guard let ranges = byClip[clip.id] else { continue }
            let merged = Self.merged(ranges)
            plan.sourceCuts[clip.id] = merged
            plan.timelineCuts += merged.map {
                CMTimeRange(start: clipStart + clip.timelineOffset(ofSourceTime: $0.start), duration: clip.timelineDuration(ofSource: $0.duration))
            }
        }
        return plan
    }

    private static func merged(_ ranges: [CMTimeRange]) -> [CMTimeRange] {
        var result: [CMTimeRange] = []
        for range in ranges.sorted(by: { $0.start < $1.start }) {
            if let last = result.last, range.start <= last.end + .oneFrame {
                result[result.count - 1] = CMTimeRange(start: last.start, end: max(last.end, range.end))
            } else {
                result.append(range)
            }
        }
        return result
    }

    /// Changes the words of the transcripts, wherever they are.
    mutating func updateWords(_ ids: Set<Word.ID>, _ change: (inout Word) -> Void) {
        for (assetID, var transcript) in transcripts {
            var changed = false
            for index in transcript.words.indices where ids.contains(transcript.words[index].id) {
                change(&transcript.words[index])
                changed = true
            }
            if changed { transcripts[assetID] = transcript }
        }
    }
}

// MARK: - Key words

public enum Keywords {
    /// Small words that are never worth highlighting.
    static let common: Set<String> = [
        // English
        "the", "and", "that", "this", "with", "have", "from", "they", "what", "when", "your", "about", "because", "there",
        "their", "would", "could", "should", "which", "really", "actually", "something", "everyone", "everything", "people",
        "going", "being", "doing", "thing", "things", "today", "these", "those", "where", "while", "other", "another",
        // Italian
        "perche", "quando", "questo", "questa", "quello", "quella", "sempre", "ancora", "allora", "proprio", "davvero",
        "qualcosa", "tutti", "tutto", "anche", "molto", "dovete", "potete", "abbiamo", "facciamo", "oggi",
        // German
        "nicht", "diese", "dieser", "dieses", "weil", "wenn", "immer", "schon", "wirklich", "eigentlich", "etwas", "heute",
        "werden", "haben", "einfach", "sondern",
        // French
        "parce", "quand", "cette", "toujours", "encore", "vraiment", "quelque", "chose", "aujourd'hui", "aujourdhui",
        "avoir", "faire", "beaucoup", "maintenant",
    ]

    /// How much a word stands out: numbers and long, meaningful words most. Zero means never.
    static func score(_ text: String, startsSentence: Bool) -> Double {
        let word = WordText.normalized(text)
        guard word.count >= 2, !common.contains(word), !FillerWords.isFiller(text) else { return 0 }
        if text.contains(where: \.isNumber) { return 5 }
        if text.contains("%") || text.contains("$") || text.contains("€") { return 5 }
        var score = 0.0
        if word.count >= 6 { score += Double(word.count) / 3 }
        // A capital in the middle of a sentence: a name or a brand.
        if let first = text.first, first.isUppercase, !startsSentence, word.count >= 3 { score += 2.5 }
        return score
    }

    /// Picks about one key word in every `every` words: the one that stands out most in each stretch.
    public static func pick(from words: [Word], every: Int = 7) -> Set<Word.ID> {
        var picked: Set<Word.ID> = []
        var start = 0
        while start < words.count {
            let stretch = words[start..<min(start + every, words.count)]
            var best: (Word.ID, Double)?
            for (offset, word) in stretch.enumerated() {
                let index = start + offset
                let previous = index > 0 ? words[index - 1].text : "."
                let startsSentence = previous.last.map { ".?!…".contains($0) } ?? true
                let value = score(word.text, startsSentence: startsSentence)
                if value >= 2, value > (best?.1 ?? 0) { best = (word.id, value) }
            }
            if let best { picked.insert(best.0) }
            start += every
        }
        return picked
    }
}

public extension Project {
    /// Marks the key words in every transcript, replacing earlier picks. Returns how many.
    @discardableResult
    mutating func pickKeywords() -> Int {
        var count = 0
        for (assetID, var transcript) in transcripts {
            let picked = Keywords.pick(from: transcript.words)
            for index in transcript.words.indices { transcript.words[index].isKeyword = picked.contains(transcript.words[index].id) }
            count += picked.count
            transcripts[assetID] = transcript
        }
        return count
    }
}

// MARK: - Emoji

public enum EmojiSuggestions {
    /// An emoji and the words that call for it, in English, Italian, German and French. Short
    /// stems match only whole words (or a plural); longer ones match the start of a word.
    static let table: [(emoji: String, stems: [String])] = [
        ("💰", ["money", "cash", "dollar", "euro", "soldi", "denaro", "geld", "argent", "rich", "ricco", "reich", "riche"]),
        ("🔥", ["fire", "hot", "fuoco", "feuer", "feu", "viral"]),
        ("❤️", ["love", "heart", "amore", "cuore", "liebe", "herz", "amour", "coeur"]),
        ("💡", ["idea", "idee", "tip", "trick", "consiglio", "trucco", "tipp", "astuce", "conseil"]),
        ("🧠", ["brain", "think", "mind", "cervello", "pensa", "mente", "gehirn", "denke", "cerveau", "pense"]),
        ("⏰", ["time", "minute", "hour", "tempo", "minut", "zeit", "stunde", "temps", "heure"]),
        ("🚀", ["rocket", "launch", "growth", "grow", "crescita", "cresce", "wachstum", "wachsen", "croissance", "fast", "veloce", "schnell", "rapide"]),
        ("😂", ["funny", "laugh", "joke", "ridere", "divertente", "scherzo", "lachen", "lustig", "witz", "rire", "drole", "blague"]),
        ("😱", ["shock", "scary", "crazy", "paura", "pazzesco", "incredibil", "angst", "verruckt", "peur", "incroyable", "unbelievab", "insane"]),
        ("⚠️", ["warning", "careful", "danger", "attenzione", "pericol", "achtung", "vorsicht", "gefahr", "attention"]),
        ("✅", ["correct", "done", "fatto", "giusto", "corretto", "richtig", "fertig", "vrai", "fait"]),
        ("❌", ["wrong", "mistake", "never", "errore", "sbagliat", "fehler", "falsch", "erreur", "faux", "jamais"]),
        ("📱", ["phone", "iphone", "app", "telefono", "cellulare", "handy", "telephone", "portable"]),
        ("🎥", ["video", "camera", "film", "youtube", "shorts"]),
        ("🎵", ["music", "song", "musica", "canzone", "musik", "lied", "musique", "chanson"]),
        ("🍕", ["food", "eat", "pizza", "cibo", "mangia", "essen", "nourriture", "manger"]),
        ("☕", ["coffee", "caffe", "kaffee", "cafe"]),
        ("💼", ["work", "job", "business", "lavoro", "azienda", "arbeit", "firma", "travail", "entreprise"]),
        ("📚", ["book", "study", "learn", "school", "libro", "studi", "impara", "scuola", "buch", "lernen", "schule", "livre", "apprend", "ecole"]),
        ("🌍", ["world", "mondo", "welt", "monde", "planet"]),
        ("🏠", ["home", "house", "casa", "haus", "maison"]),
        ("🚗", ["car", "auto", "macchina", "voiture", "drive", "guida", "fahren", "conduire"]),
        ("🏆", ["win", "winner", "champion", "vince", "vittoria", "gewinn", "sieg", "gagne", "victoire"]),
        ("💪", ["strong", "power", "forte", "forza", "stark", "kraft", "fort", "force", "gym", "palestra", "workout", "fitness"]),
        ("😴", ["sleep", "tired", "dormi", "stanco", "schlaf", "mude", "dormir", "fatigue"]),
        ("👀", ["look", "watch", "guarda", "vedi", "schau", "sehen", "regarde", "voir"]),
        ("❓", ["why", "question", "perche", "domanda", "warum", "frage", "pourquoi"]),
        ("💯", ["hundred", "perfect", "perfetto", "perfekt", "parfait"]),
        ("🎉", ["party", "celebrat", "festa", "feier", "fete", "birthday", "complean", "geburtstag", "anniversaire"]),
        ("🎯", ["goal", "target", "obiettivo", "ziel", "objectif"]),
        ("🤫", ["secret", "segreto", "geheim"]),
        ("🐶", ["dog", "cane", "hund", "chien"]),
        ("🐱", ["cat", "gatto", "katze"]),
        ("👨‍👩‍👧", ["family", "famiglia", "familie", "famille"]),
        ("🤝", ["friend", "amico", "amica", "amici", "freund", "ami", "amis"]),
        ("✈️", ["travel", "trip", "viaggi", "reise", "voyage", "flight", "volo", "flug", "vol"]),
        ("✨", ["new", "magic", "nuovo", "nuova", "magia", "neu", "magie", "nouveau", "nouvelle"]),
        ("🆓", ["free", "gratis", "gratuit", "kostenlos"]),
        ("😊", ["happy", "felice", "glucklich", "heureux", "heureuse"]),
        ("😢", ["sad", "triste", "traurig", "cry", "piange", "weinen", "pleure"]),
        ("😡", ["angry", "arrabbiat", "wutend", "wut", "colere", "fache"]),
        ("📈", ["sales", "views", "numbers", "vendite", "visualizzazioni", "verkauf", "aufrufe", "ventes", "vues"]),
        ("☀️", ["sun", "summer", "sole", "estate", "sonne", "sommer", "soleil"]),
    ]

    /// The emoji a word calls for, if any.
    public static func emoji(for text: String) -> String? {
        let word = WordText.normalized(text)
        guard word.count >= 3 else { return nil }
        for entry in table {
            for stem in entry.stems {
                if stem.count < 5 ? (word == stem || word == stem + "s") : word.hasPrefix(stem) { return entry.emoji }
            }
        }
        return nil
    }
}

public extension Project {
    /// Gives words that call for one an emoji, at most one in each caption, replacing earlier
    /// suggestions. `choose` gives a word's emoji (the built-in table unless given). Returns how many.
    @discardableResult
    mutating func suggestEmoji(_ choose: (TimedWord) -> String? = { EmojiSuggestions.emoji(for: $0.text) }) -> Int {
        let pages = CaptionLayout.pages(in: self)
        var chosen: Set<Word.ID> = []
        var emojis: [Word.ID: String] = [:]
        for page in pages {
            for word in page.words {
                if let emoji = choose(word) {
                    chosen.insert(word.wordID)
                    emojis[word.wordID] = emoji
                    break
                }
            }
        }
        for (assetID, var transcript) in transcripts {
            for index in transcript.words.indices {
                transcript.words[index].emoji = emojis[transcript.words[index].id]
            }
            transcripts[assetID] = transcript
        }
        return chosen.count
    }
}
