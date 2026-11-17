import CoreMedia
import EditorCore
import SwiftUI

/// The timeline for VoiceOver, Voice Control and Full Keyboard Access (F25): every clip, B-roll,
/// title and sound is one element with a label (what and where), a value (how long, from when, what
/// was done to it) and the actions a pointer would do by dragging and right-clicking.
struct TimelineItemAccessibility: ViewModifier {
    let item: TimelineItem
    let label: String
    let details: [String]
    let start: CMTime
    let duration: CMTime
    let model: EditorModel
    var moveEarlier: (() -> Void)?
    var moveLater: (() -> Void)?
    var startAtPlayhead: (() -> Void)?
    var canSplit = true

    func body(content: Content) -> some View {
        content
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(label)
            .accessibilityValue(value)
            .accessibilityAddTraits(model.isSelected(item) ? [.isButton, .isSelected] : .isButton)
            .accessibilityHint("Selects it and moves the playhead to its start.")
            // The default action is a click: select it, with the playhead at its start.
            .accessibilityAction { select() }
            .accessibilityActions {
                if canSplit {
                    Button("Split at Playhead") {
                        select(keepingPlayhead: true)
                        model.splitAtPlayhead()
                    }
                }
                if case .clip = item {
                    Button("Trim Start to Playhead") {
                        select(keepingPlayhead: true)
                        model.trimToPlayhead(removing: .start)
                    }
                    Button("Trim End to Playhead") {
                        select(keepingPlayhead: true)
                        model.trimToPlayhead(removing: .end)
                    }
                }
                if let moveEarlier { Button("Move Earlier", action: moveEarlier) }
                if let moveLater { Button("Move Later", action: moveLater) }
                if let startAtPlayhead { Button("Start at Playhead", action: startAtPlayhead) }
                Button("Delete") {
                    select(keepingPlayhead: true)
                    model.deleteSelection()
                }
            }
    }

    private var value: String {
        let timing = "\(TimeFormat.spoken(duration)) long, from \(TimeFormat.string(start))"
        return ([timing] + details).joined(separator: ", ")
    }

    private func select(keepingPlayhead: Bool = false) {
        model.selection = item
        guard !keepingPlayhead else { return }
        model.playback.pause()
        model.playback.seek(to: start)
    }
}

extension TimelineItemAccessibility {
    /// A main clip: "Clip 3 of 12, talk", moved earlier or later among the clips.
    init(clip: Clip, index: Int, model: EditorModel) {
        let clips = model.project.timeline.clips
        let asset = model.project.asset(id: clip.assetID)
        self.init(
            item: .clip(clip.id), label: "Clip \(index + 1) of \(clips.count), \(asset?.name ?? "missing file")",
            details: ClipBlock.spokenDetails(of: clip, isReversed: asset?.reversedFrom != nil, tooLoud: !model.tooLoudRanges(of: clip).isEmpty),
            start: model.project.timeline.startTime(ofClipAt: index), duration: clip.duration, model: model,
            moveEarlier: index > 0 ? { model.moveClip(clip.id, to: index - 1) } : nil,
            moveLater: index + 1 < clips.count ? { model.moveClip(clip.id, to: index + 1) } : nil)
    }
}

/// The Short's length in the timeline's header; too long shows a warning sign, not only red.
struct ShortLengthLabel: View {
    let model: EditorModel

    var body: some View {
        let isOver = model.project.isOverMaxDuration
        Label {
            Text("\(TimeFormat.string(model.duration)) of 3:00").monospacedDigit()
        } icon: {
            if isOver { Image(systemName: "exclamationmark.triangle.fill") }
        }
        .foregroundStyle(isOver ? .red : .secondary)
        .help(isOver ? "Too long for a Short: trim it to 3:00 or less" : "How long your Short is")
    }
}

extension View {
    func timelineItemAccessibility(
        _ item: TimelineItem, label: String, details: [String] = [], start: CMTime, duration: CMTime, model: EditorModel,
        moveEarlier: (() -> Void)? = nil, moveLater: (() -> Void)? = nil, startAtPlayhead: (() -> Void)? = nil, canSplit: Bool = true
    ) -> some View {
        modifier(
            TimelineItemAccessibility(
                item: item, label: label, details: details, start: start, duration: duration, model: model, moveEarlier: moveEarlier, moveLater: moveLater,
                startAtPlayhead: startAtPlayhead, canSplit: canSplit))
    }

    /// The ruler as the playhead (F25): its time as the value, adjusted a second at a time, with
    /// actions for single frames and the ends.
    func playheadAccessibility(_ playback: PlaybackController) -> some View {
        accessibilityElement(children: .ignore)
            .accessibilityLabel("Playhead")
            .accessibilityValue("\(TimeFormat.string(playback.currentTime)) of \(TimeFormat.string(playback.duration))")
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: playback.step(frames: Int(Project.frameRate))
                case .decrement: playback.step(frames: -Int(Project.frameRate))
                @unknown default: break
                }
            }
            .accessibilityActions {
                Button("Next Frame") { playback.step(frames: 1) }
                Button("Previous Frame") { playback.step(frames: -1) }
                Button("Go to Start") { playback.seek(to: .zero) }
                Button("Go to End") { playback.seek(to: playback.duration) }
            }
    }
}

extension ClipBlock {
    /// What the badges on a clip show, in words (they are pictures with tooltips on screen).
    static func spokenDetails(of clip: Clip, isReversed: Bool, tooLoud: Bool) -> [String] {
        var details: [String] = []
        if clip.isFrozen { details.append("freeze frame") }
        if isReversed { details.append("plays backwards") }
        if clip.averageSpeed != 1 { details.append("speed \(clip.averageSpeed.formatted(.number.precision(.fractionLength(0...2))))×") }
        return soundDetails(of: clip, tooLoud: tooLoud) + details + pictureDetails(of: clip)
    }

    private static func soundDetails(of clip: Clip, tooLoud: Bool) -> [String] {
        var details: [String] = []
        if clip.isMuted { details.append("muted") }
        if clip.cleansVoice { details.append("voice cleaned up") }
        if let effect = clip.voiceEffect, !clip.soundDetached { details.append("voice effect \(effect.displayName)") }
        if tooLoud, !clip.isMuted { details.append("too loud in places") }
        return details
    }

    private static func pictureDetails(of clip: Clip) -> [String] {
        var details: [String] = []
        if let filter = clip.look.filter, filter.strength > 0 {
            details.append("filter \(filter.filter.displayName)")
        } else if !clip.look.color.isNeutral {
            details.append("colour changed")
        }
        if clip.steadiness > 0 { details.append("steadied") }
        if clip.cutout.removeBackground != nil {
            details.append("background removed")
        } else if clip.cutout.key != nil {
            details.append("green screen taken away")
        }
        if let mask = clip.cutout.mask { details.append("shape \(mask.shape.displayName)") }
        if clip.hasMotion {
            details.append("the picture moves")
        } else if clip.placement.scale != 1 {
            details.append("zoomed to \(Int((clip.placement.scale * 100).rounded())) percent")
        }
        if !clip.effects.isEmpty { details.append(clip.effects.map(\.kind.displayName).joined(separator: " and ")) }
        return details
    }
}

extension TimeFormat {
    /// A length as it is said, e.g. "4.2 seconds" or "1 minute, 3.5 seconds" (in the Mac's language).
    static func spoken(_ time: CMTime, locale: Locale = .current) -> String {
        let tenths = time.isNumeric && time > .zero ? time.convertScale(10, method: .roundHalfAwayFromZero).value : 0
        return Duration.milliseconds(tenths * 100)
            .formatted(.units(allowed: [.minutes, .seconds], width: .wide, maximumUnitCount: 2, fractionalPart: .show(length: 1)).locale(locale))
    }
}

// MARK: The viewer's handles

extension View {
    /// The box around the selected picture in the viewer (F25): moved, sized and turned by actions
    /// instead of dragging; its size is the adjustable value.
    func pictureAccessibility(name: String, placement: Placement, model: EditorModel, clipID: Clip.ID) -> some View {
        func set(_ actionName: String, _ change: (inout Placement) -> Void) {
            var placement = placement
            change(&placement)
            model.setPlacement(placement.normalized, for: clipID, actionName: actionName)
        }
        let step = 0.05
        return accessibilityElement(children: .ignore)
            .accessibilityLabel("Picture of \(name)")
            .accessibilityValue(
                "\(Int((placement.scale * 100).rounded())) percent, turned \(Int(placement.rotation.rounded())) degrees"
                    + (placement.offsetX == 0 && placement.offsetY == 0 ? ", in the middle" : "")
            )
            .accessibilityAdjustableAction { direction in
                set("Resize Picture") { $0.scale *= direction == .increment ? 1.1 : 1 / 1.1 }
            }
            .accessibilityActions {
                Button("Move Up") { set("Move Picture") { $0.offsetY -= step } }
                Button("Move Down") { set("Move Picture") { $0.offsetY += step } }
                Button("Move Left") { set("Move Picture") { $0.offsetX -= step } }
                Button("Move Right") { set("Move Picture") { $0.offsetX += step } }
                Button("Bigger") { set("Resize Picture") { $0.scale *= 1.1 } }
                Button("Smaller") { set("Resize Picture") { $0.scale /= 1.1 } }
                Button("Turn Left") { set("Turn Picture") { $0.rotation -= 90 } }
                Button("Turn Right") { set("Turn Picture") { $0.rotation += 90 } }
                Button("Put in the Middle") {
                    set("Move Picture") {
                        $0.offsetX = 0
                        $0.offsetY = 0
                    }
                }
            }
    }

    /// A title's box in the viewer (F25): selected by its default action, moved by actions.
    func titleBoxAccessibility(_ title: TextOverlay, model: EditorModel) -> some View {
        func move(dx: Double = 0, dy: Double = 0) {
            model.editTitle(title.id, title.isSticker ? "Move Sticker" : "Move Title") {
                $0.verticalPosition = min(max($0.verticalPosition + dy, 0), 1)
                $0.horizontalPosition = min(max($0.horizontalPosition + dx, 0), 1)
            }
        }
        let fromTop = Int((title.verticalPosition * 100).rounded())
        return accessibilityElement(children: .ignore)
            .accessibilityLabel("\(title.isSticker ? "Sticker" : "Title") on screen, \(title.text.replacingOccurrences(of: "\n", with: " "))")
            .accessibilityValue("\(fromTop) percent from the top" + (title.horizontalPosition == 0.5 ? ", centred" : ""))
            .accessibilityAddTraits(model.selectedTitleID == title.id ? [.isButton, .isSelected] : .isButton)
            .accessibilityAction { model.selectedTitleID = title.id }
            .accessibilityActions {
                if !title.isSticker {
                    Button("Change the Words") {
                        model.selectedTitleID = title.id
                        model.wantsTitleTextFocus = true
                    }
                }
                Button("Move Up") { move(dy: -0.05) }
                Button("Move Down") { move(dy: 0.05) }
                Button("Move Left") { move(dx: -0.05) }
                Button("Move Right") { move(dx: 0.05) }
                Button("Centre Across") { move(dx: 0.5 - title.horizontalPosition) }
            }
    }

    /// The captions' box in the viewer: moved up and down as an adjustable value.
    func captionBoxAccessibility(middle: Double, model: EditorModel) -> some View {
        accessibilityElement(children: .ignore)
            .accessibilityLabel("Captions on screen")
            .accessibilityValue("\(Int((middle * 100).rounded())) percent from the top")
            .accessibilityAdjustableAction { direction in
                model.setCaptionPositionByDragging(middle + (direction == .increment ? -0.05 : 0.05))
            }
    }
}
