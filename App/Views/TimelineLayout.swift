import AVFoundation
import EditorCore
import SwiftUI

/// Where each lane of the timeline sits, and how time maps to points across it.
extension TimelineView {
    var rulerHeight: CGFloat { 24 }
    var captionLaneHeight: CGFloat { 22 }
    var titleRowHeight: CGFloat { 22 }
    var overlayRowHeight: CGFloat { 40 }
    var musicLaneHeight: CGFloat { 44 }
    var soundRowHeight: CGFloat { 34 }
    var rowGap: CGFloat { 3 }
    var leadingInset: CGFloat { 12 }

    var titleRows: [TextOverlay.ID: Int] {
        LanePacking.rows(model.project.titles.map { (id: $0.id, range: $0.range) })
    }
    var overlayRows: [Clip.ID: Int] {
        LanePacking.rows(model.project.overlays.map { (id: $0.id, range: $0.range) })
    }
    var soundRows: [Clip.ID: Int] {
        LanePacking.rows(model.project.sounds.map { (id: $0.id, range: $0.range) })
    }
    var titleRowCount: Int { LanePacking.count(titleRows) }
    var overlayRowCount: Int { LanePacking.count(overlayRows) }

    var titlesY: CGFloat { rulerHeight + 6 }
    var titlesHeight: CGFloat { CGFloat(titleRowCount) * (titleRowHeight + 2) }
    var overlaysY: CGFloat { titlesY + titlesHeight + rowGap }
    var overlaysHeight: CGFloat { model.project.overlays.isEmpty ? emptyLaneHeight : CGFloat(overlayRowCount) * (overlayRowHeight + rowGap) }
    var clipsY: CGFloat { overlaysY + overlaysHeight + 2 }
    var captionsY: CGFloat { clipsY + trackHeight + 6 }
    /// The captions lane takes no room until there are captions.
    var captionsHeight: CGFloat { model.captioning.pages.isEmpty ? 0 : captionLaneHeight + 4 }
    var soundsY: CGFloat { captionsY + captionsHeight }
    var soundsHeight: CGFloat { model.project.sounds.isEmpty ? emptyLaneHeight : CGFloat(LanePacking.count(soundRows)) * (soundRowHeight + 2) }
    var musicY: CGFloat { soundsY + soundsHeight + 2 }
    /// The music lane is only as tall as its Add Music button until there is a song.
    var musicHeight: CGFloat { model.project.musicRange == nil ? emptyLaneHeight + 6 : musicLaneHeight }
    var contentHeight: CGFloat { musicY + musicHeight + 12 }

    var pointsPerSecond: CGFloat { model.timelineZoom }

    func x(for time: CMTime) -> CGFloat {
        leadingInset + CGFloat(time.seconds) * pointsPerSecond
    }

    func width(of duration: CMTime) -> CGFloat {
        CGFloat(duration.seconds) * pointsPerSecond
    }

    func time(at x: CGFloat) -> CMTime {
        CMTime(seconds: max(0, Double((x - leadingInset) / pointsPerSecond)), preferredTimescale: 600)
    }

    func seconds(_ points: CGFloat) -> CMTime {
        CMTime(seconds: Double(points / pointsPerSecond), preferredTimescale: 600)
    }
}
