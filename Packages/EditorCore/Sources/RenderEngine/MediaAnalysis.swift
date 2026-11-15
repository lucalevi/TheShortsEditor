import CryptoKit
import EditorCore
import Foundation

/// A file as it is now: its path, size and date of change, as a short key. A changed file has a
/// new key, so nothing measured about its old content is used for it, and copies made from it
/// (cleaned voice, processed sound, cut-out, smooth slow motion) are named after it. `extra`
/// adds what else the copy depends on (its recipe).
nonisolated enum FileIdentity {
    static func key(of url: URL, extra: String? = nil) -> String {
        // A URL keeps the values it read once; a file changed since must be read again.
        var url = url
        url.removeAllCachedResourceValues()
        let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        var key = "\(url.path)|\(values?.fileSize ?? 0)|\(values?.contentModificationDate?.timeIntervalSince1970 ?? 0)"
        if let extra { key += "|" + extra }
        return SHA256.hash(data: Data(key.utf8)).prefix(12).map { String(format: "%02x", $0) }.joined()
    }
}

/// What has been measured about media files, kept so it is measured once: the sound levels of
/// each file (for lowering music under speech, removing pauses and the waveforms) and the shake
/// paths for Stabilize (also kept on disk, in `ShakeCache`).
///
/// Not shared by the whole process: the app owns one and hands it to whatever builds a
/// composition (`CompositionBuilder.build(…, analysis:)`, exports, posters). Everything is keyed by
/// the file as it is now (`FileIdentity`), so a file changed on disk is measured again.
public final class MediaAnalysis {
    private var levels: [String: AudioLevels?] = [:]
    private var measuringLevels: [String: Task<AudioLevels?, Never>] = [:]
    private var shakePaths: [String: ShakePath] = [:]

    public init() {}

    /// The file's sound levels, measuring them the first time. Nil when it has no sound or can't
    /// be read.
    public func levels(of url: URL) async -> AudioLevels? {
        let key = FileIdentity.key(of: url)
        if let known = levels[key] { return known }
        if let task = measuringLevels[key] { return await task.value }
        let task = Task { try? await AudioProbe.levels(of: url) }
        measuringLevels[key] = task
        let result = await task.value
        measuringLevels[key] = nil
        levels[key] = result
        return result
    }

    /// The shake path of the file at `url`, if it has been measured (on this Mac).
    public func shakePath(for url: URL) -> ShakePath? {
        let key = FileIdentity.key(of: url)
        if let path = shakePaths[key] { return path }
        guard let path = ShakeCache.stored(for: url) else { return nil }
        shakePaths[key] = path
        return path
    }

    /// Measures the shake of the file at `url` unless that was done already.
    public func measureShake(_ url: URL, progress: @escaping @Sendable (Double) -> Void = { _ in }) async throws -> ShakePath {
        if let path = shakePath(for: url) { return path }
        let path = try await Stabilizer.analyse(url, progress: progress)
        shakePaths[FileIdentity.key(of: url)] = path
        ShakeCache.store(path, for: url)
        return path
    }
}
