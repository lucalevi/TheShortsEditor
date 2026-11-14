import Foundation
import os

/// Where the app writes what went wrong (and a little of what happened), one category per part of
/// the app. Read it in Console.app (filter on the subsystem) or with
/// `log show --predicate 'subsystem == "com.lucalevi.TheShortsEditor"' --last 1h`.
///
/// Failures the user can carry on from (a thumbnail that couldn't be made, a cache that couldn't be
/// written) are logged instead of being thrown away, so a report like "my clip is black" can be
/// traced. File paths and error messages are logged as private (hidden in logs collected from
/// another Mac); what was being done and the error's domain and code are public.
public enum Log {
    public static let subsystem = "com.lucalevi.TheShortsEditor"

    /// Saving and opening Shorts, the library, bookmarks.
    public static let file = Logger(subsystem: subsystem, category: "file")
    /// Adding media: reading files, the Photos library.
    public static let media = Logger(subsystem: subsystem, category: "media")
    /// Building the composition, drawing frames, made copies (steadied, cut out, backwards, smooth).
    public static let render = Logger(subsystem: subsystem, category: "render")
    /// Writing the MP4, frames and covers.
    public static let export = Logger(subsystem: subsystem, category: "export")
    /// Sound levels, voice clean-up, voice effects, music, speech.
    public static let audio = Logger(subsystem: subsystem, category: "audio")
    /// Speech to text, translation, Apple Intelligence.
    public static let captions = Logger(subsystem: subsystem, category: "captions")
    /// Disk clean-up and made-copy folders.
    public static let storage = Logger(subsystem: subsystem, category: "storage")
}

public extension Logger {
    /// Logs a failure the user can carry on from: what was being done, and the error.
    func failure(_ action: String, _ error: any Error) {
        let ns = error as NSError
        self.error("\(action, privacy: .public) failed (\(ns.domain, privacy: .public) \(ns.code, privacy: .public)): \(error.localizedDescription, privacy: .private)")
    }

    /// Runs `work`; when it throws, logs the failure and returns nil. For work whose failure
    /// doesn't stop what the user is doing (in place of `try?`, which forgets the error).
    @discardableResult
    func attempt<T>(_ action: @autoclosure () -> String, _ work: () throws -> T) -> T? {
        do {
            return try work()
        } catch {
            failure(action(), error)
            return nil
        }
    }

    /// `attempt` for async work, run on the caller's actor. Cancelling isn't a failure and isn't logged.
    @discardableResult
    nonisolated(nonsending) func attempt<T>(_ action: @autoclosure () -> String, _ work: () async throws -> T) async -> T? {
        do {
            return try await work()
        } catch is CancellationError {
            return nil
        } catch {
            failure(action(), error)
            return nil
        }
    }
}
