import CoreMedia
import Foundation

// Stage F (one-click Shorts): storyboards, like iMovie's on iPhone. A storyboard is a shot list
// that says what to film and for how long; each shot is filled with a clip, in order.

/// The kinds of Short a storyboard can be started from.
public enum StoryboardKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case tutorial, review, beforeAfter, topThree, dayInTheLife, story

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .tutorial: "How-To"
        case .review: "Review"
        case .beforeAfter: "Before and After"
        case .topThree: "Top 3"
        case .dayInTheLife: "Day in the Life"
        case .story: "Story Time"
        }
    }

    public var hint: String {
        switch self {
        case .tutorial: "Teach one thing in three steps"
        case .review: "The good, the bad and your verdict"
        case .beforeAfter: "A transformation, start to finish"
        case .topThree: "A countdown to the best one"
        case .dayInTheLife: "Your day in quick moments"
        case .story: "Something that happened, told well"
        }
    }

    public var systemImage: String {
        switch self {
        case .tutorial: "list.number"
        case .review: "star.leadinghalf.filled"
        case .beforeAfter: "arrow.left.and.right.square"
        case .topThree: "trophy"
        case .dayInTheLife: "sun.horizon"
        case .story: "text.bubble"
        }
    }

    /// The style it looks best in.
    public var suggestedStyle: ShortStyle {
        switch self {
        case .tutorial: .explainer
        case .review: .bold
        case .beforeAfter: .pop
        case .topThree: .bold
        case .dayInTheLife: .vlog
        case .story: .cinematic
        }
    }

    public var shots: [Shot] {
        func s(_ name: String, _ direction: String, _ seconds: Int64, title: String? = nil, talking: Bool = false) -> Shot {
            Shot(name: name, direction: direction, length: CMTime(value: seconds, timescale: 1), title: title, isTalking: talking)
        }
        let follow = s("Call to action", "Look into the camera: ask them to follow, or what they think.", 3, talking: true)
        switch self {
        case .tutorial:
            return [
                s("Hook", "The finished result, up close. Say what they'll learn.", 2),
                s("Problem", "Why it matters, or what usually goes wrong.", 4, talking: true),
                s("Step 1", "Show the first step, close enough to see.", 5, title: "Step 1", talking: true),
                s("Step 2", "The second step.", 5, title: "Step 2", talking: true),
                s("Step 3", "The last step.", 5, title: "Step 3", talking: true),
                s("Payoff", "The result again, working.", 3),
                follow,
            ]
        case .review:
            return [
                s("Hook", "The product in your hand, with your verdict in one line.", 2),
                s("What it is", "What it is, what it costs, who it's for.", 5, talking: true),
                s("The good", "What you liked, shown not told.", 6, title: "The good", talking: true),
                s("The bad", "What you didn't like.", 6, title: "The bad", talking: true),
                s("Verdict", "Would you buy it again? Say it straight.", 4, title: "Worth it?", talking: true),
                follow,
            ]
        case .beforeAfter:
            return [
                s("Hook", "A flash of the after, to make them stay.", 2),
                s("Before", "How it looked at the start, from where you'll film the after.", 3, title: "Before"),
                s("The work", "The doing, in quick shots (it will be sped up later if you like).", 8),
                s("After", "The result, from the same spot as the before.", 4, title: "After"),
                s("Reaction", "You, or someone, seeing it.", 3, talking: true),
            ]
        case .topThree:
            return [
                s("Hook", "Say the topic: \u{201C}3 things you…\u{201D}", 2, talking: true),
                s("Number 3", "The good one.", 5, title: "#3", talking: true),
                s("Number 2", "The better one.", 5, title: "#2", talking: true),
                s("Number 1", "The best one, and why.", 6, title: "#1", talking: true),
                s("Call to action", "Ask which one they'd pick.", 3, talking: true),
            ]
        case .dayInTheLife:
            return [
                s("Hook", "The most interesting moment of the day.", 2),
                s("Morning", "Waking up, first coffee: a few quick shots.", 4),
                s("Getting going", "On the way, or starting work.", 4),
                s("The main thing", "What the day is really about.", 6, talking: true),
                s("Something unexpected", "A surprise, a laugh, a detail.", 4),
                s("Evening", "Winding down.", 4),
                s("Sign-off", "Say goodnight to the camera.", 2, talking: true),
            ]
        case .story:
            return [
                s("Hook", "Start with the most dramatic line of the story.", 2, talking: true),
                s("Setup", "Where you were and what was going on.", 6, talking: true),
                s("Twist", "What happened. Show it if you can.", 6, talking: true),
                s("Ending", "How it turned out, and what you learned.", 5, talking: true),
                follow,
            ]
        }
    }
}

/// One shot of a storyboard.
public struct Shot: Codable, Equatable, Sendable {
    public var name: String
    /// What to film.
    public var direction: String
    /// How long it is meant to be on screen.
    public var length: CMTime
    /// A title shown over its first seconds, like "Step 1".
    public var title: String?
    /// Someone talking: the whole clip is kept, as cutting a sentence short would spoil it. Other
    /// shots are trimmed to their length.
    public var isTalking: Bool
    /// How its clip changes into the next (templates).
    public var transition: TransitionKind? = nil
    /// How its clip comes in (templates).
    public var entrance: MotionAnimation? = nil
    /// The clip is made exactly this long, slowed down if it is shorter, and its title stays
    /// for the whole shot (templates: the cuts fall on the beat).
    public var fitsExactly = false

    public init(
        name: String, direction: String, length: CMTime, title: String? = nil, isTalking: Bool = false,
        transition: TransitionKind? = nil, entrance: MotionAnimation? = nil, fitsExactly: Bool = false
    ) {
        self.name = name
        self.direction = direction
        self.length = length
        self.title = title
        self.isTalking = isTalking
        self.transition = transition
        self.entrance = entrance
        self.fitsExactly = fitsExactly
    }

    private enum CodingKeys: String, CodingKey { case name, direction, length, title, isTalking, transition, entrance, fitsExactly }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decode(String.self, forKey: .name)
        direction = try c.decode(String.self, forKey: .direction)
        length = try c.decodeTime(forKey: .length)
        title = try c.decodeIfPresent(String.self, forKey: .title)
        isTalking = try c.decodeIfPresent(Bool.self, forKey: .isTalking) ?? false
        transition = try? c.decodeIfPresent(TransitionKind.self, forKey: .transition)
        entrance = try? c.decodeIfPresent(MotionAnimation.self, forKey: .entrance)
        fitsExactly = try c.decodeIfPresent(Bool.self, forKey: .fitsExactly) ?? false
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(name, forKey: .name)
        try c.encode(direction, forKey: .direction)
        try c.encode(time: length, forKey: .length)
        try c.encodeIfPresent(title, forKey: .title)
        try c.encode(isTalking, forKey: .isTalking)
        try c.encodeIfPresent(transition, forKey: .transition)
        try c.encodeIfPresent(entrance, forKey: .entrance)
        if fitsExactly { try c.encode(fitsExactly, forKey: .fitsExactly) }
    }
}

/// A Short's shot list and which clip fills each shot. The shots are copied in, so a Short
/// keeps its storyboard even if the app's templates change.
public struct Storyboard: Codable, Equatable, Sendable {
    public struct Slot: Codable, Equatable, Identifiable, Sendable {
        public var id: UUID
        public var shot: Shot
        /// The main clip filling it, if any. A clip that was deleted leaves the shot empty again.
        public var clipID: Clip.ID?
        /// The shot's title, added when it was filled.
        public var titleID: TextOverlay.ID?

        public init(id: UUID = UUID(), shot: Shot, clipID: Clip.ID? = nil, titleID: TextOverlay.ID? = nil) {
            self.id = id
            self.shot = shot
            self.clipID = clipID
            self.titleID = titleID
        }
    }

    public var kind: StoryboardKind
    public var slots: [Slot]
    /// The template it was made from, when it was (see `Templates.swift`).
    public var template: ShortTemplate? = nil

    public init(kind: StoryboardKind) {
        self.kind = kind
        slots = kind.shots.map { Slot(shot: $0) }
    }

    /// Its name, to show.
    public var name: String { template?.displayName ?? kind.displayName }

    /// The planned length of the whole Short.
    public var plannedLength: CMTime { slots.reduce(.zero) { $0 + $1.shot.length } }
}

public extension Project {
    /// Starts filming from a storyboard (replacing any earlier one).
    mutating func startStoryboard(_ kind: StoryboardKind) {
        storyboard = Storyboard(kind: kind)
    }

    /// The clip filling a storyboard shot, when it is still on the timeline.
    func clip(filling slot: Storyboard.Slot) -> Clip? {
        slot.clipID.flatMap { id in timeline.clips.first { $0.id == id } }
    }

    /// When each shot is planned to start in the finished Short (filled shots at their clip,
    /// empty ones where they would go), for showing the shot list as a timeline.
    func plannedStart(of slotID: Storyboard.Slot.ID) -> CMTime {
        guard let storyboard else { return .zero }
        var time = CMTime.zero
        for slot in storyboard.slots {
            if slot.id == slotID { return time }
            time = time + (clip(filling: slot)?.duration ?? slot.shot.length)
        }
        return time
    }

    /// Fills a storyboard shot with `part` of a file (or all of it): the clip goes into the
    /// storyline after the clips of the shots before it, replacing the shot's earlier clip.
    /// Shots that aren't talking are trimmed to their planned length (from the middle of a
    /// longer clip, where the action usually is). Returns the new clip's id.
    @discardableResult
    mutating func fill(_ slotID: Storyboard.Slot.ID, with assetID: MediaAsset.ID, part: CMTimeRange? = nil) -> Clip.ID? {
        guard var board = storyboard, let slotIndex = board.slots.firstIndex(where: { $0.id == slotID }),
            var clip = makeClip(of: assetID, part: part), let asset = asset(id: assetID)
        else { return nil }
        let slot = board.slots[slotIndex]
        let wanted = slot.shot.length.snappedToFrame()
        if asset.isImage {
            clip.duration = wanted
        } else if !slot.shot.isTalking, !clip.isFrozen, clip.duration > wanted {
            let spare = clip.sourceDuration - clip.timelineDuration(ofSource: wanted)
            let start = (clip.sourceStart + CMTimeMultiplyByRatio(max(spare, .zero), multiplier: 1, divisor: 2)).snappedToFrame()
            clip = clip.piece(id: clip.id, sourceStart: start, duration: wanted)
            clip.keyframes = []
        } else if slot.shot.fitsExactly, !clip.isFrozen, clip.duration < wanted {
            // Too short for its beat: slowed down to fill it (as far as slow motion goes).
            let source = clip.sourceDuration
            clip.speed = max(source.seconds / wanted.seconds, Clip.speedRange.lowerBound)
            clip.duration = min(wanted, CMTime(seconds: source.seconds / clip.speed, preferredTimescale: 600).snappedToFrame())
        }
        if slot.shot.fitsExactly {
            clip.transitionOut = slot.shot.transition.map { ClipTransition(kind: $0) }
            clip.animationIn = slot.shot.entrance.map { ClipAnimation($0, duration: CMTime(value: 2, timescale: 5)) }
        }

        // Where it goes: in place of the shot's clip, else after the last filled shot before it,
        // else before the first filled shot after it, else at the end.
        var filled: [Storyboard.Slot.ID: Clip] = [:]
        for other in board.slots { filled[other.id] = self.clip(filling: other) }
        var index = timeline.clips.count
        if let old = self.clip(filling: slot), let at = timeline.index(of: old.id) {
            index = at
            timeline.clips.remove(at: at)
        } else if let before = board.slots[..<slotIndex].reversed().compactMap({ filled[$0.id] }).first,
            let at = timeline.index(of: before.id)
        {
            index = at + 1
        } else if let after = board.slots[(slotIndex + 1)...].compactMap({ filled[$0.id] }).first,
            let at = timeline.index(of: after.id)
        {
            index = at
        }
        timeline.clips.insert(clip, at: min(index, timeline.clips.count))
        board.slots[slotIndex].clipID = clip.id

        if let oldTitle = slot.titleID { removeTitle(oldTitle) }
        board.slots[slotIndex].titleID = nil
        if let text = slot.shot.title, let range = timeline.range(of: clip.id) {
            let length = slot.shot.fitsExactly ? range.duration : min(CMTime(value: 2, timescale: 1), range.duration)
            var title = TextOverlay(text: text, start: range.start, duration: length.snappedToFrame())
            if let style { title.takeLook(of: style) }
            titles.append(title)
            board.slots[slotIndex].titleID = title.id
        }
        storyboard = board
        return clip.id
    }

    /// Takes a shot's clip (and its title) out of the Short, leaving the shot empty.
    mutating func empty(_ slotID: Storyboard.Slot.ID) {
        guard var board = storyboard, let index = board.slots.firstIndex(where: { $0.id == slotID }) else { return }
        if let clipID = board.slots[index].clipID { timeline.remove(clipID) }
        if let titleID = board.slots[index].titleID { removeTitle(titleID) }
        board.slots[index].clipID = nil
        board.slots[index].titleID = nil
        storyboard = board
    }
}
