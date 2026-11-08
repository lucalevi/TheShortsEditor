@preconcurrency import AVFoundation
import EditorCore
import Speech

/// Turns the sound of a file into timed words, on this Mac, with Apple's speech models.
/// Nothing is sent over the network except the one-time download of a language's model.
public enum Transcriber {
    public enum TranscriptionError: LocalizedError {
        case unavailable
        case unsupported(CaptionLanguage)
        case noAudio(String)

        public var errorDescription: String? {
            switch self {
            case .unavailable: "Speech recognition isn't available on this Mac."
            case .unsupported(let language): "Captions in \(language.displayName) aren't available on this Mac."
            case .noAudio(let name): "“\(name)” has no sound to make captions from."
            }
        }
    }

    /// The speech model's locale for `language`. The Mac's own region is used when it speaks that
    /// language (Swiss Italian, British English…), otherwise the language's main region.
    public static func locale(for language: CaptionLanguage, current: Locale = .current) async throws -> Locale {
        let mainRegion = ["en": "US", "it": "IT", "de": "DE", "fr": "FR"][language.rawValue] ?? ""
        var candidates: [Locale] = []
        if current.language.languageCode?.identifier == language.rawValue, let region = current.region {
            candidates.append(Locale(identifier: "\(language.rawValue)_\(region.identifier)"))
        }
        candidates.append(Locale(identifier: "\(language.rawValue)_\(mainRegion)"))
        candidates.append(Locale(identifier: language.rawValue))
        for candidate in candidates {
            if let supported = await SpeechTranscriber.supportedLocale(equivalentTo: candidate) {
                return supported
            }
        }
        throw TranscriptionError.unsupported(language)
    }

    /// Downloads the language's speech model if it isn't on this Mac yet. `progress` goes from 0 to 1.
    public static func prepare(_ language: CaptionLanguage, progress: @escaping @MainActor (Double) -> Void = { _ in }) async throws {
        guard SpeechTranscriber.isAvailable else { throw TranscriptionError.unavailable }
        let transcriber = makeTranscriber(try await locale(for: language))
        guard let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) else { return }
        let observation = request.progress.observe(\.fractionCompleted) { value, _ in
            let fraction = value.fractionCompleted
            Task { @MainActor in progress(fraction) }
        }
        defer { observation.invalidate() }
        try await request.downloadAndInstall()
    }

    /// Transcribes the sound of the file at `url`. Word times are in the file's own time.
    public static func transcribe(_ url: URL, name: String, language: CaptionLanguage) async throws -> Transcript {
        let locale = try await locale(for: language)
        let words = try await recognise(url: url, name: name, locale: locale)
        return Transcript(language: language, words: words)
    }

    nonisolated private static func makeTranscriber(_ locale: Locale) -> SpeechTranscriber {
        SpeechTranscriber(locale: locale, transcriptionOptions: [], reportingOptions: [], attributeOptions: [.audioTimeRange])
    }

    /// Runs off the main actor: reading and decoding a long file takes a while.
    @concurrent
    private static func recognise(url: URL, name: String, locale: Locale) async throws -> [Word] {
        let transcriber = makeTranscriber(locale)
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber]) else {
            throw TranscriptionError.unavailable
        }

        let results = transcriber.results
        let collector = Task {
            var words: [Word] = []
            for try await result in results {
                words.append(contentsOf: Self.words(in: result.text))
            }
            return words
        }

        let (input, feed) = AsyncStream.makeStream(of: AnalyzerInput.self)
        try await analyzer.start(inputSequence: input)
        do {
            try await readAudio(of: url, name: name, as: format) { feed.yield($0) }
            feed.finish()
            try await analyzer.finalizeAndFinishThroughEndOfInput()
        } catch {
            feed.finish()
            await analyzer.cancelAndFinishNow()
            collector.cancel()
            throw error
        }
        return try await collector.value
    }

    /// Decodes the file's first sound track into buffers the analyzer accepts, each stamped with
    /// its time in the file.
    @concurrent
    private static func readAudio(of url: URL, name: String, as format: AVAudioFormat, _ yield: (AnalyzerInput) -> Void) async throws {
        let asset = AVURLAsset(url: url)
        guard let track = try await asset.loadTracks(withMediaType: .audio).first else {
            throw TranscriptionError.noAudio(name)
        }
        // Interleaved samples in the analyzer's own rate, size and channel count.
        let pcm = AVAudioFormat(commonFormat: format.commonFormat, sampleRate: format.sampleRate, channels: format.channelCount, interleaved: true)!
        let isFloat = format.commonFormat == .pcmFormatFloat32 || format.commonFormat == .pcmFormatFloat64
        let bits = pcm.streamDescription.pointee.mBitsPerChannel
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: format.sampleRate,
            AVNumberOfChannelsKey: format.channelCount,
            AVLinearPCMBitDepthKey: bits,
            AVLinearPCMIsFloatKey: isFloat,
            AVLinearPCMIsNonInterleaved: false,
            AVLinearPCMIsBigEndianKey: false,
        ])
        let reader = try AVAssetReader(asset: asset)
        reader.add(output)
        guard reader.startReading() else { throw reader.error ?? TranscriptionError.noAudio(name) }

        while let sample = output.copyNextSampleBuffer() {
            try Task.checkCancellation()
            let frames = AVAudioFrameCount(CMSampleBufferGetNumSamples(sample))
            guard frames > 0, let buffer = AVAudioPCMBuffer(pcmFormat: pcm, frameCapacity: frames) else { continue }
            buffer.frameLength = frames
            let status = CMSampleBufferCopyPCMDataIntoAudioBufferList(sample, at: 0, frameCount: Int32(frames), into: buffer.mutableAudioBufferList)
            guard status == noErr else { continue }
            yield(AnalyzerInput(buffer: buffer, bufferStartTime: CMSampleBufferGetPresentationTimeStamp(sample)))
        }
        if reader.status == .failed { throw reader.error ?? TranscriptionError.noAudio(name) }
    }

    /// The words of one result. Each timed run is normally one word; punctuation on its own is
    /// joined to the word before it.
    nonisolated static func words(in text: AttributedString) -> [Word] {
        var words: [Word] = []
        for run in text.runs {
            guard let range = run.audioTimeRange else { continue }
            var parts: [String] = []
            for part in String(text[run.range].characters).split(whereSeparator: \.isWhitespace).map(String.init) {
                if part.allSatisfy(\.isPunctuation) {
                    if !parts.isEmpty {
                        parts[parts.count - 1] += part
                    } else if !words.isEmpty {
                        words[words.count - 1].text += part
                    }
                } else {
                    parts.append(part)
                }
            }
            // Several words in one run share its time equally.
            let count = Int32(parts.count)
            for (index, part) in parts.enumerated() {
                let start = range.start + CMTimeMultiplyByRatio(range.duration, multiplier: Int32(index), divisor: count)
                let end = range.start + CMTimeMultiplyByRatio(range.duration, multiplier: Int32(index) + 1, divisor: count)
                words.append(Word(text: part, start: start, duration: end - start))
            }
        }
        return words
    }
}
