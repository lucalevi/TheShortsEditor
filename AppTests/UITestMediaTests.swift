@preconcurrency import AVFoundation
import Foundation
import Testing

@testable import Shorts_Editor

/// The UI tests rely on the app making their video itself (`UITestMedia`); this checks that video
/// and that the hooks stay off outside a UI test run.
@Suite struct UITestMediaTests {
    @Test func theVideoIsAPortraitClipOfTheAskedLength() async throws {
        let url = try await UITestMedia.makeVideo(seconds: 2, in: TestMedia.folder)
        defer { try? FileManager.default.removeItem(at: url) }
        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration)
        #expect(duration == CMTime(value: 2, timescale: 1))
        let track = try #require(try await asset.loadTracks(withMediaType: .video).first)
        let size = try await track.load(.naturalSize)
        #expect(size == CGSize(width: 180, height: 320))
    }

    @Test func theHooksAreOffOutsideAUITestRun() {
        // The app tests run without SHORTS_TEST_RUN.
        #expect(UITestMedia.secondsToImport == nil)
        #expect(!UITestMedia.removesMedia)
    }
}
