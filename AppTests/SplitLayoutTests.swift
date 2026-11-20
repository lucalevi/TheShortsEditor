import CoreGraphics
import Testing

@testable import Shorts_Editor

/// How the editor shares the window's height between the viewer and the timeline (`EditorSplit`).
struct SplitLayoutTests {
    /// A 13" MacBook Air's window, below the toolbar.
    let laptop: CGFloat = 718

    @Test func theTimelineFitsItsLanesAndTheViewerGetsTheRest() {
        // Before: a split view gave the timeline ~360 pt of a 13" window whatever was on it.
        #expect(SplitLayout.timelineHeight(total: laptop, fitting: 250, chosen: nil) == 250)
        #expect(SplitLayout.timelineHeight(total: 1200, fitting: 250, chosen: nil) == 250)
    }

    @Test func manyLanesTakeAtMostHalfTheWindowAndScroll() {
        #expect(SplitLayout.timelineHeight(total: laptop, fitting: 600, chosen: nil) == laptop / 2)
    }

    @Test func aDraggedHeightIsKeptWithinBothMinimums() {
        #expect(SplitLayout.timelineHeight(total: laptop, fitting: 250, chosen: 400) == 400)
        // The viewer keeps its minimum…
        #expect(SplitLayout.timelineHeight(total: laptop, fitting: 250, chosen: 700) == laptop - SplitLayout.topMinimum - SplitLayout.dividerHeight)
        // …and so does the timeline, also when its lanes need less.
        #expect(SplitLayout.timelineHeight(total: laptop, fitting: 250, chosen: 20) == SplitLayout.timelineMinimum)
        #expect(SplitLayout.timelineHeight(total: laptop, fitting: 90, chosen: nil) == SplitLayout.timelineMinimum)
    }

    @Test func theSmallestWindowStillShowsBoth() {
        // The window's minimum is 680 tall, about 628 below the toolbar.
        let height = SplitLayout.timelineHeight(total: 628, fitting: 600, chosen: nil)
        #expect(height >= SplitLayout.timelineMinimum)
        #expect(628 - height - SplitLayout.dividerHeight >= SplitLayout.topMinimum)
    }
}
