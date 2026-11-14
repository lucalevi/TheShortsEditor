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
                Log.export.failure("beginExport", error)
                peak = 1 // Couldn't measure: skip that check rather than claim silence.
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
                Log.export.failure("export", error)
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

    /// A file name for the export: the Short's name, as in All Shorts (like Save Frame and the
    /// subtitle file).
    var suggestedExportName: String {
        let name = openShortName.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: .whitespaces)
        return "\(name.isEmpty ? "My Short" : name).mp4"
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
        guard let session = silenceSession else { return }
        silenceSession?.settings = settings
        silenceSession?.plan = SilencePlan.make(for: project, levels: session.listensToVoiceOnly ? pauseVoiceLevels : audioLevels, settings: settings)
    }

    /// The levels of the clips' voices alone, for finding pauses under music or noise: each file
    /// is cleaned once with Apple's voice isolation (kept in Caches, the same copy as Clean Up
    /// Voice) and measured. A file that can't be cleaned keeps its own levels.
    var pauseVoiceLevels: [MediaAsset.ID: AudioLevels] {
        audioLevels.merging(voiceLevels) { _, voice in voice }
    }

    /// Finds pauses in the voice alone, or in the whole sound again.
    func setPausesListenToVoiceOnly(_ on: Bool) {
        guard silenceSession != nil, silenceSession?.separating == nil else { return }
        silenceSession?.listensToVoiceOnly = on
        guard on else {
            suggestPauseSettings(from: audioLevels)
            return
        }
        let assets = Dictionary(project.timeline.clips.compactMap { project.asset(id: $0.assetID) }.filter(\.hasAudio).map { ($0.id, $0) }) { a, _ in a }
        let missing = assets.values.filter { voiceLevels[$0.id] == nil }
        guard !missing.isEmpty else {
            suggestPauseSettings(from: pauseVoiceLevels)
            return
        }
        silenceSession?.separating = 0
        Task {
            for (number, asset) in missing.enumerated() {
                do {
                    let cleaned = try await VoiceCleaner.clean(asset.url) { fraction in
                        Task { @MainActor in
                            if self.silenceSession?.separating != nil {
                                self.silenceSession?.separating = (Double(number) + fraction) / Double(missing.count)
                            }
                        }
                    }
                    if let levels = await LevelCache.levels(of: cleaned) { voiceLevels[asset.id] = levels }
                } catch {
                    Log.audio.failure("setPausesListenToVoiceOnly", error)
                    // That file keeps its own levels.
                }
                guard silenceSession != nil else { return }
            }
            silenceSession?.separating = nil
            suggestPauseSettings(from: pauseVoiceLevels)
        }
    }

    /// Suggests what counts as a pause from the file used most on the timeline, keeping the
    /// user's other choices.
    private func suggestPauseSettings(from levels: [MediaAsset.ID: AudioLevels]) {
        guard var settings = silenceSession?.settings else { return }
        let main = project.timeline.clips.max { $0.duration < $1.duration }?.assetID
        if let main, let mainLevels = levels[main] { settings.threshold = mainLevels.suggestedThreshold.rounded() }
        updateSilenceSettings(settings)
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
