import CoreMedia
import Foundation

// Stage L: finding the best moments. Magic Short cut to 30 s or a minute used to keep the start;
// now it reads what is said, sentence by sentence, and keeps the sentences that make the best
// Short (picked by Apple's on-device language model, see `Transcription.WordModel.bestMoments`,
// or by the rules here when it isn't available), in their order.

/// One sentence said in the main clips, where it is on the timeline.
public struct SpokenSentence: Equatable, Sendable {
    public var text: String
    /// From its first word's start to its last word's end.
    public var range: CMTimeRange
    /// Its first word, which names it across edits (see `Project.keepSentences`).
    public var firstWordID: Word.ID
    public var wordCount: Int

    public var seconds: Double { range.duration.seconds }
}

public enum MomentPicker {
    /// A sentence ends at one of these, or after this long a gap, or at this many words.
    static let sentenceEnds = Set(".?!…")
    static let gap = 1.2
    static let maxWords = 40

    /// What makes a sentence worth keeping when no language model is at hand: questions,
    /// exclamations, numbers and long words (names, things) said quickly. Counted per second,
    /// times its length, so a window of sentences adds up.
    public static func score(_ sentence: SpokenSentence) -> Double {
        let text = sentence.text
        // Plain talk counts for little, so a run of it never beats a livelier, shorter one.
        var bonus = 0.3
        if text.contains("?") { bonus += 0.8 }
        if text.contains("!") { bonus += 0.5 }
        if text.contains(where: \.isNumber) { bonus += 0.6 }
        let words = text.split(separator: " ")
        let strong = words.filter { $0.count >= 7 }.count
        bonus += min(Double(strong) / max(Double(words.count), 1) * 2, 0.8)
        // Talking fast and densely is livelier than slow, hesitant speech.
        let pace = Double(sentence.wordCount) / max(sentence.seconds, 0.5)
        bonus += min(max(pace - 2, 0) * 0.15, 0.4)
        return bonus * max(sentence.seconds, 0.5)
    }

    /// The run of sentences, one after another, with the highest score that is no longer than
    /// `target` (seconds, gaps between them counted). Their indexes, in order.
    public static func bestRun(_ sentences: [SpokenSentence], target: Double) -> [Int] {
        guard !sentences.isEmpty else { return [] }
        var best: (score: Double, range: Range<Int>) = (-1, 0..<0)
        for start in sentences.indices {
            var total = 0.0
            for end in start..<sentences.count {
                let length = (sentences[end].range.end - sentences[start].range.start).seconds
                if length > target { break }
                total += score(sentences[end])
                // The opening sentence counts a little more: it is the hook.
                let value = total + score(sentences[start]) * 0.25
                if value > best.score { best = (value, start..<(end + 1)) }
            }
        }
        if best.range.isEmpty { return [0] }
        return Array(best.range)
    }

    /// Makes sense of the sentences a language model picked: in order, each once, and dropping
    /// the weakest (never the first) until they fit `target` seconds. Nil when nothing usable
    /// is left, so the rules are used instead.
    public static func tidy(_ picks: [Int], in sentences: [SpokenSentence], target: Double) -> [Int]? {
        var chosen = Array(Set(picks.filter { sentences.indices.contains($0) })).sorted()
        guard !chosen.isEmpty else { return nil }
        func length(_ list: [Int]) -> Double { list.reduce(0) { $0 + sentences[$1].seconds } }
        while length(chosen) > target, chosen.count > 1 {
            let weakest = chosen.dropFirst().min { score(sentences[$0]) / max(sentences[$0].seconds, 0.1) < score(sentences[$1]) / max(sentences[$1].seconds, 0.1) }!
            chosen.removeAll { $0 == weakest }
        }
        // Too little kept (under a third of what was asked) isn't a Short: the rules do better.
        return length(chosen) < min(target, sentences.reduce(0) { $0 + $1.seconds }) / 3 ? nil : chosen
    }
}

public extension Project {
    /// What is said in the main clips, sentence by sentence, in timeline order.
    var spokenSentences: [SpokenSentence] {
        let words = script.filter { $0.source == .clip }
        var sentences: [SpokenSentence] = []
        var current: [TimedWord] = []
        func close() {
            guard let first = current.first, let last = current.last else { return }
            sentences.append(SpokenSentence(text: current.map(\.text).joined(separator: " "),
                                            range: CMTimeRange(start: first.range.start, end: last.range.end),
                                            firstWordID: first.wordID, wordCount: current.count))
            current = []
        }
        for word in words {
            if let last = current.last, (word.range.start - last.range.end).seconds > MomentPicker.gap { close() }
            current.append(word)
            if let end = word.text.last, MomentPicker.sentenceEnds.contains(end) || current.count >= MomentPicker.maxWords { close() }
        }
        close()
        return sentences
    }

    /// Cuts every sentence that doesn't start with one of `firstWords` out of the Short (with
    /// the moment after it, up to the next sentence). What nobody talks in stays.
    mutating func keepSentences(startingWith firstWords: Set<Word.ID>) {
        let sentences = spokenSentences
        guard sentences.contains(where: { firstWords.contains($0.firstWordID) }) else { return }
        // From the end, so earlier places don't move.
        for index in sentences.indices.reversed() where !firstWords.contains(sentences[index].firstWordID) {
            let sentence = sentences[index]
            let next = index + 1 < sentences.count ? sentences[index + 1].range.start : duration
            let end = min(sentence.range.end + MagicShort.endPadding, next)
            let range = CMTimeRange(start: sentence.range.start.snappedToFrame(), end: end.snappedToFrame())
            if range.duration > .zero { removeRange(range) }
        }
    }
}
