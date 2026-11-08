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

    public init(id: UUID = UUID(), text: String, start: CMTime, duration: CMTime) {
        self.id = id
        self.text = text
        self.start = start
        self.duration = duration
    }

    public var end: CMTime { start + duration }
    public var range: CMTimeRange { CMTimeRange(start: start, duration: duration) }
}

/// What was said in one source file.
public struct Transcript: Codable, Equatable, Sendable {
    public var language: CaptionLanguage
    /// In time order, never overlapping.
    public var words: [Word]

    public init(language: CaptionLanguage, words: [Word]) {
        self.language = language
        self.words = words
    }
}

/// The languages captions can be made in. All four have an on-device speech model.
public enum CaptionLanguage: String, Codable, CaseIterable, Identifiable, Sendable {
    case english = "en"
    case italian = "it"
    case german = "de"
    case french = "fr"

    public var id: String { rawValue }

    /// The language's own name, so each speaker recognises theirs.
    public var displayName: String {
        switch self {
        case .english: "English"
        case .italian: "Italiano"
        case .german: "Deutsch"
        case .french: "Français"
        }
    }

    /// The language the user's Mac is set to, when it is one of ours.
    public static func preferred(for locale: Locale = .current) -> CaptionLanguage {
        locale.language.languageCode.flatMap { CaptionLanguage(rawValue: $0.identifier) } ?? .english
    }
}

/// How the captions look. Each style is a complete, tested look rather than a set of knobs.
public enum CaptionStyle: String, Codable, CaseIterable, Identifiable, Sendable {
    /// Big white capitals with a black outline; the word being spoken turns yellow.
    case bold
    /// The word being spoken sits on a coloured box.
    case highlight
    /// One big word at a time.
    case oneWord
    /// White text on a dark box, like TV subtitles.
    case classic
    /// Plain white text with a soft shadow.
    case minimal

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .bold: "Bold"
        case .highlight: "Highlight"
        case .oneWord: "One Word"
        case .classic: "Subtitles"
        case .minimal: "Simple"
        }
    }

    /// The most characters on screen at once. Short pages are easier to read on a phone.
    public var maxCharacters: Int {
        switch self {
        case .oneWord: 0
        case .bold, .highlight: 16
        case .minimal: 22
        case .classic: 40
        }
    }

    public var isUppercase: Bool { self == .bold || self == .oneWord || self == .highlight }

    /// Whether the word being spoken looks different from the others.
    public var highlightsCurrentWord: Bool { self == .bold || self == .highlight }
}

/// Settings for the whole Short's captions.
public struct CaptionSettings: Codable, Equatable, Sendable {
    public var isVisible = true
    public var style: CaptionStyle = .bold
    /// Where the middle of the caption sits, from 0 (top of the screen) to 1 (bottom).
    /// Clamped to the area YouTube doesn't cover, see `SafeZone.captionRange`.
    public var verticalPosition = CaptionPlacement.bottom.verticalPosition

    public init() {}
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
}

/// The words on screen together at one time.
public struct CaptionPage: Identifiable, Equatable, Sendable {
    /// Stable while the page's first word and clip stay the same.
    public var id: String
    public var words: [TimedWord]
    /// When the page is on screen. It may stay a little longer than its last word, so it can be read.
    public var range: CMTimeRange

    public var text: String { words.map(\.text).joined(separator: " ") }

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

    /// Every word on the timeline, in order. A word belongs to a clip when its middle is inside it.
    public static func timelineWords(in project: Project) -> [TimedWord] {
        var result: [TimedWord] = []
        var clipStart = CMTime.zero
        for clip in project.timeline.clips {
            defer { clipStart = clipStart + clip.duration }
            guard let transcript = project.transcripts[clip.assetID] else { continue }
            let source = clip.sourceRange
            let clipRange = CMTimeRange(start: clipStart, duration: clip.duration)
            for word in transcript.words {
                let middle = word.start + CMTimeMultiplyByRatio(word.duration, multiplier: 1, divisor: 2)
                guard source.containsTime(middle) else { continue }
                let start = clipStart + (word.start - clip.sourceStart)
                let range = CMTimeRange(start: start, duration: word.duration).intersection(clipRange)
                guard range.duration > .zero else { continue }
                result.append(TimedWord(wordID: word.id, assetID: clip.assetID, clipID: clip.id, text: word.text, range: range))
            }
        }
        return result
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
                let breaks = last.clipID != word.clipID
                    || word.range.start - last.range.end >= pauseBreak
                    || endsSentence(last.text)
                    || characters(current + [word]) > style.maxCharacters
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
            stop = max(stop, min(stop + linger, next, end))
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
    mutating func replaceWords(_ wordIDs: [Word.ID], in assetID: MediaAsset.ID, with newText: String) {
        guard var transcript = transcripts[assetID] else { return }
        let indices = transcript.words.indices.filter { wordIDs.contains(transcript.words[$0].id) }
        guard let first = indices.first, let last = indices.last else { return }
        let old = Array(transcript.words[first...last])
        let texts = newText.split(whereSeparator: \.isWhitespace).map(String.init)

        var replacement: [Word] = []
        if texts.count == old.count {
            replacement = zip(old, texts).map { word, text in
                var word = word
                word.text = text
                return word
            }
        } else if !texts.isEmpty {
            let start = old[0].start
            let total = old[old.count - 1].end - start
            let weights = texts.map { Double($0.count) + 1 }
            let sum = weights.reduce(0, +)
            var cursor = start
            var accumulated = 0.0
            for (index, text) in texts.enumerated() {
                accumulated += weights[index]
                let end = index == texts.count - 1
                    ? start + total
                    : start + CMTimeMultiplyByFloat64(total, multiplier: accumulated / sum)
                replacement.append(Word(id: index < old.count ? old[index].id : UUID(), text: text, start: cursor, duration: end - cursor))
                cursor = end
            }
        }
        transcript.words.replaceSubrange(first...last, with: replacement)
        transcripts[assetID] = transcript
    }

    /// The assets on the timeline whose sound hasn't been transcribed in `language` yet.
    func assetsNeedingTranscription(in language: CaptionLanguage) -> [MediaAsset] {
        var seen = Set<MediaAsset.ID>()
        return timeline.clips.compactMap { clip in
            guard seen.insert(clip.assetID).inserted,
                  let asset = asset(id: clip.assetID), asset.hasAudio,
                  transcripts[clip.assetID]?.language != language
            else { return nil }
            return asset
        }
    }

    /// Whether any clip on the timeline has captions.
    var hasCaptions: Bool {
        timeline.clips.contains { transcripts[$0.assetID]?.words.isEmpty == false }
    }
}

extension Word {
    private enum CodingKeys: String, CodingKey {
        case id, text, start, duration
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        text = try c.decode(String.self, forKey: .text)
        start = try c.decodeTime(forKey: .start)
        duration = try c.decodeTime(forKey: .duration)
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(text, forKey: .text)
        try c.encode(time: start, forKey: .start)
        try c.encode(time: duration, forKey: .duration)
    }
}
