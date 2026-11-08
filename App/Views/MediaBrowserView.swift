import EditorCore
import SwiftUI

/// Everything imported into the project. Double-click (or drag) a video to put it on the timeline.
struct MediaBrowserView: View {
    @Bindable var model: EditorModel

    var body: some View {
        List(selection: $model.selectedAssetID) {
            ForEach(model.project.assets) { asset in
                MediaRow(asset: asset, thumbnail: model.thumbnails[asset.id])
                    .tag(asset.id)
                    .draggable(asset.url)
            }
        }
        .contextMenu(forSelectionType: MediaAsset.ID.self) { ids in
            Button("Add to Timeline") { ids.forEach(model.appendToTimeline) }
        } primaryAction: { ids in
            ids.forEach(model.appendToTimeline)
        }
        .overlay {
            if model.project.assets.isEmpty {
                ContentUnavailableView {
                    Label("No Media Yet", systemImage: "film.stack")
                } description: {
                    Text("Drop videos here, or click Import.")
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
            .frame(height: 32)
            .background(.bar)
            .overlay(alignment: .bottom) { Divider() }

            Group {
                switch model.sidebar {
                case .media: MediaBrowserView(model: model)
                case .captions: CaptionsView(model: model)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

private struct MediaRow: View {
    let asset: MediaAsset
    let thumbnail: CGImage?

    var body: some View {
        HStack(spacing: 10) {
            Thumbnail(image: thumbnail)
                .frame(width: 44, height: 44)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            VStack(alignment: .leading, spacing: 2) {
                Text(asset.name).lineLimit(1)
                HStack(spacing: 6) {
                    Text(TimeFormat.string(asset.duration))
                    Image(systemName: asset.displaySize.height > asset.displaySize.width ? "rectangle.portrait" : "rectangle")
                        .help(asset.displaySize.height > asset.displaySize.width ? "Vertical video" : "Horizontal video")
                    if !asset.hasAudio {
                        Image(systemName: "speaker.slash").help("No sound")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
        .help("Double-click to add to the timeline")
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
        .background(.bar)
        .overlay(alignment: .bottom) { Divider() }
    }
}

extension PanelHeader where Accessory == EmptyView {
    init(title: String) {
        self.init(title: title) { EmptyView() }
    }
}
