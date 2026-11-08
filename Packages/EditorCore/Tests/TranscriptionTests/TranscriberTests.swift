@preconcurrency import AVFoundation
import EditorCore
import Foundation
import Speech
import Testing
@testable import Transcription

/// Speech for the tests, spoken by macOS's own `say` into a file.
private func spoken(_ text: String, voice: String? = nil) throws -> URL {
    let url = FileManager.default.temporaryDirectory.appending(path: "speech-\(UUID().uuidString).aiff")
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/say")
    process.arguments = (voice.map { ["-v", $0] } ?? []) + ["-o", url.path, text]
    try process.run()
    process.waitUntilExit()
    return url
}

private var englishInstalled: Bool {
    get async {
        guard SpeechTranscriber.isAvailable,
              let locale = try? await Transcriber.locale(for: .english) else { return false }
        return await SpeechTranscriber.installedLocales.contains(locale)
    }
}

@MainActor
struct TranscriberTests {
    @Test func picksARealRegionForEachLanguage() async throws {
        // A plain "it" would map to Swiss Italian; the main region is the better guess.
        let italian = try await Transcriber.locale(for: .italian, current: Locale(identifier: "en_US"))
        #expect(italian.identifier == "it_IT")
        let swiss = try await Transcriber.locale(for: .italian, current: Locale(identifier: "it_CH"))
        #expect(swiss.identifier == "it_CH")
    }

    @Test func runsBecomeWordsWithPunctuationAttached() {
        var text = AttributedString("Hello")
        text.audioTimeRange = CMTimeRange(start: .zero, duration: CMTime(value: 1, timescale: 2))
        var comma = AttributedString(",")
        comma.audioTimeRange = CMTimeRange(start: CMTime(value: 1, timescale: 2), duration: .zero)
        var pair = AttributedString(" big world")
        pair.audioTimeRange = CMTimeRange(start: CMTime(value: 1, timescale: 1), duration: CMTime(value: 1, timescale: 1))
        let words = Transcriber.words(in: text + comma + pair)
        #expect(words.map(\.text) == ["Hello,", "big", "world"])
        #expect(words[2].start == CMTime(value: 3, timescale: 2))
    }

    @Test(.timeLimit(.minutes(2)))
    func transcribesSpeechWithWordTimes() async throws {
        guard await englishInstalled else { return }  // Needs the English model on this Mac.
        let url = try spoken("Welcome to my channel. Today we make a short video.", voice: "Samantha")
        let transcript = try await Transcriber.transcribe(url, name: "speech", language: .english)
        let text = transcript.words.map(\.text).joined(separator: " ").lowercased()
        #expect(text.contains("welcome"))
        #expect(text.contains("video"))
        let starts = transcript.words.map(\.start)
        #expect(starts == starts.sorted())
        #expect(transcript.words.allSatisfy { $0.duration >= .zero })
    }
}
