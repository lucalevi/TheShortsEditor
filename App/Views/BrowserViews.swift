import CoreMedia
import EditorCore
import RenderEngine
import SwiftUI

/// The tabs of the browser on the left: one for each kind of thing that can be put in a Short,
/// as in iMovie (Media, Audio, Titles, Transitions) and CapCut.
enum BrowserTab: String, CaseIterable, Identifiable {
    case media, audio, text, transitions, effects, captions

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .media: "Media"
        case .audio: "Audio"
        case .text: "Text"
        case .transitions: "Transitions"
        case .effects: "Effects"
        case .captions: "Captions"
        }
    }

    var systemImage: String {
        switch self {
        case .media: "photo.on.rectangle"
        case .audio: "music.note"
        case .text: "textformat"
        case .transitions: "rectangle.lefthalf.inset.filled.arrow.left"
        case .effects: "sparkles"
        case .captions: "captions.bubble"
        }
    }

    var help: String {
        switch self {
        case .media: "Your videos and pictures, and the Photos library"
        case .audio: "Music, voice-overs and sound effects"
        case .text: "Titles, ready-made texts and stickers"
        case .transitions: "How one clip turns into the next"
        case .effects: "Effects and filters for your clips"
        case .captions: "Captions from what is said, and editing by text"
        }
    }

    /// The panel the tab opens on.
    var sidebar: EditorModel.Sidebar {
        switch self {
        case .media: .media
        case .audio: .audio
        case .text: .text
        case .transitions: .transitions
        case .effects: .effects
        case .captions: .captions
        }
    }

    /// The tab a panel belongs to (Photos is in Media, Script in Captions).
    init?(_ sidebar: EditorModel.Sidebar) {
        switch sidebar {
        case .media, .photos: self = .media
        case .audio: self = .audio
        case .text: self = .text
        case .transitions: self = .transitions
        case .effects: self = .effects
        case .captions, .script: self = .captions
        case .storyboard: return nil
        }
    }
}

/// Two panels in one tab (Your Media / Photos, Captions / Script).
struct BrowserSubPicker: View {
    @Bindable var model: EditorModel
    let choices: [(EditorModel.Sidebar, String)]

    var body: some View {
        Picker("Show", selection: $model.sidebar) {
            ForEach(choices, id: \.0) { Text($0.1).tag($0.0) }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .controlSize(.small)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }
}

/// What a browser tile is put on: the selected clips, else the clip under the playhead.
@MainActor
private func targetClips(_ model: EditorModel) -> [Clip.ID] {
    let selected = model.selectedClips.map(\.id)
    if !selected.isEmpty { return selected }
    guard let (index, _) = model.project.timeline.locate(model.currentTime.snappedToFrame()) else { return [] }
    return [model.project.timeline.clips[index].id]
}

/// A square tile with a picture and a name, added with a click or dragged onto the timeline.
private struct BrowserTile<Picture: View>: View {
    let name: String
    let help: String
    let payload: BrowserDrop
    let picture: Picture
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                picture
                    .frame(maxWidth: .infinity, minHeight: 44, maxHeight: 44)
                    .background(Color(white: 0.2), in: RoundedRectangle(cornerRadius: 6))
                Text(name).font(.caption).lineLimit(1).minimumScaleFactor(0.8)
            }
            .padding(4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
        .draggable(payload.text)
        .accessibilityLabel(name)
    }
}

private let tileColumns = [GridItem(.adaptive(minimum: 74), spacing: 6)]

/// A line under a group of tiles saying how to use them.
private struct BrowserHint: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - Text

/// Titles in every style, ready-made texts and stickers.
struct TextBrowser: View {
    let model: EditorModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Titles").font(.subheadline.weight(.semibold))
                LazyVGrid(columns: tileColumns, spacing: 6) {
                    ForEach(TitleStyle.allCases) { style in
                        BrowserTile(
                            name: style.displayName, help: "Add a \(style.displayName) title at the playhead, or drag it onto the timeline",
                            payload: .title(style), picture: TitleStyleImage(style: style),
                            action: { model.addTitle(style: style) }
                        )
                    }
                }
                BrowserHint(text: "Click a style to add a title at the playhead, then type its words on the picture.")
                Divider()
                StickerPicker(model: model, isPanel: true)
            }
            .padding(12)
        }
        .disabled(model.project.timeline.clips.isEmpty)
    }
}

private struct TitleStyleImage: View {
    let style: TitleStyle
    @State private var image: CGImage?

    var body: some View {
        ZStack {
            if let image { Image(decorative: image, scale: 1).resizable().scaledToFit().padding(5) }
        }
        .task { image = TitlePreview.image(for: style.look, text: "Title") }
    }
}

// MARK: - Transitions

struct TransitionsBrowser: View {
    let model: EditorModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                LazyVGrid(columns: tileColumns, spacing: 6) {
                    ForEach(TransitionKind.allCases) { kind in
                        BrowserTile(
                            name: kind.displayName, help: "\(kind.hint) Click to put it on the cut nearest the playhead, or drag it onto a cut.",
                            payload: .transition(kind), picture: Image(systemName: kind.systemImage).font(.system(size: 20)),
                            action: { model.addTransition(kind) }
                        )
                    }
                }
                BrowserHint(text: "Click one to put it on the cut nearest the playhead (or after the selected clip), or drag it onto a cut.")
                Button("On Every Cut") { model.setTransitionOnEveryCut(model.preferredTransition) }
                    .controlSize(.small)
                    .help("The last transition you used, on every cut between clips")
                Button("Remove All Transitions") { model.setTransitionOnEveryCut(nil) }
                    .controlSize(.small)
            }
            .padding(12)
        }
        .disabled(model.project.timeline.clips.count < 2)
    }
}

// MARK: - Effects

struct EffectsBrowser: View {
    let model: EditorModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Effects").font(.subheadline.weight(.semibold))
                LazyVGrid(columns: tileColumns, spacing: 6) {
                    ForEach(EffectKind.allCases) { kind in
                        BrowserTile(
                            name: kind.displayName,
                            help: "\(kind.hint) Click to add it to the selected clip (or the one at the playhead), or drag it onto a clip.",
                            payload: .effect(kind), picture: Image(systemName: kind.systemImage).font(.system(size: 20)),
                            action: { model.addEffect(kind, to: targetClips(model)) }
                        )
                    }
                }
                Text("Filters").font(.subheadline.weight(.semibold))
                LazyVGrid(columns: tileColumns, spacing: 6) {
                    BrowserTile(
                        name: "None", help: "Take the filter off the selected clip (or the one at the playhead)", payload: .filter(nil),
                        picture: Image(systemName: "circle.slash").font(.system(size: 20)),
                        action: { model.setFilter(nil, for: targetClips(model)) }
                    )
                    ForEach(LookFilter.allCases) { filter in
                        BrowserTile(
                            name: filter.displayName, help: "Click to put it on the selected clip (or the one at the playhead), or drag it onto a clip.",
                            payload: .filter(filter), picture: FilterSwatch(filter: filter),
                            action: { model.setFilter(filter, for: targetClips(model)) }
                        )
                    }
                }
                BrowserHint(text: "Click to put it on the selected clip (or the one at the playhead), or drag it onto a clip. Change it in the clip's details.")
            }
            .padding(12)
        }
        .disabled(model.project.timeline.clips.isEmpty)
    }
}

/// A filter shown as a bar of colours through it.
private struct FilterSwatch: View {
    let filter: LookFilter

    var body: some View {
        let choice = FilterChoice(filter)
        HStack(spacing: 0) {
            ForEach(Array(Self.samples.enumerated()), id: \.offset) { _, sample in
                let c = choice.apply(sample)
                Rectangle().fill(Color(.sRGB, red: c.r, green: c.g, blue: c.b))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .padding(6)
    }

    /// Skin, sky, grass, shadow and highlight.
    private static let samples: [RGB] = [
        RGB(0.85, 0.62, 0.5), RGB(0.35, 0.6, 0.9), RGB(0.3, 0.65, 0.3), RGB(0.15, 0.15, 0.18), RGB(0.95, 0.93, 0.88),
    ]
}

// MARK: - Audio

/// Music for under the Short, then voice-overs and sound effects (`SoundsView`).
struct AudioBrowser: View {
    let model: EditorModel

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Music").font(.subheadline.weight(.semibold))
                    Spacer()
                    if let song = model.musicAsset {
                        Button("Edit \(song.name)") { model.selection = .music }
                            .controlSize(.small)
                            .lineLimit(1)
                            .help("The music's volume and settings")
                    }
                }
                LazyVGrid(columns: tileColumns, spacing: 6) {
                    ForEach(MusicMood.allCases) { mood in
                        BrowserTile(
                            name: mood.displayName, help: "\(mood.hint). Click to play it under your whole Short.", payload: .music(mood),
                            picture: Image(systemName: "music.note").font(.system(size: 18)),
                            action: { model.addMoodMusic(mood) }
                        )
                    }
                }
                Button("Song from a File…") { MusicImportPanel.run(model: model) }
                    .controlSize(.small)
                BrowserHint(text: "Music plays under the whole Short and goes down while people talk.")
            }
            .padding(12)
            .disabled(model.project.timeline.clips.isEmpty)
            Divider()
            SoundsView(model: model)
        }
    }
}

// MARK: - Dragging tiles onto the timeline

/// What a browser tile carries when it is dragged onto the timeline, as plain text (the drop
/// on the timeline turns it back).
enum BrowserDrop: Equatable {
    case title(TitleStyle)
    case transition(TransitionKind)
    case effect(EffectKind)
    case filter(LookFilter?)
    case music(MusicMood)

    private static let prefix = "shorts-editor:"

    var text: String {
        switch self {
        case .title(let style): Self.prefix + "title:" + style.rawValue
        case .transition(let kind): Self.prefix + "transition:" + kind.rawValue
        case .effect(let kind): Self.prefix + "effect:" + kind.rawValue
        case .filter(let filter): Self.prefix + "filter:" + (filter?.rawValue ?? "none")
        case .music(let mood): Self.prefix + "music:" + mood.rawValue
        }
    }

    init?(text: String) {
        guard text.hasPrefix(Self.prefix) else { return nil }
        let parts = text.dropFirst(Self.prefix.count).split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return nil }
        switch parts[0] {
        case "title": guard let style = TitleStyle(rawValue: parts[1]) else { return nil }; self = .title(style)
        case "transition": guard let kind = TransitionKind(rawValue: parts[1]) else { return nil }; self = .transition(kind)
        case "effect": guard let kind = EffectKind(rawValue: parts[1]) else { return nil }; self = .effect(kind)
        case "filter": self = .filter(LookFilter(rawValue: parts[1]))
        case "music": guard let mood = MusicMood(rawValue: parts[1]) else { return nil }; self = .music(mood)
        default: return nil
        }
    }
}

extension EditorModel {
    /// A browser tile dropped on the timeline at `time`: a title starts there, a transition goes
    /// on the nearest cut, an effect or filter on the clip there, music under the whole Short.
    func dropBrowserItem(_ drop: BrowserDrop, at time: CMTime) {
        let time = time.snappedToFrame().clamped(.zero, max(.zero, duration - .oneFrame))
        let clipThere = project.timeline.locate(time).map { [project.timeline.clips[$0.index].id] } ?? []
        switch drop {
        case .title(let style):
            playback.seek(to: time)
            addTitle(style: style)
        case .transition(let kind):
            guard let cut = project.timeline.clipBeforeCut(nearest: time) else { return NSSound.beep() }
            setTransition(kind, after: cut)
        case .effect(let kind):
            addEffect(kind, to: clipThere)
        case .filter(let filter):
            setFilter(filter, for: clipThere)
        case .music(let mood):
            addMoodMusic(mood)
        }
    }
}
