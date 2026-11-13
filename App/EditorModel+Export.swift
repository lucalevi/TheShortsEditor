import AVFoundation
import EditorCore
import ImageIO
import RenderEngine
import SwiftUI
import Transcription

/// Exporting the Short, and removing pauses.
extension EditorModel {
    // MARK: Export

    /// Opens the Export sheet and runs the checks.
    func beginExport() {
        guard !project.timeline.clips.isEmpty, exportPhase == nil else { return }
        player.pause()
        exportPhase = .checking
        let project = project
        exportTask = Task {
            let firstSecond = CMTimeRange(start: .zero, duration: min(CMTime(value: 1, timescale: 1), project.duration))
            let peak: Float?
            do {
                peak = try await AudioProbe.peak(of: project, in: firstSecond)
            } catch {
                peak = 1  // Couldn't measure: skip that check rather than claim silence.
            }
            guard exportPhase == .checking else { return }
            exportPhase = .review(ExportReview.issues(for: project, openingPeak: peak, titleFrames: TitlePreview.frames(in: project), missing: missingAssets))
        }
    }

    /// Writes the Short to `url`, showing progress in the Export sheet.
    func export(to url: URL) {
        let project = project
        exportPhase = .exporting(0)
        exportTask = Task {
            do {
                try await Exporter.export(project, to: url, evenOutLoudness: evensOutLoudness) { fraction in
                    if case .exporting = self.exportPhase { self.exportPhase = .exporting(fraction) }
                }
                exportPhase = .finished(url)
            } catch is CancellationError {
                exportPhase = nil
            } catch {
                exportPhase = .failed(error.localizedDescription)
            }
        }
    }

    /// Stops a running export (removing the partial file) or closes the sheet.
    func endExport() {
        exportTask?.cancel()
        exportTask = nil
        exportPhase = nil
    }

    /// A file name for the export, from the first clip's name.
    var suggestedExportName: String {
        let base = project.timeline.clips.first.flatMap { project.asset(id: $0.assetID)?.name } ?? "My"
        return "\(base) Short.mp4"
    }

    // MARK: Removing pauses

    /// Opens the Remove Pauses panel: measures the sound of the clips (once per file) and plans
    /// the cuts with settings suggested from the sound itself. Nothing changes until `applySilenceRemoval`.
    func beginRemovingSilences() {
        guard silenceSession == nil, !project.timeline.clips.isEmpty else { return }
        player.pause()
        silenceSession = SilenceSession()
        let assets = Dictionary(project.timeline.clips.compactMap { project.asset(id: $0.assetID) }.map { ($0.id, $0) }) { a, _ in a }
        Task {
            for asset in assets.values where asset.hasAudio && audioLevels[asset.id] == nil {
                if let levels = await LevelCache.levels(of: asset.url) {
                    audioLevels[asset.id] = levels
                }
            }
            guard silenceSession != nil else { return }
            var settings = SilenceSettings()
            // Suggest from the file used most on the timeline.
            let main = project.timeline.clips.max { $0.duration < $1.duration }?.assetID
            if let main, let levels = audioLevels[main] { settings.threshold = levels.suggestedThreshold.rounded() }
            silenceSession?.isMeasuring = false
            updateSilenceSettings(settings)
        }
    }

    func updateSilenceSettings(_ settings: SilenceSettings) {
        guard silenceSession != nil else { return }
        silenceSession?.settings = settings
        silenceSession?.plan = SilencePlan.make(for: project, levels: audioLevels, settings: settings)
    }

    func applySilenceRemoval() {
        guard let plan = silenceSession?.plan, !plan.isEmpty else { return }
        silenceSession = nil
        apply("Remove Pauses") { $0.apply(plan) }
    }

    func cancelSilenceRemoval() {
        silenceSession = nil
    }

    /// Plays from the start, skipping the parts that would be cut.
    func previewSilenceRemoval() {
        seek(to: .zero)
        player.play()
    }
}
