import CoreMedia
import Foundation
import Testing
@testable import EditorCore

private func project(seconds: Int64, hasAudio: Bool = true) -> Project {
    var project = Project()
    let asset = MediaAsset(url: URL(fileURLWithPath: "/tmp/a.mov"), name: "a", duration: CMTime(value: seconds, timescale: 1),
                           displaySize: CGSize(width: 1080, height: 1920), hasAudio: hasAudio)
    project.addAsset(asset)
    project.appendClip(of: asset.id)
    return project
}

struct ExportReviewTests {
    private func kinds(_ issues: [ExportIssue]) -> [ExportIssue.Kind] { issues.map(\.kind) }

    @Test func aGoodShortHasOnlyTheCaptionTip() {
        #expect(kinds(ExportReview.issues(for: project(seconds: 30), openingPeak: 0.5)) == [.noCaptions])
    }

    @Test func warningsComeBeforeTips() {
        let issues = ExportReview.issues(for: project(seconds: 200), openingPeak: 0.001)
        #expect(kinds(issues) == [.tooLong, .quietStart, .noCaptions])
    }

    @Test func silentVideoGetsATipNotAWarning() {
        let issues = ExportReview.issues(for: project(seconds: 20, hasAudio: false), openingPeak: nil)
        #expect(kinds(issues) == [.noSound])
    }

    @Test func hiddenCaptionsAreMentioned() {
        var p = project(seconds: 20)
        p.transcripts[p.assets[0].id] = Transcript(language: .english, words: [Word(text: "hi", start: .zero, duration: CMTime(value: 1, timescale: 2))])
        #expect(kinds(ExportReview.issues(for: p, openingPeak: 0.5)).isEmpty)
        p.captions.isVisible = false
        #expect(kinds(ExportReview.issues(for: p, openingPeak: 0.5)) == [.captionsHidden])
    }

    @Test func titleUnderYouTubesInterfaceIsAWarning() {
        var p = project(seconds: 20)
        p.transcripts[p.assets[0].id] = Transcript(language: .english, words: [Word(text: "hi", start: .zero, duration: CMTime(value: 1, timescale: 2))])
        let id = p.addTitle(at: .zero, text: "Hook")
        let clear = CGRect(x: 200, y: 400, width: 600, height: 150)
        #expect(kinds(ExportReview.issues(for: p, openingPeak: 0.5, titleFrames: [id: clear])).isEmpty)
        let underTop = CGRect(x: 200, y: 120, width: 600, height: 150)
        #expect(kinds(ExportReview.issues(for: p, openingPeak: 0.5, titleFrames: [id: underTop])) == [.titleCovered])
        let underBottom = CGRect(x: 200, y: 1400, width: 600, height: 150)
        #expect(kinds(ExportReview.issues(for: p, openingPeak: 0.5, titleFrames: [id: underBottom])) == [.titleCovered])
    }

    @Test func titleAfterTheEndIsMentioned() {
        var p = project(seconds: 20)
        p.titles.append(TextOverlay(text: "Gone", start: CMTime(value: 30, timescale: 1), duration: CMTime(value: 2, timescale: 1)))
        #expect(kinds(ExportReview.issues(for: p, openingPeak: 0.5)) == [.noCaptions, .titleAfterEnd])
    }
}
