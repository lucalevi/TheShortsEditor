@preconcurrency import AVFoundation
import EditorCore
import Foundation

/// Text to speech with the Mac's own voices (and the user's Personal Voice, when they allow it),
/// on this Mac: written to a sound file to place as a voice-over.
@MainActor
public enum SpeechMaker {
    public struct Voice: Identifiable, Hashable, Sendable {
        public let id: String
        public let name: String
        public let language: String
        public let isPersonal: Bool
        public let isBetter: Bool
    }

    /// The voices for a language ("en", "it-IT"…): Personal Voice first, then the best quality.
    public static func voices(for language: String) -> [Voice] {
        let prefix = String(language.prefix(2))
        return AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.hasPrefix(prefix) }
            .map { voice in
                Voice(
                    id: voice.identifier, name: voice.name, language: voice.language,
                    isPersonal: voice.voiceTraits.contains(.isPersonalVoice), isBetter: voice.quality != .default)
            }
            .sorted { a, b in
                if a.isPersonal != b.isPersonal { return a.isPersonal }
                if a.isBetter != b.isBetter { return a.isBetter }
                return a.name < b.name
            }
    }

    /// Asks once to use the user's Personal Voice. True when allowed.
    public static func allowPersonalVoice() async -> Bool {
        await withCheckedContinuation { continuation in
            AVSpeechSynthesizer.requestPersonalVoiceAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
    }

    public static var personalVoiceAllowed: Bool {
        AVSpeechSynthesizer.personalVoiceAuthorizationStatus == .authorized
    }

    static func utterance(_ text: String, voice: String?, rate: Double) -> AVSpeechUtterance {
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = voice.flatMap(AVSpeechSynthesisVoice.init(identifier:))
        // 1 is the voice's normal pace.
        utterance.rate = Float(Double(AVSpeechUtteranceDefaultSpeechRate) * rate).clamped(
            AVSpeechUtteranceMinimumSpeechRate, AVSpeechUtteranceMaximumSpeechRate)
        return utterance
    }

    private static var previewer: AVSpeechSynthesizer?

    /// Says it out loud now (a preview).
    public static func preview(_ text: String, voice: String?, rate: Double = 1) {
        previewer?.stopSpeaking(at: .immediate)
        let synthesizer = AVSpeechSynthesizer()
        previewer = synthesizer
        synthesizer.speak(utterance(text, voice: voice, rate: rate))
    }

    public static func stopPreview() { previewer?.stopSpeaking(at: .immediate) }

    /// Writes the spoken text to a new sound file in `folder`. Throws when nothing was spoken.
    public static func makeFile(_ text: String, voice: String?, rate: Double = 1, in folder: URL) async throws -> URL {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        // Named after its first words, so it is easy to find in Media.
        let words = text.split(whereSeparator: \.isWhitespace).prefix(4).joined(separator: " ")
            .components(separatedBy: CharacterSet(charactersIn: "/:\\")).joined()
        var url = folder.appending(path: "Spoken – \(words).caf")
        var number = 2
        while FileManager.default.fileExists(atPath: url.path) {
            url = folder.appending(path: "Spoken – \(words) \(number).caf")
            number += 1
        }
        let synthesizer = AVSpeechSynthesizer()
        let writer = BufferWriter(url: url)
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            var finished = false
            synthesizer.write(utterance(text, voice: voice, rate: rate)) { buffer in
                guard !finished else { return }
                guard let pcm = buffer as? AVAudioPCMBuffer, pcm.frameLength > 0 else {
                    finished = true
                    continuation.resume()
                    return
                }
                writer.append(pcm)
            }
        }
        _ = synthesizer
        guard writer.close() else { throw CocoaError(.fileWriteUnknown) }
        return url
    }

    /// Collects the synthesizer's buffers into a file (it calls back on its own queue).
    private final class BufferWriter: @unchecked Sendable {
        let url: URL
        private var file: AVAudioFile?
        private var wrote = false
        private let lock = NSLock()

        init(url: URL) { self.url = url }

        func append(_ buffer: AVAudioPCMBuffer) {
            lock.lock(); defer { lock.unlock() }
            if file == nil {
                file = Log.audio.attempt("Making the spoken voice's file") {
                    try AVAudioFile(
                        forWriting: url, settings: buffer.format.settings, commonFormat: buffer.format.commonFormat, interleaved: buffer.format.isInterleaved)
                }
            }
            if let file { Log.audio.attempt("Writing the spoken voice") { try file.write(from: buffer) } }
            wrote = true
        }

        func close() -> Bool {
            lock.lock(); defer { lock.unlock() }
            file = nil
            return wrote
        }
    }
}

private extension Float {
    func clamped(_ low: Float, _ high: Float) -> Float { Swift.min(Swift.max(self, low), high) }
}
