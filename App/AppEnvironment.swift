import Foundation

/// Where the app keeps its files and settings.
///
/// Normally that is its folder in Application Support and the standard preferences. Under tests it
/// is a separate folder and a separate preferences suite, so a test never sees, changes or cleans
/// up the user's Shorts:
/// - the app tests (`AppTests`, hosted in the app) are noticed by XCTest's own environment;
/// - the UI tests (`AppUITests`) launch the app with `SHORTS_TEST_RUN=<name>`, and with
///   `SHORTS_TEST_FRESH=1` to start that run from nothing (relaunching without it finds the same
///   Shorts again, e.g. after a forced quit).
nonisolated enum AppEnvironment {
    /// The name of this test run, or nil when the app runs for real.
    static let testRun: String? = {
        let environment = ProcessInfo.processInfo.environment
        if let name = environment["SHORTS_TEST_RUN"], !name.isEmpty {
            // A folder name, never a path.
            return name.replacingOccurrences(of: "/", with: "-")
        }
        return environment["XCTestConfigurationFilePath"] != nil ? "app-tests" : nil
    }()

    static var isTesting: Bool { testRun != nil }

    /// The app's own folder: `Application Support/Shorts Editor`, or a test run's folder.
    static let appFolder: URL = {
        let support = URL.applicationSupportDirectory
        guard let testRun else { return support.appending(path: "Shorts Editor", directoryHint: .isDirectory) }
        let tests = support.appending(path: "Shorts Editor Tests", directoryHint: .isDirectory)
        let folder = tests.appending(path: testRun, directoryHint: .isDirectory)
        if startsFresh {
            try? FileManager.default.removeItem(at: folder)
            removeOldRuns(in: tests)
        }
        return folder
    }()

    /// Libraries of earlier test runs, left a day ago or more (each UI test has its own).
    private static func removeOldRuns(in tests: URL) {
        let manager = FileManager.default
        let runs = (try? manager.contentsOfDirectory(at: tests, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        for run in runs {
            let modified = (try? run.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            if Date.now.timeIntervalSince(modified) > 24 * 3600 { try? manager.removeItem(at: run) }
        }
    }

    /// The app's preferences: the standard ones, or a test run's own. (`UserDefaults` is thread-safe.)
    nonisolated(unsafe) static let defaults: UserDefaults = {
        guard let testRun else { return .standard }
        let suite = "com.lucalevi.TheShortsEditor.tests.\(testRun)"
        let defaults = UserDefaults(suiteName: suite) ?? .standard
        if startsFresh { defaults.removePersistentDomain(forName: suite) }
        return defaults
    }()

    /// Where Export writes during a UI test run (they can't drive the system's save panel); nil otherwise.
    static var uiTestExportFolder: URL? {
        guard ProcessInfo.processInfo.environment["SHORTS_TEST_RUN"] != nil else { return nil }
        let folder = appFolder.appending(path: "Exports", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    /// The app tests always start from nothing; a UI test run when it asks.
    private static var startsFresh: Bool {
        let environment = ProcessInfo.processInfo.environment
        return environment["SHORTS_TEST_FRESH"] == "1" || (environment["SHORTS_TEST_RUN"] == nil && environment["XCTestConfigurationFilePath"] != nil)
    }
}
