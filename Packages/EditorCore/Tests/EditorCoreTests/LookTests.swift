import CoreGraphics
import CoreMedia
import Foundation
import Testing

@testable import EditorCore

private func close(_ a: Double, _ b: Double, _ tolerance: Double = 0.01) -> Bool { abs(a - b) <= tolerance }
private func close(_ a: RGB, _ b: RGB, _ tolerance: Double = 0.01) -> Bool {
    close(a.r, b.r, tolerance) && close(a.g, b.g, tolerance) && close(a.b, b.b, tolerance)
}

private func video(_ name: String) -> MediaAsset {
    MediaAsset(
        url: URL(fileURLWithPath: "/tmp/\(name)"), name: name, duration: CMTime(value: 10, timescale: 1),
        displaySize: CGSize(width: 1080, height: 1920), hasAudio: true)
}

/// A picture of `count` pixels: an even ramp from dark to bright, tinted by `cast`.
private func ramp(from low: Double = 0, to high: Double = 1, cast: RGB = RGB(gray: 1), count: Int = 200) -> [RGB] {
    (0..<count).map { i in
        let v = low + (high - low) * Double(i) / Double(count - 1)
        return RGB(v * cast.r, v * cast.g, v * cast.b).clamped
    }
}

struct ColorAdjustmentTests {
    @Test func neutralAdjustmentsLeaveEveryColourAlone() {
        let neutral = ColorAdjustments()
        for c in [RGB(0, 0, 0), RGB(1, 1, 1), RGB(0.2, 0.5, 0.9), RGB(0.7, 0.3, 0.1)] {
            #expect(neutral.apply(c) == c)
        }
        #expect(ClipLook().isNeutral)
        #expect(ClipLook().apply(RGB(0.3, 0.4, 0.5)) == RGB(0.3, 0.4, 0.5))
    }

    @Test func exposureBrightensAndDarkens() {
        let mid = RGB(gray: 0.4)
        #expect(ColorAdjustments(exposure: 0.5).apply(mid).luma > 0.5)
        #expect(ColorAdjustments(exposure: -0.5).apply(mid).luma < 0.33)
        // Black stays black, and nothing goes past white.
        #expect(ColorAdjustments(exposure: 1).apply(RGB(gray: 0)) == RGB(gray: 0))
        #expect(ColorAdjustments(exposure: 1).apply(RGB(gray: 0.9)).r <= 1)
    }

    @Test func contrastSpreadsDarkAndLightButKeepsTheEndsAndMiddle() {
        let more = ColorAdjustments(contrast: 1), less = ColorAdjustments(contrast: -1)
        #expect(more.apply(RGB(gray: 0.25)).r < 0.25)
        #expect(more.apply(RGB(gray: 0.75)).r > 0.75)
        #expect(less.apply(RGB(gray: 0.25)).r > 0.25)
        #expect(close(more.apply(RGB(gray: 0.5)).r, 0.5))
        #expect(more.apply(RGB(gray: 0)).r == 0 && more.apply(RGB(gray: 1)).r == 1)
    }

    @Test func toneCurvesNeverTurnBack() {
        // Brighter in, brighter (or equal) out, at every extreme of the sliders.
        for contrast in [-1.0, 1] {
            for shadows in [-1.0, 1] {
                for highlights in [-1.0, 1] {
                    let a = ColorAdjustments(contrast: contrast, highlights: highlights, shadows: shadows)
                    var last = -1.0
                    for i in 0...100 {
                        let y = a.toneCurve(Double(i) / 100)
                        #expect(y >= last - 0.000001)
                        last = y
                    }
                }
            }
        }
    }

    @Test func shadowsAndHighlightsWorkOnTheirOwnPart() {
        let lift = ColorAdjustments(shadows: 1)
        #expect(lift.apply(RGB(gray: 0.3)).r > 0.35)
        #expect(close(lift.apply(RGB(gray: 0.95)).r, 0.95, 0.03))
        let recover = ColorAdjustments(highlights: -1)
        #expect(recover.apply(RGB(gray: 0.7)).r < 0.65)
        #expect(close(recover.apply(RGB(gray: 0.05)).r, 0.05, 0.03))
    }

    @Test func saturationGoesFromGreyToDoubleTheColour() {
        let red = RGB(0.6, 0.3, 0.3)
        let grey = ColorAdjustments(saturation: -1).apply(red)
        #expect(close(grey.r, grey.g) && close(grey.g, grey.b))
        #expect(close(grey.luma, red.luma))
        #expect(ColorAdjustments(saturation: 0.5).apply(red).saturation > red.saturation)
    }

    @Test func warmthAndTintKeepGreyAsBright() {
        let warm = ColorAdjustments(warmth: 1).apply(RGB(gray: 0.5))
        #expect(warm.r > warm.b)
        #expect(close(warm.luma, 0.5))
        let magenta = ColorAdjustments(tint: 1).apply(RGB(gray: 0.5))
        #expect(magenta.g < magenta.r && magenta.g < magenta.b)
        #expect(close(magenta.luma, 0.5))
    }

    @Test func pickingWhiteMakesThatSpotGrey() {
        // A bluish wall and a green-tinted one.
        for sample in [RGB(0.55, 0.62, 0.78), RGB(0.6, 0.75, 0.6), RGB(0.8, 0.6, 0.45)] {
            let balanced = ColorAdjustments().balanced(sample, toward: .white)
            let out = balanced.apply(sample)
            #expect(close(out.r, out.g, 0.02) && close(out.g, out.b, 0.02))
        }
    }

    @Test func pickingWhiteKeepsTheOtherSliders() {
        let before = ColorAdjustments(exposure: 0.3, contrast: 0.2, saturation: -0.4)
        let after = before.balanced(RGB(0.5, 0.5, 0.7), toward: .white)
        #expect(after.exposure == 0.3 && after.contrast == 0.2 && after.saturation == -0.4)
        #expect(after.warmth > 0)
    }

    @Test func pickingSkinGivesItANaturalHue() {
        // Skin filmed under bluish light.
        let sample = RGB(0.6, 0.55, 0.6)
        let out = ColorAdjustments().balanced(sample, toward: .skin).apply(sample)
        let wanted = ColorAdjustments.BalanceTarget.skin.color
        #expect(close(out.r / out.b, wanted.r / wanted.b, 0.05))
        #expect(close(out.g / out.b, wanted.g / wanted.b, 0.05))
    }

    @Test func pickingABlackOrBlownOutSpotChangesNothing() {
        let a = ColorAdjustments(exposure: 0.2)
        #expect(a.balanced(RGB(0.01, 0.01, 0.2), toward: .white) == a)
        #expect(a.balanced(RGB(1, 1, 0.9), toward: .white) == a)
    }

    @Test func valuesAreKeptInRangeAndRounded() {
        let a = ColorAdjustments(exposure: 3, contrast: -0.123456).tidied
        #expect(a.exposure == 1 && a.contrast == -0.12)
    }
}

struct FrameStatsTests {
    @Test func measuresBrightnessSpreadAndColour() {
        let stats = FrameStats(pixels: ramp())!
        #expect(close(stats.median, 0.5, 0.02))
        #expect(stats.dark < 0.03 && stats.bright > 0.97)
        #expect(close(stats.saturation, 0))
        #expect(FrameStats(pixels: []) == nil)
    }

    @Test func enhanceLeavesAGoodPictureNearlyAlone() {
        let auto = ColorAdjustments.auto(for: FrameStats(mean: RGB(gray: 0.45), dark: 0.05, median: 0.45, bright: 0.95, saturation: 0.4))
        #expect(auto.isNeutral)
    }

    @Test func enhanceFixesADarkFlatBluishPicture() {
        let pixels = ramp(from: 0.1, to: 0.45, cast: RGB(0.8, 0.9, 1.0))
        let stats = FrameStats(pixels: pixels)!
        let auto = ColorAdjustments.auto(for: stats)
        #expect(auto.exposure > 0)
        #expect(auto.contrast > 0)
        #expect(auto.warmth > 0) // takes some of the blue out
        let after = FrameStats(pixels: pixels.map(auto.apply))!
        #expect(after.median > stats.median)
        #expect(after.bright - after.dark > stats.bright - stats.dark)
        // Half of the cast is left (a sunset should stay a sunset), but less than before.
        #expect(after.mean.b / after.mean.r < stats.mean.b / stats.mean.r)
    }

    @Test func matchColorBringsAPictureCloseToTheReference() {
        let reference = ramp(from: 0.05, to: 0.9, cast: RGB(1, 0.85, 0.7)).map { $0.saturated(0.3).clamped }
        let target = ramp(from: 0.15, to: 0.6, cast: RGB(0.75, 0.85, 1))
        let wanted = FrameStats(pixels: reference)!
        let before = FrameStats(pixels: target)!
        let match = ColorAdjustments.matching(target, to: wanted)
        let after = FrameStats(pixels: target.map(match.apply))!
        #expect(abs(after.median - wanted.median) < abs(before.median - wanted.median) / 2)
        #expect(
            abs((after.mean.r / after.mean.b) - (wanted.mean.r / wanted.mean.b)) < abs((before.mean.r / before.mean.b) - (wanted.mean.r / wanted.mean.b)) / 2)
        #expect(after.bright - after.dark > before.bright - before.dark)
    }

    @Test func matchingAPictureToItselfChangesNothing() {
        let pixels = ramp(from: 0.1, to: 0.8, cast: RGB(1, 0.9, 0.8))
        let match = ColorAdjustments.matching(pixels, to: FrameStats(pixels: pixels)!)
        #expect(abs(match.exposure) <= 0.02 && abs(match.contrast) <= 0.02 && abs(match.warmth) <= 0.02 && abs(match.saturation) <= 0.02)
    }
}

struct FilterTests {
    @Test func everyFilterChangesThePictureAndStaysInRange() {
        let samples = [RGB(0.1, 0.2, 0.3), RGB(0.8, 0.6, 0.5), RGB(0.5, 0.5, 0.5), RGB(0, 0, 0), RGB(1, 1, 1)]
        for filter in LookFilter.allCases {
            var changed = false
            for c in samples {
                let out = filter.apply(c)
                #expect(out == out.clamped, "\(filter) went out of range")
                if !close(out, c, 0.02) { changed = true }
            }
            #expect(changed, "\(filter) does nothing")
        }
        #expect(Set(LookFilter.allCases.map(\.displayName)).count == LookFilter.allCases.count)
    }

    @Test func blackAndWhiteFiltersHaveNoColour() {
        for filter in [LookFilter.blackAndWhite, .noir] {
            let out = filter.apply(RGB(0.8, 0.3, 0.2))
            #expect(close(out.r, out.g) && close(out.g, out.b))
        }
    }

    @Test func warmIsWarmerThanCool() {
        let grey = RGB(gray: 0.5)
        let warm = LookFilter.warm.apply(grey), cool = LookFilter.cool.apply(grey)
        #expect(warm.r > warm.b && cool.b > cool.r)
    }

    @Test func strengthBlendsBetweenTheOriginalAndTheFilter() {
        let c = RGB(0.8, 0.3, 0.2)
        let half = FilterChoice(.blackAndWhite, strength: 0.5).apply(c)
        let full = LookFilter.blackAndWhite.apply(c)
        #expect(close(half, c.mixed(with: full, 0.5)))
        #expect(FilterChoice(.noir, strength: 0).apply(c) == c)
        #expect(FilterChoice(.noir, strength: 3).strength == 1)
        #expect(FilterChoice(.vintage, strength: 0.5).vignette == LookFilter.vintage.vignette / 2)
        #expect(ClipLook(filter: FilterChoice(.noir, strength: 0)).isNeutral)
    }

    @Test func aLookAppliesTheSlidersBeforeTheFilter() {
        let look = ClipLook(color: ColorAdjustments(exposure: 0.5), filter: FilterChoice(.blackAndWhite))
        let c = RGB(0.3, 0.2, 0.1)
        #expect(look.apply(c) == LookFilter.blackAndWhite.apply(ColorAdjustments(exposure: 0.5).apply(c)))
    }
}

struct LookOnProjectTests {
    private func twoClips() -> (Project, Clip.ID, Clip.ID) {
        var p = Project()
        let a = p.addAsset(video("a.mov"))
        p.appendClip(of: a)
        p.appendClip(of: a)
        return (p, p.timeline.clips[0].id, p.timeline.clips[1].id)
    }

    @Test func aFilterOnEveryClip() {
        var (p, a, b) = twoClips()
        p.setFilterOnEveryClip(FilterChoice(.film, strength: 0.7))
        #expect(p.anyClip(id: a)?.look.filter == FilterChoice(.film, strength: 0.7))
        #expect(p.anyClip(id: b)?.look.filter == FilterChoice(.film, strength: 0.7))
        p.setFilterOnEveryClip(nil)
        #expect(p.anyClip(id: a)?.look.filter == nil)
    }

    @Test func splittingKeepsTheLookOnBothPieces() {
        var (p, a, _) = twoClips()
        p.updateLook(of: a) { $0.color.exposure = 0.4 }
        p.updateAnyClip(a) { $0.steadiness = 0.7 }
        _ = p.timeline.split(at: CMTime(value: 5, timescale: 1))
        #expect(p.timeline.clips.count == 3)
        #expect(p.timeline.clips[0].look.color.exposure == 0.4 && p.timeline.clips[1].look.color.exposure == 0.4)
        #expect(p.timeline.clips[1].steadiness == 0.7)
    }

    @Test func copyPasteAndResetLook() {
        var (p, a, b) = twoClips()
        p.updateLook(of: a) { $0 = ClipLook(color: ColorAdjustments(warmth: 0.3), filter: FilterChoice(.moody)) }
        p.updateAnyClip(a) { $0.steadiness = 0.5 }
        #expect(p.changedSettings(of: a).contains(.look))
        #expect(!p.changedSettings(of: b).contains(.look))
        p.pasteSettings([.look], from: p.anyClip(id: a)!, to: b)
        #expect(p.anyClip(id: b)?.look == p.anyClip(id: a)?.look)
        #expect(p.anyClip(id: b)?.steadiness == 0.5)
        p.resetSettings([.look], of: b)
        #expect(p.anyClip(id: b)?.look == ClipLook())
        #expect(p.anyClip(id: b)?.steadiness == 0)
        // Pasting the picture alone leaves the look as it was.
        p.pasteSettings([.picture], from: p.anyClip(id: a)!, to: b)
        #expect(p.anyClip(id: b)?.look == ClipLook())
    }

    @Test func looksAreSavedAndReadBack() throws {
        var (p, a, _) = twoClips()
        p.updateLook(of: a) { $0 = ClipLook(color: ColorAdjustments(exposure: 0.25, tint: -0.1), filter: FilterChoice(.tealOrange, strength: 0.6)) }
        p.updateAnyClip(a) { $0.steadiness = 0.8 }
        p.look = FilterChoice(.vintage, strength: 0.4)
        let data = try JSONEncoder().encode(p)
        let read = try JSONDecoder().decode(Project.self, from: data)
        #expect(read == p)
        // A clip with no look saves nothing for it.
        let plain = try JSONEncoder().encode(p.timeline.clips[1])
        #expect(!String(decoding: plain, as: UTF8.self).contains("look"))
        #expect(ProjectFile.currentVersion >= 5)
    }
}

struct StabilizationTests {
    /// A path that shakes ±`amount` every other frame around a slow pan to the right.
    private func shaky(amount: Double = 0.02, frames: Int = 120) -> ShakePath {
        ShakePath(
            interval: 1.0 / 30,
            positions: (0..<frames).map { i in
                CGPoint(x: Double(i) * 0.001 + (i.isMultiple(of: 2) ? amount : -amount), y: i.isMultiple(of: 2) ? -amount : amount)
            })
    }

    @Test func correctionCancelsTheShakeButKeepsThePan() {
        let path = shaky()
        for frame in 30..<90 {
            let t = Double(frame) / 30
            let c = path.correction(at: t, steadiness: 0.5)
            let steadied = CGPoint(x: path.position(at: t).x + c.dx, y: path.position(at: t).y + c.dy)
            // After moving, the content is on the smooth pan line.
            #expect(abs(steadied.x - Double(frame) * 0.001) < 0.004)
            #expect(abs(steadied.y) < 0.004)
        }
    }

    @Test func aSteadyPathNeedsNoCorrectionOrZoom() {
        let still = ShakePath(interval: 1.0 / 30, positions: Array(repeating: CGPoint(x: 0.1, y: -0.05), count: 60))
        let c = still.correction(at: 1, steadiness: 1)
        #expect(abs(c.dx) < 0.000001 && abs(c.dy) < 0.000001)
        #expect(still.zoom(over: 0...2, steadiness: 1) < 1.01)
    }

    @Test func zoomHidesTheMovedEdgesUpToALimit() {
        let small = shaky(amount: 0.01).zoom(over: 0...4, steadiness: 0.5)
        #expect(small > 1.03 && small < 1.1)
        let big = shaky(amount: 0.3).zoom(over: 0...4, steadiness: 0.5)
        #expect(big == ShakePath.maxZoom)
        #expect(shaky().zoom(over: 0...4, steadiness: 0) == 1)
    }

    @Test func moreSteadinessSmoothsOverALongerTime() {
        // A slow sway (one second each way) is kept at low steadiness, mostly removed at full.
        let sway = ShakePath(interval: 1.0 / 30, positions: (0..<300).map { i in CGPoint(x: 0.03 * sin(Double(i) / 30 * .pi), y: 0) })
        let low = abs(sway.correction(at: 5.5, steadiness: 0).dx)
        let high = abs(sway.correction(at: 5.5, steadiness: 1).dx)
        #expect(high > low * 2)
    }

    @Test func theMoveNeverUncoversAnEdge() {
        let clip = Clip(assetID: UUID(), sourceStart: .zero, duration: CMTime(value: 4, timescale: 1), steadiness: 1)
        let steadying = Steadying(path: shaky(amount: 0.3), clip: clip)
        for frame in 0..<120 {
            let (shift, zoom) = steadying.adjustment(atSourceTime: CMTime(value: CMTimeValue(frame), timescale: 30))
            #expect(abs(shift.dx) <= (zoom - 1) / 2 + 0.0001 && abs(shift.dy) <= (zoom - 1) / 2 + 0.0001)
        }
        // As a transform: the picture's corners stay outside the frame.
        let size = CGSize(width: 1920, height: 1080)
        let transform = steadying.transform(atSourceTime: CMTime(value: 7, timescale: 30), naturalSize: size)
        let moved = CGRect(origin: .zero, size: size).applying(transform)
        #expect(moved.minX <= 0.01 && moved.minY <= 0.01 && moved.maxX >= size.width - 0.01 && moved.maxY >= size.height - 0.01)
    }
}
