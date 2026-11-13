import CoreMedia
import Foundation

// Stage L: templates. A template is a storyboard made to be filled rather than filmed: a fixed
// number of shots, each a whole number of beats of its style's music long, with its text,
// transition and entrance already set. Filling it with clips (in order) makes a Short whose cuts
// land on the beat; each shot can then be swapped in the Shots panel like any storyboard.

/// The ready-made templates.
public enum ShortTemplate: String, Codable, CaseIterable, Identifiable, Sendable {
    case montage, countdown, beforeAfter, travel, recipe, reveal

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .montage: "Quick Montage"
        case .countdown: "Top 5"
        case .beforeAfter: "Before and After"
        case .travel: "Travel Diary"
        case .recipe: "Recipe"
        case .reveal: "Product Reveal"
        }
    }

    public var hint: String {
        switch self {
        case .montage: "Your best moments, one per beat"
        case .countdown: "Five things, best last"
        case .beforeAfter: "A flash from before to after"
        case .travel: "A trip in a handful of places"
        case .recipe: "Ingredients, three steps, ready"
        case .reveal: "Build up, then show it off"
        }
    }

    public var systemImage: String {
        switch self {
        case .montage: "square.grid.3x3.fill"
        case .countdown: "list.number"
        case .beforeAfter: "arrow.left.and.right.square"
        case .travel: "airplane"
        case .recipe: "fork.knife"
        case .reveal: "gift"
        }
    }

    /// The style it comes in, which also sets the music and so the beat.
    public var style: ShortStyle {
        switch self {
        case .montage, .countdown: .bold
        case .beforeAfter: .pop
        case .travel: .vlog
        case .recipe: .explainer
        case .reveal: .cinematic
        }
    }

    /// The shots: what to put in each, how many beats it lasts, its text and how it changes to the next.
    public var shots: [TemplateShot] {
        typealias S = TemplateShot
        switch self {
        case .montage:
            return [
                S("Opener", "Your strongest moment", beats: 4, title: "My week", animation: .zoom),
                S("Moment", "Something happening", beats: 4, transition: .whip),
                S("Moment", "A close-up", beats: 4, transition: .whip),
                S("Moment", "Something moving", beats: 4, transition: .zoom),
                S("Moment", "A face, a reaction", beats: 4, transition: .whip),
                S("Moment", "A wide view", beats: 4, transition: .whip),
                S("Moment", "A funny bit", beats: 4, transition: .zoom),
                S("Ending", "The moment to end on", beats: 4, title: "Follow for more"),
            ]
        case .countdown:
            return [
                S("Topic", "Something that shows what the list is about", beats: 4, title: "Top 5 …", animation: .pop),
                S("Number 5", "The fifth", beats: 8, title: "#5", transition: .whip),
                S("Number 4", "The fourth", beats: 8, title: "#4", transition: .whip),
                S("Number 3", "The third", beats: 8, title: "#3", transition: .whip),
                S("Number 2", "The second", beats: 8, title: "#2", transition: .whip),
                S("Number 1", "The best one", beats: 8, title: "#1", transition: .throughWhite),
                S("Ending", "Ask which one they'd pick", beats: 4, title: "Which one's yours?"),
            ]
        case .beforeAfter:
            return [
                S("Before", "How it was", beats: 8, title: "Before"),
                S("After", "How it is now, from the same spot", beats: 8, title: "After", transition: .throughWhite),
                S("Detail", "A close-up of the result", beats: 4, transition: .zoom),
                S("Ending", "You with it, or it from another side", beats: 4, transition: .slide),
            ]
        case .travel:
            return [
                S("Arrival", "Where you arrived: a sign, a view", beats: 4, title: "Where to next?", animation: .fade),
                S("Place", "A place you went", beats: 4, transition: .slide),
                S("Food", "Something you ate", beats: 4, transition: .slide),
                S("Place", "Another place", beats: 4, transition: .slide),
                S("People", "Who you were with, or the locals", beats: 4, transition: .slide),
                S("Sunset", "The best view, to end on", beats: 4, title: "Worth it", transition: .dissolve),
            ]
        case .recipe:
            return [
                S("The dish", "The finished dish, up close", beats: 4, title: "Ready in 10 minutes", animation: .pop),
                S("Ingredients", "Everything on the table", beats: 8, title: "You need", transition: .slideUp),
                S("Step 1", "The first step", beats: 8, title: "Step 1", transition: .slideUp),
                S("Step 2", "The second step", beats: 8, title: "Step 2", transition: .slideUp),
                S("Step 3", "The last step", beats: 8, title: "Step 3", transition: .slideUp),
                S("Ready", "The dish, served", beats: 4, title: "Enjoy!", transition: .zoom),
            ]
        case .reveal:
            return [
                S("Tease", "A glimpse: a corner, the box", beats: 4, title: "Wait for it…", animation: .fade),
                S("Closer", "A little more of it", beats: 4, transition: .dissolve),
                S("Closer", "Almost all of it", beats: 4, transition: .dissolve),
                S("Reveal", "The whole thing, in its best light", beats: 8, title: "Here it is", transition: .throughWhite),
                S("Detail", "What makes it special", beats: 4, transition: .zoom),
                S("Detail", "Another detail", beats: 4, transition: .zoom),
                S("Ending", "It in use, or in your hand", beats: 4, transition: .dissolve),
            ]
        }
    }

    /// How long a beat of the template's music is.
    public var beatLength: Double { 60 / style.music.tempo }

    /// The shots' lengths on whole frames, worked out from where each cut falls, so rounding
    /// never adds up: every cut is within half a frame of its beat.
    public var shotLengths: [CMTime] {
        var beats = 0
        var previous = CMTime.zero
        return shots.map { shot in
            beats += shot.beats
            let cut = CMTime(seconds: Double(beats) * beatLength, preferredTimescale: 600).snappedToFrame()
            defer { previous = cut }
            return cut - previous
        }
    }

    /// The length of the whole Short.
    public var length: CMTime { shotLengths.reduce(.zero, +) }
}

/// One shot of a template.
public struct TemplateShot: Equatable, Sendable {
    public var name: String
    public var direction: String
    public var beats: Int
    public var title: String?
    /// How it changes to the next shot.
    public var transition: TransitionKind?
    /// How the first shot comes in.
    public var animation: MotionAnimation?

    public init(_ name: String, _ direction: String, beats: Int, title: String? = nil,
                transition: TransitionKind? = nil, animation: MotionAnimation? = nil) {
        self.name = name
        self.direction = direction
        self.beats = beats
        self.title = title
        self.transition = transition
        self.animation = animation
    }
}

public extension Storyboard {
    /// A storyboard to fill from a template: its shots, timed to the beat.
    init(template: ShortTemplate) {
        kind = .story
        self.template = template
        slots = zip(template.shots, template.shotLengths).enumerated().map { index, pair in
            let (shot, length) = pair
            // The transition goes on the shot before, which changes into this one.
            let next = template.shots.indices.contains(index + 1) ? template.shots[index + 1].transition : nil
            return Slot(shot: Shot(name: shot.name, direction: shot.direction, length: length, title: shot.title,
                                   transition: next, entrance: shot.animation, fitsExactly: true))
        }
    }
}

public extension Project {
    /// Makes a Short from a template: its storyboard, filled in order with `assetIDs` (used again
    /// from a different part when there are fewer files than shots).
    mutating func fillTemplate(_ template: ShortTemplate, with assetIDs: [MediaAsset.ID]) {
        let board = Storyboard(template: template)
        storyboard = board
        guard !assetIDs.isEmpty else { return }
        let uses = (board.slots.count + assetIDs.count - 1) / assetIDs.count
        for (index, slot) in board.slots.enumerated() {
            let assetID = assetIDs[index % assetIDs.count]
            let use = index / assetIDs.count
            var part: CMTimeRange?
            if uses > 1, let asset = asset(id: assetID), !asset.isImage {
                // The same file again: a different stretch of it each time, when each stretch is
                // long enough for its shot (a short file is used whole every time).
                let share = CMTimeMultiplyByRatio(asset.duration, multiplier: 1, divisor: Int32(uses))
                if share >= slot.shot.length {
                    part = CMTimeRange(start: CMTimeMultiplyByRatio(share, multiplier: Int32(use), divisor: 1).snappedToFrame(), duration: share.snappedToFrame())
                }
            }
            fill(slot.id, with: assetID, part: part)
        }
    }
}
