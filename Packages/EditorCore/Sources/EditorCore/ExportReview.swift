import Foundation

/// Something worth knowing before exporting a Short.
public struct ExportIssue: Identifiable, Equatable, Sendable {
    public enum Kind: String, Sendable {
        case tooLong, quietStart, noSound, noCaptions, captionsHidden
    }

    public enum Severity: Sendable {
        /// Likely to hurt the Short: shown first, in orange.
        case warning
        /// A suggestion.
        case tip
    }

    public let kind: Kind
    public let severity: Severity
    public let title: String
    public let detail: String
    public var id: Kind { kind }
}

/// The checks run before export. None of them blocks exporting: the user decides.
public enum ExportReview {
    /// Below this peak level (about −40 dBFS) the opening counts as silent.
    public static let silenceThreshold: Float = 0.01

    /// `openingPeak` is the loudest sample in the first second (0…1), or nil when the Short has
    /// no sound at all.
    public static func issues(for project: Project, openingPeak: Float?) -> [ExportIssue] {
        var issues: [ExportIssue] = []
        if project.isOverMaxDuration {
            issues.append(ExportIssue(
                kind: .tooLong, severity: .warning,
                title: "Longer than 3:00",
                detail: "YouTube will post it as a regular video, not a Short. Trim it to 3:00 or less."
            ))
        }
        if let openingPeak {
            if openingPeak < silenceThreshold {
                issues.append(ExportIssue(
                    kind: .quietStart, severity: .warning,
                    title: "The first second is silent",
                    detail: "Viewers decide in a moment. Start with someone talking or with sound, and cut any quiet intro."
                ))
            }
        } else {
            issues.append(ExportIssue(
                kind: .noSound, severity: .tip,
                title: "No sound",
                detail: "Your Short has no sound. That's fine if it's meant to be watched in silence."
            ))
        }
        let hasSpeechSource = project.timeline.clips.contains { project.asset(id: $0.assetID)?.hasAudio == true }
        if !project.hasCaptions, hasSpeechSource {
            issues.append(ExportIssue(
                kind: .noCaptions, severity: .tip,
                title: "No captions",
                detail: "Many people watch Shorts with the sound off. Captions keep them watching."
            ))
        } else if project.hasCaptions, !project.captions.isVisible {
            issues.append(ExportIssue(
                kind: .captionsHidden, severity: .tip,
                title: "Captions are hidden",
                detail: "Your captions won't be in the video. Turn on “Show captions” to include them."
            ))
        }
        return issues.sorted { $0.severity == .warning && $1.severity == .tip }
    }
}
