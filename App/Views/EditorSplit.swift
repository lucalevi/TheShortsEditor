import SwiftUI

/// The editor's two halves: the media, viewer and details on top, the timeline below.
///
/// Unlike a plain split view, which hands the timeline half of any extra height, the timeline is
/// only as tall as its lanes need (up to half the window), so the viewer and the details get the
/// rest: on a 13" screen that is most of the difference between a usable viewer and a small one.
/// Dragging the divider sets the timeline's height (kept across launches); double-clicking it
/// goes back to fitting the lanes.
struct EditorSplit<Top: View, Bottom: View>: View {
    @ViewBuilder var top: Top
    /// The timeline, given where to report the height its lanes need.
    @ViewBuilder var bottom: (Binding<CGFloat>) -> Bottom

    /// The height the person dragged the timeline to, or 0 to fit its lanes.
    @AppStorage(SettingsKey.timelineHeight, store: AppEnvironment.defaults) private var chosenHeight: Double = 0
    /// What the timeline's lanes need, as the timeline reports it (`TimelineView.fittingHeight`).
    @State private var fittingHeight: CGFloat = 280
    /// The timeline's height when a drag of the divider began.
    @State private var dragStart: CGFloat?

    var body: some View {
        GeometryReader { geometry in
            let height = SplitLayout.timelineHeight(
                total: geometry.size.height, fitting: fittingHeight, chosen: chosenHeight > 0 ? chosenHeight : nil)
            VStack(spacing: 0) {
                top.frame(height: max(geometry.size.height - height - SplitLayout.dividerHeight, 0))
                divider(timelineHeight: height, total: geometry.size.height)
                bottom($fittingHeight).frame(height: height)
            }
        }
    }

    private func divider(timelineHeight: CGFloat, total: CGFloat) -> some View {
        // A thin line that is easy to grab: 9 points tall to the pointer, 1 point in the layout.
        Rectangle()
            .fill(.separator)
            .frame(height: SplitLayout.dividerHeight)
            .frame(maxWidth: .infinity, maxHeight: 9)
            .contentShape(Rectangle())
            .padding(.vertical, -4)
            .zIndex(1)
            .pointerStyle(.rowResize)
            .gesture(
                DragGesture(minimumDistance: 1, coordinateSpace: .global)
                    .onChanged { value in
                        let start = dragStart ?? timelineHeight
                        dragStart = start
                        chosenHeight = Double(SplitLayout.clamped(start - value.translation.height, total: total))
                    }
                    .onEnded { _ in dragStart = nil }
            )
            .onTapGesture(count: 2) { chosenHeight = 0 }
            .help("Drag to make the timeline taller or shorter. Double-click to fit it to what is on it.")
            .accessibilityElement()
            .accessibilityLabel("Timeline height")
            .accessibilityValue(chosenHeight > 0 ? "Chosen" : "Fits its lanes")
            .accessibilityAction(named: "Fit the timeline to its lanes") { chosenHeight = 0 }
            .accessibilityAdjustableAction { direction in
                let step: CGFloat = direction == .increment ? 40 : -40
                chosenHeight = Double(SplitLayout.clamped(timelineHeight + step, total: total))
            }
            .accessibilityIdentifier("timelineDivider")
    }
}

/// How `EditorSplit` shares the window's height between the top half and the timeline.
enum SplitLayout {
    static var dividerHeight: CGFloat { 1 }
    /// The viewer and details never get less than this.
    static var topMinimum: CGFloat { 280 }
    /// The timeline never gets less than this: the header, the ruler and the clips.
    static var timelineMinimum: CGFloat { 170 }

    /// How tall the timeline is in a window `total` points tall: the height the person chose, or
    /// what its lanes need up to half the window, kept between both minimums.
    static func timelineHeight(total: CGFloat, fitting: CGFloat, chosen: CGFloat?) -> CGFloat {
        clamped(chosen ?? min(fitting, total / 2), total: total)
    }

    static func clamped(_ height: CGFloat, total: CGFloat) -> CGFloat {
        let maximum = max(total - topMinimum - dividerHeight, timelineMinimum)
        return min(max(height, timelineMinimum), maximum)
    }
}
