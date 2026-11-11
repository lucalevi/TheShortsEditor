import CoreMedia
import Foundation

// Stage F (one-click Shorts): Magic Short, like iMovie's Magic Movie. Pick clips (or one long
// video), get a first cut: filler words and pauses out, captions, a hook title, punch-ins, music
// and an ending that loops back cleanly. Then it is edited like any other Short.

/// How long the Magic Short should be.
public enum MagicLength: String, CaseIterable, Identifiable, Sendable {
    case keepAll, about60, about30

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .keepAll: "Keep it all"
        case .about60: "About 1 minute"
        case .about30: "About 30 seconds"
        }
    }

    /// The longest it may be. Even "Keep it all" stops at YouTube's limit.
    public var target: CMTime {
        switch self {
        case .keepAll: Project.maxDuration
        case .about60: CMTime(value: 60, timescale: 1)
        case .about30: CMTime(value: 30, timescale: 1)
        }
    }
}

/// What Magic Short does. Every part is on unless the user turns it off.
public struct MagicOptions: Equatable, Sendable {
    public var style: ShortStyle
    public var length: MagicLength
    public var removesFillers = true
    public var removesPauses = true
    public var showsCaptions = true
    public var addsHookTitle = true
    public var addsMusic = true

    public init(style: ShortStyle = .bold, length: MagicLength = .keepAll) {
        self.style = style
        self.length = length
    }
}

/// What Magic Short did, to tell the user.
public struct MagicReport: Equatable, Sendable {
    public var removedFillers = 0
    public var removedPauses = 0
    /// How much shorter the Short got, in total.
    public var removedTime = CMTime.zero
    public var hasSpeech = false
    /// The hook title, if one was added.
    public var hookTitleID: TextOverlay.ID?
    /// The hook title still says "Your hook here": no speech to take it from.
    public var hookNeedsText = false

    public init() {}
}

public enum MagicShort {
    /// Clips with nobody talking are cut to this much (from their middle), so a pile of footage
    /// becomes a quick montage.
    public static let quietClipLength = CMTime(value: 4, timescale: 1)
    /// How long the hook title stays.
    public static let hookLength = CMTime(value: 5, timescale: 2)
    /// The most words a hook title takes from the first sentence.
    public static let hookWords = 7
    /// How long the Short goes on after its last word, so the loop back to the start feels tight.
    public static let endPadding = CMTime(value: 6, timescale: Project.frameRate)
    public static let placeholderHook = "Your hook here"

    /// The first sentence said, shortened to a title: the whole sentence when it is short,
    /// otherwise its first words and "…". Nil when nothing is said.
    public static func hookText(from words: [TimedWord]) -> String? {
        var sentence: [String] = []
        for word in words {
            sentence.append(word.text)
            if let last = word.text.last, ".?!…".contains(last) { break }
        }
        guard !sentence.isEmpty else { return nil }
        var text: String
        if sentence.count <= hookWords {
            text = sentence.joined(separator: " ")
            // A question keeps its mark; a full stop isn't wanted on a title.
            while let last = text.last, ".,;:".contains(last) { text.removeLast() }
        } else {
            text = sentence.prefix(hookWords - 2).joined(separator: " ")
            while let last = text.last, ".,;:!?".contains(last) { text.removeLast() }
            text += "…"
        }
        guard let first = text.first else { return nil }
        return first.uppercased() + text.dropFirst()
    }
}

public extension Project {
    /// The files that have someone talking in them.
    var speakingAssets: Set<MediaAsset.ID> {
        Set(transcripts.filter { !$0.value.words.isEmpty }.keys)
    }

    /// Makes a first cut of the clips on the timeline (see `MagicShort`). `levels` are the
    /// files' sound levels (for finding pauses), `music` the style's music file.
    @discardableResult
    mutating func makeMagic(_ options: MagicOptions, levels: [MediaAsset.ID: AudioLevels], music: MediaAsset?) -> MagicReport {
        var report = MagicReport()
        let startLength = duration
        let speaking = speakingAssets
        report.hasSpeech = hasCaptions

        if options.removesFillers, report.hasSpeech {
            let fillers = Set(fillerAndRepeatedWords())
            report.removedFillers = fillers.count
            if !fillers.isEmpty { apply(cutPlan(removing: fillers)) }
        }

        if options.removesPauses {
            // Only where someone talks: in quiet footage, every moment is a "pause".
            let speechLevels = levels.filter { speaking.contains($0.key) }
            if !speechLevels.isEmpty {
                var settings = SilenceSettings()
                let main = timeline.clips.filter { speaking.contains($0.assetID) }.max { $0.duration < $1.duration }?.assetID
                if let main, let mainLevels = speechLevels[main] { settings.threshold = mainLevels.suggestedThreshold.rounded() }
                let plan = SilencePlan.make(for: self, levels: speechLevels, settings: settings)
                report.removedPauses = plan.timelineCuts.count
                apply(plan)
            }
        }

        if timeline.clips.count > 1 { shortenQuietClips(speaking: speaking) }
        fit(to: options.length.target)

        applyStyle(options.style, music: options.addsMusic ? music : nil)
        if !options.addsMusic, self.music?.isMoodMusic == true { self.music = nil }

        captions.isVisible = options.showsCaptions && report.hasSpeech
        if report.hasSpeech {
            if options.style.highlightsKeywords { pickKeywords() }
            if options.style.showsEmoji { suggestEmoji() }
        }

        if options.addsHookTitle, duration > .zero {
            let text = MagicShort.hookText(from: script)
            var title = TextOverlay(text: text ?? MagicShort.placeholderHook, start: .zero,
                                    duration: min(MagicShort.hookLength, duration).snappedToFrame())
            title.takeLook(of: options.style)
            titles.insert(title, at: 0)
            report.hookTitleID = title.id
            report.hookNeedsText = text == nil
        }

        makeLoopFriendlyEnding()
        report.removedTime = max(startLength - duration, .zero)
        return report
    }

    /// Cuts clips nobody talks in down to `MagicShort.quietClipLength`, keeping their middle.
    mutating func shortenQuietClips(speaking: Set<MediaAsset.ID>) {
        for index in timeline.clips.indices {
            let clip = timeline.clips[index]
            guard !speaking.contains(clip.assetID), !clip.isFrozen, asset(id: clip.assetID)?.isImage == false,
                  clip.duration > MagicShort.quietClipLength + CMTime(value: 1, timescale: 1) else { continue }
            timeline.clips[index] = clip.middle(MagicShort.quietClipLength)
        }
    }

    /// Makes the Short no longer than `target`. With speech, it ends after the last whole sentence
    /// that fits (or the last word); without, every clip gives up the same share, keeping its middle.
    mutating func fit(to target: CMTime) {
        let target = target.snappedToFrame()
        guard duration > target else { return }
        let words = script
        if !words.isEmpty {
            let fitting = words.filter { $0.range.end + MagicShort.endPadding <= target }
            let sentenceEnd = fitting.last { word in word.text.last.map { ".?!…".contains($0) } ?? false }
            let cut = ((sentenceEnd ?? fitting.last)?.range.end).map { ($0 + MagicShort.endPadding).snappedToFrame() } ?? target
            removeRange(CMTimeRange(start: cut, end: duration))
        } else {
            let share = target.seconds / duration.seconds
            for index in timeline.clips.indices {
                let clip = timeline.clips[index]
                let length = max(CMTime(seconds: clip.duration.seconds * share, preferredTimescale: 600).snappedToFrame(), Clip.minimumDuration)
                timeline.clips[index] = clip.middle(length)
            }
            // Rounding to frames can leave a frame or two over.
            if duration > target { removeRange(CMTimeRange(start: target, end: duration)) }
        }
    }

    /// Ends the Short so it loops back to the start cleanly: right after the last word, with no
    /// fade on the last clip, and app-made music ending on the beat instead of fading out.
    mutating func makeLoopFriendlyEnding() {
        guard let last = timeline.clips.indices.last else { return }
        let lastStart = duration - timeline.clips[last].duration
        if let word = script.last, word.clipID == timeline.clips[last].id {
            let end = (word.range.end + MagicShort.endPadding).snappedToFrame()
            if end > lastStart + Clip.minimumDuration, end < duration {
                timeline.clips[last].duration = end - lastStart
            }
        }
        timeline.clips[last].fadeOut = .zero
        timeline.clips[last].pictureFadeOut = .zero
        timeline.clips[last].transitionOut = nil
        fitMoodMusic()
    }
}

extension Clip {
    /// The middle `length` of the clip (or all of it, when it is shorter).
    func middle(_ length: CMTime) -> Clip {
        guard length < duration else { return self }
        let skip = CMTimeMultiplyByRatio(duration - length, multiplier: 1, divisor: 2).snappedToFrame()
        var clip = piece(id: id, sourceStart: sourceTime(atOffset: skip), duration: length.snappedToFrame())
        if isFrozen { clip.sourceStart = sourceStart }
        return clip
    }
}
