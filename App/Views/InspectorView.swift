import EditorCore
import SwiftUI

/// Details of the selected clip, or of the whole Short when nothing is selected.
struct InspectorView: View {
    @Bindable var model: EditorModel

    var body: some View {
        VStack(spacing: 0) {
            PanelHeader(
                title: model.silenceSession != nil
                    ? "Remove Pauses"
                    : model.timelineRange != nil
                        ? "Range"
                        : model.timelineSelection.count > 1
                            ? "\(model.timelineSelection.count) Selected"
                            : model.selectedTitle != nil
                                ? (model.selectedTitle?.isSticker == true ? "Sticker" : "Title")
                                : model.selectedOverlay != nil
                                    ? "Over the Clips"
                                    : model.selectedSound != nil
                                        ? (model.selectedSound!.isVoiceOver
                                            ? "Voice-Over"
                                            : model.selectedSound!.detachedFrom != nil
                                                ? "Clip Sound" : model.selectedSound!.lowersUnderSpeech ? "Song" : "Sound Effect")
                                        : model.selection == .music && model.project.music != nil
                                            ? "Music"
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

    /// Selected sound effects and voice-overs.
    private var sounds: [SoundClip] {
        model.project.sounds.filter { model.isSelected(.sound($0.id)) }
    }

    private var summary: [String] {
        let items = model.timelineSelection.items
        let titles = items.filter { if case .title = $0 { true } else { false } }.count
        let overlays = clips.count - mainClips.count
        let voiceOvers = sounds.filter(\.isVoiceOver).count
        let otherSounds = sounds.count - voiceOvers
        var parts: [String] = []
        if !mainClips.isEmpty { parts.append(mainClips.count == 1 ? "1 clip" : "\(mainClips.count) clips") }
        if overlays > 0 { parts.append(overlays == 1 ? "1 clip over the others" : "\(overlays) clips over the others") }
        if titles > 0 { parts.append(titles == 1 ? "1 title" : "\(titles) titles") }
        if voiceOvers > 0 { parts.append(voiceOvers == 1 ? "1 voice-over" : "\(voiceOvers) voice-overs") }
        if otherSounds > 0 { parts.append(otherSounds == 1 ? "1 sound" : "\(otherSounds) sounds") }
        if items.contains(.music) { parts.append("the music") }
        return parts
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(summary.formatted(.list(type: .and)).capitalizedFirst + " selected. Changes here apply to all of them.")
                .fixedSize(horizontal: false, vertical: true)

            let heard = clips + sounds.map(\.clip)
            if !heard.isEmpty {
                MultipleVolumeSlider(model: model, clips: heard)
            }

            if !clips.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Picture").font(.subheadline.weight(.semibold))
                    HStack {
                        Button("Fill Screen") { model.setFraming(.fill, for: clips.map(\.id)) }
                        Button("Show All") { model.setFraming(.fit, for: clips.map(\.id)) }
                    }
                    Button(model.isPunchedIn(clips) ? "Remove Punch-In" : "Punch In", systemImage: "plus.magnifyingglass") {
                        model.togglePunchIn(clips.map(\.id))
                    }
                    if mainClips.count > 1 {
                        Button("Punch In on Every Other Cut") { model.punchInOnAlternateCuts() }
                            .help("Zoom in on every other clip from the same recording, so jump cuts look like a change of camera")
                    }
                    if !mainClips.isEmpty {
                        let allBlack = mainClips.allSatisfy { $0.background == .black }
                        Button(allBlack ? "Blurred Background" : "Black Background") {
                            model.setBackground(allBlack ? .blur : .black, for: mainClips.map(\.id))
                        }
                        .help("What fills the screen around pictures that don't cover it")
                    }
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

            if !pictureClips.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Effects").font(.subheadline.weight(.semibold))
                    Button("Choose an Effect…", systemImage: "sparkles") { model.sidebar = .effects }
                        .help("Opens the Effects tab: click an effect there to add it to every selected clip")
                    Text("Click an effect in the Effects tab to add it to every selected clip.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
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
                Tip(
                    icon: "circle.lefthalf.filled",
                    text:
                        "Press ⌥T to put a transition on the cut nearest the playhead. Plain cuts are usually best; keep transitions for a change of place or time."
                )
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
