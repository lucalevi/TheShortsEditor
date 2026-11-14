import CoreMedia
import EditorCore
import RenderEngine
import SwiftUI

/// How fast a clip plays.
struct SpeedSection: View {
    let model: EditorModel
    let clips: [Clip]
    @State private var dragging: Double?

    private var speed: Double { clips.first?.speed ?? 1 }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Speed").font(.subheadline.weight(.semibold))
                Spacer()
                if clips.contains(where: { $0.speed != 1 }) {
                    Button("Reset") { model.setSpeed(1, for: clips.map(\.id)) }
                        .controlSize(.small)
                        .help("Back to normal speed (1×)")
                }
            }
            HStack(spacing: 4) {
                ForEach(Clip.speedPresets, id: \.self) { preset in
                    Button(label(preset)) { model.setSpeed(preset, for: clips.map(\.id)) }
                        .buttonStyle(.bordered)
                        .tint(abs(speed - preset) < 0.001 ? .accentColor : nil)
                        .accessibilityAddTraits(abs(speed - preset) < 0.001 ? .isSelected : [])
                }
            }
            .controlSize(.small)
            HStack {
                // A logarithmic slider: as far from 1× to 2× as from 0.5× to 1×.
                Slider(
                    value: Binding(get: { log2(dragging ?? speed) }, set: { dragging = pow(2, $0) }),
                    in: log2(Clip.speedRange.lowerBound)...log2(Clip.speedRange.upperBound)
                ) { editing in
                    if !editing, let value = dragging {
                        dragging = nil
                        model.setSpeed((value * 20).rounded() / 20, for: clips.map(\.id))
                    }
                }
                .controlSize(.small)
                Text(label(dragging ?? speed)).monospacedDigit().frame(width: 44, alignment: .trailing)
            }
            Text(speed > 1 ? "Faster and shorter. Voices keep their pitch." : speed < 1 ? "Slow motion: longer. Voices keep their pitch." : "As recorded.")
                .font(.caption)
                .foregroundStyle(.secondary)
            RhythmSpeedExtras(model: model, clips: clips)
            TimeExtras(model: model, clips: clips)
        }
    }

    private func label(_ value: Double) -> String {
        value == value.rounded() ? "\(Int(value))×" : "\(value.formatted(.number.precision(.fractionLength(0...2))))×"
    }
}

/// Voice clean-up for clips with sound.
struct CleanVoiceToggle: View {
    let model: EditorModel
    let clips: [Clip]

    var body: some View {
        let progress = clips.compactMap { model.voiceCleaning[$0.assetID] }.first
        VStack(alignment: .leading, spacing: 4) {
            Toggle("Clean up voice", isOn: Binding(get: { clips.allSatisfy(\.cleansVoice) }, set: { model.setCleansVoice($0, for: clips.map(\.id)) }))
                .disabled(progress != nil)
            if let progress {
                ProgressView(value: progress) { Text("Cleaning up the sound…").font(.caption) }
            } else {
                Text("Removes background noise and hum, keeps the voice. Done on this Mac with Apple's voice isolation.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// Following the subject: makes a horizontal clip vertical by gliding with the face or subject.
struct FollowSubjectButton: View {
    let model: EditorModel
    let clip: Clip

    var body: some View {
        let isWide = model.project.asset(id: clip.assetID).map { $0.displaySize.width > $0.displaySize.height * 0.75 } ?? false
        if isWide {
            VStack(alignment: .leading, spacing: 4) {
                if let reframing = model.reframing, reframing.clipID == clip.id {
                    ProgressView(value: reframing.progress) { Text("Finding the subject…").font(.caption) }
                } else {
                    Button("Follow the Subject", systemImage: "person.crop.rectangle") { model.followSubject(clip.id) }
                        .disabled(model.reframing != nil)
                        .help("Fill the screen and glide to keep the face (or what stands out) in the middle")
                }
            }
            .controlSize(.small)
        }
    }
}

/// How B-roll shares the screen: over the clip, split screen, or small in a corner.
struct LayoutSection: View {
    let model: EditorModel
    let overlay: Overlay

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Layout").font(.subheadline.weight(.semibold))
            Picker(
                "Layout",
                selection: Binding(
                    get: { overlay.layout.isSplit },
                    set: { split in
                        model.setLayout(split ? .top : .free, for: overlay.id)
                    })
            ) {
                Text("Over").tag(false)
                Text("Split Screen").tag(true)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            Text(
                overlay.layout == .free
                    ? "Over the clip below it. Or put it small in a corner:"
                    : "This clip fills the part chosen below, the clip under it the rest. Two split clips at once can share the screen in three, like a top and a bottom third."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            if overlay.layout.isSplit {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 4) {
                    ForEach(OverlayLayout.splits) { layout in
                        let isChosen = overlay.layout == layout
                        Button {
                            model.setLayout(layout, for: overlay.id)
                        } label: {
                            Label(layout.displayName, systemImage: isChosen ? "checkmark" : layout.symbolName)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .help("This clip in the \(layout.displayName.lowercased()) of the screen")
                        .accessibilityAddTraits(isChosen ? .isSelected : [])
                    }
                }
                .controlSize(.small)
            }
            if overlay.layout == .free {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 4) {
                    ForEach(PictureCorner.allCases) { corner in
                        Button(corner.displayName) { model.putInCorner(corner, overlayID: overlay.id) }
                            .help("Small, in the corner, clear of YouTube's buttons")
                    }
                }
                .controlSize(.small)
            }
        }
    }
}

/// A sound effect or voice-over.
struct SoundInspector: View {
    let model: EditorModel
    let sound: SoundClip

    var body: some View {
        let asset = model.project.asset(id: sound.clip.assetID)
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Label(
                    sound.detachedFrom != nil ? "Sound of \(asset?.name ?? "a clip")" : asset?.name ?? "Missing sound",
                    systemImage: sound.isVoiceOver ? "mic.fill" : sound.detachedFrom != nil ? "waveform.path" : "waveform"
                )
                .font(.headline)
                .lineLimit(2)
                Text("From \(TimeFormat.string(sound.start)) for \(TimeFormat.string(sound.duration))")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            ClipSoundPublic(model: model, clip: sound.clip)
            if sound.detachedFrom != nil {
                Text(
                    "Detached from its clip. Drag its start earlier to hear it before the picture changes, or its end later to let it carry on over the next clip."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
            SoundShapingSection(model: model, clip: sound.clip)
                .id(sound.id)
            if sound.detachedFrom == nil {
                Toggle(
                    "It's a voice-over",
                    isOn: Binding(
                        get: { sound.isVoiceOver },
                        set: { on in
                            model.apply(on ? "Mark as Voice-Over" : "Mark as Sound Effect") { $0.updateSound(sound.id) { $0.isVoiceOver = on } }
                        }))
                Text("The music is lowered under voice-overs, as under people talking in your clips.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if sound.canLowerUnderSpeech {
                Toggle(
                    "Lower while people talk",
                    isOn: Binding(
                        get: { sound.lowersUnderSpeech },
                        set: { on in
                            model.apply(on ? "Lower Sound Under Speech" : "Keep Sound Level") { $0.updateSound(sound.id) { $0.lowersUnderSpeech = on } }
                        }))
                Text("For a second song or background sound: it goes quieter whenever someone speaks, like the music.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if sound.isVoiceOver || sound.detachedFrom != nil { CleanVoiceToggle(model: model, clips: [sound.clip]) }
            FollowClipToggle(model: model, item: .sound(sound.id))
            HStack {
                Button("Start at Playhead") { model.moveSound(sound.id, to: model.currentTime) }
                Button("Delete", systemImage: "trash", role: .destructive) { model.deleteSelection() }
            }
            .controlSize(.small)
        }
    }
}

/// Volume with a live value while dragging, saved when let go.
struct ClipSoundPublic: View {
    let model: EditorModel
    let clip: Clip
    @State private var dragging: Double?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Volume").font(.subheadline.weight(.semibold))
            HStack {
                Button(clip.isMuted ? "Unmute" : "Mute", systemImage: clip.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill") {
                    model.setClipMuted(clip.id, !clip.isMuted)
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
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
        }
    }
}

/// A row of colour swatches, optionally with "None". Each swatch says its colour when pointed at.
struct ColorRow: View {
    let title: String
    let selection: RGBA?
    var allowsNone = false
    let onChange: (RGBA?) -> Void

    private static let names = ["White", "Black", "Yellow", "Orange", "Red", "Pink", "Purple", "Blue", "Cyan", "Green", "Lime"]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            HStack(spacing: 4) {
                if allowsNone {
                    swatch(nil, name: "None")
                }
                ForEach(Array(RGBA.palette.enumerated()), id: \.offset) { index, color in
                    swatch(color, name: Self.names[index])
                }
            }
        }
    }

    private func swatch(_ color: RGBA?, name: String) -> some View {
        let isSelected = color == selection
        return Button {
            onChange(color)
        } label: {
            ZStack {
                if let color {
                    Circle().fill(Color(red: color.red, green: color.green, blue: color.blue))
                } else {
                    Circle().strokeBorder(Color.secondary, lineWidth: 1)
                    Image(systemName: "line.diagonal").font(.system(size: 10))
                }
            }
            .frame(width: 16, height: 16)
            .overlay(Circle().strokeBorder(Color.primary.opacity(isSelected ? 1 : 0.25), lineWidth: isSelected ? 2.5 : 1).padding(-2))
        }
        .buttonStyle(.plain)
        .help(name)
        .accessibilityLabel(name)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// A menu of font families, with the system font and adding font files.
struct FontMenu: View {
    let model: EditorModel
    let selection: String?
    let onChange: (String?) -> Void

    var body: some View {
        Menu {
            Button("System Font") { onChange(nil) }
            Divider()
            ForEach(FontLibrary.families, id: \.self) { family in
                Button(family) { onChange(family) }
            }
            Divider()
            Button("Add Fonts…") { model.importFonts() }
        } label: {
            Text(selection ?? "System Font").lineLimit(1)
        }
        .help("The font. Add your own with Add Fonts… at the bottom.")
    }
}

/// Whether a title, B-roll clip or sound moves with the main clip under its start.
struct FollowClipToggle: View {
    let model: EditorModel
    let item: TimelineItem

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Toggle("Move with the clip under it", isOn: Binding(get: { model.project.followsClip(item) }, set: { model.setFollowsClip($0, for: item) }))
            Text(
                model.project.followsClip(item)
                    ? "Pinned to the clip below its start (the thin line on the timeline): moving, trimming or speeding up that clip carries it along."
                    : "Stays at its time on the timeline whatever happens to the clips, e.g. to land on a beat of the music."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// Reset All for a clip, and copying its settings to others.
struct ClipSettingsButtons: View {
    let model: EditorModel
    let clipID: Clip.ID

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Settings").font(.subheadline.weight(.semibold))
            HStack {
                Button("Copy", systemImage: "doc.on.doc") { model.copySettings() }
                    .help("Copy this clip's picture, motion, speed and sound settings (⌥⌘C), to paste on other clips (⌥⌘V)")
                Menu("Paste") {
                    Button("All") { model.pasteSettings(Set(SettingsKind.allCases)) }
                    Divider()
                    ForEach(SettingsKind.allCases) { kind in
                        Button(kind.displayName) { model.pasteSettings([kind]) }
                    }
                }
                .fixedSize()
                .disabled(model.copiedClip == nil || model.copiedClip?.id == clipID)
                Button("Reset All") { model.resetSettings(Set(SettingsKind.allCases), of: [clipID]) }
                    .disabled(model.project.changedSettings(of: clipID).isEmpty)
                    .help("Back to how the clip was when added: picture, motion, speed and sound")
            }
            .controlSize(.small)
        }
    }
}

/// A stretch of the storyline picked with R or X: what can be done to just that part.
struct RangeInspector: View {
    let model: EditorModel
    let range: CMTimeRange
    @State private var volume: Double = 1

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("\(TimeFormat.string(range.duration)) picked").font(.headline).monospacedDigit()
                Text("From \(TimeFormat.string(range.start)) to \(TimeFormat.string(range.end))")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 6) {
                Button("Delete This Part", systemImage: "trash") { model.deleteRange() }
                    .help("Take it out; what comes after closes up (⌫)")
                Button("Keep Only This Part", systemImage: "scissors") { model.trimToRange() }
                    .help("Trim the clips it touches to just this part (⌥/)")
                Button("Play It", systemImage: "play.fill") { model.playSelection() }
                    .help("Play just this part (/). With Loop on, it plays over and over.")
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("Speed of this part").font(.subheadline.weight(.semibold))
                HStack(spacing: 4) {
                    ForEach(Clip.speedPresets, id: \.self) { speed in
                        Button(speed == 1 ? "1×" : "\(speed.formatted())×") { model.setSpeedInRange(speed) }
                            .buttonStyle(.bordered)
                    }
                }
                .controlSize(.small)
                Text("The picture eases into and out of the new speed. Turn that off under Speed on the clip.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Instant Replay", systemImage: "gobackward") { model.addInstantReplay() }
                    .controlSize(.small)
                    .help("Show this part once more straight after itself, at half speed")
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("Volume of this part").font(.subheadline.weight(.semibold))
                HStack {
                    Slider(value: $volume, in: 0...Clip.maxVolume) { editing in
                        if !editing { model.setVolumeInRange((volume * 20).rounded() / 20) }
                    }
                    .controlSize(.small)
                    Text("\(Int((volume * 100).rounded()))%").monospacedDigit().frame(width: 44, alignment: .trailing)
                }
                Button("Mute This Part", systemImage: "speaker.slash") { model.setVolumeInRange(1, muted: true) }
                    .controlSize(.small)
                Text("The sound fades smoothly into and out of the new volume.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Button("Clear Range") { model.clearRanges() }
                .controlSize(.small)
            Text("Hold R and drag across clips to pick another part, or press X for the clip under the pointer. Escape lets go.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

extension OverlayLayout {
    /// A small picture of where the clip goes.
    var symbolName: String {
        switch self {
        case .free: "rectangle"
        case .top, .topThird: "rectangle.tophalf.filled"
        case .bottom, .bottomThird: "rectangle.bottomhalf.filled"
        case .left: "rectangle.lefthalf.filled"
        case .right: "rectangle.righthalf.filled"
        }
    }
}
