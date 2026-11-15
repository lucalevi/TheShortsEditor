@preconcurrency import AVFoundation
import EditorCore
import Testing

@testable import RenderEngine

// MARK: - Stage F: style music

struct MusicLibraryTests {
    @Test func everyMoodSoundsAndStaysUnderFullScale() {
        for mood in MusicMood.allCases {
            let music = MusicLibrary.render(mood, seconds: 30)
            let peak = max(music.left.map(abs).max() ?? 0, music.right.map(abs).max() ?? 0)
            let rms = sqrt(music.left.reduce(0) { $0 + Double($1 * $1) } / Double(music.left.count))
            #expect(peak <= 0.9, "\(mood)")
            #expect(rms > 0.05, "\(mood) is too quiet: \(rms)")
            #expect(music.left != music.right, "\(mood) should be stereo")
        }
    }

    @Test func theLoopRepeatsExactly() {
        let mood = MusicMood.upbeat
        let music = MusicLibrary.render(mood, seconds: 60)
        let bar = Int((240 / mood.tempo * MusicLibrary.sampleRate).rounded())
        let loopStart = 2 * bar, loop = 16 * bar
        let sample = loopStart + 12_345
        #expect(music.left[sample] == music.left[sample + loop])
    }

    @Test(.timeLimit(.minutes(2)))
    func musicFileCoversTheLongestShort() async throws {
        let url = try await MusicLibrary.fileURL(for: .calm)
        let asset = try await MediaProbe.probe(url)
        #expect(!asset.hasVideo && asset.hasAudio)
        #expect(asset.duration >= Project.maxDuration)
    }
}
