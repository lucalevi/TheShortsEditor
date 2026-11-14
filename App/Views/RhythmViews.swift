import CoreMedia
import EditorCore
import RenderEngine
import SwiftUI

// Rhythm (Stage I) in the inspector: speed curves and smooth slow motion (under Speed), how a
// clip comes in and goes out, and the music's beats, place and looping.

/// A tile in one of the small grids (speed curves, animations): a drawing or symbol and a name.
/// Chosen is shown by a thicker frame too, not by colour alone.
struct RhythmTile<Icon: View>: View {
    let name: String
    let hint: String
    let isChosen: Bool
    let action: () -> Void
    @ViewBuilder let icon: () -> Icon

    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                icon().frame(height: 20)
                Text(name).font(.caption2).lineLimit(1).minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(isChosen ? Color.accentColor.opacity(0.35) : Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
            .overlay {
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

/// The shape of a speed curve: high is fast, low is slow, with a faint line at normal speed.
struct SpeedCurveDrawing: View {
    let shape: SpeedCurveShape?

    var body: some View {
        Canvas { context, size in
            let maxFactor = 5.0
            func y(_ factor: Double) -> CGFloat {
                // On a log scale, so slow and fast look as far from normal.
                let value = (log2(factor) - log2(0.2)) / (log2(maxFactor) - log2(0.2))
                return size.height * (1 - CGFloat(min(max(value, 0), 1)))
            }
            var normal = Path()
            normal.move(to: CGPoint(x: 0, y: y(1)))
            normal.addLine(to: CGPoint(x: size.width, y: y(1)))
            context.stroke(normal, with: .color(.secondary.opacity(0.5)), style: StrokeStyle(lineWidth: 0.5, dash: [2, 2]))
            var line = Path()
            let steps = 40
            for i in 0...steps {
                let u = Double(i) / Double(steps)
                let point = CGPoint(x: size.width * CGFloat(u), y: y(shape?.factor(at: u) ?? 1))
                if i == 0 { line.move(to: point) } else { line.addLine(to: point) }
            }
            context.stroke(line, with: .color(.primary), lineWidth: 1.5)
        }
        .frame(width: 34, height: 18)
    }
}

/// Speed curves and smooth slow motion, under the clip's speed.
struct RhythmSpeedExtras: View {
    let model: EditorModel
    let clips: [Clip]

    private let columns = [GridItem(.adaptive(minimum: 62), spacing: 6)]
    private var mainClips: [Clip] { clips.filter { model.project.timeline.index(of: $0.id) != nil && !$0.isFrozen } }
    private var curve: SpeedCurveShape? { mainClips.first?.speedCurve?.shape }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !mainClips.isEmpty {
                Text("Speed curve").font(.subheadline.weight(.semibold))
                LazyVGrid(columns: columns, alignment: .leading, spacing: 6) {
                    RhythmTile(name: "None", hint: "One speed all through", isChosen: curve == nil) {
                        model.setSpeedCurve(nil, for: mainClips.map(\.id))
                    } icon: {
                        SpeedCurveDrawing(shape: nil)
                    }
                    ForEach(SpeedCurveShape.allCases) { shape in
                        RhythmTile(name: shape.displayName, hint: shape.hint, isChosen: curve == shape) {
                            model.setSpeedCurve(shape, for: mainClips.map(\.id))
                        } icon: {
                            SpeedCurveDrawing(shape: shape)
                        }
                    }
                }
                if curve != nil {
                    Text("The clip speeds up and slows down by itself, on top of its speed. It shows the same footage, so its length changes.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            SmoothSlowMotionToggle(model: model, clips: clips)
        }
    }
}

/// Makes slowed-down video smooth by making up the pictures in between.
struct SmoothSlowMotionToggle: View {
    let model: EditorModel
    let clips: [Clip]

    var body: some View {
        let candidates = clips.filter { model.canSmooth($0) || $0.smoothSlowMotion }
        if !candidates.isEmpty {
            let progress = candidates.compactMap { model.smoothing[$0.id] }.first
            VStack(alignment: .leading, spacing: 4) {
                Toggle(
                    "Smooth slow motion",
                    isOn: Binding(
                        get: { candidates.allSatisfy(\.smoothSlowMotion) },
                        set: { model.setSmoothSlowMotion($0, for: candidates.map(\.id)) })
                )
                .toggleStyle(.checkbox)
                if let progress {
                    ProgressView(value: progress) { Text("Making the pictures in between…").font(.caption) }
                } else {
                    Text(
                        FrameInterpolator.usesOpticalFlow
                            ? "Slowed down, this video would show the same picture several times. This makes the pictures in between, on this Mac."
                            : "Slowed down, this video would show the same picture several times. This blends the pictures in between."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

/// How the clip's picture comes in at its start and goes at its end.
struct ClipAnimationSection: View {
    let model: EditorModel
    let clip: Clip

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Comes in and goes out").font(.subheadline.weight(.semibold))
            row(entering: true)
            row(entering: false)
        }
    }

    @ViewBuilder
    private func row(entering: Bool) -> some View {
        let animation = entering ? clip.animationIn : clip.animationOut
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(entering ? "Comes in" : "Goes out").frame(width: 64, alignment: .leading)
                Picker(
                    entering ? "Comes in" : "Goes out",
                    selection: Binding(get: { animation?.kind }, set: { model.setAnimation($0, entering: entering, for: [clip.id]) })
                ) {
                    Text("None").tag(MotionAnimation?.none)
                    Divider()
                    ForEach(MotionAnimation.allCases) { kind in
                        Label(kind.displayName, systemImage: kind.systemImage).tag(MotionAnimation?.some(kind))
                    }
                }
                .labelsHidden()
                .controlSize(.small)
            }
            if let animation {
                AnimationLengthSlider(model: model, clipID: clip.id, entering: entering, length: animation.duration)
            }
        }
    }
}

private struct AnimationLengthSlider: View {
    let model: EditorModel
    let clipID: Clip.ID
    let entering: Bool
    let length: CMTime
    @State private var dragging: Double?

    var body: some View {
        let seconds = dragging ?? length.seconds
        HStack {
            Text("Length").font(.caption).frame(width: 64, alignment: .leading)
            Slider(value: Binding(get: { seconds }, set: { dragging = $0 }), in: ClipAnimation.durationRange) { editing in
                if !editing, let value = dragging {
                    dragging = nil
                    model.setAnimationLength(CMTime(seconds: value, preferredTimescale: 600), entering: entering, for: clipID)
                }
            }
            .controlSize(.small)
            Text("\(seconds.formatted(.number.precision(.fractionLength(1)))) s").monospacedDigit().font(.caption).frame(width: 36, alignment: .trailing)
        }
    }
}

/// The music's beats, where it starts on the timeline, and looping.
struct MusicRhythmSection: View {
    let model: EditorModel
    let music: BackgroundMusic
    let song: MediaAsset
    @State private var draggingStart: Double?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Beats").font(.subheadline.weight(.semibold))
                HStack {
                    Toggle("Show beats", isOn: Binding(get: { music.showsBeats && model.project.hasBeats }, set: { model.setShowsBeats($0) }))
                        .toggleStyle(.checkbox)
                        .disabled(model.findingBeats)
                    if model.findingBeats {
                        ProgressView().controlSize(.small)
                        Text("Listening…").font(.caption).foregroundStyle(.secondary)
                    }
                }
                Text(
                    music.mood != nil
                        ? "The app's music knows its beats. They show on the music, and cuts and edges snap to them."
                        : "Finds the song's beats by listening to it, on this Mac. They show on the music, and cuts and edges snap to them."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                Menu("Cut to the Beat") {
                    ForEach(BeatSpacing.allCases) { spacing in
                        Button(spacing.displayName) { model.cutToBeat(spacing) }
                    }
                }
                .fixedSize()
                .disabled(model.findingBeats)
                .help("Trim the clips so every cut lands on a beat of the music")
                if music.showsBeats {
                    HStack {
                        Button("Add Beat") { model.addBeatAtPlayhead() }
                            .help("Add a beat where the playhead is")
                        Button("Remove Beat") { model.removeBeatAtPlayhead() }
                            .disabled(!model.beatNearPlayhead)
                            .help("Remove the beat at the playhead")
                        if music.mood == nil || music.beats != nil {
                            Button("Find Again") { model.findBeatsAgain() }
                                .disabled(model.findingBeats)
                                .help(music.mood == nil ? "Listen to the song again (forgets beats added by hand)" : "Back to the music's own beats")
                        }
                    }
                    .controlSize(.small)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Starts on the timeline at").font(.subheadline.weight(.semibold))
                let latest = max(model.duration.seconds - 1, 0)
                HStack {
                    Slider(value: Binding(get: { draggingStart ?? music.start.seconds }, set: { draggingStart = $0 }), in: 0...max(latest, 0.01)) { editing in
                        if !editing, let value = draggingStart {
                            draggingStart = nil
                            model.setMusicTimelineStart(CMTime(seconds: value, preferredTimescale: 600))
                        }
                    }
                    .disabled(latest <= 0)
                    Text(TimeFormat.string(CMTime(seconds: draggingStart ?? music.start.seconds, preferredTimescale: 600)))
                        .monospacedDigit()
                        .frame(width: 48, alignment: .trailing)
                }
                HStack {
                    Button("Start at Playhead") { model.setMusicTimelineStart(model.currentTime) }
                        .disabled(model.currentTime >= model.duration)
                    if music.start > .zero {
                        Button("Start with the Short") { model.setMusicTimelineStart(.zero) }
                    }
                }
                .controlSize(.small)
                Text("Let the Short begin without music, then bring the song in. You can also drag the music on the timeline.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if music.mood == nil {
                    Toggle("Loop the song", isOn: Binding(get: { music.loops }, set: { model.setMusicLoops($0) }))
                        .toggleStyle(.checkbox)
                    Text("When the song ends before your Short does, it starts again from its beginning.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}
