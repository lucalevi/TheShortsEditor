import EditorCore
import SwiftUI

/// The tabs of a clip's details, so only one kind of setting shows at a time (iMovie's adjustments
/// bar, CapCut's tabs) instead of one long page.
enum ClipDetailsTab: String, CaseIterable, Identifiable {
    case picture, colour, speed, sound, effects

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .picture: "Picture"
        case .colour: "Colour"
        case .speed: "Speed"
        case .sound: "Sound"
        case .effects: "Effects"
        }
    }

    var systemImage: String {
        switch self {
        case .picture: "crop"
        case .colour: "circle.lefthalf.filled"
        case .speed: "gauge.with.dots.needle.67percent"
        case .sound: "speaker.wave.2"
        case .effects: "sparkles"
        }
    }

    var help: String {
        switch self {
        case .picture: "Fill or fit, size and place, steadying, cut-outs"
        case .colour: "Enhance, filters and colour sliders"
        case .speed: "Slow motion, fast forward, freeze frames"
        case .sound: "Volume, fades, clean-up and voice effects"
        case .effects: "How it comes in and goes out, effects, the transition after it"
        }
    }
}

/// A row of tabs: an icon with its name under it.
struct DetailsTabBar<Tab: Hashable & Identifiable>: View {
    let tabs: [Tab]
    /// The tab showing (none: something else is shown, e.g. the shot list).
    let selection: Tab?
    let onSelect: (Tab) -> Void
    let name: (Tab) -> String
    let systemImage: (Tab) -> String
    var help: (Tab) -> String = { _ in "" }

    var body: some View {
        HStack(spacing: 2) {
            ForEach(tabs) { tab in
                let isSelected = tab == selection
                Button {
                    onSelect(tab)
                } label: {
                    VStack(spacing: 2) {
                        Image(systemName: systemImage(tab)).font(.system(size: 14))
                        Text(name(tab)).font(.caption2.weight(isSelected ? .bold : .regular)).lineLimit(1).minimumScaleFactor(0.7)
                    }
                    .frame(maxWidth: .infinity, minHeight: 38)
                    .background(isSelected ? Color.accentColor.opacity(0.3) : .clear, in: RoundedRectangle(cornerRadius: 6))
                    .overlay {
                        RoundedRectangle(cornerRadius: 6).strokeBorder(isSelected ? Color.accentColor : .clear, lineWidth: 1.5)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(help(tab))
                .accessibilityLabel(name(tab))
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
    }
}

/// The selected main clip: its name and length, the tabs, the chosen tab's settings, and the
/// actions every clip has.
struct ClipInspector: View {
    let model: EditorModel
    let clip: Clip
    /// The tab last chosen, kept for every clip in this window.
    @SceneStorage("clipDetailsTab") private var tab = ClipDetailsTab.picture

    private var asset: MediaAsset? { model.project.asset(id: clip.assetID) }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 10) {
                Thumbnail(image: model.thumbnails[clip.assetID])
                    .frame(width: 54, height: 54)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                VStack(alignment: .leading, spacing: 2) {
                    Text(asset?.name ?? "Missing media").font(.headline).lineLimit(2)
                    Text("Length \(TimeFormat.string(clip.duration))").foregroundStyle(.secondary)
                }
            }

            DetailsTabBar(tabs: ClipDetailsTab.allCases, selection: tab, onSelect: { tab = $0 }, name: \.displayName, systemImage: \.systemImage, help: \.help)

            switch tab {
            case .picture: picture
            case .colour: LookSection(model: model, clip: clip).id(clip.id)
            case .speed: speed
            case .sound: sound
            case .effects: effects
            }

            Divider()
            ClipSettingsButtons(model: model, clipID: clip.id)
            HStack {
                Button("Split at Playhead", systemImage: "scissors") { model.splitAtPlayhead() }
                Button("Delete", systemImage: "trash", role: .destructive) { model.deleteSelection() }
            }
            .controlSize(.small)
        }
    }

    @ViewBuilder
    private var picture: some View {
        PictureSection(model: model, clip: clip, isMain: true)
            .id(clip.id)
        if model.canStabilize(clip) {
            SteadySection(model: model, clip: clip)
                .id(clip.id)
        }
        MotionSection(model: model, clip: clip)
        if model.canCutOut(clip) {
            CutoutSection(model: model, clip: clip, isMain: true)
                .id(clip.id)
        }
    }

    @ViewBuilder
    private var speed: some View {
        HStack {
            Button("Freeze Frame", systemImage: "snowflake") { model.addFreezeFrame() }
                .help("Hold the picture at the playhead for three seconds (⌥F)")
                .disabled(clip.isFrozen || asset?.isImage == true)
            Button("Replay", systemImage: "gobackward") { model.addInstantReplay() }
                .help("Show this clip once more straight after itself, at half speed")
        }
        .controlSize(.small)
        if clip.isFrozen {
            FreezeSection(model: model, clip: clip)
        } else if asset?.isImage != true {
            SpeedSection(model: model, clips: [clip])
                .id(clip.id)
        } else {
            Text("A picture has no speed: drag its edge on the timeline to show it longer.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var sound: some View {
        if clip.isFrozen {
            Text("A freeze frame is one picture, without sound.").foregroundStyle(.secondary)
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
    }

    @ViewBuilder
    private var effects: some View {
        ClipAnimationSection(model: model, clip: clip)
            .id(clip.id)
        EffectsSection(model: model, clip: clip)
            .id(clip.id)
        TransitionSection(model: model, clip: clip)
            .id(clip.id)
    }
}

/// A video or picture shown over the main clips (B-roll, picture-in-picture), with the same tabs.
struct OverlayInspector: View {
    let model: EditorModel
    let overlay: Overlay
    @SceneStorage("clipDetailsTab") private var tab = ClipDetailsTab.picture

    private var asset: MediaAsset? { model.project.asset(id: overlay.clip.assetID) }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 10) {
                Thumbnail(image: model.thumbnails[overlay.clip.assetID])
                    .frame(width: 54, height: 54)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                VStack(alignment: .leading, spacing: 2) {
                    Text(asset?.name ?? "Missing media").font(.headline).lineLimit(2)
                    Text("From \(TimeFormat.string(overlay.start)) for \(TimeFormat.string(overlay.duration))")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
            Text("Shown over the clips below it. Their sound keeps playing.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            DetailsTabBar(tabs: ClipDetailsTab.allCases, selection: tab, onSelect: { tab = $0 }, name: \.displayName, systemImage: \.systemImage, help: \.help)

            switch tab {
            case .picture: picture
            case .colour: LookSection(model: model, clip: overlay.clip).id(overlay.id)
            case .speed: speed
            case .sound: sound
            case .effects: effects
            }

            Divider()
            FollowClipToggle(model: model, item: .overlay(overlay.id))
            ClipSettingsButtons(model: model, clipID: overlay.id)
            HStack {
                Button("Start at Playhead") { model.moveOverlay(overlay.id, to: model.playback.currentTime) }
                Button("Delete", systemImage: "trash", role: .destructive) { model.deleteSelection() }
            }
            .controlSize(.small)
        }
    }

    @ViewBuilder
    private var picture: some View {
        LayoutSection(model: model, overlay: overlay)
        PictureSection(model: model, clip: overlay.clip, isMain: false)
            .id(overlay.id)
        SeeThroughSection(model: model, clip: overlay.clip)
            .id(overlay.id)
        if model.canStabilize(overlay.clip) {
            SteadySection(model: model, clip: overlay.clip)
                .id(overlay.id)
        }
        MotionSection(model: model, clip: overlay.clip)
        if model.canCutOut(overlay.clip) {
            CutoutSection(model: model, clip: overlay.clip, isMain: false)
                .id(overlay.clip.id)
        }
    }

    @ViewBuilder
    private var speed: some View {
        if asset?.isImage != true {
            SpeedSection(model: model, clips: [overlay.clip])
                .id(overlay.id)
        } else {
            Text("A picture has no speed: drag its edge on the timeline to show it longer.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var sound: some View {
        if asset?.hasAudio == true {
            Toggle("Play its own sound", isOn: Binding(get: { !overlay.clip.isMuted }, set: { model.setClipMuted(overlay.id, !$0) }))
            if !overlay.clip.isMuted {
                ClipSound(model: model, clip: overlay.clip, hasSound: true)
                    .id(overlay.id)
                CleanVoiceToggle(model: model, clips: [overlay.clip])
                SoundShapingSection(model: model, clip: overlay.clip)
                    .id(overlay.id)
            }
        } else {
            Text("This has no sound.").foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var effects: some View {
        ClipAnimationSection(model: model, clip: overlay.clip)
            .id(overlay.clip.id)
        EffectsSection(model: model, clip: overlay.clip)
            .id(overlay.clip.id)
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
                Text(
                    clip.isMuted
                        ? "This clip is silent." : "100% is the sound as recorded. Your whole Short is evened out to YouTube's loudness when you export."
                )
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
