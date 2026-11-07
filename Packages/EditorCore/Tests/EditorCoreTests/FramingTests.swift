import CoreGraphics
import Testing
@testable import EditorCore

struct FramingTests {
    private let canvas = Project.canvasSize

    private func placed(_ size: CGSize, _ framing: Framing, rotation: CGAffineTransform = .identity) -> CGRect {
        CGRect(origin: .zero, size: size)
            .applying(framing.transform(naturalSize: size, preferredTransform: rotation))
    }

    private func isClose(_ a: CGRect, _ b: CGRect) -> Bool {
        abs(a.minX - b.minX) < 0.5 && abs(a.minY - b.minY) < 0.5 && abs(a.width - b.width) < 0.5 && abs(a.height - b.height) < 0.5
    }

    @Test func verticalFootageFillsExactly() {
        #expect(isClose(placed(CGSize(width: 1080, height: 1920), .fill), CGRect(origin: .zero, size: canvas)))
        #expect(isClose(placed(CGSize(width: 720, height: 1280), .fit), CGRect(origin: .zero, size: canvas)))
    }

    @Test func horizontalFillCropsTheSides() {
        // 16:9 scaled to 1920 tall is 3413 wide, centred.
        let rect = placed(CGSize(width: 1920, height: 1080), .fill)
        #expect(abs(rect.height - 1920) < 0.5)
        #expect(abs(rect.width - 3413.33) < 0.5)
        #expect(abs(rect.midX - canvas.width / 2) < 0.5)
    }

    @Test func horizontalFitLetterboxes() {
        let rect = placed(CGSize(width: 1920, height: 1080), .fit)
        #expect(isClose(rect, CGRect(x: 0, y: 656.25, width: 1080, height: 607.5)))
    }

    @Test func rotatedPhoneFootageEndsUpUpright() {
        // An iPhone portrait recording: stored 1920×1080 with a 90° rotation.
        let rotation = CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: 1080, ty: 0)
        #expect(isClose(placed(CGSize(width: 1920, height: 1080), .fill, rotation: rotation), CGRect(origin: .zero, size: canvas)))
    }

    @Test func safeZoneRectsStayOnCanvas() {
        let bounds = CGRect(origin: .zero, size: canvas)
        for rect in SafeZone.coveredRects {
            #expect(bounds.contains(rect))
        }
    }
}
