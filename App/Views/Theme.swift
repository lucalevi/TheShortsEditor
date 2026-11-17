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

/// The border of a timeline item. Selection must show without colour (F25; the owner works with a
/// black-and-white screen filter): the selected border is much thicker, more so with Differentiate
/// Without Color, and Increase Contrast makes the other borders solid.
struct TimelineBorder: ViewModifier {
    let isSelected: Bool
    let color: Color
    let opacity: Double
    let cornerRadius: CGFloat
    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiate
    @Environment(\.colorSchemeContrast) private var contrast

    func body(content: Content) -> some View {
        content.overlay {
            RoundedRectangle(cornerRadius: cornerRadius)
                .strokeBorder(
                    isSelected ? Color.yellow : color.opacity(contrast == .increased ? 1 : opacity),
                    lineWidth: isSelected ? (differentiate ? 4 : 3) : (contrast == .increased ? 1.5 : 1))
        }
    }
}

extension View {
    func timelineBorder(isSelected: Bool, color: Color, opacity: Double, cornerRadius: CGFloat) -> some View {
        modifier(TimelineBorder(isSelected: isSelected, color: color, opacity: opacity, cornerRadius: cornerRadius))
    }
}
