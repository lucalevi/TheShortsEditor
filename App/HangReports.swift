import EditorCore
import Foundation
import MetricKit

/// Hangs the app had on this Mac, as macOS reports them (MetricKit, F12): each report is logged
/// (`Log.performance`) and kept in `Diagnostics/` in the app's folder, the newest `kept` of them,
/// for Help ▸ Report a Problem (Phase 8). macOS delivers them some time after they happen,
/// usually the next day or the next launch.
final class HangReports: NSObject, MXMetricManagerSubscriber {
    static let shared = HangReports()
    nonisolated static let kept = 20

    nonisolated static var folder: URL { AppEnvironment.appFolder.appending(path: "Diagnostics", directoryHint: .isDirectory) }

    /// Starts listening; called once at launch. Not under tests, whose runs shouldn't add reports.
    func start() {
        guard !AppEnvironment.isTesting else { return }
        MXMetricManager.shared.add(self)
    }

    nonisolated func didReceive(_ payloads: [MXDiagnosticPayload]) {
        for payload in payloads {
            let hangs = payload.hangDiagnostics ?? []
            for hang in hangs {
                let duration = hang.hangDuration.converted(to: .milliseconds).value
                Log.performance.error("The app hung for \(Int(duration), privacy: .public) ms (version \(hang.applicationVersion, privacy: .public))")
            }
            let crashes = payload.crashDiagnostics?.count ?? 0
            if crashes > 0 { Log.performance.error("macOS reported \(crashes, privacy: .public) crash(es)") }
            guard !hangs.isEmpty || crashes > 0 else { continue }
            Self.keep(payload.jsonRepresentation(), named: payload.timeStampEnd)
        }
    }

    /// Saves one report and removes the oldest beyond `kept`.
    nonisolated static func keep(_ report: Data, named date: Date, in folder: URL = folder) {
        let manager = FileManager.default
        Log.performance.attempt("Keeping a hang report") {
            try manager.createDirectory(at: folder, withIntermediateDirectories: true)
            let name = date.formatted(.iso8601).replacingOccurrences(of: ":", with: "-")
            try ProjectStore.safelyWrite(report, to: folder.appending(path: "\(name).json"))
            let reports = try manager.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
                .filter { $0.pathExtension == "json" }
                .sorted { $0.lastPathComponent > $1.lastPathComponent }
            for old in reports.dropFirst(kept) { try manager.removeItem(at: old) }
        }
    }
}
