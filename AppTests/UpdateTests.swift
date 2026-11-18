import Foundation
import Testing

@testable import Shorts_Editor

/// Check for Updates… (F32): versions compare as numbers, and only a newer release is offered.
@MainActor
struct UpdateTests {
    @Test func versionsCompareAsNumbersNotText() throws {
        #expect(try #require(Version("v0.10.0")) > #require(Version("0.9.3")))
        #expect(try #require(Version("1.0")) == #require(Version("1.0.0")))
        #expect(try #require(Version("V2.0.0-beta")) == #require(Version("2.0.0")))
        #expect(Version("1.2.3")?.description == "1.2.3")
        for bad in ["", "v", "1.2.3.4", "1..2", "one", "1.-2.0"] { #expect(Version(bad) == nil, "\(bad)") }
    }

    @Test func onlyANewerReleaseIsOffered() {
        let page = URL(string: "https://github.com/lucalevi/TheShortsEditor/releases/tag/v0.2.0")!
        let release = UpdateChecker.Release(tagName: "v0.2.0", htmlURL: page)
        #expect(UpdateChecker.outcome(of: release, current: "0.1.0") == .newer(version: "0.2.0", page: page))
        #expect(UpdateChecker.outcome(of: release, current: "0.2.0") == .upToDate)
        // A build of unreleased code is newer than the newest release.
        #expect(UpdateChecker.outcome(of: release, current: "0.3.0") == .upToDate)
        #expect(UpdateChecker.outcome(of: nil, current: "0.1.0") == .noRelease)
        // A tag that isn't a version is never offered.
        #expect(UpdateChecker.outcome(of: .init(tagName: "nightly", htmlURL: page), current: "0.1.0") == .upToDate)
    }

    @Test func gitHubsAnswerIsRead() throws {
        let json = #"{"tag_name":"v1.4.0","html_url":"https://github.com/x/y/releases/tag/v1.4.0","name":"Shorts Editor 1.4.0","assets":[]}"#
        let release = try JSONDecoder().decode(UpdateChecker.Release.self, from: Data(json.utf8))
        #expect(release.tagName == "v1.4.0")
        #expect(release.htmlURL.lastPathComponent == "v1.4.0")
    }

    @Test func theAppSaysItsOwnVersion() {
        #expect(Version(UpdateChecker.currentVersion) != nil)
    }
}
