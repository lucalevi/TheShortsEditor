import CoreMedia
import EditorCore
import SwiftUI

/// Everything imported into the project. Double-click (or drag) a video to put it on the timeline.
struct MediaBrowserView: View {
    @Bindable var model: EditorModel

    var body: some View {
        List(selection: $model.selectedAssetID) {
            ForEach(model.project.assets) { asset in
                MediaRow(model: model, asset: asset, thumbnail: model.thumbnails[asset.id], isMissing: model.missingAssets.contains(asset.id))
                    .tag(asset.id)
                    .draggable(asset.url)
            }
        }
        .contextMenu(forSelectionType: MediaAsset.ID.self) { ids in
            let assets = ids.compactMap(model.project.asset(id:))
            if assets.contains(where: \.hasVideo) {
                Button("Add to End (E)") { assets.filter(\.hasVideo).map(\.id).forEach(model.appendMedia) }
                Button("Insert at Playhead (W)") {
                    if let first = assets.first(where: \.hasVideo) {
                        model.selectedAssetID = first.id
                        model.insertSelectedMedia()
                    }
                }
                .disabled(model.project.timeline.clips.isEmpty)
                Button("Add Over Clips at Playhead") {
                    model.importFiles(assets.filter(\.hasVideo).map(\.url), to: .overlay(at: model.currentTime))
                }
                .disabled(model.project.timeline.clips.isEmpty)
            }
            if !assets.isEmpty {
                Divider()
                Button("Delete", role: .destructive) { model.removeAssets(Set(ids)) }
            }
            if assets.contains(where: { model.missingAssets.contains($0.id) }) {
                Button("Find Missing Files…") { model.findMissingFiles() }
            }
            if assets.count == 1, let asset = assets.first, asset.hasAudio {
                Button(asset.hasVideo ? "Use Its Sound as Music" : "Use as Music") { model.useAsMusic(asset.id) }
                if !asset.hasVideo {
                    Button("Add as Sound Effect at Playhead") { model.addSound(asset.id) }
                        .disabled(model.project.timeline.clips.isEmpty)
                }
            }
        } primaryAction: { ids in
            ids.forEach(model.appendMedia)
        }
        .onDeleteCommand {
            if let id = model.selectedAssetID { model.removeAssets([id]) }
        }
        .scrollContentBackground(.hidden)
        .overlay {
            if model.project.assets.isEmpty {
                ContentUnavailableView {
                    Label("No Media Yet", systemImage: "film.stack")
                } description: {
                    Text("Drop videos, pictures or music here, or click Import.")
                } actions: {
                    Button("Import…") { MediaImportPanel.run(model: model, addToTimeline: false) }
                }
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            model.importFiles(urls, addToTimeline: false)
            return true
        }
    }
}

/// The left panel: imported media, or the captions.
struct SidebarView: View {
    @Bindable var model: EditorModel

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Picker("Show", selection: $model.sidebar) {
                    ForEach(EditorModel.Sidebar.allCases.filter { $0 != .storyboard }) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                // Five tabs: the small size keeps them inside the panel.
                .controlSize(.small)
                if model.isImporting { ProgressView().controlSize(.small) }
            }
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity)
            .frame(height: 32)
            .background(Theme.header)
            .overlay(alignment: .bottom) { Divider() }

            // A Short started from a storyboard has its shot list above the tabs.
            if let board = model.project.storyboard {
                Button { model.sidebar = .storyboard } label: {
                    HStack(spacing: 6) {
                        Image(systemName: board.kind.systemImage)
                        Text("Shot List: \(board.kind.displayName)").fontWeight(model.sidebar == .storyboard ? .bold : .regular)
                        Spacer(minLength: 0)
                        if model.sidebar == .storyboard { Image(systemName: "checkmark") }
                    }
                    .padding(.horizontal, 12)
                    .frame(height: 28)
                    .background(model.sidebar == .storyboard ? Color.accentColor.opacity(0.35) : Theme.header)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .overlay(alignment: .bottom) { Divider() }
                .help("What to film for each shot, and which clip fills it")
            }

            Group {
                switch model.sidebar {
                case .media: MediaBrowserView(model: model)
                case .photos: PhotosView(model: model)
                case .captions: CaptionsView(model: model)
                case .script: ScriptView(model: model)
                case .sounds: SoundsView(model: model)
                case .storyboard: StoryboardView(model: model)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Theme.panel)
    }
}

private struct MediaRow: View {
    let model: EditorModel
    let asset: MediaAsset
    let thumbnail: CGImage?
    let isMissing: Bool
    @State private var rowWidth: CGFloat = 1
    @State private var isHovered = false

    private var isUsed: Bool { model.project.usageCount(of: asset.id) > 0 }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 10) {
                Group {
                    if asset.hasVideo {
                        Thumbnail(image: thumbnail)
                    } else {
                        Rectangle().fill(.quaternary).overlay { Image(systemName: "music.note").font(.title3).foregroundStyle(.secondary) }
                    }
                }
                .frame(width: 44, height: 44)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                VStack(alignment: .leading, spacing: 2) {
                    Text(asset.name).lineLimit(1)
                    if isMissing {
                        Label("Can't be found", systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                    HStack(spacing: 6) {
                        if asset.isImage {
                            Text("Picture")
                        } else {
                            Text(TimeFormat.string(asset.duration))
                        }
                        if asset.isImage {
                            Image(systemName: "photo").help("A still picture")
                        } else if asset.hasVideo {
                            Image(systemName: asset.displaySize.height > asset.displaySize.width ? "rectangle.portrait" : "rectangle")
                                .help(asset.displaySize.height > asset.displaySize.width ? "Vertical video" : "Horizontal video")
                        } else {
                            Text("Music")
                        }
                        if !asset.hasAudio, !asset.isImage {
                            Image(systemName: "speaker.slash").help("No sound")
                        }
                        if isUsed {
                            Label("Used", systemImage: "checkmark.circle.fill")
                                .labelStyle(.titleAndIcon)
                                .foregroundStyle(.orange)
                                .help("In your Short. The orange marks on the bar show which parts.")
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                if isHovered, asset.hasVideo {
                    Button("Add to End", systemImage: "plus.circle.fill") { model.appendMedia(asset.id) }
                        .labelStyle(.iconOnly)
                        .buttonStyle(.borderless)
                        .font(.title2)
                        .help(model.mediaPart(of: asset.id) != nil ? "Add the chosen part to the end of your Short (E)" : "Add to the end of your Short (E)")
                }
            }
            if !asset.isImage {
                MediaStrip(model: model, asset: asset)
            }
        }
        .padding(.vertical, 2)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { rowWidth = max($0, 1) }
        .onContinuousHover { phase in
            switch phase {
            case .active(let point):
                isHovered = true
                guard asset.hasVideo else { return }
                let fraction = min(max(point.x / rowWidth, 0), 1)
                model.skimMedia(asset.id, at: CMTime(seconds: asset.duration.seconds * fraction, preferredTimescale: 600))
            case .ended:
                isHovered = false
                model.skimMedia(asset.id, at: nil)
            }
        }
        .help(asset.hasVideo ? "Move the pointer across it to look through it. Double-click or press E to add it to the end, W to put it in at the playhead. Drag across the bar under it to use only part."
              : "Double-click to use as the music")
    }
}

/// The length of a file as a bar: the parts used in the Short are marked, the part chosen for
/// adding is framed, and the skimmer shows where the pointer is. Drag across it to choose a part.
private struct MediaStrip: View {
    let model: EditorModel
    let asset: MediaAsset
    @State private var anchor: Double?

    private func fraction(_ time: CMTime) -> CGFloat {
        guard asset.duration.seconds > 0 else { return 0 }
        return CGFloat(min(max(time.seconds / asset.duration.seconds, 0), 1))
    }

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.14))
                ForEach(Array(model.project.usedParts(of: asset.id).enumerated()), id: \.offset) { _, part in
                    Rectangle()
                        .fill(Color.orange)
                        .frame(width: max(fraction(part.duration) * width, 2), height: 4)
                        .offset(x: fraction(part.start) * width)
                }
                if let part = model.mediaPart(of: asset.id) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.yellow.opacity(0.35))
                        .overlay(RoundedRectangle(cornerRadius: 2).strokeBorder(Color.yellow, lineWidth: 2))
                        .frame(width: max(fraction(part.duration) * width, 3))
                        .offset(x: fraction(part.start) * width)
                }
                if let skim = model.mediaSkim, skim.assetID == asset.id {
                    Rectangle().fill(Color.white).frame(width: 2).offset(x: fraction(skim.time) * width - 1)
                }
            }
            .contentShape(Rectangle())
            .highPriorityGesture(DragGesture(minimumDistance: 0).onChanged { value in
                guard asset.hasVideo else { return }
                let seconds = { (x: CGFloat) in Double(min(max(x / max(width, 1), 0), 1)) * asset.duration.seconds }
                if anchor == nil { anchor = seconds(value.startLocation.x) }
                let a = anchor!, b = seconds(value.location.x)
                guard abs(b - a) * Double(width) / max(asset.duration.seconds, 0.001) > 3 else { return }
                model.selectedAssetID = asset.id
                model.mediaRange = (asset.id, CMTimeRange(start: CMTime(seconds: min(a, b), preferredTimescale: 600).snappedToFrame(),
                                                          end: CMTime(seconds: max(a, b), preferredTimescale: 600).snappedToFrame()))
            }.onEnded { value in
                if abs(value.translation.width) < 3, model.mediaRange?.assetID == asset.id { model.mediaRange = nil }
                anchor = nil
            })
        }
        .frame(height: 10)
        .help("Drag across to use only this part of the file. Orange marks the parts already in your Short.")
        .accessibilityLabel(model.mediaPart(of: asset.id).map { "Chosen part: \(TimeFormat.string($0.duration))" } ?? "Whole file")
    }
}

/// A still image, or a neutral placeholder while it loads.
struct Thumbnail: View {
    let image: CGImage?

    var body: some View {
        if let image {
            Image(decorative: image, scale: 1)
                .resizable()
                .aspectRatio(contentMode: .fill)
        } else {
            Rectangle().fill(.quaternary)
                .overlay { Image(systemName: "film").foregroundStyle(.secondary) }
        }
    }
}

/// The small title row at the top of each panel.
struct PanelHeader<Accessory: View>: View {
    let title: String
    @ViewBuilder var accessory: Accessory

    var body: some View {
        HStack {
            Text(title).font(.headline)
            Spacer()
            accessory
        }
        .padding(.horizontal, 12)
        .frame(height: 32)
        .background(Theme.header)
        .overlay(alignment: .bottom) { Divider() }
    }
}

extension PanelHeader where Accessory == EmptyView {
    init(title: String) {
        self.init(title: title) { EmptyView() }
    }
}
