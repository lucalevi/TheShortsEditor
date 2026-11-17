@preconcurrency import AVFoundation
import EditorCore

extension AVAssetReaderOutput {
    /// `copyNextSampleBuffer()`, which blocks while it decodes, on a thread of its own
    /// (`BlockingWork`), for loops that await other work between samples.
    nonisolated func nextSample() async -> CMSampleBuffer? {
        let output = Unchecked(self)
        return await BlockingWork.run { Unchecked(output.value.copyNextSampleBuffer()) }.value
    }
}
