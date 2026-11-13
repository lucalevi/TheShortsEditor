import EditorCore
import Foundation
import FoundationModels

/// Smarter key words, emoji and filler words, read by Apple's on-device language model. Nothing
/// leaves the Mac. When the model isn't available (an older Mac, Apple Intelligence off, or a
/// language it doesn't speak) callers fall back to the rules in `Keywords`, `EmojiSuggestions`
/// and `FillerWords`.
public enum WordModel {
    public enum Task: Sendable {
        case keywords, emoji, fillers
    }

    /// Whether the model can be used for captions in `language` on this Mac.
    public static func isAvailable(for language: CaptionLanguage?) -> Bool {
        let model = SystemLanguageModel.default
        guard model.isAvailable else { return false }
        guard let language else { return true }
        return model.supportsLocale(Locale(identifier: language.rawValue))
    }

    /// Why the model can't be used, in plain words, or nil when it can.
    public static var unavailableReason: String? {
        switch SystemLanguageModel.default.availability {
        case .available: nil
        case .unavailable(.appleIntelligenceNotEnabled): "Turn on Apple Intelligence in System Settings for smarter picks."
        case .unavailable(.modelNotReady): "Apple Intelligence is still getting ready on this Mac."
        case .unavailable(.deviceNotEligible): "This Mac can't run Apple Intelligence."
        case .unavailable: "Apple Intelligence isn't available."
        }
    }

    /// Reads the script and picks what `task` asks for. Long scripts are read in pieces.
    public static func picks(for words: [TimedWord], language: CaptionLanguage?, task: Task) async throws -> SmartWordPicks {
        var all = SmartWordPicks()
        for chunk in SmartWords.chunks(of: words) {
            try _Concurrency.Task.checkCancellation()
            let session = LanguageModelSession(instructions: instructions(language: language))
            let prompt = prompt(for: task) + "\n\n" + SmartWords.numbered(chunk)
            let options = GenerationOptions(temperature: 0.2)
            switch task {
            case .keywords:
                let answer = try await session.respond(to: prompt, generating: KeyWordAnswer.self, options: options).content
                all.merge(SmartWords.picks(in: chunk, keywords: answer.keyWords, fillers: [], emoji: []))
            case .fillers:
                let answer = try await session.respond(to: prompt, generating: FillerAnswer.self, options: options).content
                all.merge(SmartWords.picks(in: chunk, keywords: [], fillers: answer.fillerWords, emoji: []))
            case .emoji:
                let answer = try await session.respond(to: prompt, generating: EmojiAnswer.self, options: options).content
                all.merge(SmartWords.picks(in: chunk, keywords: [], fillers: [], emoji: answer.choices.map { ($0.wordNumber, $0.emoji) }))
            }
        }
        return all
    }

    private static func instructions(language: CaptionLanguage?) -> String {
        let spoken = language.map { " The speaker talks in \(Locale(identifier: "en").localizedString(forLanguageCode: $0.rawValue) ?? $0.rawValue)." } ?? ""
        return """
        You help make captions for a short vertical video (a YouTube Short).\(spoken) \
        You get the transcript as numbered words, like "[1] Hello [2] everyone". \
        Answer only with word numbers from the transcript.
        """
    }

    private static func prompt(for task: Task) -> String {
        switch task {
        case .keywords:
            "Pick the key words to highlight in the captions: numbers, names, and the strongest words that carry the message. About one word in seven, never small words like articles or pronouns."
        case .fillers:
            "Pick the words said only as fillers, which add no meaning and can be cut: sounds like um or eh, and words used as fillers such as like, you know, basically, tipo, cioè, allora, praticamente, also, halt, genre, bah, pues, o sea. Only pick a word when it is used as a filler in this sentence, not when it carries meaning."
        case .emoji:
            "Pick a few words that call for an emoji and the emoji to show with them, at most one every ten words, only where the emoji clearly matches the word's meaning."
        }
    }
}

@Generable
struct KeyWordAnswer {
    @Guide(description: "Numbers of the key words")
    var keyWords: [Int]
}

@Generable
struct FillerAnswer {
    @Guide(description: "Numbers of the filler words")
    var fillerWords: [Int]
}

@Generable
struct EmojiAnswer {
    @Guide(description: "Words that call for an emoji")
    var choices: [EmojiChoice]
}

@Generable
struct EmojiChoice {
    @Guide(description: "The word's number")
    var wordNumber: Int
    @Guide(description: "One emoji")
    var emoji: String
}
