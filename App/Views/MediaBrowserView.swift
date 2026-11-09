import EditorCore
import SwiftUI

/// Everything imported into the project. Double-click (or drag) a video to put it on the timeline.
struct MediaBrowserView: View {
    @Bindable var model: EditorModel

    var body: some View {
        List(selection: $model.selectedAssetID) {
            ForEach(model.project.assets) { asset in
                MediaRow(asset: asset, thumbnail: model.thumbnails[asset.id], isMissing: model.missingAssets.contains(asset.id))
                    .tag(asset.id)
                    .draggable(asset.url)
            }
        }
        .contextMenu(forSelectionType: MediaAsset.ID.self) { ids in
            let assets = ids.compactMap(model.project.asset(id:))
            if assets.contains(where: \.hasVideo) {
                Button("Add to Timeline") { assets.filter(\.hasVideo).map(\.id).forEach(model.appendToTimeline) }
                Button("Add Over Clips at Playhead") {
                    model.importFiles(assets.filter(\.hasVideo).map(\.url), to: .overlay(at: model.currentTime))
                }
                .disabled(model.project.timeline.clips.isEmpty)
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
            ids.forEach(model.appendToTimeline)
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
                    ForEach(EditorModel.Sidebar.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                if model.isImporting { ProgressView().controlSize(.small) }
            }
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity)
            .frame(height: 32)
            .background(Theme.header)
            .overlay(alignment: .bottom) { Divider() }

            Group {
                switch model.sidebar {
                case .media: MediaBrowserView(model: model)
                case .captions: CaptionsView(model: model)
                case .script: ScriptView(model: model)
                case .sounds: SoundsView(model: model)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Theme.panel)
    }
}

private struct MediaRow: View {
    let asset: MediaAsset
    let thumbnail: CGImage?
    let isMissing: Bool

    var body: some View {
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
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
        .help(asset.hasVideo ? "Double-click to add to the timeline. Right-click to put it over the clips (B-roll)." : "Double-click to use as the music")
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
