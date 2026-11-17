import AVFoundation
import Foundation
import Testing

@testable import Shorts_Editor

/// Errors are shown with what can be done about them (F22): the kind of trouble decides the buttons.
@MainActor
struct ProblemTests {
    @Test func aFullDiskIsRecognisedEvenWhenWrapped() {
        let posix = NSError(domain: NSPOSIXErrorDomain, code: Int(ENOSPC))
        #expect(ProblemKind(posix) == .diskFull)
        #expect(ProblemKind(CocoaError(.fileWriteOutOfSpace)) == .diskFull)
        #expect(ProblemKind(NSError(domain: AVFoundationErrorDomain, code: AVError.diskFull.rawValue)) == .diskFull)
        // AVFoundation often hides the real cause one level down.
        let wrapped = NSError(domain: AVFoundationErrorDomain, code: AVError.unknown.rawValue, userInfo: [NSUnderlyingErrorKey: posix])
        #expect(ProblemKind(wrapped) == .diskFull)
    }

    @Test func missingFilesAndRefusalsAreRecognised() {
        #expect(ProblemKind(CocoaError(.fileReadNoSuchFile)) == .fileMissing)
        #expect(ProblemKind(NSError(domain: NSPOSIXErrorDomain, code: Int(ENOENT))) == .fileMissing)
        #expect(ProblemKind(CocoaError(.fileWriteNoPermission)) == .noPermission)
        #expect(ProblemKind(NSError(domain: NSPOSIXErrorDomain, code: Int(EACCES))) == .noPermission)
        #expect(ProblemKind(CancellationError()) == .other)
    }

    @Test func theMessageSaysWhatToDoAndTryAgainOnlyWhenItCanHelp() {
        var retried = false
        // A POSIX error says nothing about what to do: the kind's own suggestion is added.
        let full = AlertMessage("The export failed", error: NSError(domain: NSPOSIXErrorDomain, code: Int(ENOSPC)), retry: { retried = true })
        #expect(full.kind == .diskFull)
        #expect(full.message.contains("Free up some space"))
        // Foundation's errors bring their own suggestion, which is used instead.
        let cocoa = AlertMessage("The export failed", error: CocoaError(.fileWriteOutOfSpace))
        #expect(cocoa.message.contains("\n\n"))
        full.retry?()
        #expect(retried)

        // A missing file doesn't come back by trying again: no Try Again, its own button instead.
        let missing = AlertMessage("This Short can't be opened", error: CocoaError(.fileReadNoSuchFile), retry: {})
        #expect(missing.retry == nil)
        #expect(missing.message.contains("moved, renamed or deleted"))
    }

    @Test func anErrorsOwnSuggestionComesFirst() {
        struct Damaged: LocalizedError {
            var errorDescription: String? { "The file is damaged." }
            var recoverySuggestion: String? { "Open a backup with File ▸ Revert To." }
        }
        let problem = AlertMessage("This Short can't be opened", error: Damaged())
        #expect(problem.message == "The file is damaged.\n\nOpen a backup with File ▸ Revert To.")
    }
}
