import AVFoundation
import EditorCore
import SwiftUI

/// The storyline: clips back to back, a ruler for scrubbing, and the playhead.
struct TimelineView: View {
    @Bindable var model: EditorModel
    @State private var scrollPosition = ScrollPosition(edge: .leading)
    @State private var visibleX: ClosedRange<CGFloat> = 0...0
    @State private var isDropTargeted = false

    private let rulerHeight: CGFloat = 24
    private let trackHeight: CGFloat = 72
    private let captionLaneHeight: CGFloat = 22
    private let leadingInset: CGFloat = 12

    private var pointsPerSecond: CGFloat { model.timelineZoom }

    private func x(for time: CMTime) -> CGFloat {
        leadingInset + CGFloat(time.seconds) * pointsPerSecond
    }

    private func time(at x: CGFloat) -> CMTime {
        CMTime(seconds: max(0, Double((x - leadingInset) / pointsPerSecond)), preferredTimescale: 600)
    }

    var body: some View {
        VStack(spacing: 0) {
            PanelHeader(title: "Timeline") {
                HStack(spacing: 8) {
                    Text("\(TimeFormat.string(model.duration)) of 3:00")
                        .monospacedDigit()
                        .foregroundStyle(model.project.isOverMaxDuration ? .red : .secondary)
                    Divider().frame(height: 14)
                    Image(systemName: "minus.magnifyingglass").foregroundStyle(.secondary)
                    Slider(value: $model.timelineZoom, in: EditorModel.zoomRange)
                        .frame(width: 110)
                        .controlSize(.small)
                        .help("Zoom the timeline (⌘+ / ⌘−)")
                    Image(systemName: "plus.magnifyingglass").foregroundStyle(.secondary)
                }
                .font(.callout)
            }
            GeometryReader { geometry in
                ScrollView(.horizontal) {
                    ZStack(alignment: .topLeading) {
                        ruler
                        clipsRow.offset(y: rulerHeight + 8)
                        captionLane.offset(y: rulerHeight + 8 + trackHeight + 6)
                        pauseCuts.offset(y: rulerHeight + 8)
                        limitMarker
                        playhead
                    }
                    .frame(width: max(geometry.size.width, contentWidth), height: geometry.size.height, alignment: .topLeading)
                }
                .scrollPosition($scrollPosition)
                .onScrollGeometryChange(for: ClosedRange<CGFloat>.self) { scroll in
                    scroll.visibleRect.minX...scroll.visibleRect.maxX
                } action: { _, newValue in
                    visibleX = newValue
                }
            }
            .background(isDropTargeted ? Color.accentColor.opacity(0.08) : Color.clear)
            .dropDestination(for: URL.self) { urls, _ in
                model.importFiles(urls, addToTimeline: true)
                return true
            } isTargeted: { isDropTargeted = $0 }
        }
        .onChange(of: model.currentTime) {
            // Keep the playhead in view while playing.
            let playheadX = x(for: model.currentTime)
            if model.isPlaying, !visibleX.contains(playheadX) {
                scrollPosition.scrollTo(x: max(0, playheadX - 40))
            }
        }
    }

    private var contentWidth: CGFloat {
        x(for: model.duration) + 10 * pointsPerSecond
    }

    /// Seconds along the top. Click or drag here to move the playhead.
    private var ruler: some View {
        Canvas { context, size in
            let step = rulerStep
            var second = 0.0
            while leadingInset + CGFloat(second) * pointsPerSecond < size.width {
                let x = leadingInset + CGFloat(second) * pointsPerSecond
                context.fill(Path(CGRect(x: x, y: size.height - 8, width: 1, height: 8)), with: .color(.secondary))
                let label = TimeFormat.string(CMTime(seconds: second, preferredTimescale: 600)).dropLast(2)
                context.draw(Text(label).font(.caption2).foregroundStyle(.secondary), at: CGPoint(x: x + 3, y: 7), anchor: .leading)
                second += step
            }
        }
        .frame(height: rulerHeight)
        .contentShape(Rectangle())
        .gesture(DragGesture(minimumDistance: 0).onChanged { value in
            model.pause()
            model.seek(to: time(at: value.location.x))
        })
        .help("Click or drag to move the playhead")
    }

    /// A label every 1, 2, 5, 10… seconds, whichever keeps them about 60 points apart.
    private var rulerStep: Double {
        [1.0, 2, 5, 10, 15, 30, 60].first { $0 * pointsPerSecond >= 60 } ?? 60
    }

    @ViewBuilder
    private var clipsRow: some View {
        if model.project.timeline.clips.isEmpty {
            Text("Drop videos here, or double-click one in Media")
                .foregroundStyle(.secondary)
                .frame(height: trackHeight)
                .padding(.leading, leadingInset)
        } else {
            HStack(spacing: 0) {
                ForEach(Array(model.project.timeline.clips.enumerated()), id: \.element.id) { index, clip in
                    ClipBlock(
                        clip: clip,
                        name: model.project.asset(id: clip.assetID)?.name ?? "Missing",
                        thumbnail: model.thumbnails[clip.assetID],
                        isSelected: clip.id == model.selectedClipID
                    )
                    .frame(width: max(CGFloat(clip.duration.seconds) * pointsPerSecond, 2), height: trackHeight)
                    .onTapGesture { location in
                        model.selectedClipID = clip.id
                        let start = model.project.timeline.startTime(ofClipAt: index)
                        model.pause()
                        model.seek(to: start + CMTime(seconds: Double(location.x / pointsPerSecond), preferredTimescale: 600))
                    }
                    .contextMenu {
                        Button("Split at Playhead") { model.splitAtPlayhead() }
                        Picker("Framing", selection: Binding(get: { clip.framing }, set: { model.setFraming($0, for: clip.id) })) {
                            Text("Fill Screen").tag(Framing.fill)
                            Text("Show All").tag(Framing.fit)
                        }
                        if index > 0 {
                            Button("Move Earlier") { model.moveClip(clip.id, to: index - 1) }
                        }
                        if index < model.project.timeline.clips.count - 1 {
                            Button("Move Later") { model.moveClip(clip.id, to: index + 1) }
                        }
                        Divider()
                        Button("Delete Clip", role: .destructive) {
                            model.selectedClipID = clip.id
                            model.deleteSelectedClip()
                        }
                    }
                }
            }
            .padding(.leading, leadingInset)
        }
    }

    /// The captions, under the clips they belong to. Click one to go there and fix its words.
    private var captionLane: some View {
        ZStack(alignment: .topLeading) {
            ForEach(model.captionPages) { page in
                let isCurrent = model.currentCaption?.id == page.id
                Text(page.text)
                    .font(.caption2.weight(.medium))
                    .lineLimit(1)
                    .padding(.horizontal, 4)
                    .frame(width: max(CGFloat(page.range.duration.seconds) * pointsPerSecond - 2, 3), height: captionLaneHeight, alignment: .leading)
                    .background(
                        Color.orange.opacity(isCurrent ? 0.55 : 0.3),
                        in: RoundedRectangle(cornerRadius: 4)
                    )
                    .clipped()
                    .offset(x: x(for: page.range.start) + 1)
                    .onTapGesture {
                        model.pause()
                        model.seek(to: page.firstFrame)
                        model.sidebar = .captions
                        model.focusedCaptionID = page.id
                    }
                    .help(page.text)
            }
        }
        .opacity(model.project.captions.isVisible ? 1 : 0.4)
    }

    /// While choosing pauses to remove: the parts that would be cut, over the clips.
    @ViewBuilder
    private var pauseCuts: some View {
        if let cuts = model.silenceSession?.plan.timelineCuts {
            ZStack(alignment: .topLeading) {
                ForEach(Array(cuts.enumerated()), id: \.offset) { _, cut in
                    Rectangle()
                        .fill(Color.red.opacity(0.45))
                        .overlay(Rectangle().strokeBorder(Color.red, lineWidth: 1))
                        .frame(width: max(CGFloat(cut.duration.seconds) * pointsPerSecond, 1), height: trackHeight)
                        .offset(x: x(for: cut.start))
                }
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }

    /// A red line at 3:00, the longest a Short can be.
    @ViewBuilder
    private var limitMarker: some View {
        let limitX = x(for: Project.maxDuration)
        if limitX < contentWidth {
            Rectangle()
                .fill(Color.red.opacity(0.7))
                .frame(width: 2)
                .offset(x: limitX)
                .help("3:00 — the maximum length of a Short")
        }
    }

    private var playhead: some View {
        VStack(spacing: 0) {
            Image(systemName: "arrowtriangle.down.fill")
                .font(.system(size: 10))
                .foregroundStyle(.red)
            Rectangle().fill(.red).frame(width: 2)
        }
        .offset(x: x(for: model.currentTime) - 5, y: rulerHeight - 10)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct ClipBlock: View {
    let clip: Clip
    let name: String
    let thumbnail: CGImage?
    let isSelected: Bool

    var body: some View {
        RoundedRectangle(cornerRadius: 6)
            .fill(Color.accentColor.opacity(0.25))
            .overlay(alignment: .leading) {
                Thumbnail(image: thumbnail)
                    .frame(width: 40)
                    .clipped()
                    .opacity(0.9)
            }
            .overlay(alignment: .topLeading) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(name).font(.caption.weight(.medium)).lineLimit(1)
                    Text(TimeFormat.string(clip.duration)).font(.caption2).foregroundStyle(.secondary)
                }
                .padding(.leading, 46)
                .padding(.top, 6)
                .padding(.trailing, 4)
            }
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay {
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(isSelected ? Color.yellow : Color.accentColor.opacity(0.6), lineWidth: isSelected ? 2 : 1)
            }
            .padding(.horizontal, 1)
            .contentShape(Rectangle())
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
