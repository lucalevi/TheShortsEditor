import AVFoundation
import EditorCore
import Foundation
import Testing

@testable import Shorts_Editor

/// Media written by the tests themselves (so they need no files on disk), and ways to wait for
/// the app's background work.
enum TestMedia {
    struct WriteError: Error {}

    /// A folder for this run's media, inside the app's container (the app is sandboxed, and opens
    /// its own container's files without being handed them).
    static let folder: URL = {
        let folder = FileManager.default.temporaryDirectory.appending(path: "AppTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }()

    /// A portrait video of one colour, `seconds` long at 30 fps, with a steady tone as its sound.
    static func video(seconds: Int = 2, width: Int = 180, height: Int = 320, bgra: (UInt8, UInt8, UInt8, UInt8) = (40, 160, 220, 255)) async throws -> URL {
        let url = folder.appending(path: "clip-\(UUID().uuidString).mov")
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let video = AVAssetWriterInput(
            mediaType: .video,
            outputSettings: [
                AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: width, AVVideoHeightKey: height,
                AVVideoColorPropertiesKey: [
                    AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2,
                    AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_709_2,
                    AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2,
                ],
            ])
        video.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: video, sourcePixelBufferAttributes: nil)
        let audio = AVAssetWriterInput(
            mediaType: .audio, outputSettings: [AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 48_000, AVNumberOfChannelsKey: 1])
        audio.expectsMediaDataInRealTime = false
        writer.add(video)
        writer.add(audio)
        guard writer.startWriting() else { throw writer.error ?? WriteError() }
        writer.startSession(atSourceTime: .zero)
        let picture = try solidBuffer(width: width, height: height, bgra: bgra)
        let frames = 30 * seconds
        var nextVideo = 0, nextAudio = 0
        // Feed whichever input is ready: the writer interleaves sound and picture.
        while nextVideo < frames || nextAudio < frames {
            var progressed = false
            if nextVideo < frames, video.isReadyForMoreMediaData {
                guard adaptor.append(picture, withPresentationTime: CMTime(value: Int64(nextVideo), timescale: 30)) else { throw writer.error ?? WriteError() }
                nextVideo += 1
                progressed = true
                if nextVideo == frames { video.markAsFinished() }
            }
            if nextAudio < frames, audio.isReadyForMoreMediaData {
                guard audio.append(try toneBuffer(frame: nextAudio)) else { throw writer.error ?? WriteError() }
                nextAudio += 1
                progressed = true
                if nextAudio == frames { audio.markAsFinished() }
            }
            if writer.status == .failed { throw writer.error ?? WriteError() }
            if !progressed { try await Task.sleep(for: .milliseconds(2)) }
        }
        await writer.finishWriting()
        guard writer.status == .completed else { throw writer.error ?? WriteError() }
        return url
    }

    private static func solidBuffer(width: Int, height: Int, bgra: (UInt8, UInt8, UInt8, UInt8)) throws -> CVPixelBuffer {
        var buffer: CVPixelBuffer?
        CVPixelBufferCreate(kCFAllocatorDefault, width, height, kCVPixelFormatType_32BGRA, nil, &buffer)
        guard let buffer else { throw WriteError() }
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        let base = CVPixelBufferGetBaseAddress(buffer)!.assumingMemoryBound(to: UInt8.self)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
        for y in 0..<height {
            for x in 0..<width {
                let p = base + y * bytesPerRow + x * 4
                (p[0], p[1], p[2], p[3]) = bgra
            }
        }
        return buffer
    }

    /// 1/30 s of a 440 Hz tone, 48 kHz mono.
    private static func toneBuffer(frame: Int) throws -> CMSampleBuffer {
        let count = 1600, first = frame * count
        let samples = (0..<count).map { i in Int16(sin(2 * .pi * 440 * Double(first + i) / 48_000) * 12_000) }
        var description = AudioStreamBasicDescription(
            mSampleRate: 48_000, mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kLinearPCMFormatFlagIsSignedInteger | kLinearPCMFormatFlagIsPacked,
            mBytesPerPacket: 2, mFramesPerPacket: 1, mBytesPerFrame: 2, mChannelsPerFrame: 1, mBitsPerChannel: 16, mReserved: 0)
        var format: CMAudioFormatDescription?
        CMAudioFormatDescriptionCreate(
            allocator: nil, asbd: &description, layoutSize: 0, layout: nil, magicCookieSize: 0, magicCookie: nil, extensions: nil, formatDescriptionOut: &format
        )
        var block: CMBlockBuffer?
        let bytes = count * 2
        CMBlockBufferCreateWithMemoryBlock(
            allocator: nil, memoryBlock: nil, blockLength: bytes, blockAllocator: nil, customBlockSource: nil, offsetToData: 0, dataLength: bytes,
            flags: kCMBlockBufferAssureMemoryNowFlag, blockBufferOut: &block)
        guard let format, let block else { throw WriteError() }
        _ = samples.withUnsafeBytes { CMBlockBufferReplaceDataBytes(with: $0.baseAddress!, blockBuffer: block, offsetIntoDestination: 0, dataLength: bytes) }
        var sample: CMSampleBuffer?
        CMAudioSampleBufferCreateReadyWithPacketDescriptions(
            allocator: nil, dataBuffer: block, formatDescription: format, sampleCount: count,
            presentationTimeStamp: CMTime(value: CMTimeValue(first), timescale: 48_000), packetDescriptions: nil, sampleBufferOut: &sample)
        guard let sample else { throw WriteError() }
        return sample
    }
}

/// Waits until `condition` holds, checking every 20 ms, for at most `seconds`. Records an issue
/// (and returns false) when it never does.
@discardableResult
func waitUntil(
    _ what: Comment, seconds: Double = 20, sourceLocation: SourceLocation = #_sourceLocation, _ condition: () -> Bool
) async -> Bool {
    let deadline = Date.now.addingTimeInterval(seconds)
    while !condition() {
        guard Date.now < deadline else {
            Issue.record("Timed out waiting: \(what)", sourceLocation: sourceLocation)
            return false
        }
        try? await Task.sleep(for: .milliseconds(20))
    }
    return true
}

/// An editor like the app's, with an undo manager of its own (there is no window) whose steps are
/// closed by `step(_:)`, as the run loop closes them in the app. Every edit must happen inside an
/// open group (`step`, `importToTimeline`, or `beginUndoGrouping`): registering undo with none open
/// raises an Objective-C exception, which unwinding through Swift async code turns into a hang or a
/// crash much later.
@MainActor
final class TestEditor {
    let model = EditorModel()
    let undo = UndoManager()

    init() {
        undo.groupsByEvent = false
        model.ownUndoManager = undo
    }

    /// A new empty Short, open in the editor.
    static func withNewShort() -> TestEditor {
        let editor = TestEditor()
        editor.model.newShort()
        return editor
    }

    /// One user action: its undo registrations become one undo step.
    func step(_ action: () -> Void) {
        undo.beginUndoGrouping()
        action()
        undo.endUndoGrouping()
    }

    /// Imports files onto the end of the timeline and waits until the edit is made and built.
    func importToTimeline(_ urls: [URL]) async {
        let before = model.project.timeline.clips.count
        undo.beginUndoGrouping()
        model.importFiles(urls, addToTimeline: true)
        await waitUntil("the files are on the timeline") { model.project.timeline.clips.count >= before + urls.count }
        undo.endUndoGrouping()
        await model.waitUntilBuilt()
    }

    /// Moves the playhead and waits until the player is there (its time observer would otherwise
    /// report the old time once more).
    func seek(to time: CMTime) async {
        model.playback.seek(to: time)
        await waitUntil("the player is at the playhead") {
            model.playback.player.currentTime().snappedToFrame() == time.snappedToFrame() && model.currentTime == time.snappedToFrame()
        }
    }

    /// Writes any change now and waits until it is on disk.
    func saveAndWait() {
        model.saveNow()
        ProjectStore.finishSaving()
    }
}
