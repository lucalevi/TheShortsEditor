import AVFoundation
import EditorCore

/// Test-only: the videos a UI test run (`AppUITests`) works with.
///
/// The UI tests can't hand the app a file. Both are sandboxed, so a file the test runner writes is
/// one the app may not read, and opening it with the app through Launch Services
/// (`XCUIApplication.open`) started a second copy of the app with the user's own library. So
/// the copy under test makes the video itself, in its test run's folder, and imports it as if it
/// had been opened from Finder:
/// - `SHORTS_TEST_IMPORT=<seconds>`: a portrait video that many seconds long is added at launch;
/// - `SHORTS_TEST_REMOVE_MEDIA=1`: those videos are deleted at launch (a Short with missing media).
///
/// Both are ignored unless the app runs under a UI test (`SHORTS_TEST_RUN`).
enum UITestMedia {
    /// How long a video to add at launch, or nil.
    static var secondsToImport: Int? {
        guard isUITestRun, let value = ProcessInfo.processInfo.environment["SHORTS_TEST_IMPORT"] else { return nil }
        return Int(value).flatMap { $0 > 0 ? $0 : nil }
    }

    static var removesMedia: Bool {
        isUITestRun && ProcessInfo.processInfo.environment["SHORTS_TEST_REMOVE_MEDIA"] == "1"
    }

    /// Where the test videos are kept: inside the test run's own folder, so a fresh run removes them.
    static var folder: URL {
        AppEnvironment.appFolder.appending(path: "Test media", directoryHint: .isDirectory)
    }

    private static var isUITestRun: Bool { ProcessInfo.processInfo.environment["SHORTS_TEST_RUN"] != nil }

    /// Called once the window exists: removes the test videos if asked, then adds one if asked.
    static func prepare(_ model: EditorModel) {
        if removesMedia {
            Log.file.attempt("Removing the UI test's videos") { try FileManager.default.removeItem(at: folder) }
        }
        guard let seconds = secondsToImport else { return }
        Task {
            guard let video = await Log.media.attempt("Making the UI test's video", { try await makeVideo(seconds: seconds, in: folder) }) else { return }
            model.importFiles([video], addToTimeline: true)
        }
    }

    /// A silent portrait video of one grey, `seconds` long at 30 fps, written into `folder`.
    static func makeVideo(seconds: Int, in folder: URL) async throws -> URL {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appending(path: "clip-\(UUID().uuidString.prefix(6)).mov")
        let (width, height) = (180, 320)
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let input = AVAssetWriterInput(
            mediaType: .video, outputSettings: [AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: width, AVVideoHeightKey: height])
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: nil)
        writer.add(input)
        guard writer.startWriting() else { throw writer.error ?? CocoaError(.fileWriteUnknown) }
        writer.startSession(atSourceTime: .zero)
        var buffer: CVPixelBuffer?
        CVPixelBufferCreate(kCFAllocatorDefault, width, height, kCVPixelFormatType_32BGRA, nil, &buffer)
        guard let picture = buffer else { throw CocoaError(.fileWriteUnknown) }
        CVPixelBufferLockBaseAddress(picture, [])
        memset(CVPixelBufferGetBaseAddress(picture), 0x80, CVPixelBufferGetDataSize(picture))
        CVPixelBufferUnlockBaseAddress(picture, [])
        for frame in 0..<(30 * seconds) {
            while !input.isReadyForMoreMediaData { try await Task.sleep(for: .milliseconds(5)) }
            guard adaptor.append(picture, withPresentationTime: CMTime(value: Int64(frame), timescale: 30)) else {
                throw writer.error ?? CocoaError(.fileWriteUnknown)
            }
        }
        input.markAsFinished()
        await writer.finishWriting()
        guard writer.status == .completed else { throw writer.error ?? CocoaError(.fileWriteUnknown) }
        return url
    }
}
