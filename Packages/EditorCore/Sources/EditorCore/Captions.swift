import CoreGraphics
import CoreMedia
import Foundation

/// A spoken word with its timing in the source file (not on the timeline).
///
/// Transcripts belong to a `MediaAsset` and use the file's own time, so captions follow the
/// clips automatically when they are split, deleted or moved.
public struct Word: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public var text: String
    public var start: CMTime
    public var duration: CMTime
    /// Shown in the accent colour wherever it is on screen, to make it stand out.
    public var isKeyword: Bool
    /// An emoji shown with the caption this word is in, or nil.
    public var emoji: String?
    /// A caption break the user made before this word (split or merge), or nil to let the layout decide.
    public var captionBreak: CaptionBreak?
    /// The caption goes on a new line after this word (⌘↩ while editing it).
    public var lineBreakAfter: Bool = false
    /// When this word ends a caption, the caption ends with it instead of staying a moment to be
    /// read. Set when the user drags the caption's end on the timeline.
    public var endsExactly: Bool = false
    /// The caption this word starts, in another language, shown as a second line.
    public var translation: CaptionTranslation?

    public init(id: UUID = UUID(), text: String, start: CMTime, duration: CMTime, isKeyword: Bool = false, emoji: String? = nil,
                captionBreak: CaptionBreak? = nil, lineBreakAfter: Bool = false, endsExactly: Bool = false) {
        self.id = id
        self.text = text
        self.start = start
        self.duration = duration
        self.isKeyword = isKeyword
        self.emoji = emoji
        self.captionBreak = captionBreak
        self.lineBreakAfter = lineBreakAfter
        self.endsExactly = endsExactly
    }

    public var end: CMTime { start + duration }
    public var range: CMTimeRange { CMTimeRange(start: start, duration: duration) }
}

/// A caption break the user chose, which the automatic layout keeps.
public enum CaptionBreak: String, Codable, Sendable {
    /// A new caption starts at this word.
    case newCaption
    /// This word stays in the same caption as the word before it.
    case joined
}

/// A caption in a second language. It is kept only while the caption still reads `source`, so
/// editing the words or the caption breaks hides an out-of-date translation.
public struct CaptionTranslation: Codable, Equatable, Hashable, Sendable {
    public var source: String
    public var text: String

    public init(source: String, text: String) {
        self.source = source
        self.text = text
    }
}

/// What was said in one source file.
public struct Transcript: Codable, Equatable, Sendable {
    public var language: CaptionLanguage
    /// In time order, never overlapping.
    public var words: [Word]
    /// Typed or imported rather than heard (an SRT file): shown even where the clip is muted.
    public var isTyped: Bool

    public init(language: CaptionLanguage, words: [Word], isTyped: Bool = false) {
        self.language = language
        self.words = words
        self.isTyped = isTyped
    }

    private enum CodingKeys: String, CodingKey { case language, words, isTyped }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        language = try c.decode(CaptionLanguage.self, forKey: .language)
        words = try c.decode([Word].self, forKey: .words)
        isTyped = try c.decodeIfPresent(Bool.self, forKey: .isTyped) ?? false
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(language, forKey: .language)
        try c.encode(words, forKey: .words)
        if isTyped { try c.encode(isTyped, forKey: .isTyped) }
    }
}

/// The languages captions can be made in. Each has an on-device speech model.
public enum CaptionLanguage: String, Codable, CaseIterable, Identifiable, Sendable {
    case english = "en"
    case italian = "it"
    case german = "de"
    case french = "fr"
    case spanish = "es"
    case portuguese = "pt"

    public var id: String { rawValue }

    /// The language's own name, so each speaker recognises theirs.
    public var displayName: String {
        switch self {
        case .english: "English"
        case .italian: "Italiano"
        case .german: "Deutsch"
        case .french: "Français"
        case .spanish: "Español"
        case .portuguese: "Português"
        }
    }

    /// The language the user's Mac is set to, when it is one of ours.
    public static func preferred(for locale: Locale = .current) -> CaptionLanguage {
        locale.language.languageCode.flatMap { CaptionLanguage(rawValue: $0.identifier) } ?? .english
    }
}

/// The spoken-language choice for making captions: one language, or found by listening.
public enum CaptionLanguageChoice: Hashable, Identifiable, Sendable {
    case automatic
    case language(CaptionLanguage)

    public var id: String {
        switch self {
        case .automatic: "auto"
        case .language(let language): language.rawValue
        }
    }

    public var displayName: String {
        switch self {
        case .automatic: "Find automatically"
        case .language(let language): language.displayName
        }
    }

    public static var allCases: [CaptionLanguageChoice] { [.automatic] + CaptionLanguage.allCases.map { .language($0) } }
}

/// How the captions look. Each look is complete and tested, with its own word animation,
/// rather than a set of knobs.
public enum CaptionStyle: String, Codable, CaseIterable, Identifiable, Sendable {
    /// Big white capitals with a black outline; the word being spoken turns yellow and grows.
    case bold
    /// The word being spoken sits on a coloured box.
    case highlight
    /// One big word at a time.
    case oneWord
    /// Two to four words at a time, big and centred, in normal case.
    case phrase
    /// The words fill with colour as they are spoken.
    case karaoke
    /// Soft coloured light around the letters; the spoken word shines brightest.
    case glow
    /// The spoken word jumps up.
    case bounce
    /// Words appear one by one as they are spoken.
    case typewriter
    /// Hollow letters; the spoken word fills in.
    case outline
    /// White text on a dark box, like TV subtitles.
    case classic
    /// Plain white text with a soft shadow.
    case minimal

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .bold: "Bold Pop"
        case .highlight: "Box"
        case .oneWord: "One Word"
        case .phrase: "Phrase"
        case .karaoke: "Karaoke"
        case .glow: "Glow"
        case .bounce: "Bounce"
        case .typewriter: "Typewriter"
        case .outline: "Outline"
        case .classic: "Subtitles"
        case .minimal: "Simple"
        }
    }

    /// The most characters on screen at once. Short pages are easier to read on a phone.
    public var maxCharacters: Int {
        switch self {
        case .oneWord: 0
        case .bold, .highlight, .bounce, .glow, .outline: 16
        case .karaoke, .minimal: 22
        case .phrase: 26
        case .typewriter: 30
        case .classic: 40
        }
    }

    /// The most words on screen at once, when the style limits them.
    public var maxWords: Int? { self == .phrase ? 4 : nil }

    public var isUppercase: Bool {
        switch self {
        case .bold, .oneWord, .highlight, .bounce, .glow, .outline: true
        case .phrase, .karaoke, .typewriter, .classic, .minimal: false
        }
    }

    /// Whether the word being spoken looks different from the others.
    public var highlightsCurrentWord: Bool {
        switch self {
        case .bold, .highlight, .karaoke, .glow, .bounce, .outline: true
        case .oneWord, .phrase, .typewriter, .classic, .minimal: false
        }
    }
}

/// Settings for the whole Short's captions.
public struct CaptionSettings: Codable, Equatable, Hashable, Sendable {
    public var isVisible = true
    public var style: CaptionStyle = .bold
    /// Where the middle of the caption sits, from 0 (top of the screen) to 1 (bottom).
    /// Clamped to the area YouTube doesn't cover, see `SafeZone.captionRange`.
    public var verticalPosition = CaptionPlacement.bottom.verticalPosition
    /// A font family, or nil for the system font.
    public var fontFamily: String?
    /// Bigger or smaller than the style's own size (1 is as designed).
    public var sizeScale: Double = 1
    /// The letters' colour, or nil for the style's.
    public var textColor: RGBA?
    /// The colour of the word being spoken (or its box) and of key words, or nil for the style's.
    public var accentColor: RGBA?
    /// Key words (`Word.isKeyword`) shown in the accent colour.
    public var showsKeywords = true
    /// Emoji (`Word.emoji`) shown above the caption they are in.
    public var showsEmoji = true
    /// The language of the second line (a language code such as "en"), or nil for none.
    public var translationLanguage: String?

    public static let sizeRange: ClosedRange<Double> = 0.6...1.6

    public init() {}

    private enum CodingKeys: String, CodingKey {
        case isVisible, style, verticalPosition, fontFamily, sizeScale, textColor, accentColor, showsKeywords, showsEmoji, translationLanguage
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        isVisible = try c.decodeIfPresent(Bool.self, forKey: .isVisible) ?? true
        style = try c.decodeIfPresent(CaptionStyle.self, forKey: .style) ?? .bold
        verticalPosition = try c.decodeIfPresent(Double.self, forKey: .verticalPosition) ?? CaptionPlacement.bottom.verticalPosition
        fontFamily = try c.decodeIfPresent(String.self, forKey: .fontFamily)
        sizeScale = try c.decodeIfPresent(Double.self, forKey: .sizeScale) ?? 1
        textColor = try c.decodeIfPresent(RGBA.self, forKey: .textColor)
        accentColor = try c.decodeIfPresent(RGBA.self, forKey: .accentColor)
        showsKeywords = try c.decodeIfPresent(Bool.self, forKey: .showsKeywords) ?? true
        showsEmoji = try c.decodeIfPresent(Bool.self, forKey: .showsEmoji) ?? true
        translationLanguage = try c.decodeIfPresent(String.self, forKey: .translationLanguage)
    }

    /// Whether anything differs from how the style looks on its own.
    public var isCustomized: Bool {
        fontFamily != nil || sizeScale != 1 || textColor != nil || accentColor != nil
    }
}

/// The simple choice of where captions go, offered instead of a free slider.
public enum CaptionPlacement: String, CaseIterable, Identifiable, Sendable {
    case top, middle, bottom

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .top: "Top"
        case .middle: "Middle"
        case .bottom: "Bottom"
        }
    }

    public var verticalPosition: Double {
        switch self {
        case .top: 0.25
        case .middle: 0.5
        case .bottom: 0.66
        }
    }

    /// The placement closest to a stored position.
    public init(_ position: Double) {
        self = Self.allCases.min { abs($0.verticalPosition - position) < abs($1.verticalPosition - position) } ?? .bottom
    }
}

/// One word as it appears on the timeline.
public struct TimedWord: Equatable, Sendable {
    public var wordID: Word.ID
    public var assetID: MediaAsset.ID
    public var clipID: Clip.ID
    public var text: String
    /// Timeline range, cut to the clip it plays in.
    public var range: CMTimeRange
    public var isKeyword: Bool = false
    public var emoji: String?
    /// Where the word is heard.
    public var source: CaptionSource = .clip
    public var captionBreak: CaptionBreak?
    public var lineBreakAfter = false
    public var endsExactly = false
    public var translation: CaptionTranslation?
}

/// Where a caption's words are heard: the main clips, a B-roll clip's own sound, or a sound
/// item (a voice-over, a detached sound or a sound file).
public enum CaptionSource: String, Codable, Sendable {
    case clip, broll, sound
}

/// The words on screen together at one time.
public struct CaptionPage: Identifiable, Equatable, Sendable {
    /// Stable while the page's first word and clip stay the same.
    public var id: String
    public var words: [TimedWord]
    /// When the page is on screen. It may stay a little longer than its last word, so it can be read.
    public var range: CMTimeRange

    /// The words as shown, with the line breaks the user chose.
    public var text: String {
        var result = ""
        for (index, word) in words.enumerated() {
            if index > 0 { result += words[index - 1].lineBreakAfter ? "\n" : " " }
            result += word.text
        }
        return result
    }

    /// The words on one line, for comparing and for the timeline.
    public var plainText: String { words.map(\.text).joined(separator: " ") }

    /// The indices of words followed by a line break.
    public var lineBreaks: Set<Int> { Set(words.indices.filter { words[$0].lineBreakAfter && $0 < words.count - 1 }) }

    /// The translation of this caption, when one was made for the words it has now.
    public var translation: String? {
        guard let stored = words.first?.translation, stored.source == plainText else { return nil }
        return stored.text
    }

    /// Where the words are heard.
    public var source: CaptionSource { words[0].source }
    public var clipID: Clip.ID { words[0].clipID }

    /// The emoji shown with this caption: the first one any of its words has.
    public var emoji: String? { words.lazy.compactMap(\.emoji).first }

    /// The first whole frame on which the page is on screen, for jumping to it.
    public var firstFrame: CMTime {
        range.start.convertScale(Project.frameRate, method: .roundTowardPositiveInfinity)
    }
    public var assetID: MediaAsset.ID { words[0].assetID }

    /// The word being spoken at `time`: the last one that has started. Between words the
    /// previous one stays highlighted, which looks calmer than flickering back to none.
    public func wordIndex(at time: CMTime) -> Int {
        words.lastIndex { $0.range.start <= time } ?? 0
    }
}

public extension SafeZone {
    /// The range `CaptionSettings.verticalPosition` is kept in: between the covered top and bottom.
    static var captionRange: ClosedRange<Double> {
        let height = Double(Project.canvasSize.height)
        return (Double(top) + 120) / height ... (height - Double(bottom) - 120) / height
    }
}

public enum CaptionLayout {
    /// A gap this long between words starts a new page.
    public static let pauseBreak = CMTime(value: 7, timescale: 10)
    /// How long a page may stay after its last word when nothing follows straight away.
    public static let linger = CMTime(value: 1, timescale: 2)

    /// Every word heard in the Short, in order. A word belongs to a clip when its middle is
    /// inside it. Captions are what you hear: the main clips, then B-roll with its sound on, then
    /// sound items (voice-overs first). Where two of them talk at once, the voice-over wins, then
    /// other sounds, then the main clips, then B-roll. Muted clips have no captions, unless their
    /// captions were typed or imported.
    public static func timelineWords(in project: Project) -> [TimedWord] {
        var kept: [TimedWord] = []
        func add(_ words: [TimedWord]) {
            guard !words.isEmpty else { return }
            if kept.isEmpty {
                kept = words
                return
            }
            let ranges = kept.map(\.range)
            let fresh = words.filter { word in !overlaps(word.range, sortedRanges: ranges) }
            kept = (kept + fresh).sorted { $0.range.start < $1.range.start }
        }
        let end = CMTimeRange(start: .zero, duration: project.duration)
        let sounds = project.sounds.filter { project.isCaptioned($0.clip) }
        for sound in sounds.sorted(by: { $0.isVoiceOver && !$1.isVoiceOver }) {
            add(words(of: sound.clip, at: sound.start, source: .sound, in: project, within: end))
        }
        var main: [TimedWord] = []
        var clipStart = CMTime.zero
        for clip in project.timeline.clips {
            defer { clipStart = clipStart + clip.duration }
            guard project.isCaptioned(clip) else { continue }
            main += words(of: clip, at: clipStart, source: .clip, in: project, within: end)
        }
        add(main)
        for overlay in project.overlays where project.isCaptioned(overlay.clip) {
            add(words(of: overlay.clip, at: overlay.start, source: .broll, in: project, within: end))
        }
        return kept
    }

    /// The words of `clip`'s file it plays, on the timeline, cut to the clip and to `within`.
    private static func words(of clip: Clip, at clipStart: CMTime, source kind: CaptionSource, in project: Project,
                              within bounds: CMTimeRange) -> [TimedWord] {
        guard let transcript = project.transcripts[clip.assetID] else { return [] }
        let source = clip.sourceRange
        let clipRange = CMTimeRange(start: clipStart, duration: clip.duration).intersection(bounds)
        guard clipRange.duration > .zero else { return [] }
        var result: [TimedWord] = []
        for word in transcript.words {
            let middle = word.start + CMTimeMultiplyByRatio(word.duration, multiplier: 1, divisor: 2)
            guard source.containsTime(middle) else { continue }
            let start = clipStart + clip.timelineOffset(ofSourceTime: word.start)
            let range = CMTimeRange(start: start, duration: clip.timelineDuration(ofSource: word.duration)).intersection(clipRange)
            guard range.duration > .zero else { continue }
            result.append(TimedWord(wordID: word.id, assetID: clip.assetID, clipID: clip.id, text: word.text, range: range,
                                    isKeyword: word.isKeyword, emoji: word.emoji, source: kind, captionBreak: word.captionBreak,
                                    lineBreakAfter: word.lineBreakAfter, endsExactly: word.endsExactly, translation: word.translation))
        }
        return result
    }

    /// Whether `range` overlaps any of `sortedRanges` (in start order, not overlapping each other).
    private static func overlaps(_ range: CMTimeRange, sortedRanges: [CMTimeRange]) -> Bool {
        // The last range starting before `range` ends is the only one that can overlap it.
        var low = 0, high = sortedRanges.count
        while low < high {
            let mid = (low + high) / 2
            if sortedRanges[mid].start < range.end { low = mid + 1 } else { high = mid }
        }
        // Ranges before it end even earlier, since they don't overlap each other.
        return low > 0 && sortedRanges[low - 1].end > range.start
    }

    /// Groups the timeline's words into pages for `style`. Pages never cross a cut between clips,
    /// and a new one starts after a pause, at the end of a sentence, or when the page is full.
    public static func pages(in project: Project, style: CaptionStyle? = nil) -> [CaptionPage] {
        let style = style ?? project.captions.style
        let words = timelineWords(in: project)
        var groups: [[TimedWord]] = []
        var current: [TimedWord] = []

        func characters(_ words: [TimedWord]) -> Int {
            words.reduce(0) { $0 + $1.text.count } + max(words.count - 1, 0)
        }

        for word in words {
            if let last = current.last {
                let breaks: Bool
                if last.clipID != word.clipID {
                    breaks = true
                } else if let chosen = word.captionBreak {
                    breaks = chosen == .newCaption
                } else {
                    breaks = word.range.start - last.range.end >= pauseBreak
                        || endsSentence(last.text)
                        || characters(current + [word]) > style.maxCharacters
                        || style.maxWords.map { current.count >= $0 } ?? false
                }
                if breaks {
                    groups.append(current)
                    current = []
                }
            }
            current.append(word)
        }
        if !current.isEmpty { groups.append(current) }

        let end = project.duration
        return groups.enumerated().map { index, words in
            let start = words[0].range.start
            var stop = words[words.count - 1].range.end
            let next = index + 1 < groups.count ? groups[index + 1][0].range.start : end
            if !words[words.count - 1].endsExactly {
                stop = max(stop, min(stop + linger, next, end))
            }
            return CaptionPage(
                id: "\(words[0].clipID)-\(words[0].wordID)",
                words: words,
                range: CMTimeRange(start: start, end: stop)
            )
        }
    }

    /// The page on screen at `time`, if any.
    public static func page(at time: CMTime, in pages: [CaptionPage]) -> CaptionPage? {
        pages.first { $0.range.containsTime(time) }
    }

    private static func endsSentence(_ text: String) -> Bool {
        guard let last = text.last else { return false }
        return ".?!…".contains(last)
    }
}

public extension Project {
    /// Replaces the words of a caption page with `newText`, for fixing what the transcription got
    /// wrong. The new words share the old words' time in proportion to their length; when the
    /// number of words is unchanged, each keeps its own timing. Empty text removes the words.
    /// A new line in the text is kept as a line break in the caption. Returns the new words' ids.
    @discardableResult
    mutating func replaceWords(_ wordIDs: [Word.ID], in assetID: MediaAsset.ID, with newText: String) -> [Word.ID] {
        guard var transcript = transcripts[assetID] else { return [] }
        let indices = transcript.words.indices.filter { wordIDs.contains(transcript.words[$0].id) }
        guard let first = indices.first, let last = indices.last else { return [] }
        let old = Array(transcript.words[first...last])
        let tokens = CaptionText.tokens(newText)

        var replacement: [Word] = []
        if tokens.count == old.count {
            replacement = zip(old, tokens).map { word, token in
                var word = word
                word.text = token.text
                word.lineBreakAfter = token.lineBreakAfter
                return word
            }
        } else if !tokens.isEmpty {
            let start = old[0].start
            let total = old[old.count - 1].end - start
            let weights = tokens.map { Double($0.text.count) + 1 }
            let sum = weights.reduce(0, +)
            var cursor = start
            var accumulated = 0.0
            for (index, token) in tokens.enumerated() {
                accumulated += weights[index]
                let end = index == tokens.count - 1
                    ? start + total
                    : start + CMTimeMultiplyByFloat64(total, multiplier: accumulated / sum)
                var word = Word(id: index < old.count ? old[index].id : UUID(), text: token.text, start: cursor, duration: end - cursor,
                                lineBreakAfter: token.lineBreakAfter)
                if index < old.count {
                    word.isKeyword = old[index].isKeyword
                    word.emoji = old[index].emoji
                }
                replacement.append(word)
                cursor = end
            }
            replacement[0].captionBreak = old[0].captionBreak
            replacement[0].translation = old[0].translation
            replacement[replacement.count - 1].endsExactly = old[old.count - 1].endsExactly
        }
        transcript.words.replaceSubrange(first...last, with: replacement)
        transcripts[assetID] = transcript
        return replacement.map(\.id)
    }

    /// Whether the words of `clip` appear as captions: when its sound plays, or its captions
    /// were typed. Built-in sound effects never have captions.
    func isCaptioned(_ clip: Clip) -> Bool {
        guard let asset = asset(id: clip.assetID), !asset.isBuiltInSound else { return false }
        if clip.soundDetached { return false }
        return clip.effectiveVolume > 0 || transcripts[clip.assetID]?.isTyped == true
    }

    /// The assets heard in the Short (main clips, B-roll with sound, sound items) whose sound
    /// hasn't been transcribed in `language` yet. Voice-overs come first.
    func assetsNeedingTranscription(in language: CaptionLanguage) -> [MediaAsset] {
        assetsHeard().filter { transcripts[$0.id]?.language != language && transcripts[$0.id]?.isTyped != true }
    }

    /// Every asset whose sound is heard in the Short, once each: voice-overs, other sound items,
    /// the main clips, then B-roll with its sound on.
    func assetsHeard() -> [MediaAsset] {
        var seen = Set<MediaAsset.ID>()
        let clips = sounds.sorted { $0.isVoiceOver && !$1.isVoiceOver }.map(\.clip) + timeline.clips + overlays.map(\.clip)
        return clips.compactMap { clip in
            guard clip.effectiveVolume > 0, seen.insert(clip.assetID).inserted,
                  let asset = asset(id: clip.assetID), asset.hasAudio, !asset.isBuiltInSound
            else { return nil }
            return asset
        }
    }

    /// Whether the Short has any captions.
    var hasCaptions: Bool {
        !CaptionLayout.timelineWords(in: self).isEmpty
    }

    /// The clip with this id, wherever it is (main clips, B-roll or sounds), and where it starts
    /// on the timeline.
    func anyClip(_ id: Clip.ID) -> (clip: Clip, start: CMTime)? {
        if let index = timeline.index(of: id) { return (timeline.clips[index], timeline.startTime(ofClipAt: index)) }
        if let overlay = overlay(id: id) { return (overlay.clip, overlay.start) }
        if let sound = sound(id: id) { return (sound.clip, sound.start) }
        return nil
    }
}

public extension MediaAsset {
    /// One of the app's own sound effects, which have no words in them.
    var isBuiltInSound: Bool { url.path.contains("/Shorts Editor/Sound Effects/") }
}

extension Word {
    private enum CodingKeys: String, CodingKey {
        case id, text, start, duration, isKeyword, emoji, captionBreak, lineBreakAfter, endsExactly, translation
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        text = try c.decode(String.self, forKey: .text)
        start = try c.decodeTime(forKey: .start)
        duration = try c.decodeTime(forKey: .duration)
        isKeyword = try c.decodeIfPresent(Bool.self, forKey: .isKeyword) ?? false
        emoji = try c.decodeIfPresent(String.self, forKey: .emoji)
        captionBreak = try c.decodeIfPresent(CaptionBreak.self, forKey: .captionBreak)
        lineBreakAfter = try c.decodeIfPresent(Bool.self, forKey: .lineBreakAfter) ?? false
        endsExactly = try c.decodeIfPresent(Bool.self, forKey: .endsExactly) ?? false
        translation = try c.decodeIfPresent(CaptionTranslation.self, forKey: .translation)
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(text, forKey: .text)
        try c.encode(time: start, forKey: .start)
        try c.encode(time: duration, forKey: .duration)
        try c.encode(isKeyword, forKey: .isKeyword)
        try c.encodeIfPresent(emoji, forKey: .emoji)
        try c.encodeIfPresent(captionBreak, forKey: .captionBreak)
        if lineBreakAfter { try c.encode(lineBreakAfter, forKey: .lineBreakAfter) }
        if endsExactly { try c.encode(endsExactly, forKey: .endsExactly) }
        try c.encodeIfPresent(translation, forKey: .translation)
    }
}
