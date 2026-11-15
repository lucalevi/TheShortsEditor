import CoreGraphics
import CoreMedia
import Foundation
import Testing

@testable import EditorCore

private func seconds(_ s: Double) -> CMTime { CMTime(seconds: s, preferredTimescale: 600).snappedToFrame() }

private func video(_ name: String = "talk.mov", seconds: Int64 = 10, size: CGSize = CGSize(width: 1080, height: 1920), audio: Bool = true) -> MediaAsset {
    MediaAsset(url: URL(fileURLWithPath: "/tmp/\(name)"), name: name, duration: CMTime(value: seconds, timescale: 1), displaySize: size, hasAudio: audio)
}

private func sound(_ name: String = "pop.m4a", seconds: Double = 1) -> MediaAsset {
    MediaAsset(
        url: URL(fileURLWithPath: "/tmp/\(name)"), name: name, duration: CMTime(seconds: seconds, preferredTimescale: 600), displaySize: .zero, hasAudio: true,
        hasVideo: false)
}

/// One 10 s video with a transcript: a word every second ("w0" … "w9"), each half a second long.
private func talking(words: [String]? = nil) -> (Project, MediaAsset.ID) {
    var p = Project()
    let id = p.addAsset(video())
    p.appendClip(of: id)
    let texts = words ?? (0..<10).map { "w\($0)" }
    p.transcripts[id] = Transcript(
        language: .english,
        words: texts.enumerated().map { index, text in
            Word(text: text, start: seconds(Double(index)), duration: seconds(0.5))
        })
    return (p, id)
}

struct LayoutTests {
    @Test func aSplitLayoutSharesTheScreen() throws {
        var (p, _) = talking()
        let added = p.addOverlay(of: p.addAsset(video("broll.mov")), at: seconds(1))
        let id = try #require(added)
        p.updateOverlay(id) { $0.layout = .top }
        let regions = p.regions(at: seconds(2))
        #expect(regions.overlays[id] == CGRect(x: 0, y: 0, width: 1080, height: 960))
        #expect(regions.main == CGRect(x: 0, y: 960, width: 1080, height: 960))
        // Before the B-roll starts, the main clip has the whole screen.
        #expect(p.regions(at: seconds(0.5)).main.height == 1920)
    }

    @Test func sideBySideAndThirds() throws {
        var (p, _) = talking()
        let broll = p.addAsset(video("broll.mov"))
        let added = p.addOverlay(of: broll, at: seconds(1))
        let id = try #require(added)
        p.updateOverlay(id) { $0.layout = .left }
        var regions = p.regions(at: seconds(2))
        #expect(regions.overlays[id] == CGRect(x: 0, y: 0, width: 540, height: 1920))
        #expect(regions.main == CGRect(x: 540, y: 0, width: 540, height: 1920))
        p.updateOverlay(id) { $0.layout = .bottomThird }
        regions = p.regions(at: seconds(2))
        #expect(regions.overlays[id] == CGRect(x: 0, y: 1280, width: 1080, height: 640))
        #expect(regions.main == CGRect(x: 0, y: 0, width: 1080, height: 1280))
    }

    @Test func twoSplitClipsShareTheScreenInThree() throws {
        var (p, _) = talking()
        let broll = p.addAsset(video("broll.mov"))
        let one = p.addOverlay(of: broll, at: seconds(1)), two = p.addOverlay(of: broll, at: seconds(1))
        let first = try #require(one), second = try #require(two)
        p.updateOverlay(first) { $0.layout = .topThird }
        p.updateOverlay(second) { $0.layout = .bottomThird }
        var regions = p.regions(at: seconds(2))
        #expect(regions.overlays[first] == CGRect(x: 0, y: 0, width: 1080, height: 640))
        #expect(regions.overlays[second] == CGRect(x: 0, y: 1280, width: 1080, height: 640))
        #expect(regions.main == CGRect(x: 0, y: 640, width: 1080, height: 640))
        // A side strip sits between the top and bottom ones.
        p.updateOverlay(second) { $0.layout = .right }
        regions = p.regions(at: seconds(2))
        #expect(regions.overlays[second] == CGRect(x: 540, y: 640, width: 540, height: 1280))
        #expect(regions.main == CGRect(x: 0, y: 640, width: 540, height: 1280))
        // Two halves on top of each other would leave nothing: the topmost wins, the other covers all.
        p.updateOverlay(first) { $0.layout = .top }
        p.updateOverlay(second) { $0.layout = .bottom }
        regions = p.regions(at: seconds(2))
        #expect(regions.overlays[second] == CGRect(x: 0, y: 960, width: 1080, height: 960))
        #expect(regions.overlays[first] == nil)
        #expect(regions.main == CGRect(x: 0, y: 0, width: 1080, height: 960))
        // The same edge twice: the topmost.
        p.updateOverlay(first) { $0.layout = .bottomThird }
        #expect(p.regions(at: seconds(2)).overlays[first] == nil)
        // Old files without the new layouts still read.
        let back = try JSONDecoder().decode(Project.self, from: JSONEncoder().encode(p))
        #expect(back.overlays.map(\.layout) == [.bottomThird, .bottom])
    }

    @Test func pictureInPictureCornersStayClearOfYouTubesButtons() {
        for corner in PictureCorner.allCases {
            for size in [CGSize(width: 1080, height: 1920), CGSize(width: 1920, height: 1080)] {
                let placement = Placement.pictureInPicture(corner, displaySize: size, framing: .fill)
                let frame = Framing.fill.placedFrame(of: size, placement: placement)
                let rect = CGRect(
                    x: frame.center.x - frame.size.width / 2, y: frame.center.y - frame.size.height / 2,
                    width: frame.size.width, height: frame.size.height)
                #expect(!SafeZone.covers(rect), "\(corner) \(size)")
                #expect(CGRect(origin: .zero, size: Project.canvasSize).contains(rect))
            }
        }
    }

    @Test func aPictureInARegionIsPlacedInsideIt() {
        let region = CGRect(x: 0, y: 960, width: 1080, height: 960)
        let frame = Framing.fill.placedFrame(of: CGSize(width: 1920, height: 1080), placement: .identity, region: region)
        #expect(frame.center == CGPoint(x: 540, y: 1440))
        #expect(frame.covers(region))
    }

    @Test func reframingFollowsTheSubjectAcross() {
        let clip = Clip(assetID: UUID(), sourceStart: .zero, duration: seconds(4))
        let horizontal = CGSize(width: 1920, height: 1080)
        // The subject walks from the left third to the right third.
        let samples = stride(from: 0.0, through: 4, by: 0.25).map { Reframe.Sample(time: seconds($0), x: 0.3 + 0.4 * $0 / 4) }
        let frames = Reframe.keyframes(for: clip, displaySize: horizontal, samples: samples)
        #expect(frames.count >= 2)
        #expect(frames.first!.placement.offsetX > 0) // subject on the left: picture moves right
        #expect(frames.last!.placement.offsetX < 0)
        let room = (Framing.fill.framedSize(of: horizontal).width - 1080) / 2 / 1080
        #expect(frames.allSatisfy { abs($0.placement.offsetX) <= room + 0.0001 })
    }

    @Test func aStillSubjectGivesOneKeyframe() {
        let clip = Clip(assetID: UUID(), sourceStart: .zero, duration: seconds(4))
        let samples = stride(from: 0.0, through: 4, by: 0.5).map { Reframe.Sample(time: seconds($0), x: 0.4) }
        #expect(Reframe.keyframes(for: clip, displaySize: CGSize(width: 1920, height: 1080), samples: samples).count == 1)
    }

    @Test func verticalFootageHasNothingToFollow() {
        let clip = Clip(assetID: UUID(), sourceStart: .zero, duration: seconds(4))
        #expect(Reframe.keyframes(for: clip, displaySize: CGSize(width: 1080, height: 1920), samples: [Reframe.Sample(time: .zero, x: 0.1)]).isEmpty)
    }
}
