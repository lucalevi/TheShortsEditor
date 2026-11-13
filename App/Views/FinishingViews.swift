import CoreMedia
import EditorCore
import Photos
import RenderEngine
import SwiftUI

// MARK: - Photos library

/// The Photos tab: videos and pictures from the user's Photos library, added without exporting
/// them first.
struct PhotosView: View {
    let model: EditorModel
    @State private var status = PhotosLibrary.status
    @AppStorage("photosKind") private var kind: PhotosLibrary.Kind = .videos
    @State private var items: [PHAsset] = []
    @State private var selection: Set<String> = []

    private var selectedAssets: [PHAsset] { items.filter { selection.contains($0.localIdentifier) } }

    var body: some View {
        if status == .authorized || status == .limited {
            library
        } else {
            access
        }
    }

    private var access: some View {
        ContentUnavailableView {
            Label("Your Photos Library", systemImage: "photo.on.rectangle.angled")
        } description: {
            Text(status == .denied || status == .restricted
                 ? "Shorts Editor isn't allowed to see your photos. Turn it on in System Settings ▸ Privacy & Security ▸ Photos."
                 : "Use videos and photos from your iPhone straight from Photos, without exporting them first. Items in iCloud are downloaded when you add them.")
        } actions: {
            if status == .denied || status == .restricted {
                Button("Open Privacy Settings") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Photos") { NSWorkspace.shared.open(url) }
                }
            } else {
                Button("Show My Photos") {
                    Task { status = await PhotosLibrary.requestAccess() }
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    private var library: some View {
        VStack(spacing: 0) {
            Picker("Show", selection: $kind) {
                ForEach(PhotosLibrary.Kind.allCases) { Text($0.displayName).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(8)

            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), spacing: 4)], spacing: 4) {
                    ForEach(items, id: \.localIdentifier) { asset in
                        PhotoTile(asset: asset, isSelected: selection.contains(asset.localIdentifier), progress: model.photoDownloads[asset.localIdentifier])
                            .onTapGesture(count: 2) { model.importFromPhotos([asset], to: .timelineEnd) }
                            .onTapGesture { select(asset) }
                            .contextMenu { menu(for: selection.contains(asset.localIdentifier) ? selectedAssets : [asset]) }
                    }
                }
                .padding(.horizontal, 8)
            }
            .overlay {
                if items.isEmpty {
                    ContentUnavailableView(kind == .photos ? "No Photos" : kind == .videos ? "No Videos" : "Nothing Here",
                                           systemImage: "photo.on.rectangle",
                                           description: Text(status == .limited ? "Only the items you allowed are shown." : "Your Photos library has none."))
                }
            }

            Divider()
            HStack {
                Button("Add to End") { model.importFromPhotos(selectedAssets, to: .timelineEnd) }
                    .help("Put the selected items at the end of your Short (double-click does the same)")
                Button("Over Clips") { model.importFromPhotos(selectedAssets, to: .overlay(at: model.currentTime)) }
                    .disabled(model.project.timeline.clips.isEmpty)
                    .help("Show the selected items over your clips from the playhead (B-roll)")
                Spacer()
                Button("To Media") { model.importFromPhotos(selectedAssets, to: .media) }
                    .help("Add to Media only, to use later")
            }
            .controlSize(.small)
            .disabled(selection.isEmpty)
            .padding(8)
        }
        .task(id: kind) {
            items = PhotosLibrary.items(kind)
            selection = selection.filter { id in items.contains { $0.localIdentifier == id } }
        }
    }

    /// Click picks one; ⌘-click adds or removes; ⇧-click picks everything from the last one.
    private func select(_ asset: PHAsset) {
        let id = asset.localIdentifier
        let flags = NSEvent.modifierFlags
        if flags.contains(.command) {
            if selection.contains(id) { selection.remove(id) } else { selection.insert(id) }
        } else if flags.contains(.shift), let anchor = items.firstIndex(where: { selection.contains($0.localIdentifier) }),
                  let index = items.firstIndex(where: { $0.localIdentifier == id }) {
            selection = Set(items[min(anchor, index)...max(anchor, index)].map(\.localIdentifier))
        } else {
            selection = [id]
        }
    }

    @ViewBuilder
    private func menu(for assets: [PHAsset]) -> some View {
        Button("Add to End") { model.importFromPhotos(assets, to: .timelineEnd) }
        Button("Add Over Clips at Playhead") { model.importFromPhotos(assets, to: .overlay(at: model.currentTime)) }
            .disabled(model.project.timeline.clips.isEmpty)
        Button("Add to Media") { model.importFromPhotos(assets, to: .media) }
    }
}

private struct PhotoTile: View {
    let asset: PHAsset
    let isSelected: Bool
    let progress: Double?
    @State private var image: NSImage?

    var body: some View {
        ZStack {
            Rectangle().fill(.quaternary)
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
            }
        }
        .frame(height: 92)
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .overlay(alignment: .bottomTrailing) {
            HStack(spacing: 3) {
                if asset.mediaSubtypes.contains(.videoHighFrameRate) { Image(systemName: "slowmo") }
                if let length = asset.lengthLabel { Text(length) }
            }
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 3))
            .padding(3)
        }
        .overlay {
            if let progress {
                ZStack {
                    Color.black.opacity(0.5)
                    VStack(spacing: 4) {
                        ProgressView(value: progress).progressViewStyle(.circular).controlSize(.small)
                        Text(progress > 0 ? "\(Int(progress * 100))%" : "Copying…").font(.caption2).foregroundStyle(.white)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 4))
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 4)
                .strokeBorder(isSelected ? Color.accentColor : .clear, lineWidth: 3)
        }
        .overlay(alignment: .topLeading) {
            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.white, Color.accentColor)
                    .padding(4)
            }
        }
        .contentShape(Rectangle())
        .task(id: asset.localIdentifier) { image = await PhotosLibrary.thumbnail(of: asset) }
        .help(asset.creationDate.map { $0.formatted(date: .abbreviated, time: .shortened) } ?? "")
    }
}

// MARK: - Clip trimmer

/// The whole file of a clip, with the part it shows bright (iMovie's clip trimmer). Drag the ends
/// to trim, or drag the bright part to show another stretch of the same video at the same length.
struct ClipTrimmerView: View {
    let model: EditorModel
    let clipID: Clip.ID

    private enum Drag: Equatable { case start, end, slide }
    @State private var drag: Drag?
    /// How far the drag has moved, in the file's time.
    @State private var dragDelta: Double = 0

    private let stripHeight: CGFloat = 54

    var body: some View {
        if let clip = model.project.anyClip(id: clipID), let media = model.project.asset(id: clip.assetID), media.duration > .zero {
            content(clip, media)
        }
    }

    private func content(_ clip: Clip, _ media: MediaAsset) -> some View {
        let fileSeconds = media.duration.seconds
        let (start, end) = shownRange(clip)
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Label("Clip Trimmer", systemImage: "film").font(.callout.weight(.semibold))
                Text(media.name).lineLimit(1).foregroundStyle(.secondary)
                Spacer()
                Text("Shows \(TimeFormat.string(CMTime(seconds: start, preferredTimescale: 600)))–\(TimeFormat.string(CMTime(seconds: end, preferredTimescale: 600))) of \(TimeFormat.string(media.duration)) · on the timeline \(TimeFormat.string(clip.timelineDuration(ofSource: CMTime(seconds: end - start, preferredTimescale: 600))))")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                Button("Done") { model.trimmerClipID = nil }
                    .keyboardShortcut(.cancelAction)
                    .controlSize(.small)
            }
            .font(.callout)

            GeometryReader { geometry in
                let width = geometry.size.width
                let x = { (seconds: Double) in CGFloat(seconds / fileSeconds) * width }
                ZStack(alignment: .topLeading) {
                    strip(media, width: width)
                    // Outside the clip: dimmed.
                    Rectangle().fill(.black.opacity(0.6)).frame(width: max(0, x(start)), height: stripHeight)
                    Rectangle().fill(.black.opacity(0.6)).frame(width: max(0, width - x(end)), height: stripHeight).offset(x: x(end))
                    // The clip: framed, dragged to slide.
                    RoundedRectangle(cornerRadius: 3)
                        .strokeBorder(Color.yellow, lineWidth: 3)
                        .contentShape(Rectangle())
                        .frame(width: max(8, x(end) - x(start)), height: stripHeight)
                        .offset(x: x(start))
                        .gesture(dragGesture(.slide, clip: clip, width: width, fileSeconds: fileSeconds))
                        .help("Drag to show another part of the video at the same length")
                    handle(.start).offset(x: x(start) - 4)
                        .gesture(dragGesture(.start, clip: clip, width: width, fileSeconds: fileSeconds))
                    handle(.end).offset(x: x(end) - 6)
                        .gesture(dragGesture(.end, clip: clip, width: width, fileSeconds: fileSeconds))
                }
            }
            .frame(height: stripHeight)
        }
        .padding(10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
        .shadow(radius: 8)
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
        .onAppear { model.showTip(.trimmer) }
    }

    /// The part of the file the clip shows, as it would be with the drag under way (seconds).
    private func shownRange(_ clip: Clip) -> (Double, Double) {
        let start = clip.sourceStart.seconds, end = clip.sourceRange.end.seconds
        switch drag {
        case .start: return (start + dragDelta, end)
        case .end: return (start, end + dragDelta)
        case .slide: return (start + dragDelta, end + dragDelta)
        case nil: return (start, end)
        }
    }

    private func handle(_ edge: ClipEdge) -> some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(Color.yellow)
            .frame(width: 10, height: stripHeight)
            .overlay(Capsule().fill(.black.opacity(0.6)).frame(width: 2, height: 18))
            .contentShape(Rectangle().inset(by: -4))
            .onHover { inside in if inside { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() } }
            .help(edge == .start ? "Drag to change where the clip starts" : "Drag to change where the clip ends")
    }

    private func dragGesture(_ kind: Drag, clip: Clip, width: CGFloat, fileSeconds: Double) -> some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                drag = kind
                let wanted = Double(value.translation.width / max(width, 1)) * fileSeconds
                dragDelta = limited(wanted, kind: kind, clip: clip)
                let (start, end) = shownRange(clip)
                // The viewer shows the frame at the dragged edge (the start while sliding).
                model.skimMedia(clip.assetID, at: CMTime(seconds: kind == .end ? end : start, preferredTimescale: 600))
            }
            .onEnded { _ in
                let delta = CMTime(seconds: dragDelta, preferredTimescale: 600)
                switch kind {
                case .start: model.trimInTrimmer(clip.id, edge: .start, bySource: delta)
                case .end: model.trimInTrimmer(clip.id, edge: .end, bySource: delta)
                case .slide: model.slipClip(clip.id, bySource: delta)
                }
                drag = nil
                dragDelta = 0
                model.skimMedia(clip.assetID, at: nil)
            }
    }

    /// The drag kept inside what the file and the edit allow (seconds of the file).
    private func limited(_ seconds: Double, kind: Drag, clip: Clip) -> Double {
        switch kind {
        case .slide:
            guard let limits = model.project.slipLimits(of: clip.id) else { return 0 }
            return min(max(seconds, limits.start.seconds), limits.end.seconds)
        case .start, .end:
            guard let limits = model.project.trimLimits(for: clip, edge: kind == .start ? .start : .end) else { return 0 }
            // Trim limits are in timeline time; the file moves `speed` times as fast.
            return min(max(seconds, limits.start.seconds * clip.speed), limits.end.seconds * clip.speed)
        }
    }

    /// Pictures along the whole file.
    private func strip(_ media: MediaAsset, width: CGFloat) -> some View {
        Canvas { context, size in
            guard let strip = model.filmstrips[media.id], let first = strip.images.first else { return }
            let tileWidth = size.height * CGFloat(first.width) / CGFloat(max(first.height, 1))
            var x: CGFloat = 0
            while x < size.width {
                let seconds = Double((x + tileWidth / 2) / size.width) * media.duration.seconds
                if let image = strip.image(at: CMTime(seconds: seconds, preferredTimescale: 600)) {
                    context.draw(Image(decorative: image, scale: 1), in: CGRect(x: x, y: 0, width: tileWidth, height: size.height))
                }
                x += tileWidth
            }
        }
        .frame(width: width, height: stripHeight)
        .background(Color.black)
        .clipShape(RoundedRectangle(cornerRadius: 3))
    }
}

// MARK: - Markers

/// Markers on the ruler: a flag with its name. Click to go there, drag to move, double-click to
/// rename; right-click for more.
struct TimelineMarkers: View {
    let model: EditorModel
    let leadingInset: CGFloat
    let pointsPerSecond: CGFloat
    let rulerHeight: CGFloat
    let height: CGFloat
    @State private var dragging: (id: Marker.ID, time: CMTime)?
    @State private var name = ""

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(model.project.markers.filter { $0.time <= model.duration }) { marker in
                let time = dragging?.id == marker.id ? dragging!.time : marker.time
                let x = leadingInset + CGFloat(time.seconds) * pointsPerSecond
                // A faint line down through the lanes.
                Rectangle()
                    .fill(Color.white.opacity(0.25))
                    .frame(width: 1, height: max(0, height - rulerHeight))
                    .offset(x: x, y: rulerHeight)
                    .allowsHitTesting(false)
                flag(marker)
                    .offset(x: x - 1, y: rulerHeight - 14)
            }
        }
    }

    private func flag(_ marker: Marker) -> some View {
        HStack(spacing: 2) {
            Image(systemName: "flag.fill").font(.system(size: 9))
            if pointsPerSecond >= 40 {
                Text(marker.name).font(.caption2).lineLimit(1).frame(maxWidth: 90, alignment: .leading)
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 3)
        .padding(.vertical, 1)
        .background(Color.purple.opacity(0.85), in: RoundedRectangle(cornerRadius: 3))
        .fixedSize()
        .help("\(marker.name) at \(TimeFormat.string(marker.time)). Double-click to rename, drag to move.")
        .onTapGesture(count: 2) {
            name = marker.name
            model.markerBeingRenamed = marker.id
        }
        .onTapGesture {
            model.pause()
            model.seek(to: marker.time)
        }
        .gesture(DragGesture(minimumDistance: 3).onChanged { value in
            let moved = marker.time + CMTime(seconds: Double(value.translation.width / pointsPerSecond), preferredTimescale: 600)
            dragging = (marker.id, model.markerDropTime(moved.clamped(.zero, model.duration), for: marker.id))
        }.onEnded { _ in
            if let dragging { model.moveMarker(dragging.id, to: dragging.time) }
            dragging = nil
        })
        .contextMenu {
            Button("Rename…") {
                name = marker.name
                model.markerBeingRenamed = marker.id
            }
            Button("Go to Marker") { model.seek(to: marker.time) }
            Divider()
            Button("Delete Marker", role: .destructive) { model.deleteMarker(marker.id) }
        }
        .popover(isPresented: Binding(get: { model.markerBeingRenamed == marker.id },
                                      set: { if !$0 { model.markerBeingRenamed = nil } })) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Marker at \(TimeFormat.string(marker.time))").font(.headline)
                TextField("Name", text: $name)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 200)
                    .onSubmit { save(marker) }
                HStack {
                    Button("Delete", role: .destructive) {
                        model.markerBeingRenamed = nil
                        model.deleteMarker(marker.id)
                    }
                    Spacer()
                    Button("Done") { save(marker) }.keyboardShortcut(.defaultAction)
                }
            }
            .padding(12)
        }
    }

    private func save(_ marker: Marker) {
        model.markerBeingRenamed = nil
        if name != marker.name { model.renameMarker(marker.id, to: name) }
    }
}

// MARK: - Settings

/// Shorts Editor ▸ Settings (⌘,): how new clips start, like iMovie's settings.
struct SettingsView: View {
    let model: EditorModel
    @AppStorage(SettingsKey.pictureSeconds) private var pictureSeconds = MediaAsset.imageClipDuration.seconds
    @AppStorage(SettingsKey.picturePlacement) private var placement: NewClipSettings.PicturePlacement = .automatic
    @AppStorage(SettingsKey.slowMotionAutomatically) private var slowMotion = true
    @AppStorage(SettingsKey.transitionFrames) private var transitionFrames = Int(ClipTransition.defaultDuration.value)

    var body: some View {
        Form {
            Section {
                LabeledContent("Picture length") {
                    HStack {
                        Slider(value: $pictureSeconds, in: NewClipSettings.pictureLengthRange, step: 0.5)
                            .frame(width: 180)
                        Text("\(pictureSeconds.formatted(.number.precision(.fractionLength(1)))) s")
                            .monospacedDigit()
                            .frame(width: 44, alignment: .trailing)
                    }
                }
                Picker("Picture placement", selection: $placement) {
                    ForEach(NewClipSettings.PicturePlacement.allCases) { Text($0.displayName).tag($0) }
                }
                Text(placementHelp).font(.caption).foregroundStyle(.secondary)
            } header: {
                Text("New pictures")
            }

            Section {
                LabeledContent("Transition length") {
                    HStack {
                        Slider(value: Binding(get: { Double(transitionFrames) / Double(Project.frameRate) },
                                              set: { transitionFrames = Int(ClipTransition.allowed(CMTime(seconds: $0, preferredTimescale: 600)).value) }),
                               in: ClipTransition.minimumDuration.seconds...ClipTransition.maximumDuration.seconds)
                            .frame(width: 180)
                        Text("\((Double(transitionFrames) / Double(Project.frameRate)).formatted(.number.precision(.fractionLength(1)))) s")
                            .monospacedDigit()
                            .frame(width: 44, alignment: .trailing)
                    }
                }
                Text("For transitions you add from now on. Ones already in your Shorts keep their length.")
                    .font(.caption).foregroundStyle(.secondary)
            } header: {
                Text("Transitions")
            }

            Section {
                Toggle("Slow down slow-motion footage automatically", isOn: $slowMotion)
                Text("Videos filmed at 100 pictures a second or more (an iPhone's Slo-mo) start slowed down, as smoothly as they allow.")
                    .font(.caption).foregroundStyle(.secondary)
            } header: {
                Text("New videos")
            }

            StorageSettings(model: model)
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var placementHelp: String {
        switch placement {
        case .automatic: "Upright pictures fill the screen; wide ones are shown whole."
        case .fill: "Pictures fill the screen; the edges that don't fit are cut off."
        case .fit: "Pictures are shown whole, with a blurred copy around them."
        case .slowZoom: "Pictures fill the screen and slowly zoom in."
        }
    }
}
