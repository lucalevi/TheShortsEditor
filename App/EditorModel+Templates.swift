import AppKit
import EditorCore
import RenderEngine
import SwiftUI
import Transcription

/// Stage L: templates, the best moments for Magic Short, and the cover.
extension EditorModel {
    // MARK: Templates

    /// Chooses clips for `template`, then makes a new Short from them, cut to the beat of the
    /// template's music. The shots can then be swapped in the Shots panel.
    func newShort(fromTemplate template: ShortTemplate) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.movie, .image]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.prompt = "Fill \(template.displayName)"
        panel.message = "Choose up to \(template.shots.count) clips or pictures. They play in the order they were filmed; swap any shot afterwards. Fewer is fine: they are used again."
        guard panel.runModal() == .OK, !panel.urls.isEmpty else { return }
        choosesTemplate = false
        let urls = Array(Self.inFilmingOrder(panel.urls).prefix(template.shots.count))
        Task {
            // The music first, so the Short comes in one step with its beat.
            let music = await styleMusic(template.style.music)
            if !(screen == .editor && project.timeline.clips.isEmpty) { newShort() }
            importFiles(urls, to: .media, actionName: "Fill \(template.displayName)") { [weak self] project, ids in
                let order = urls.compactMap { url in project.assets.first { $0.url.standardizedFileURL == url.standardizedFileURL }?.id }
                project.fillTemplate(template, with: order.isEmpty ? ids : order)
                project.applyStyle(template.style, music: music)
                // The style's motion is the style's, not the user's (see `apply`); back to normal after this edit.
                self?.isRestyling = true
                Task { @MainActor in self?.isRestyling = false }
            }
            if let music { loadPreviewsIfNeeded(music) }
            sidebar = .storyboard
        }
    }

    /// Files chosen together, in the order they were made (filmed or taken), oldest first; by name
    /// when that is the same. An Open panel gives its own order, not the order of the clicks.
    static func inFilmingOrder(_ urls: [URL]) -> [URL] {
        func made(_ url: URL) -> Date {
            let values = try? url.resourceValues(forKeys: [.creationDateKey, .contentModificationDateKey])
            return values?.creationDate ?? values?.contentModificationDate ?? .distantFuture
        }
        let dates = Dictionary(urls.map { ($0, made($0)) }, uniquingKeysWith: { first, _ in first })
        return urls.sorted { a, b in
            let da = dates[a] ?? .distantFuture, db = dates[b] ?? .distantFuture
            if da != db { return da < db }
            return a.lastPathComponent.localizedStandardCompare(b.lastPathComponent) == .orderedAscending
        }
    }

    // MARK: Best moments

    /// For Magic Short cut to a length: picks the sentences to keep, with Apple's on-device
    /// model when it can, else by the rules. Nil when there is nothing to choose.
    func bestMoments(in trial: Project, options: MagicOptions, levels: [MediaAsset.ID: AudioLevels],
                     language: CaptionLanguage) async -> (kept: Set<Word.ID>, byModel: Bool)? {
        let sentences = trial.magicSentences(options, levels: levels)
        guard !sentences.isEmpty else { return nil }
        // A little room for the pauses left between sentences and the ending.
        let target = options.length.target.seconds * 0.92
        var picks: [Int]?
        if WordModel.isAvailable(for: language) {
            picks = try? await WordModel.bestMoments(sentences, target: target, language: language)
        }
        let chosen = picks ?? MomentPicker.bestRun(sentences, target: target)
        return (Set(chosen.map { sentences[$0].firstWordID }), picks != nil)
    }

    // MARK: Cover

    /// Opens the cover sheet, starting from the Short's cover or a suggested one.
    func beginCover() {
        guard !project.timeline.clips.isEmpty else { return }
        player.pause()
        coverDraft = project.cover ?? project.suggestedCover
    }

    /// Keeps the cover with the Short (it is also its picture in the home window).
    func keepCover(_ cover: ShortCover) {
        guard cover != project.cover else { return }
        apply("Cover") { $0.cover = cover }
    }

    /// Saves the cover as a 1080 × 1920 JPEG where the user says.
    func saveCover(_ cover: ShortCover) {
        keepCover(cover)
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.jpeg]
        panel.nameFieldStringValue = suggestedExportName.replacingOccurrences(of: ".mp4", with: "") + " cover.jpg"
        panel.canCreateDirectories = true
        panel.message = "Upload this picture to YouTube as the Short's thumbnail."
        panel.prompt = "Save Cover"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let project = project
        Task {
            do {
                let image = try await ProjectPoster.cover(of: project, cover)
                try FrameExport.write(image, to: url, format: .jpeg)
            } catch {
                alert = AlertMessage(title: "The cover couldn't be saved", message: error.localizedDescription)
            }
        }
    }
}
