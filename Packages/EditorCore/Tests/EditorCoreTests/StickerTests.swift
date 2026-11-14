import CoreGraphics
import CoreMedia
import Foundation
import Testing

@testable import EditorCore

private func t(_ s: Double) -> CMTime { CMTime(seconds: s, preferredTimescale: 600).snappedToFrame() }

private func tenSeconds() -> Project {
    var p = Project()
    let asset = MediaAsset(
        url: URL(fileURLWithPath: "/tmp/a.mov"), name: "a.mov", duration: CMTime(value: 10, timescale: 1),
        displaySize: CGSize(width: 1080, height: 1920), hasAudio: true)
    p.appendClip(of: p.addAsset(asset))
    return p
}

struct TitleLookPresetTests {
    @Test func thereAreThirteenLooksEachDifferent() {
        #expect(TitleStyle.allCases.count == 13)
        #expect(Set(TitleStyle.allCases.map(\.look)).count == 13)
    }

    @Test func oldLooksStillOpen() throws {
        // A look saved before glow, pop shadow and letter spacing existed.
        let json =
            #"{"weight":0.6,"size":90,"textColor":{"red":1,"green":1,"blue":1,"alpha":1},"outlineWidth":20,"boxPerLine":false,"shadow":false,"uppercase":false}"#
        let look = try JSONDecoder().decode(TextLook.self, from: Data(json.utf8))
        #expect(look.glowColor == nil && look.popShadowColor == nil && look.letterSpacing == 0)
        let neon = TitleStyle.neon.look
        #expect(try JSONDecoder().decode(TextLook.self, from: JSONEncoder().encode(neon)) == neon)
    }

    @Test func aStyleDoesNotRestyleStickers() {
        var p = tenSeconds()
        let sticker = p.addSticker(Sticker(.emoji("🔥")), at: .zero)
        let title = p.addTitle(at: .zero, text: "Hi")
        p.applyStyle(.pop)
        #expect(p.title(id: sticker)?.style == .simple)
        #expect(p.title(id: title)?.style == ShortStyle.pop.titleStyle)
    }
}

struct TitleMotionTests {
    @Test func anExitEndsAway() {
        var title = TextOverlay(text: "Bye", start: .zero, duration: t(3))
        title.exit = ClipAnimation(.fade, duration: t(0.5))
        #expect(title.motionState(atOffset: t(1)) == nil)
        let end = title.motionState(atOffset: t(3) - .oneFrame)!
        #expect(end.opacity < 0.1)
    }

    @Test func aLoopKeepsMovingAndStaysSmall() {
        var title = TextOverlay(text: "Hi", start: .zero, duration: t(3))
        title.loop = .pulse
        let scales = stride(from: 0.0, to: 2, by: 0.1).map { title.motionState(atOffset: t($0))!.scale }
        #expect(scales.max()! > 1.03 && scales.min()! < 0.97)
        for loop in TitleLoop.allCases {
            for second in stride(from: 0.0, to: 3, by: 0.05) {
                let state = loop.state(seconds: second)
                #expect(state.scale > 0.8 && state.scale < 1.2 && state.opacity > 0.3 && state.opacity <= 1)
            }
        }
    }

    @Test func exitAndLoopSurviveSaving() throws {
        var title = TextOverlay(text: "Hi", start: .zero, duration: t(3))
        title.exit = ClipAnimation(.slideLeft)
        title.loop = .wiggle
        title.rotation = -8
        title.track = [TrackPoint(offset: .zero, x: 0.5, y: 0.5), TrackPoint(offset: t(1), x: 0.6, y: 0.4)]
        let back = try JSONDecoder().decode(TextOverlay.self, from: JSONEncoder().encode(title))
        #expect(back == title)
    }
}

struct StickerModelTests {
    @Test func aStickerIsATimedTitleInTheMiddle() {
        var p = tenSeconds()
        let id = p.addSticker(Sticker(.symbol("arrow.down"), color: .yellow), at: t(9.5))
        let item = p.title(id: id)!
        #expect(item.isSticker && item.text == "Arrow Down")
        // Near the end it starts earlier, so it is seen for its whole 2 s.
        #expect(item.end == t(10) && item.duration == t(2))
        #expect(item.horizontalPosition == 0.5)
    }

    @Test func stickersSurviveSaving() throws {
        var p = tenSeconds()
        let id = p.addSticker(Sticker(.emoji("🚀"), size: 400), at: .zero)
        let back = try JSONDecoder().decode(TextOverlay.self, from: JSONEncoder().encode(p.title(id: id)!))
        #expect(back.sticker == Sticker(.emoji("🚀"), size: 400))
    }

    @Test func everySymbolHasAName() {
        #expect(StickerCatalog.symbols.count == 24)
        #expect(Set(StickerCatalog.symbols.map(\.name)).count == 24)
        #expect(Sticker(.symbol("bell.fill")).name == "Bell")
    }
}

struct TrackingModelTests {
    @Test func aTrackedTitleMovesByHowFarItsSubjectMoved() {
        var title = TextOverlay(text: "Look", start: t(2), duration: t(3), verticalPosition: 0.3, horizontalPosition: 0.5)
        title.track = [TrackPoint(offset: .zero, x: 0.4, y: 0.6), TrackPoint(offset: t(1), x: 0.6, y: 0.5)]
        #expect(title.position(atOffset: .zero) == (0.5, 0.3))
        let half = title.position(atOffset: t(0.5))
        #expect(abs(half.x - 0.6) < 0.001 && abs(half.y - 0.25) < 0.001)
        // After the last point it stays.
        let later = title.position(atOffset: t(2.5))
        #expect(abs(later.x - 0.7) < 0.001 && abs(later.y - 0.2) < 0.001)
    }
}

struct TextTemplateTests {
    @Test func everyTemplateAddsItsItemsAtThePlayhead() {
        for template in TextTemplate.allCases {
            var p = tenSeconds()
            let ids = p.addTextTemplate(template, at: t(4))
            #expect(!ids.isEmpty)
            #expect(p.titles.count == ids.count)
            #expect(p.titles.allSatisfy { $0.start == t(4) })
            // The first is the text to type in.
            #expect(p.title(id: ids[0])?.isSticker == false)
        }
    }

    @Test func nearTheEndATemplateStartsEarlier() {
        var p = tenSeconds()
        let ids = p.addTextTemplate(.subscribe, at: t(9))
        #expect(p.title(id: ids[0])?.end == t(10))
        #expect(p.title(id: ids[1])?.sticker?.kind == .symbol("bell.fill"))
        // Each one is its own item.
        #expect(Set(ids).count == 2)
    }
}

struct PatchTrackerTests {
    /// A 200×200 noisy picture with a bright cross whose middle is at (cx, cy).
    private func frame(_ cx: Int, _ cy: Int) -> GrayFrame {
        var pixels = [Float](repeating: 0, count: 200 * 200)
        for y in 0..<200 {
            for x in 0..<200 {
                var v = Float((x * 7 + y * 13) % 40)
                if (abs(x - cx) < 4 && abs(y - cy) < 16) || (abs(y - cy) < 4 && abs(x - cx) < 16) { v = 250 }
                pixels[y * 200 + x] = v
            }
        }
        return GrayFrame(width: 200, height: 200, pixels: pixels)
    }

    @Test func itFollowsAShapeThatMoves() {
        var tracker = PatchTracker(frame: frame(60, 100), x: 60, y: 100, radius: 20, reach: 15)
        for step in 1...10 {
            #expect(tracker.next(frame(60 + step * 6, 100 - step * 3)) != nil)
        }
        #expect(abs(tracker.x - 120) <= 1 && abs(tracker.y - 70) <= 1)
    }

    @Test func itStopsWhenTheShapeIsGone() {
        var tracker = PatchTracker(frame: frame(100, 100), x: 100, y: 100, radius: 20, reach: 15)
        let empty = GrayFrame(width: 200, height: 200, pixels: [Float](repeating: 30, count: 200 * 200))
        #expect(tracker.next(empty) == nil)
        #expect(tracker.x == 100)
    }
}
