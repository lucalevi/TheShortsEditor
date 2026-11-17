import AppKit
import XCTest

/// The paths a user must always be able to take, driven through the real app (F18): add a video,
/// edit it, undo and redo, export; a Short whose media went missing; an edit surviving a forced
/// quit; and an accessibility audit of both windows.
///
/// Each test runs the app with a library of its own (`SHORTS_TEST_RUN`, see `AppEnvironment`), so
/// the user's Shorts and settings are never touched. Run with `make uitest` (macOS asks once for
/// Automation Mode; see STATUS.md).
@MainActor
final class CriticalPathTests: XCTestCase {
    private var app: XCUIApplication!
    private let run = "ui-\(UUID().uuidString.prefix(8))"
    private let bundleID = "com.lucalevi.TheShortsEditor"

    /// Called first by every test: the app is quit at the end. (Its test run's folder, the
    /// videos included, is removed by the next fresh run a day later; see `AppEnvironment`.)
    private func begin() throws {
        continueAfterFailure = false
        addTeardownBlock { @MainActor [weak self] in self?.app?.terminate() }
    }

    // MARK: The paths

    func testAddEditUndoRedoAndExport() throws {
        try begin()
        launch(fresh: true, videoSeconds: 3)
        let clips = timelineClips
        XCTAssertTrue(clips.firstMatch.waitForExistence(timeout: 30), "The video never reached the timeline")
        XCTAssertEqual(clips.count, 1)

        // A second in (30 frames), then split.
        app.activate()
        for _ in 0..<30 { press(.rightArrow) }
        menu("Split at Playhead")
        XCTAssertTrue(waitFor { clips.count == 2 }, "Split at Playhead didn't make two clips")

        menu("Undo Split Clip")
        XCTAssertTrue(waitFor { clips.count == 1 }, "Undo didn't put the clip back together")
        menu("Redo Split Clip")
        XCTAssertTrue(waitFor { clips.count == 2 }, "Redo didn't split it again")

        // Export. Under UI tests the app skips the save panel (a system service the tests can't
        // reach) and writes into its test run's own folder; the file itself is checked by
        // ExportTests (AppTests) and ExporterTests.
        menu("Export Short…")
        let chooseFile = app.buttons["Export…"]
        XCTAssertTrue(chooseFile.waitForExistence(timeout: 30), "The export checks never finished")
        chooseFile.click()
        let done = app.buttons["Done"]
        if !done.waitForExistence(timeout: 120) {
            print("SCREEN AFTER EXPORT:\n\(app.debugDescription)")
            XCTFail("The export never finished")
        }
        done.click()
        XCTAssertFalse(app.sheets.firstMatch.exists, "The export sheet stayed open")
    }

    func testAnEditSurvivesAForcedQuit() throws {
        try begin()
        launch(fresh: true, videoSeconds: 3)
        XCTAssertTrue(timelineClips.firstMatch.waitForExistence(timeout: 30))
        app.activate()
        for _ in 0..<30 { press(.rightArrow) }
        menu("Split at Playhead")
        XCTAssertTrue(waitFor { self.timelineClips.count == 2 })
        // Autosave comes a second after the edit.
        Thread.sleep(forTimeInterval: 3)
        forceQuit()

        // The app reopens where it was (F27 state restoration): the Short, with its split.
        launch(fresh: false)
        XCTAssertTrue(waitFor { self.timelineClips.count == 2 }, "The split was lost in the forced quit, or the Short didn't reopen")
    }

    func testAShortWithMissingMediaOpensAndSaysSo() throws {
        try begin()
        launch(fresh: true, videoSeconds: 2)
        XCTAssertTrue(timelineClips.firstMatch.waitForExistence(timeout: 30))
        app.activate()
        menu("All Shorts")
        app.terminate()

        launch(fresh: false, removeMedia: true)
        openFirstShort()
        XCTAssertTrue(app.staticTexts["A file can't be found"].waitForExistence(timeout: 20), "No word about the missing file")
        XCTAssertEqual(timelineClips.count, 1, "The clip of the missing file should stay on the timeline")
        XCTAssertTrue(app.buttons["Find Missing Files…"].exists)
    }

    /// File ▸ New Window opens a second window with All Shorts, its own editor (F27).
    func testANewWindowOpensBesideTheFirst() throws {
        try begin()
        launch(fresh: true, videoSeconds: 2)
        XCTAssertTrue(timelineClips.firstMatch.waitForExistence(timeout: 30))
        menu("New Window")
        XCTAssertTrue(waitFor { self.app.windows.count >= 2 }, "No second window")
        // The first window still has its Short.
        XCTAssertEqual(timelineClips.count, 1)
    }

    /// Needs Screen Recording for the test runner (the audit looks at screenshots), so it runs only
    /// when asked: `TEST_RUNNER_SHORTS_UI_AUDIT=1 make uitest`.
    func testAccessibilityAudit() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["SHORTS_UI_AUDIT"] == "1", "Set TEST_RUNNER_SHORTS_UI_AUDIT=1 (needs Screen Recording)")
        try begin()
        launch(fresh: true)
        // Contrast is judged from screenshots, which need Screen Recording for the test runner:
        // left to Phase 7 (F25), with the B&W check by eye.
        let audits = XCUIAccessibilityAuditType.all.subtracting(.contrast)
        try app.performAccessibilityAudit(for: audits)
        app.terminate()
        launch(fresh: true, videoSeconds: 2)
        XCTAssertTrue(timelineClips.firstMatch.waitForExistence(timeout: 30))
        try app.performAccessibilityAudit(for: audits)
    }

    // MARK: Helpers

    /// Brings the app back in front if something else took it (keys and menus reach only the
    /// app in front; a Terminal coming forward made runs fail).
    private func front() {
        if app.state != .runningForeground { app.activate() }
    }

    private func press(_ key: XCUIKeyboardKey) {
        front()
        app.typeKey(key, modifierFlags: [])
    }

    private func menu(_ title: String) {
        front()
        app.menuItems[title].click()
    }

    private var timelineClips: XCUIElementQuery {
        app.descendants(matching: .any).matching(identifier: "timeline.clip")
    }

    /// Launches the copy under test. `videoSeconds`: a video that long is added at launch, as if
    /// opened from Finder; `removeMedia`: the videos added so far are deleted first. The app makes
    /// and removes them itself (`UITestMedia`): the runner can't hand it a file, and
    /// `XCUIApplication.open` started a second copy of the app with the user's own library.
    private func launch(fresh: Bool, videoSeconds: Int? = nil, removeMedia: Bool = false) {
        app = XCUIApplication()
        app.launchEnvironment["SHORTS_TEST_RUN"] = run
        app.launchEnvironment["SHORTS_TEST_FRESH"] = fresh ? "1" : "0"
        if let videoSeconds { app.launchEnvironment["SHORTS_TEST_IMPORT"] = String(videoSeconds) }
        if removeMedia { app.launchEnvironment["SHORTS_TEST_REMOVE_MEDIA"] = "1" }
        app.launch()
        // Keys and menus reach only the app in front.
        app.activate()
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 20))
    }

    /// Kills the app as a crash or a power cut would: no chance to save.
    private func forceQuit() {
        for running in NSRunningApplication.runningApplications(withBundleIdentifier: bundleID) { running.forceTerminate() }
        let gone = waitFor(seconds: 10) { NSRunningApplication.runningApplications(withBundleIdentifier: self.bundleID).isEmpty }
        XCTAssertTrue(gone, "The app didn't quit")
    }

    /// Opens the newest Short from All Shorts (the home window).
    private func openFirstShort() {
        let tile = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH 'My Short'")).firstMatch
        XCTAssertTrue(tile.waitForExistence(timeout: 20), "The Short isn't in All Shorts")
        app.activate()
        tile.doubleClick()
    }

    private func waitFor(seconds: TimeInterval = 15, _ condition: @escaping () -> Bool) -> Bool {
        let deadline = Date.now.addingTimeInterval(seconds)
        while Date.now < deadline {
            if condition() { return true }
            RunLoop.current.run(until: Date.now.addingTimeInterval(0.1))
        }
        return condition()
    }
}
