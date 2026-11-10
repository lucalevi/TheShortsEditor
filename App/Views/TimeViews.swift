import CoreMedia
import EditorCore
import SwiftUI

// Transitions, freeze frames, backwards and see-through B-roll: the pieces of the inspector and
// the timeline that belong to them.

/// Chooses the transition on the cut after a clip: a grid of kinds, its length, and a few
/// things to do with it. Used in the pop-up on the timeline and in the clip inspector.
struct TransitionPicker: View {
    let model: EditorModel
    /// The clip before the cut.
    let clipID: Clip.ID
    @State private var draggingLength: Double?

    private var transition: ClipTransition? { model.project.transition(after: clipID) }
    private var span: TransitionSpan? { model.project.timeline.transitionSpans.first { $0.from == clipID } }

    private let columns = [GridItem(.adaptive(minimum: 62), spacing: 6)]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            LazyVGrid(columns: columns, alignment: .leading, spacing: 6) {
                tile("None", systemImage: "scissors", hint: "A plain cut", isChosen: transition == nil) {
                    model.setTransition(nil, after: clipID)
                }
                ForEach(TransitionKind.allCases) { kind in
                    tile(kind.displayName, systemImage: kind.systemImage, hint: kind.hint, isChosen: transition?.kind == kind) {
                        model.setTransition(kind, after: clipID)
                        model.playTransition(after: clipID)
                    }
                }
            }
            if let transition {
                let seconds = draggingLength ?? transition.duration.seconds
                HStack {
                    Text("Length")
                    Slider(value: Binding(get: { seconds }, set: { draggingLength = $0 }),
                           in: ClipTransition.minimumDuration.seconds...ClipTransition.maximumDuration.seconds) { editing in
                        if !editing, let value = draggingLength {
                            draggingLength = nil
                            model.setTransitionLength(CMTime(seconds: value, preferredTimescale: 600), after: clipID)
                        }
                    }
                    .controlSize(.small)
                    Text("\(seconds.formatted(.number.precision(.fractionLength(1)))) s").monospacedDigit().frame(width: 40, alignment: .trailing)
                }
                if let span, span.range.duration < transition.duration {
                    Label("Plays for \(span.range.duration.seconds.formatted(.number.precision(.fractionLength(1)))) s: a clip beside it is too short for more.", systemImage: "info.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else if span == nil {
                    Label("Not shown: a clip beside it is too short.", systemImage: "info.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Button("Play It", systemImage: "play.fill") { model.playTransition(after: clipID) }
                        .help("Play from a second before the cut to a second after it")
                    if model.project.timeline.clips.count > 2 {
                        Button("Use on Every Cut") { model.setTransitionOnEveryCut(transition) }
                            .help("Put this transition, at this length, between all the clips")
                    }
                }
                .controlSize(.small)
            }
            if model.project.transitionCount > (transition == nil ? 0 : 1) {
                Button("Remove All Transitions") { model.setTransitionOnEveryCut(nil) }
                    .controlSize(.small)
            }
        }
    }

    private func tile(_ name: String, systemImage: String, hint: String, isChosen: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: systemImage).font(.system(size: 16)).frame(height: 20)
                Text(name).font(.caption2).lineLimit(1).minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(isChosen ? Color.accentColor.opacity(0.35) : Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
            .overlay {
                // Chosen is shown by a thicker frame too, not by colour alone.
                RoundedRectangle(cornerRadius: 6).strokeBorder(isChosen ? Color.primary : Color.white.opacity(0.12), lineWidth: isChosen ? 2 : 1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(hint)
        .accessibilityLabel(name)
        .accessibilityAddTraits(isChosen ? .isSelected : [])
    }
}

/// The clip inspector's part about how the clip changes into the next one.
struct TransitionSection: View {
    let model: EditorModel
    let clip: Clip

    var body: some View {
        if let index = model.project.timeline.index(of: clip.id), index + 1 < model.project.timeline.clips.count {
            VStack(alignment: .leading, spacing: 6) {
                Text("Into the next clip").font(.subheadline.weight(.semibold))
                TransitionPicker(model: model, clipID: clip.id)
                Text("A transition plays over the last moments of this clip and the first of the next. Your Short keeps its length.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// The marker on a cut that has a transition: click it to change the transition.
struct CutBadge: View {
    @Bindable var model: EditorModel
    let clipID: Clip.ID
    let kind: TransitionKind

    var body: some View {
        Button {
            model.transitionPickerCut = clipID
        } label: {
            Image(systemName: kind.systemImage)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.black)
                .frame(width: 20, height: 20)
                .background(Color.white, in: RoundedRectangle(cornerRadius: 5))
                .overlay { RoundedRectangle(cornerRadius: 5).strokeBorder(.black.opacity(0.6), lineWidth: 1) }
                .shadow(color: .black.opacity(0.5), radius: 2, y: 1)
        }
        .buttonStyle(.plain)
        .help("Transition: \(kind.displayName). Click to change it.")
        .accessibilityLabel("Transition: \(kind.displayName)")
        .popover(isPresented: Binding(get: { model.transitionPickerCut == clipID }, set: { if !$0, model.transitionPickerCut == clipID { model.transitionPickerCut = nil } }),
                 arrowEdge: .top) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Transition").font(.headline)
                TransitionPicker(model: model, clipID: clipID)
            }
            .padding(12)
            .frame(width: 300)
        }
        .contextMenu {
            Button("Play It") { model.playTransition(after: clipID) }
            Button("Remove Transition") { model.setTransition(nil, after: clipID) }
        }
    }
}

/// A freeze frame's inspector: how long it holds.
struct FreezeSection: View {
    let model: EditorModel
    let clip: Clip

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Freeze Frame", systemImage: "snowflake").font(.subheadline.weight(.semibold))
            Text("Holds one picture of the video, without sound.")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(spacing: 4) {
                ForEach([1, 2, 3, 5], id: \.self) { seconds in
                    let isNow = abs(clip.duration.seconds - Double(seconds)) < 0.02
                    Button("\(seconds) s") { model.setFreezeLength(CMTime(value: CMTimeValue(seconds), timescale: 1), for: clip.id) }
                        .buttonStyle(.bordered)
                        .tint(isNow ? .accentColor : nil)
                        .accessibilityAddTraits(isNow ? .isSelected : [])
                }
            }
            .controlSize(.small)
            Text("Or drag its edges on the timeline for any length.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

/// Speed extras for video clips: backwards, a gradual change of speed, and a hint for footage
/// filmed for slow motion.
struct TimeExtras: View {
    let model: EditorModel
    let clips: [Clip]

    var body: some View {
        let turnable = clips.filter { model.project.canReverse($0) }
        VStack(alignment: .leading, spacing: 6) {
            if !turnable.isEmpty {
                let progress = turnable.compactMap { model.reversing[$0.id] }.first
                Toggle("Play backwards", isOn: Binding(get: { turnable.allSatisfy { model.project.isReversed($0) } },
                                                       set: { _ in model.toggleBackwards(for: turnable.map(\.id)) }))
                    .disabled(progress != nil)
                if let progress {
                    ProgressView(value: progress) { Text("Turning the clip round…").font(.caption) }
                        .controlSize(.small)
                } else if turnable.contains(where: { model.project.isReversed($0) }) {
                    Text("Plays from a backwards copy of the video, sound included.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if clips.count == 1, let clip = clips.first {
                let ramp = model.speedRampState(of: clip.id)
                if ramp.applies {
                    Toggle("Change speed gradually", isOn: Binding(get: { ramp.isOn }, set: { model.setSmoothSpeed($0, for: [clip.id]) }))
                    Text(ramp.isOn ? "The picture eases into this speed from the part before, and out of it after, instead of jumping."
                         : "The speed changes in one jump at the cut.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let media = model.project.asset(id: clip.assetID), let slowest = media.smoothestSlowSpeed, let rate = media.frameRate {
                    Label("Filmed at \(Int(rate.rounded())) pictures a second: slow motion stays smooth down to \(slowest.formatted(.number.precision(.fractionLength(0...2))))×.",
                          systemImage: "tortoise")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

/// For a clip over the main ones: how solid it is, and how it appears and goes.
struct SeeThroughSection: View {
    let model: EditorModel
    let clip: Clip
    @State private var dragging: (opacity: Double?, fadeIn: Double?, fadeOut: Double?) = (nil, nil, nil)

    private var placement: Placement { model.placementAtPlayhead(of: clip) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("See-through and fades").font(.subheadline.weight(.semibold))
            row("Solid", value: dragging.opacity ?? placement.opacity, range: 0...1, label: { "\(Int(($0 * 100).rounded()))%" }) { value in
                dragging.opacity = value
                var p = placement
                p.opacity = value
                model.previewPlacement(p, for: clip.id)
            } onEnd: {
                if let value = dragging.opacity { model.editPlacement(of: clip, "See-Through") { $0.opacity = (value * 20).rounded() / 20 } }
                dragging.opacity = nil
            }
            row("Fade in", value: dragging.fadeIn ?? clip.pictureFadeIn.seconds, range: 0...2, label: seconds) { dragging.fadeIn = $0 } onEnd: {
                if let value = dragging.fadeIn { model.setPictureFade(.start, to: CMTime(seconds: value, preferredTimescale: 600), for: clip.id) }
                dragging.fadeIn = nil
            }
            row("Fade out", value: dragging.fadeOut ?? clip.pictureFadeOut.seconds, range: 0...2, label: seconds) { dragging.fadeOut = $0 } onEnd: {
                if let value = dragging.fadeOut { model.setPictureFade(.end, to: CMTime(seconds: value, preferredTimescale: 600), for: clip.id) }
                dragging.fadeOut = nil
            }
            Text(clip.hasMotion
                 ? "100% hides what is under it. This picture moves, so how solid it is gets saved at the playhead as a keyframe: it can appear or go over time."
                 : "100% hides what is under it. Lower it to let the clip below show through. Fades make it appear and go gently.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func seconds(_ value: Double) -> String {
        value < 0.02 ? "Off" : "\(value.formatted(.number.precision(.fractionLength(1)))) s"
    }

    private func row(_ title: String, value: Double, range: ClosedRange<Double>, label: @escaping (Double) -> String,
                     onChange: @escaping (Double) -> Void, onEnd: @escaping () -> Void) -> some View {
        HStack {
            Text(title).frame(width: 56, alignment: .leading)
            Slider(value: Binding(get: { min(max(value, range.lowerBound), range.upperBound) }, set: onChange), in: range) { editing in
                if !editing { onEnd() }
            }
            .controlSize(.small)
            Text(label(value)).monospacedDigit().frame(width: 42, alignment: .trailing)
        }
    }
}
