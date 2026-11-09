import CoreMedia
import Foundation

/// How loud a source file is, one value per frame (1/30 s) of its own time.
public struct AudioLevels: Equatable, Sendable {
    /// Loudness of each frame-long window in dBFS (0 is full scale, −100 is silence).
    public var decibels: [Float]

    public init(decibels: [Float]) {
        self.decibels = decibels
    }

    public static let silence: Float = -100

    /// A sensible starting point for "quiet": a third of the way from the background noise up
    /// to the speech, so it adapts to quiet rooms and noisy ones.
    public var suggestedThreshold: Float {
        let sorted = decibels.sorted()
        guard !sorted.isEmpty else { return -40 }
        let floor = max(sorted[sorted.count / 10], -70)
        let speech = sorted[min(sorted.count * 9 / 10, sorted.count - 1)]
        return min(max(floor + (speech - floor) / 3, -60), -15)
    }
}

/// The user's choices for removing pauses.
public struct SilenceSettings: Equatable, Sendable {
    /// Windows quieter than this (dBFS) count as silent.
    public var threshold: Float
    /// How much quiet to keep before and after speech, so words aren't clipped and it doesn't feel rushed.
    public var padding: CMTime
    /// Shorter pauses are natural and stay.
    public var minimumPause: CMTime

    public init(threshold: Float = -40, padding: CMTime = CMTime(value: 4, timescale: 30), minimumPause: CMTime = CMTime(value: 9, timescale: 30)) {
        self.threshold = threshold
        self.padding = padding
        self.minimumPause = minimumPause
    }
}

/// What removing pauses would cut, worked out before anything changes so it can be previewed.
public struct SilencePlan: Equatable, Sendable {
    /// Per clip, the parts of its source to remove, in source time.
    public var sourceCuts: [Clip.ID: [CMTimeRange]]
    /// The same parts on the current timeline, for showing them.
    public var timelineCuts: [CMTimeRange]

    public init(sourceCuts: [Clip.ID: [CMTimeRange]] = [:], timelineCuts: [CMTimeRange] = []) {
        self.sourceCuts = sourceCuts
        self.timelineCuts = timelineCuts
    }

    public var removedDuration: CMTime { timelineCuts.reduce(.zero) { $0 + $1.duration } }
    public var isEmpty: Bool { timelineCuts.isEmpty }

    /// Plans the cuts for every clip whose file has `levels`. Pauses at the very start or end of
    /// a clip are cut completely (no padding), so the Short starts and ends on sound.
    public static func make(for project: Project, levels: [MediaAsset.ID: AudioLevels], settings: SilenceSettings) -> SilencePlan {
        let rate = Int64(Project.frameRate)
        let padding = Int64(settings.padding.convertScale(Project.frameRate, method: .roundHalfAwayFromZero).value)
        let minimum = max(Int64(settings.minimumPause.convertScale(Project.frameRate, method: .roundHalfAwayFromZero).value), 1)
        func frame(_ time: CMTime, up: Bool) -> Int64 {
            time.convertScale(Project.frameRate, method: up ? .roundTowardPositiveInfinity : .roundTowardNegativeInfinity).value
        }

        var sourceCuts: [Clip.ID: [CMTimeRange]] = [:]
        var timelineCuts: [CMTimeRange] = []
        var clipStart = CMTime.zero
        for clip in project.timeline.clips {
            defer { clipStart = clipStart + clip.duration }
            guard let audio = levels[clip.assetID] else { continue }
            let first = frame(clip.sourceStart, up: true)
            let end = frame(clip.sourceRange.end, up: false)
            guard first < end else { continue }

            var cuts: [CMTimeRange] = []
            var index = first
            while index < end {
                guard isQuiet(audio, index, settings.threshold) else { index += 1; continue }
                var runEnd = index
                while runEnd < end, isQuiet(audio, runEnd, settings.threshold) { runEnd += 1 }
                let cutStart = index == first ? index : index + padding
                let cutEnd = runEnd == end ? runEnd : runEnd - padding
                // Cutting the whole clip is never what's wanted; leave a clip that's all quiet alone.
                let wholeClip = index == first && runEnd == end
                if cutEnd - cutStart >= minimum, !wholeClip {
                    cuts.append(CMTimeRange(start: CMTime(value: cutStart, timescale: Int32(rate)), end: CMTime(value: cutEnd, timescale: Int32(rate))))
                }
                index = runEnd
            }
            guard !cuts.isEmpty else { continue }
            sourceCuts[clip.id] = cuts
            timelineCuts += cuts.map {
                // Clamp to the clip, whose ends may fall between frames of the source.
                let range = $0.intersection(clip.sourceRange)
                return CMTimeRange(start: clipStart + clip.timelineOffset(ofSourceTime: range.start), duration: clip.timelineDuration(ofSource: range.duration))
            }
        }
        return SilencePlan(sourceCuts: sourceCuts, timelineCuts: timelineCuts)
    }

    private static func isQuiet(_ levels: AudioLevels, _ index: Int64, _ threshold: Float) -> Bool {
        // Past the end of the measured sound counts as quiet.
        guard index >= 0, index < Int64(levels.decibels.count) else { return true }
        return levels.decibels[Int(index)] < threshold
    }
}

public extension Project {
    /// Applies a plan: each clip with cuts is replaced by the pieces between them. The first piece
    /// keeps the clip's identity, so a selection survives.
    mutating func apply(_ plan: SilencePlan) {
        var clips: [Clip] = []
        for clip in timeline.clips {
            guard let cuts = plan.sourceCuts[clip.id] else {
                clips.append(clip)
                continue
            }
            var pieces: [CMTimeRange] = []
            var cursor = clip.sourceStart
            for cut in cuts.sorted(by: { $0.start < $1.start }) {
                if cut.start > cursor { pieces.append(CMTimeRange(start: cursor, end: cut.start)) }
                cursor = max(cursor, cut.end)
            }
            if clip.sourceRange.end > cursor { pieces.append(CMTimeRange(start: cursor, end: clip.sourceRange.end)) }
            let kept = pieces.filter { $0.duration >= .oneFrame }
            for (number, piece) in kept.enumerated() {
                var part = clip.piece(id: number == 0 ? clip.id : UUID(), sourceStart: piece.start, duration: clip.timelineDuration(ofSource: piece.duration).snappedToFrame())
                part.keepFades(isFirst: number == 0, isLast: number == kept.count - 1)
                clips.append(part)
            }
        }
        timeline.clips = clips
    }
}
