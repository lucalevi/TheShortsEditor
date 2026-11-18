import AppKit
import EditorCore
import Foundation

/// Shorts Editor ▸ Check for Updates… (F32, ADR 0011). The app is shared as a `.dmg` on GitHub
/// Releases, without a Developer ID, so updates are announced, not installed: this asks GitHub for
/// the newest release and, when it is newer than this copy, offers to open its page. It only runs
/// when the user chooses it; the app never checks by itself. The request carries nothing about the
/// user (a generic User-Agent, which GitHub requires).
@Observable
final class UpdateChecker {
    static let shared = UpdateChecker()

    static let latestRelease = URL(string: "https://api.github.com/repos/lucalevi/TheShortsEditor/releases/latest")!
    static let releasesPage = URL(string: "https://github.com/lucalevi/TheShortsEditor/releases")!

    /// True while asking GitHub (the menu item is disabled meanwhile).
    private(set) var isChecking = false

    /// This copy's version (`CFBundleShortVersionString`).
    static var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
    }

    /// The newest release as GitHub describes it (only the fields used).
    struct Release: Decodable, Equatable {
        var tagName: String
        var htmlURL: URL

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case htmlURL = "html_url"
        }
    }

    /// What the check found.
    enum Outcome: Equatable {
        /// This copy is the newest (or newer: a build of unreleased code).
        case upToDate
        /// A newer version, and the page to download it from.
        case newer(version: String, page: URL)
        /// Nothing has been published yet.
        case noRelease
    }

    /// Compares GitHub's newest release with this copy's version.
    static func outcome(of release: Release?, current: String) -> Outcome {
        guard let release else { return .noRelease }
        guard let latest = Version(release.tagName), let mine = Version(current), latest > mine else { return .upToDate }
        return .newer(version: latest.description, page: release.htmlURL)
    }

    /// Asks GitHub for the newest release; nil when none is published (GitHub answers 404).
    static func latest(session: URLSession = .shared) async throws -> Release? {
        var request = URLRequest(url: latestRelease, timeoutInterval: 15)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Shorts-Editor", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 404 { return nil }
        guard (200..<300).contains(status) else { throw URLError(.badServerResponse) }
        return try JSONDecoder().decode(Release.self, from: data)
    }

    /// The menu item: checks, then says what was found.
    func check() {
        guard !isChecking else { return }
        isChecking = true
        Task {
            defer { isChecking = false }
            do {
                let outcome = Self.outcome(of: try await Self.latest(), current: Self.currentVersion)
                Log.updates.info("Checked for updates: \(String(describing: outcome), privacy: .public)")
                show(outcome)
            } catch {
                Log.updates.failure("Checking for updates", error)
                showFailure(error)
            }
        }
    }

    private func show(_ outcome: Outcome) {
        let alert = NSAlert()
        switch outcome {
        case .newer(let version, let page):
            alert.messageText = "Shorts Editor \(version) is available"
            alert.informativeText =
                "You have version \(Self.currentVersion). Download the new .dmg from its page and drag the app to "
                + "Applications again, as the first time; your Shorts stay as they are."
            alert.addButton(withTitle: "Open Download Page")
            alert.addButton(withTitle: "Later")
            if alert.runModal() == .alertFirstButtonReturn { NSWorkspace.shared.open(page) }
        case .upToDate, .noRelease:
            alert.messageText = "Shorts Editor is up to date"
            alert.informativeText = "Version \(Self.currentVersion) is the newest."
            alert.addButton(withTitle: "OK")
            alert.runModal()
        }
    }

    private func showFailure(_ error: any Error) {
        let alert = NSAlert()
        alert.messageText = "Couldn't check for updates"
        alert.informativeText = "\(error.localizedDescription)\n\nCheck your internet connection, or look at the releases page yourself."
        alert.addButton(withTitle: "Try Again")
        alert.addButton(withTitle: "Open Releases Page")
        alert.addButton(withTitle: "Cancel")
        switch alert.runModal() {
        case .alertFirstButtonReturn: check()
        case .alertSecondButtonReturn: NSWorkspace.shared.open(Self.releasesPage)
        default: break
        }
    }
}

/// A semantic version, major.minor.patch, as in tags ("v1.2.0") and `CFBundleShortVersionString`.
/// A missing part counts as 0 ("1.2" is 1.2.0); anything after a "-" (a pre-release) is ignored.
struct Version: Comparable, CustomStringConvertible, Sendable {
    var parts: [Int]

    init?(_ text: String) {
        var text = Substring(text.trimmingCharacters(in: .whitespaces))
        if text.first == "v" || text.first == "V" { text = text.dropFirst() }
        let core = text.split(separator: "-", maxSplits: 1).first ?? ""
        let numbers = core.split(separator: ".", omittingEmptySubsequences: false).map { Int($0) }
        guard (1...3).contains(numbers.count), numbers.allSatisfy({ ($0 ?? -1) >= 0 }) else { return nil }
        parts = numbers.compactMap(\.self) + Array(repeating: 0, count: 3 - numbers.count)
    }

    var description: String { parts.map(String.init).joined(separator: ".") }

    static func < (a: Version, b: Version) -> Bool { a.parts.lexicographicallyPrecedes(b.parts) }
}
