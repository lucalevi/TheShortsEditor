import AVFoundation
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
    private var folder: URL!

    /// Called first by every test: a folder for its files, and the app quit and the folder gone at the end.
    private func begin() throws {
        continueAfterFailure = false
        folder = FileManager.default.temporaryDirectory.appending(path: "AppUITests-\(run)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let folder = folder!
        addTeardownBlock { @MainActor [weak self] in
            self?.app?.terminate()
            try? FileManager.default.removeItem(at: folder)
        }
    }

    // MARK: The paths

    func testAddEditUndoRedoAndExport() throws {
        try begin()
        launch(fresh: true)
        app.open(try makeVideo(seconds: 3))
        let clips = timelineClips
        XCTAssertTrue(clips.firstMatch.waitForExistence(timeout: 30), "The video never reached the timeline")
        XCTAssertEqual(clips.count, 1)

        // A second in (30 frames), then split.
        for _ in 0..<30 { app.typeKey(.rightArrow, modifierFlags: []) }
        app.menuItems["Split at Playhead"].click()
        XCTAssertTrue(waitFor { clips.count == 2 }, "Split at Playhead didn't make two clips")

        app.menuItems["Undo Split Clip"].click()
        XCTAssertTrue(waitFor { clips.count == 1 }, "Undo didn't put the clip back together")
        app.menuItems["Redo Split Clip"].click()
        XCTAssertTrue(waitFor { clips.count == 2 }, "Redo didn't split it again")

        // Export. Under UI tests the app skips the save panel (a system service the tests can't
        // reach) and writes into its test run's own folder; the file itself is checked by
        // ExportTests (AppTests) and ExporterTests.
        app.menuItems["Export Short…"].click()
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
        launch(fresh: true)
        app.open(try makeVideo(seconds: 3))
        XCTAssertTrue(timelineClips.firstMatch.waitForExistence(timeout: 30))
        for _ in 0..<30 { app.typeKey(.rightArrow, modifierFlags: []) }
        app.menuItems["Split at Playhead"].click()
        XCTAssertTrue(waitFor { self.timelineClips.count == 2 })
        // Autosave comes a second after the edit.
        Thread.sleep(forTimeInterval: 3)
        forceQuit()

        launch(fresh: false)
        openFirstShort()
        XCTAssertTrue(waitFor { self.timelineClips.count == 2 }, "The split was lost in the forced quit")
    }

    func testAShortWithMissingMediaOpensAndSaysSo() throws {
        try begin()
        launch(fresh: true)
        let video = try makeVideo(seconds: 2)
        app.open(video)
        XCTAssertTrue(timelineClips.firstMatch.waitForExistence(timeout: 30))
        app.menuItems["All Shorts"].click()
        app.terminate()

        try FileManager.default.removeItem(at: video)
        launch(fresh: false)
        openFirstShort()
        XCTAssertTrue(app.staticTexts["A file can't be found"].waitForExistence(timeout: 20), "No word about the missing file")
        XCTAssertEqual(timelineClips.count, 1, "The clip of the missing file should stay on the timeline")
        XCTAssertTrue(app.buttons["Find Missing Files…"].exists)
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
        app.open(try makeVideo(seconds: 2))
        XCTAssertTrue(timelineClips.firstMatch.waitForExistence(timeout: 30))
        try app.performAccessibilityAudit(for: audits)
    }

    // MARK: Helpers

    private var timelineClips: XCUIElementQuery {
        app.descendants(matching: .any).matching(identifier: "timeline.clip")
    }

    private func launch(fresh: Bool) {
        app = XCUIApplication()
        app.launchEnvironment["SHORTS_TEST_RUN"] = run
        app.launchEnvironment["SHORTS_TEST_FRESH"] = fresh ? "1" : "0"
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

    /// A portrait test video (silent, one colour), written into this test's folder.
    private func makeVideo(seconds: Int) throws -> URL {
        let url = folder.appending(path: "clip-\(UUID().uuidString.prefix(6)).mov")
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let input = AVAssetWriterInput(
            mediaType: .video, outputSettings: [AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: 180, AVVideoHeightKey: 320])
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: nil)
        writer.add(input)
        XCTAssertTrue(writer.startWriting())
        writer.startSession(atSourceTime: .zero)
        var buffer: CVPixelBuffer?
        CVPixelBufferCreate(kCFAllocatorDefault, 180, 320, kCVPixelFormatType_32BGRA, nil, &buffer)
        let picture = try XCTUnwrap(buffer)
        CVPixelBufferLockBaseAddress(picture, [])
        memset(CVPixelBufferGetBaseAddress(picture), 0x80, CVPixelBufferGetDataSize(picture))
        CVPixelBufferUnlockBaseAddress(picture, [])
        for frame in 0..<(30 * seconds) {
            while !input.isReadyForMoreMediaData { RunLoop.current.run(until: Date.now.addingTimeInterval(0.005)) }
            XCTAssertTrue(adaptor.append(picture, withPresentationTime: CMTime(value: Int64(frame), timescale: 30)))
        }
        input.markAsFinished()
        let finished = expectation(description: "written")
        writer.finishWriting { finished.fulfill() }
        wait(for: [finished], timeout: 30)
        XCTAssertEqual(writer.status, .completed)
        return url
    }
}
