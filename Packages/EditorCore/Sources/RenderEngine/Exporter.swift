@preconcurrency import AVFoundation
import EditorCore

/// Writes a project to an MP4 file that matches YouTube's recommended upload settings:
/// H.264 High profile, 1080×1920 at 30 fps, closed GOPs of half a second, AAC-LC 48 kHz stereo,
/// and the index at the front of the file ("fast start").
///
/// Frames come from the same `ShortsCompositor` as the preview, so the file looks exactly like
/// what was seen while editing.
public enum Exporter {
    /// About 12 Mbps: a little above YouTube's ~10 Mbps reference for 1080p30, because YouTube
    /// re-encodes everything and a cleaner upload survives that better.
    public static let videoBitRate = 12_000_000
    /// YouTube suggests 384 kbps; 320 kbps is the most Apple's AAC encoder does for stereo.
    public static let audioBitRate = 320_000
    public static let audioSampleRate = 48_000.0

    public enum ExportError: LocalizedError {
        case cannotWrite(String)
        case failed(String)

        public var errorDescription: String? {
            switch self {
            case .cannotWrite(let detail): "The video file can't be written. \(detail)"
            case .failed(let detail): "The export stopped. \(detail)"
            }
        }
    }

    /// Exports `project` to `url`, replacing any file there. `progress` goes from 0 to 1 and is
    /// called on the main actor. Cancelling the task stops the export and removes the partial file.
    public static func export(_ project: Project, to url: URL, progress: @escaping @MainActor (Double) -> Void = { _ in }) async throws {
        let built = try await CompositionBuilder.build(project)
        let composition = built.composition
        let duration = composition.duration

        try? FileManager.default.removeItem(at: url)
        let writer: AVAssetWriter
        let reader: AVAssetReader
        do {
            writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
            reader = try AVAssetReader(asset: composition)
        } catch {
            throw ExportError.cannotWrite(error.localizedDescription)
        }
        writer.shouldOptimizeForNetworkUse = true

        // Video: frames drawn by the compositor, encoded to YouTube's recommendation.
        let videoTracks = try await composition.loadTracks(withMediaType: .video)
        let videoOutput = AVAssetReaderVideoCompositionOutput(videoTracks: videoTracks, videoSettings: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
        ])
        videoOutput.videoComposition = built.videoComposition
        videoOutput.alwaysCopiesSampleData = false
        let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        videoInput.expectsMediaDataInRealTime = false

        var pumps: [Pump] = []
        guard reader.canAdd(videoOutput), writer.canAdd(videoInput) else {
            throw ExportError.cannotWrite("The video settings weren't accepted.")
        }
        reader.add(videoOutput)
        writer.add(videoInput)
        pumps.append(Pump(output: videoOutput, input: videoInput, label: "video"))

        // Sound, when there is any: mixed down to stereo 48 kHz, then AAC.
        let audioTracks = try await composition.loadTracks(withMediaType: .audio)
        if !audioTracks.isEmpty {
            let audioOutput = AVAssetReaderAudioMixOutput(audioTracks: audioTracks, audioSettings: [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVSampleRateKey: audioSampleRate,
                AVNumberOfChannelsKey: 2,
                AVLinearPCMBitDepthKey: 32,
                AVLinearPCMIsFloatKey: true,
                AVLinearPCMIsNonInterleaved: false,
                AVLinearPCMIsBigEndianKey: false,
            ])
            audioOutput.alwaysCopiesSampleData = false
            let audioInput = AVAssetWriterInput(mediaType: .audio, outputSettings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: audioSampleRate,
                AVNumberOfChannelsKey: 2,
                AVEncoderBitRateKey: audioBitRate,
            ])
            audioInput.expectsMediaDataInRealTime = false
            guard reader.canAdd(audioOutput), writer.canAdd(audioInput) else {
                throw ExportError.cannotWrite("The sound settings weren't accepted.")
            }
            reader.add(audioOutput)
            writer.add(audioInput)
            pumps.append(Pump(output: audioOutput, input: audioInput, label: "audio"))
        }

        guard reader.startReading() else { throw ExportError.failed(reader.error?.localizedDescription ?? "") }
        guard writer.startWriting() else { throw ExportError.cannotWrite(writer.error?.localizedDescription ?? "") }
        writer.startSession(atSourceTime: .zero)

        // Report progress from the video's position, a few times a second.
        let reporter = Task {
            while !Task.isCancelled {
                let done = pumps[0].lastTime
                if duration > .zero { progress(min(max(done.seconds / duration.seconds, 0), 1)) }
                try? await Task.sleep(for: .milliseconds(150))
            }
        }
        defer { reporter.cancel() }

        await withTaskCancellationHandler {
            await withTaskGroup(of: Void.self) { group in
                for pump in pumps {
                    group.addTask { await pump.run() }
                }
            }
        } onCancel: {
            pumps.forEach { $0.cancel() }
        }

        if Task.isCancelled || pumps.contains(where: \.isCancelled) {
            reader.cancelReading()
            writer.cancelWriting()
            try? FileManager.default.removeItem(at: url)
            throw CancellationError()
        }
        if reader.status == .failed {
            writer.cancelWriting()
            try? FileManager.default.removeItem(at: url)
            throw ExportError.failed(reader.error?.localizedDescription ?? "")
        }
        await writer.finishWriting()
        guard writer.status == .completed else {
            try? FileManager.default.removeItem(at: url)
            throw ExportError.failed(writer.error?.localizedDescription ?? "")
        }
        progress(1)
    }

    static var videoSettings: [String: Any] {
        [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: Int(Project.canvasSize.width),
            AVVideoHeightKey: Int(Project.canvasSize.height),
            AVVideoColorPropertiesKey: [
                AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2,
                AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_709_2,
                AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2,
            ],
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: videoBitRate,
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
                AVVideoH264EntropyModeKey: AVVideoH264EntropyModeCABAC,
                AVVideoExpectedSourceFrameRateKey: Int(Project.frameRate),
                // A key frame every half second: YouTube asks for closed GOPs of half the frame rate.
                AVVideoMaxKeyFrameIntervalKey: Int(Project.frameRate) / 2,
                AVVideoAllowFrameReorderingKey: true,
            ] as [String: Any],
        ]
    }
}

/// Moves samples from a reader output to a writer input on its own queue until either runs out.
/// AVFoundation drives it from that queue; the class only bridges it to async/await.
nonisolated private final class Pump: @unchecked Sendable {
    private let output: AVAssetReaderOutput
    private let input: AVAssetWriterInput
    private let queue: DispatchQueue
    private let state = NSLock()
    private var _cancelled = false
    private var _lastTime = CMTime.zero
    /// Touched only on `queue`.
    private var finished = false

    init(output: AVAssetReaderOutput, input: AVAssetWriterInput, label: String) {
        self.output = output
        self.input = input
        queue = DispatchQueue(label: "export.\(label)")
    }

    var isCancelled: Bool { state.withLock { _cancelled } }
    var lastTime: CMTime { state.withLock { _lastTime } }

    func cancel() { state.withLock { _cancelled = true } }

    func run() async {
        await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
            input.requestMediaDataWhenReady(on: queue) { [self] in
                guard !finished else { return }
                while input.isReadyForMoreMediaData {
                    guard !isCancelled, let sample = output.copyNextSampleBuffer(), input.append(sample) else {
                        finished = true
                        input.markAsFinished()
                        done.resume()
                        return
                    }
                    let time = CMSampleBufferGetPresentationTimeStamp(sample)
                    state.withLock { _lastTime = time }
                }
            }
        }
    }
}
