import CoreGraphics
import CoreMedia
import Foundation
import Testing

@testable import EditorCore

private func t(_ s: Double) -> CMTime { CMTime(seconds: s, preferredTimescale: 600).snappedToFrame() }

private func oneClip(seconds: Int64 = 10) -> Project {
    var p = Project()
    let asset = MediaAsset(
        url: URL(fileURLWithPath: "/tmp/a.mov"), name: "a.mov", duration: CMTime(value: seconds, timescale: 1),
        displaySize: CGSize(width: 1080, height: 1920), hasAudio: true)
    p.appendClip(of: p.addAsset(asset))
    return p
}

struct EffectTests {
    @Test func effectsGoOnTheirPartOfTheClip() {
        var clip = Clip(assetID: UUID(), sourceStart: .zero, duration: t(4))
        clip.effects = [ClipEffect(.flash, part: .start, length: t(0.4)), ClipEffect(.blur, part: .end, length: t(1)), ClipEffect(.shake)]
        #expect(clip.activeEffects(atOffset: t(0.1)).map(\.effect.kind) == [.flash, .shake])
        #expect(clip.activeEffects(atOffset: t(2)).map(\.effect.kind) == [.shake])
        let late = clip.activeEffects(atOffset: t(3.5))
        #expect(late.map(\.effect.kind) == [.blur, .shake])
        #expect(abs(late[0].progress - 0.5) < 0.05)
        #expect(clip.activeEffects(atOffset: t(4)).isEmpty)
    }

    @Test func oneOfEachKindAndValuesStayInRange() {
        var p = oneClip()
        let id = p.timeline.clips[0].id
        p.addEffect(.glitch, to: [id])
        p.addEffect(.glitch, to: [id])
        #expect(p.timeline.clips[0].effects.count == 1)
        #expect(p.timeline.clips[0].effects[0].part == .wholeClip)
        p.addEffect(.flash, to: [id])
        #expect(p.timeline.clips[0].effects[1].part == .start)
        let effect = p.timeline.clips[0].effects[0].id
        p.updateEffect(effect, on: id) {
            $0.strength = 3; $0.length = t(20)
        }
        #expect(p.timeline.clips[0].effects[0].strength == 1)
        #expect(p.timeline.clips[0].effects[0].length == t(3))
        p.removeEffect(effect, from: id)
        #expect(p.timeline.clips[0].effects.map(\.kind) == [.flash])
    }

    @Test func aSplitKeepsStartEffectsFirstAndEndEffectsLast() {
        var p = oneClip()
        p.timeline.clips[0].effects = [ClipEffect(.flash, part: .start), ClipEffect(.blur, part: .end), ClipEffect(.vhs)]
        p.timeline.split(at: t(5))
        #expect(p.timeline.clips[0].effects.map(\.kind) == [.flash, .vhs])
        #expect(p.timeline.clips[1].effects.map(\.kind) == [.blur, .vhs])
        #expect(p.timeline.clips[0].effects[1].id != p.timeline.clips[1].effects[1].id)
    }

    @Test func effectsAreCopiedWithTheLookAndReset() {
        var p = oneClip()
        p.appendClip(of: p.assets[0].id)
        let a = p.timeline.clips[0].id, b = p.timeline.clips[1].id
        p.addEffect(.filmGrain, to: [a])
        p.pasteSettings([.look], from: p.timeline.clips[0], to: b)
        #expect(p.timeline.clips[1].effects.map(\.kind) == [.filmGrain])
        #expect(p.changedSettings(of: b).contains(.look))
        p.resetSettings([.look], of: b)
        #expect(p.timeline.clips[1].effects.isEmpty)
    }

    @Test func effectsSurviveSaving() throws {
        var clip = Clip(assetID: UUID(), sourceStart: .zero, duration: t(4))
        clip.effects = [ClipEffect(.lightLeak, strength: 0.3, part: .end, length: t(1.5))]
        let back = try JSONDecoder().decode(Clip.self, from: JSONEncoder().encode(clip))
        #expect(back.effects == clip.effects)
    }
}
