import CoreMedia
import EditorCore
import Foundation
import Testing

@testable import Shorts_Editor

/// What VoiceOver says about the timeline (F25): lengths in words, and what the badges on a clip
/// show (on screen they are only pictures with tooltips).
struct AccessibilityTests {
    @Test func lengthsAreSaidInWords() {
        let english = Locale(identifier: "en_US")
        #expect(TimeFormat.spoken(CMTime(value: 42, timescale: 10), locale: english) == "4.2 seconds")
        #expect(TimeFormat.spoken(CMTime(value: 635, timescale: 10), locale: english) == "1 minute, 3.5 seconds")
        #expect(TimeFormat.spoken(.zero, locale: english) == "0.0 seconds")
        // In Italian too, from the same code.
        #expect(TimeFormat.spoken(CMTime(value: 42, timescale: 10), locale: Locale(identifier: "it_IT")) == "4,2 secondi")
    }

    @Test func aClipsBadgesAreSaid() {
        var clip = Clip(assetID: UUID(), sourceStart: .zero, duration: CMTime(value: 3, timescale: 1))
        #expect(ClipBlock.spokenDetails(of: clip, isReversed: false, tooLoud: false).isEmpty)
        clip.isMuted = true
        clip.steadiness = 0.5
        clip.placement.scale = 1.5
        let details = ClipBlock.spokenDetails(of: clip, isReversed: true, tooLoud: true)
        #expect(details == ["muted", "plays backwards", "steadied", "zoomed to 150 percent"])
    }
}
