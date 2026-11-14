import CoreGraphics
import CoreMedia
import Foundation
import Testing

@testable import EditorCore

private func t(_ s: Double) -> CMTime { CMTime(seconds: s, preferredTimescale: 600).snappedToFrame() }

private func oneClip() -> Project {
    var p = Project()
    let asset = MediaAsset(
        url: URL(fileURLWithPath: "/tmp/a.mov"), name: "a.mov", duration: CMTime(value: 10, timescale: 1),
        displaySize: CGSize(width: 1080, height: 1920), hasAudio: true)
    p.appendClip(of: p.addAsset(asset))
    return p
}

struct CutoutTests {
    // MARK: Green screen

    @Test func theScreenGoesAndThePersonStays() {
        let key = ColorKey()
        #expect(key.keyed(0.2, 0.75, 0.3).alpha < 0.01)
        // A bit lighter or darker green is still the screen: brightness doesn't count.
        #expect(key.keyed(0.3, 0.9, 0.4).alpha < 0.05)
        #expect(key.keyed(0.1, 0.5, 0.15).alpha < 0.2)
        // Skin, a white shirt, black hair, a red top stay.
        for (r, g, b) in [(0.9, 0.7, 0.6), (0.95, 0.95, 0.95), (0.05, 0.05, 0.05), (0.8, 0.1, 0.1)] {
            #expect(key.keyed(r, g, b).alpha > 0.99, "\(r) \(g) \(b)")
        }
        // A blue screen key leaves green alone.
        #expect(ColorKey(color: ColorKey.blue).keyed(0.2, 0.75, 0.3).alpha > 0.99)
    }

    @Test func strengthAndSoftnessWidenTheEdge() {
        let greenish = (0.45, 0.65, 0.45)
        let weak = ColorKey(strength: 0.1, softness: 0).keyed(greenish.0, greenish.1, greenish.2).alpha
        let strong = ColorKey(strength: 1, softness: 0).keyed(greenish.0, greenish.1, greenish.2).alpha
        #expect(weak > strong)
        #expect(strong < 0.01)
        let hard = ColorKey(strength: 0.2, softness: 0), soft = ColorKey(strength: 0.2, softness: 1)
        // Just past the hard edge: fully kept with no softness, only partly with it.
        let pixel = (0.35, 0.6, 0.38)
        #expect(hard.keyed(pixel.0, pixel.1, pixel.2).alpha > 0.99)
        #expect(soft.keyed(pixel.0, pixel.1, pixel.2).alpha < 0.9)
    }

    @Test func spillTakesTheGreenGlowOffWhatIsKept() {
        // A grey shirt lit a little green by the screen.
        let glow = (0.55, 0.68, 0.55)
        let none = ColorKey(strength: 0.1, spill: 0).keyed(glow.0, glow.1, glow.2)
        let full = ColorKey(strength: 0.1, spill: 1).keyed(glow.0, glow.1, glow.2)
        #expect(none.green - none.red > 0.1)
        #expect(full.green - full.red < none.green - none.red - 0.05)
        // Its brightness stays about the same; a red that leans away from green is untouched.
        let y = { (c: (red: Double, green: Double, blue: Double, alpha: Double)) in 0.299 * c.red + 0.587 * c.green + 0.114 * c.blue }
        #expect(abs(y(full) - y(none)) < 0.02)
        let red = ColorKey(spill: 1).keyed(0.8, 0.1, 0.1)
        #expect(abs(red.red - 0.8) < 0.001 && abs(red.green - 0.1) < 0.001)
    }

    @Test func theScreenColourIsFoundInAPicture() {
        var pixels: [(Double, Double, Double)] = Array(repeating: (0.15, 0.7, 0.25), count: 600)
        pixels += Array(repeating: (0.85, 0.65, 0.55), count: 250)
        pixels += Array(repeating: (0.5, 0.5, 0.5), count: 400)
        let found = try! #require(ColorKey.screenColor(in: pixels))
        #expect(abs(found.green - 0.7) < 0.01 && abs(found.red - 0.15) < 0.01)
        #expect(ColorKey.screenColor(in: Array(repeating: (0.5, 0.5, 0.5), count: 100)) == nil)
    }

    // MARK: Masks

    @Test func aCircleKeepsItsMiddle() {
        let size = CGSize(width: 1000, height: 2000)
        let mask = ClipMask(shape: .circle, size: 0.5, feather: 0)
        #expect(mask.visibility(at: CGPoint(x: 500, y: 1000), in: size) == 1)
        // Radius 250 (half of 0.5 × the shorter side).
        #expect(mask.visibility(at: CGPoint(x: 740, y: 1000), in: size) == 1)
        #expect(mask.visibility(at: CGPoint(x: 760, y: 1000), in: size) == 0)
        #expect(mask.visibility(at: CGPoint(x: 0, y: 0), in: size) == 0)
        var inverted = mask
        inverted.inverted = true
        #expect(inverted.visibility(at: CGPoint(x: 0, y: 0), in: size) == 1)
        // Stretched wider: further to the side, less far up.
        var wide = mask
        wide.stretch = 4
        #expect(wide.visibility(at: CGPoint(x: 900, y: 1000), in: size) == 1)
        #expect(wide.visibility(at: CGPoint(x: 500, y: 1150), in: size) == 0)
    }

    @Test func aLineKeepsTheTopAndTurns() {
        let size = CGSize(width: 1000, height: 1000)
        let line = ClipMask(shape: .line, feather: 0)
        #expect(line.visibility(at: CGPoint(x: 500, y: 300), in: size) == 1)
        #expect(line.visibility(at: CGPoint(x: 500, y: 700), in: size) == 0)
        // Turned a quarter clockwise, the kept side is the right.
        var turned = line
        turned.rotation = 90
        #expect(turned.visibility(at: CGPoint(x: 800, y: 500), in: size) == 1)
        #expect(turned.visibility(at: CGPoint(x: 200, y: 500), in: size) == 0)
        // A soft edge fades over a distance.
        let soft = ClipMask(shape: .line, feather: 1)
        let middle = soft.visibility(at: CGPoint(x: 500, y: 500), in: size)
        #expect(abs(middle - 0.5) < 0.01)
        #expect(soft.visibility(at: CGPoint(x: 500, y: 450), in: size) > 0.6)
    }

    @Test func aRectangleAndABand() {
        let size = CGSize(width: 1000, height: 1000)
        let box = ClipMask(shape: .rectangle, size: 0.5, feather: 0, roundness: 0)
        #expect(box.visibility(at: CGPoint(x: 740, y: 740), in: size) == 1)
        #expect(box.visibility(at: CGPoint(x: 760, y: 500), in: size) == 0)
        var round = box
        round.roundness = 1
        // Fully round corners: the corner itself is cut off.
        #expect(round.visibility(at: CGPoint(x: 740, y: 740), in: size) == 0)
        let band = ClipMask(shape: .band, size: 0.2, feather: 0)
        #expect(band.visibility(at: CGPoint(x: 100, y: 590), in: size) == 1)
        #expect(band.visibility(at: CGPoint(x: 100, y: 620), in: size) == 0)
        #expect(band.visibility(at: CGPoint(x: 100, y: 380), in: size) == 0)
    }

    // MARK: Clips

    @Test func cutoutsAreSavedAndOldFilesHaveNone() throws {
        var clip = Clip(assetID: UUID(), sourceStart: .zero, duration: t(2))
        clip.cutout = ClipCutout(removeBackground: .people, key: ColorKey(strength: 0.6), mask: ClipMask(shape: .heart, rotation: 20), blend: .screen)
        clip.background = .color
        clip.backgroundColor = .yellow
        let decoded = try JSONDecoder().decode(Clip.self, from: JSONEncoder().encode(clip))
        #expect(decoded.cutout == clip.cutout)
        #expect(decoded.background == .color && decoded.backgroundColor == .yellow)

        let plain = Clip(assetID: UUID(), sourceStart: .zero, duration: t(2))
        let json = String(decoding: try JSONEncoder().encode(plain), as: UTF8.self)
        #expect(!json.contains("cutout") && !json.contains("backgroundColor"))
        let old = try JSONDecoder().decode(Clip.self, from: JSONEncoder().encode(plain))
        #expect(old.cutout.isEmpty && old.backgroundColor == .white)
    }

    @Test func cutoutsFollowSplitsAndSettings() throws {
        var p = oneClip()
        let id = p.timeline.clips[0].id
        p.updateCutout(of: id) { $0.mask = ClipMask(shape: .circle) }
        #expect(p.removesBackgrounds == false)
        p.updateCutout(of: id) { $0.removeBackground = .subject }
        #expect(p.removesBackgrounds)
        _ = p.timeline.split(at: t(4))
        #expect(p.timeline.clips.count == 2)
        #expect(p.timeline.clips.allSatisfy { $0.cutout.mask?.shape == .circle && $0.cutout.removeBackground == .subject })

        #expect(p.changedSettings(of: id).contains(.cutout))
        let source = p.timeline.clips[0]
        let other = p.timeline.clips[1].id
        p.resetSettings([.cutout], of: other)
        #expect(p.timeline.clips[1].cutout.isEmpty)
        p.pasteSettings([.cutout], from: source, to: other)
        #expect(p.timeline.clips[1].cutout == source.cutout)
    }
}
