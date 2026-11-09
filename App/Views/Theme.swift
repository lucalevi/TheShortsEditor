import SwiftUI

/// The editor's greys, in the spirit of Final Cut Pro, iMovie and CapCut: the video stands out
/// against a near-black viewer, the panels around it are mid-dark grey, and the timeline sits a
/// step darker than the panels. The whole app runs in Dark Mode (see `AppDelegate`), so system
/// controls, sheets, menus and Open/Save panels match.
enum Theme {
    /// Media, captions and the inspector.
    static let panel = Color(white: 0.165)
    /// The strip at the top of each panel and under the viewer.
    static let header = Color(white: 0.205)
    /// Behind the video in the viewer.
    static let viewer = Color(white: 0.085)
    /// Behind the clips on the timeline.
    static let timeline = Color(white: 0.12)
}
