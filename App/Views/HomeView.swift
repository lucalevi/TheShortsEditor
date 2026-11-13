import CoreMedia
import EditorCore
import SwiftUI

/// The home window, like iMovie's Projects: every Short as a picture, newest first, grouped by
/// when it was last changed. Click a Short to edit it; everything is saved as you go.
struct HomeView: View {
    @Bindable var model: EditorModel
    @State private var search = ""
    @State private var renamingID: UUID?
    @State private var isDropTargeted = false

    static let tileWidth: CGFloat = 150
    private let columns = [GridItem(.adaptive(minimum: tileWidth, maximum: tileWidth), spacing: 22, alignment: .top)]

    private var shown: [ShortEntry] {
        model.shorts.filter { ShortsLibrary.matches($0.name, search: search) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                if search.isEmpty {
                    LazyVGrid(columns: columns, alignment: .leading, spacing: 22) {
                        NewShortTile { model.newShort() }
                        StartTile(title: "Magic Short", systemImage: "wand.and.stars",
                                  help: "Choose clips and get a first cut: pauses out, captions, a hook title and music") { model.newMagicShort() }
                        StartTile(title: "Storyboard", systemImage: "list.bullet.rectangle.portrait",
                                  help: "Start from a shot list that tells you what to film (how-to, review, top 3…)") { model.choosesStoryboard = true }
                        StartTile(title: "Template", systemImage: "square.grid.3x3.square",
                                  help: "Choose clips and get a Short cut on the beat, with text and transitions (montage, top 5, recipe…)") { model.choosesTemplate = true }
                    }
                    if model.shorts.isEmpty {
                        Text("Start an empty Short, let Magic Short make a first cut from your clips, or follow a storyboard. Your Shorts will appear here. Each one is saved as you edit it, so you can come back to it any time.")
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: 460, alignment: .leading)
                    }
                }
                ForEach(ShortsLibrary.grouped(shown, date: \.modified), id: \.0) { section, entries in
                    VStack(alignment: .leading, spacing: 12) {
                        Text(section.title())
                            .font(.title3.weight(.semibold))
                        LazyVGrid(columns: columns, alignment: .leading, spacing: 22) {
                            ForEach(entries) { entry in
                                ShortTile(model: model, entry: entry, renamingID: $renamingID)
                            }
                        }
                    }
                }
                if !search.isEmpty, shown.isEmpty {
                    Text("No Shorts are called “\(search)”.")
                        .foregroundStyle(.secondary)
                }
            }
            .padding(28)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(isDropTargeted ? Color.accentColor.opacity(0.08) : Color.clear)
        .background(Theme.panel)
        .searchable(text: $search, placement: .toolbar, prompt: "Search Shorts")
        .dropDestination(for: URL.self) { urls, _ in
            // Videos dropped here start a new Short with them; a project file is added.
            model.importFiles(urls, addToTimeline: true)
            return true
        } isTargeted: { isDropTargeted = $0 }
        .toolbar {
            ToolbarItem {
                Button("New Short", systemImage: "plus") { model.newShort() }
                    .help("Start a new Short (⌘N)")
            }
        }
        .navigationTitle("Shorts")
        .navigationSubtitle(subtitle)
    }

    private var subtitle: String {
        switch model.shorts.count {
        case 0: ""
        case 1: "1 Short"
        default: "\(model.shorts.count) Shorts"
        }
    }
}

/// The poster shape: a 9:16 card.
private struct Poster<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        content
            .frame(width: HomeView.tileWidth, height: HomeView.tileWidth * 16 / 9)
            .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

private struct NewShortTile: View {
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                Poster {
                    ZStack {
                        Color(white: isHovered ? 0.26 : 0.21)
                        VStack(spacing: 10) {
                            Image(systemName: "plus")
                                .font(.system(size: 38, weight: .light))
                            Text("New Short")
                                .font(.headline)
                        }
                        .foregroundStyle(.primary)
                    }
                }
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.secondary.opacity(0.5), style: StrokeStyle(lineWidth: 1.5, dash: [6, 4])))
                Text(" ").font(.callout)   // lines up with the names under the other tiles
            }
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help("Start a new Short (⌘N)")
        .accessibilityLabel("New Short")
    }
}

private struct ShortTile: View {
    @Bindable var model: EditorModel
    let entry: ShortEntry
    @Binding var renamingID: UUID?
    @State private var typedName = ""
    @State private var isHovered = false
    @FocusState private var nameFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isRenaming: Bool { renamingID == entry.id }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button { model.openShort(entry.id) } label: {
                Poster {
                    ZStack(alignment: .bottomTrailing) {
                        if let poster = model.posters[entry.id] {
                            Image(decorative: poster, scale: 1)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                        } else {
                            ZStack {
                                Color(white: 0.1)
                                Image(systemName: "film")
                                    .font(.system(size: 30))
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        Text(TimeFormat.string(entry.duration).dropLast(2))
                            .font(.caption.monospacedDigit().weight(.semibold))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(.black.opacity(0.7), in: RoundedRectangle(cornerRadius: 4))
                            .foregroundStyle(.white)
                            .padding(6)
                    }
                }
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.white.opacity(isHovered ? 0.8 : 0), lineWidth: 2))
                // With Reduce Motion the border alone shows the pointer is over it.
                .scaleEffect(isHovered && !reduceMotion ? 1.02 : 1)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: isHovered)
            }
            .buttonStyle(.plain)
            .onHover { isHovered = $0 }
            .help("Click to edit “\(entry.name)”")

            if isRenaming {
                TextField("Name", text: $typedName)
                    .textFieldStyle(.roundedBorder)
                    .focused($nameFocused)
                    .onSubmit { finishRenaming() }
                    .onExitCommand { renamingID = nil }
                    .onChange(of: nameFocused) { if !nameFocused, isRenaming { finishRenaming() } }
                    .onAppear {
                        typedName = entry.name
                        nameFocused = true
                    }
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text(entry.name)
                        .font(.callout.weight(.medium))
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .onTapGesture(count: 2) { renamingID = entry.id }
                        .help("Double-click to rename")
                    Spacer(minLength: 0)
                    Menu {
                        actions
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .menuStyle(.button)
                    .buttonStyle(.borderless)
                    .menuIndicator(.hidden)
                    .fixedSize()
                    .help("Rename, duplicate or delete")
                    .accessibilityLabel("More for \(entry.name)")
                }
            }
            Text(entry.modified.formatted(date: .abbreviated, time: .shortened))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(width: HomeView.tileWidth, alignment: .leading)
        .contextMenu { actions }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(entry.name)
    }

    @ViewBuilder
    private var actions: some View {
        Button("Edit") { model.openShort(entry.id) }
        Button("Rename") { renamingID = entry.id }
        Button("Duplicate") { model.duplicateShort(entry.id) }
        Divider()
        Button("Delete…", role: .destructive) { model.deleteShorts([entry.id]) }
    }

    private func finishRenaming() {
        renamingID = nil
        model.renameShort(entry.id, to: typedName)
    }
}
