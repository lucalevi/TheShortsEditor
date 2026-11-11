import EditorCore
import SwiftUI

/// Details of the selected clip, or of the whole Short when nothing is selected.
struct InspectorView: View {
    @Bindable var model: EditorModel

    var body: some View {
        VStack(spacing: 0) {
            PanelHeader(title: model.silenceSession != nil ? "Remove Pauses"
                        : model.timelineRange != nil ? "Range"
                        : model.timelineSelection.count > 1 ? "\(model.timelineSelection.count) Selected"
                        : model.selectedTitle != nil ? "Title"
                        : model.selectedOverlay != nil ? "Over the Clips"
                        : model.selectedSound != nil ? (model.selectedSound!.isVoiceOver ? "Voice-Over" : model.selectedSound!.detachedFrom != nil ? "Clip Sound" : "Sound Effect")
                        : model.selection == .music && model.project.music != nil ? "Music"
                        : model.selectedClip == nil ? "Your Short" : "Clip")
            ScrollView {
                Group {
                    if model.silenceSession != nil {
                        SilencePanel(model: model)
                    } else if let range = model.timelineRange {
                        RangeInspector(model: model, range: range)
                    } else if model.timelineSelection.count > 1 {
                        MultipleInspector(model: model)
                    } else if model.selection == .music, let music = model.project.music, let song = model.musicAsset {
                        MusicInspector(model: model, music: music, song: song)
                    } else if let title = model.selectedTitle {
                        TitleInspector(model: model, title: title)
                            .id(title.id)
                    } else if let overlay = model.selectedOverlay {
                        OverlayInspector(model: model, overlay: overlay)
                    } else if let sound = model.selectedSound {
                        SoundInspector(model: model, sound: sound)
                            .id(sound.id)
                    } else if let clip = model.selectedClip {
                        ClipInspector(model: model, clip: clip)
                    } else {
                        ProjectInspector(model: model)
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .background(Theme.panel)
    }
}

/// Several items selected on the timeline: what they are, and what can be done to all of them.
private struct MultipleInspector: View {
    let model: EditorModel

    private var clips: [Clip] {
        model.project.timeline.clips.filter { model.isSelected(.clip($0.id)) }
            + model.project.overlays.map(\.clip).filter { model.isSelected(.overlay($0.id)) }
    }

    private var mainClips: [Clip] {
        clips.filter { model.project.timeline.index(of: $0.id) != nil }
    }

    private var summary: [String] {
        let items = model.timelineSelection.items
        let titles = items.filter { if case .title = $0 { true } else { false } }.count
        let overlays = clips.count - mainClips.count
        var parts: [String] = []
        if !mainClips.isEmpty { parts.append(mainClips.count == 1 ? "1 clip" : "\(mainClips.count) clips") }
        if overlays > 0 { parts.append(overlays == 1 ? "1 clip over the others" : "\(overlays) clips over the others") }
        if titles > 0 { parts.append(titles == 1 ? "1 title" : "\(titles) titles") }
        if items.contains(.music) { parts.append("the music") }
        return parts
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(summary.formatted(.list(type: .and)).capitalizedFirst + " selected.")
                .fixedSize(horizontal: false, vertical: true)

            if !clips.isEmpty {
                let allMuted = clips.allSatisfy(\.isMuted)
                VStack(alignment: .leading, spacing: 6) {
                    Text("Framing").font(.subheadline.weight(.semibold))
                    HStack {
                        Button("Fill Screen") { model.setFraming(.fill, for: clips.map(\.id)) }
                        Button("Show All") { model.setFraming(.fit, for: clips.map(\.id)) }
                    }
                    Text("Sets every selected clip at once.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text("Zoom").font(.subheadline.weight(.semibold))
                    Button(model.isPunchedIn(clips) ? "Remove Punch-In" : "Punch In", systemImage: "plus.magnifyingglass") {
                        model.togglePunchIn(clips.map(\.id))
                    }
                    if mainClips.count > 1 {
                        Button("Punch In on Every Other Cut") { model.punchInOnAlternateCuts() }
                            .help("Zoom in on every other clip from the same recording, so jump cuts look like a change of camera")
                    }
                }
                if !mainClips.isEmpty {
                    let allBlack = mainClips.allSatisfy { $0.background == .black }
                    Button(allBlack ? "Blurred Background" : "Black Background") {
                        model.setBackground(allBlack ? .blur : .black, for: mainClips.map(\.id))
                    }
                    .help("What fills the screen around pictures that don't cover it")
                }
                Button(allMuted ? "Unmute Clips" : "Mute Clips", systemImage: allMuted ? "speaker.wave.2" : "speaker.slash") {
                    model.setClipsMuted(clips.map(\.id), !allMuted)
                }
            }

            let pictureClips = clips.filter { model.project.asset(id: $0.assetID)?.hasVideo == true }
            if !pictureClips.isEmpty {
                MultipleLookSection(model: model, clips: pictureClips)
            }

            let videoClips = clips.filter { model.project.asset(id: $0.assetID)?.isImage != true }
            if !videoClips.isEmpty {
                SpeedSection(model: model, clips: videoClips)
            }

            Button("Delete All Selected", systemImage: "trash", role: .destructive) { model.deleteSelection() }

            Text("⌘-click adds or removes one item. ⇧-click adds the clips in between. Drag across empty space on the timeline to select with a rectangle.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private extension String {
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}

private struct ClipInspector: View {
    let model: EditorModel
    let clip: Clip

    private var asset: MediaAsset? { model.project.asset(id: clip.assetID) }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Thumbnail(image: model.thumbnails[clip.assetID])
                .frame(height: 110)
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 4) {
                Text(asset?.name ?? "Missing media").font(.headline).lineLimit(2)
                Text("Length \(TimeFormat.string(clip.duration))").foregroundStyle(.secondary)
            }

            HStack {
                Button("Freeze Frame", systemImage: "snowflake") { model.addFreezeFrame() }
                    .help("Hold the picture at the playhead for three seconds (⌥F)")
                    .disabled(clip.isFrozen || asset?.isImage == true)
                Button("Replay", systemImage: "gobackward") { model.addInstantReplay() }
                    .help("Show this clip once more straight after itself, at half speed")
            }
            .controlSize(.small)

            PictureSection(model: model, clip: clip, isMain: true)
                .id(clip.id)

            LookSection(model: model, clip: clip)
                .id(clip.id)

            if model.canStabilize(clip) {
                SteadySection(model: model, clip: clip)
                    .id(clip.id)
            }

            MotionSection(model: model, clip: clip)

            if clip.isFrozen {
                FreezeSection(model: model, clip: clip)
            } else if asset?.isImage != true {
                SpeedSection(model: model, clips: [clip])
                    .id(clip.id)
            }

            if clip.isFrozen {
                // One picture: no sound of its own.
            } else {
                if !clip.soundDetached {
                    ClipSound(model: model, clip: clip, hasSound: asset?.hasAudio ?? false)
                        .id(clip.id)
                }
                if asset?.hasAudio == true, asset?.isImage != true {
                    if !clip.soundDetached { CleanVoiceToggle(model: model, clips: [clip]) }
                    SoundShapingSection(model: model, clip: clip, isMain: true)
                        .id(clip.id)
                }
            }

            TransitionSection(model: model, clip: clip)
                .id(clip.id)

            ClipSettingsButtons(model: model, clipID: clip.id)

            HStack {
                Button("Split at Playhead", systemImage: "scissors") { model.splitAtPlayhead() }
                Button("Delete", systemImage: "trash", role: .destructive) { model.deleteSelection() }
            }
            .controlSize(.small)
        }
    }
}

/// The clip's volume, with a mute switch. The change is saved when the slider is let go.
private struct ClipSound: View {
    let model: EditorModel
    let clip: Clip
    let hasSound: Bool
    /// The slider's value while it is being dragged.
    @State private var dragging: Double?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Sound").font(.subheadline.weight(.semibold))
            if hasSound {
                HStack {
                    Button(clip.isMuted ? "Unmute" : "Mute", systemImage: clip.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill") {
                        model.setClipMuted(clip.id, !clip.isMuted)
                    }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .frame(width: 22)
                    .help(clip.isMuted ? "Turn this clip's sound back on" : "Silence this clip")
                    Slider(value: Binding(get: { dragging ?? clip.volume }, set: { dragging = $0 }), in: 0...Clip.maxVolume) { editing in
                        if !editing, let value = dragging {
                            dragging = nil
                            model.setClipVolume(clip.id, (value * 20).rounded() / 20)
                        }
                    }
                    .disabled(clip.isMuted)
                    Text(clip.isMuted ? "Off" : "\(Int(((dragging ?? clip.volume) * 100).rounded()))%")
                        .monospacedDigit()
                        .frame(width: 40, alignment: .trailing)
                }
                Text(clip.isMuted ? "This clip is silent." : "100% is the sound as recorded. Your whole Short is evened out to YouTube's loudness when you export.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if clip.volume != 1, !clip.isMuted {
                    Button("Reset to 100%") { model.setClipVolume(clip.id, 1) }.controlSize(.small)
                }
            } else {
                Text("This clip has no sound.").foregroundStyle(.secondary)
            }
        }
    }
}

/// A video or picture shown over the main clips (B-roll, picture-in-picture).
private struct OverlayInspector: View {
    let model: EditorModel
    let overlay: Overlay

    private var asset: MediaAsset? { model.project.asset(id: overlay.clip.assetID) }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Thumbnail(image: model.thumbnails[overlay.clip.assetID])
                .frame(height: 110)
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 4) {
                Text(asset?.name ?? "Missing media").font(.headline).lineLimit(2)
                Text("From \(TimeFormat.string(overlay.start)) for \(TimeFormat.string(overlay.duration))")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                Text("Shown over the clips below it. Their sound keeps playing.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            LayoutSection(model: model, overlay: overlay)

            PictureSection(model: model, clip: overlay.clip, isMain: false)
                .id(overlay.id)

            SeeThroughSection(model: model, clip: overlay.clip)
                .id(overlay.id)

            LookSection(model: model, clip: overlay.clip)
                .id(overlay.id)

            if model.canStabilize(overlay.clip) {
                SteadySection(model: model, clip: overlay.clip)
                    .id(overlay.id)
            }

            MotionSection(model: model, clip: overlay.clip)

            if asset?.isImage != true {
                SpeedSection(model: model, clips: [overlay.clip])
                    .id(overlay.id)
            }

            if asset?.hasAudio == true {
                VStack(alignment: .leading, spacing: 6) {
                    Toggle("Play its own sound", isOn: Binding(get: { !overlay.clip.isMuted }, set: { model.setClipMuted(overlay.id, !$0) }))
                    if !overlay.clip.isMuted {
                        ClipSound(model: model, clip: overlay.clip, hasSound: true)
                            .id(overlay.id)
                        CleanVoiceToggle(model: model, clips: [overlay.clip])
                        SoundShapingSection(model: model, clip: overlay.clip)
                            .id(overlay.id)
                    }
                }
            }

            FollowClipToggle(model: model, item: .overlay(overlay.id))

            ClipSettingsButtons(model: model, clipID: overlay.id)

            HStack {
                Button("Start at Playhead") { model.moveOverlay(overlay.id, to: model.currentTime) }
                Button("Delete", systemImage: "trash", role: .destructive) { model.deleteSelection() }
            }
            .controlSize(.small)
        }
    }
}

private struct ProjectInspector: View {
    let model: EditorModel

    private var fractionOfLimit: Double {
        min(model.duration.seconds / Project.maxDuration.seconds, 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Length").font(.subheadline.weight(.semibold))
                Text("\(TimeFormat.string(model.duration)) of 3:00 max")
                    .monospacedDigit()
                ProgressView(value: fractionOfLimit)
                    .tint(model.project.isOverMaxDuration ? .red : .accentColor)
                if model.project.isOverMaxDuration {
                    Label("Too long for a Short. Trim it to 3:00 or less.", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                        .font(.caption)
                }
            }

            ShortStyleSection(model: model)

            if !model.project.timeline.clips.isEmpty {
                ShortLookSection(model: model)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Format").font(.subheadline.weight(.semibold))
                Text("Vertical 9:16 · 1080 × 1920 · 30 fps").foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Tips").font(.subheadline.weight(.semibold))
                Tip(icon: "bolt.fill", text: "Make the very first second the hook. Cut any intro.")
                Tip(icon: "textformat", text: "Add a title (⌘T) at the start to say what the Short is about.")
                Tip(icon: "rectangle.dashed", text: "Keep faces and text out of the dimmed areas. YouTube covers them.")
                Tip(icon: "hand.tap", text: "Click a clip to select it. Drag it to move it, or drag its edges to trim it.")
                Tip(icon: "rectangle.on.rectangle", text: "Drop B-roll or pictures on the row above the clips to show them over your clips.")
                Tip(icon: "plus.magnifyingglass", text: "Punch in on every other cut (Clip menu) to hide jump cuts.")
                Tip(icon: "circle.lefthalf.filled", text: "Press ⌥T to put a transition on the cut nearest the playhead. Plain cuts are usually best; keep transitions for a change of place or time.")
            }
        }
    }
}

private struct Tip: View {
    let icon: String
    let text: String

    var body: some View {
        Label {
            Text(text).fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: icon).foregroundStyle(.tint)
        }
        .font(.callout)
    }
}
