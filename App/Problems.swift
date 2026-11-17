import AVFoundation
import AppKit
import EditorCore
import SwiftUI

/// What kind of trouble an error is, so the app can offer the way out (F22) instead of only
/// showing its text.
enum ProblemKind: Equatable {
    /// The disk is full: free up space (Settings ▸ Storage lists what the app can remove).
    case diskFull
    /// A file isn't where it was: find it.
    case fileMissing
    /// The app may not read or write there (the sandbox, or the file's own permissions).
    case noPermission
    /// The microphone, camera or Photos library was refused in System Settings.
    case privacy(PrivacyPane)
    /// Anything else: trying again may help.
    case other

    enum PrivacyPane: String {
        case microphone = "Privacy_Microphone"
        case photos = "Privacy_Photos"

        var settingsURL: URL {
            URL(string: "x-apple.systempreferences:com.apple.preference.security?\(rawValue)")!
        }
    }

    init(_ error: any Error) {
        self = Self.kind(of: error as NSError, depth: 0)
    }

    private static func kind(of error: NSError, depth: Int) -> ProblemKind {
        switch (error.domain, error.code) {
        case (NSCocoaErrorDomain, NSFileWriteOutOfSpaceError), (NSPOSIXErrorDomain, Int(ENOSPC)), (AVFoundationErrorDomain, AVError.diskFull.rawValue):
            return .diskFull
        case (NSCocoaErrorDomain, NSFileReadNoSuchFileError), (NSCocoaErrorDomain, NSFileNoSuchFileError), (NSPOSIXErrorDomain, Int(ENOENT)),
            (NSURLErrorDomain, NSURLErrorFileDoesNotExist):
            return .fileMissing
        case (NSCocoaErrorDomain, NSFileReadNoPermissionError), (NSCocoaErrorDomain, NSFileWriteNoPermissionError), (NSPOSIXErrorDomain, Int(EPERM)),
            (NSPOSIXErrorDomain, Int(EACCES)), (NSURLErrorDomain, NSURLErrorNoPermissionsToReadFile):
            return .noPermission
        default:
            // Foundation and AVFoundation often wrap the error that says what really happened.
            if depth < 4, let underlying = error.userInfo[NSUnderlyingErrorKey] as? NSError {
                return kind(of: underlying, depth: depth + 1)
            }
            return .other
        }
    }

    /// What to tell the user to do, when the error itself doesn't say.
    var suggestion: String? {
        switch self {
        case .diskFull: "Your Mac's disk is full. Free up some space and try again."
        case .fileMissing: "The file may have been moved, renamed or deleted."
        case .noPermission: "Shorts Editor isn't allowed to use that place. Choose the file or folder again, or pick another one."
        case .privacy(.microphone): "Allow Shorts Editor to use the microphone in System Settings ▸ Privacy & Security."
        case .privacy(.photos): "Allow Shorts Editor to use your photos in System Settings ▸ Privacy & Security."
        case .other: nil
        }
    }
}

/// A problem shown to the user: what went wrong, why, and buttons for what can be done about it.
struct AlertMessage: Identifiable {
    let id = UUID()
    let title: String
    let message: String
    var kind: ProblemKind = .other
    /// Runs the failed work again; offered when it may now work.
    var retry: (@MainActor () -> Void)?

    init(title: String, message: String, kind: ProblemKind = .other, retry: (@MainActor () -> Void)? = nil) {
        self.title = title
        self.message = message
        self.kind = kind
        self.retry = retry
    }

    /// A problem from an error: its text and the error's own suggestion (or one for its kind), with
    /// "Try Again" when `retry` is given and trying again can help.
    init(_ title: String, error: any Error, kind: ProblemKind? = nil, retry: (@MainActor () -> Void)? = nil) {
        let kind = kind ?? ProblemKind(error)
        self.title = title
        let suggestion = (error as? LocalizedError)?.recoverySuggestion ?? (error as NSError).localizedRecoverySuggestion ?? kind.suggestion
        message = [error.localizedDescription, suggestion].compactMap(\.self).joined(separator: "\n\n")
        self.kind = kind
        // Missing files and refusals don't go away by trying again: their own button comes first.
        self.retry = kind == .other || kind == .diskFull ? retry : nil
    }
}

/// The buttons of a problem's alert, by its kind.
struct ProblemActions: View {
    let problem: AlertMessage
    let model: EditorModel
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        switch problem.kind {
        case .diskFull:
            Button("Free Up Space…") { openSettings() }
        case .fileMissing where !model.missingAssets.isEmpty:
            Button("Find Missing Files…") { model.findMissingFiles() }
        case .privacy(let pane):
            Button("Open System Settings") { NSWorkspace.shared.open(pane.settingsURL) }
        default:
            EmptyView()
        }
        if let retry = problem.retry {
            Button("Try Again") { retry() }
        }
        Button("OK", role: .cancel) {}
    }
}

extension EditorModel {
    /// Why an export failed, and where it was going (for Try Again).
    struct ExportFailure: Equatable {
        let message: String
        let kind: ProblemKind
        let url: URL
    }
}
