import AVFoundation
import AppKit
import EditorCore
import SwiftUI

/// Selecting on the timeline by drawing a rectangle across it.
extension TimelineView {
    /// The empty space behind everything: click to deselect, drag to select with a rectangle
    /// (holding ⌘ or ⇧ adds to what is already selected).
    var marqueeArea: some View {
        Color.clear
            .contentShape(Rectangle())
            .gesture(emptySpaceGesture)
    }

    /// Click: deselect and move the playhead. Drag: select with a rectangle.
    var emptySpaceGesture: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named(Self.contentSpace))
            .onChanged { value in
                if rangeAnchor != nil || (marquee == nil && model.isRangeKeyDown && abs(value.translation.width) > 3) {
                    if rangeAnchor == nil {
                        model.playback.pause()
                        rangeAnchor = time(at: value.startLocation.x)
                    }
                    model.setTimelineRange(from: rangeAnchor!, to: time(at: value.location.x))
                    return
                }
                let rect = CGRect(
                    x: min(value.startLocation.x, value.location.x),
                    y: min(value.startLocation.y, value.location.y),
                    width: abs(value.location.x - value.startLocation.x),
                    height: abs(value.location.y - value.startLocation.y))
                guard rect.width > 3 || rect.height > 3 || marquee != nil else { return }
                if marqueeBase == nil { marqueeBase = model.timelineSelection }
                marquee = rect
                var selection = marqueeBase ?? TimelineSelection()
                let adding = !NSEvent.modifierFlags.isDisjoint(with: [.command, .shift])
                selection.select(items(in: rect), adding: adding)
                model.timelineSelection = selection
            }
            .onEnded { value in
                if rangeAnchor != nil {
                    rangeAnchor = nil
                    return
                }
                if marquee == nil, NSEvent.modifierFlags.isDisjoint(with: [.command, .shift]) {
                    model.selection = nil // a plain click on empty space
                    model.selectedAssetID = nil
                    model.timelineRange = nil
                    model.playback.pause() // ...also moves the playhead there
                    model.playback.seek(to: time(at: value.location.x))
                }
                marquee = nil
                marqueeBase = nil
            }
    }

    @ViewBuilder
    var marqueeRectangle: some View {
        if let marquee {
            Rectangle()
                .fill(Color.accentColor.opacity(0.15))
                .overlay(Rectangle().strokeBorder(Color.accentColor.opacity(0.9), lineWidth: 1))
                .frame(width: marquee.width, height: marquee.height)
                .offset(x: marquee.minX, y: marquee.minY)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }

    /// The clips, overlays, titles and music a rectangle on the timeline touches.
    func items(in rect: CGRect) -> Set<EditorModel.Selection> {
        let lanes: [(TimelineLane, CGFloat, CGFloat)] = [
            (.titles, titlesY, titlesHeight),
            (.overlays, overlaysY, overlaysHeight),
            (.clips, clipsY, trackHeight),
            (.sounds, soundsY, soundsHeight),
            (.music, musicY, musicHeight),
        ]
        let covered = Set(lanes.filter { _, y, height in rect.minY < y + height && rect.maxY > y }.map(\.0))
        guard !covered.isEmpty else { return [] }
        let range = CMTimeRange(start: time(at: rect.minX), end: time(at: rect.maxX))
        return model.project.timelineItems(overlapping: range, in: covered)
    }
}
