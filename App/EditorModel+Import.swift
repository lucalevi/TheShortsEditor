import AVFoundation
import EditorCore
import RenderEngine
import SwiftUI

/// Adding files: reading them, then putting them in Media and where the user dropped them.
extension EditorModel {
    /// Where imported files go.
    enum ImportDestination: Equatable {
        /// Only into Media.
        case media
        /// Also to the end of the timeline (a song becomes the music).
        case timelineEnd
        /// Also over the clips, starting at this time (videos and pictures).
        case overlay(at: CMTime)
        /// Sound files as sound effects, starting at this time.
        case sound(at: CMTime)
    }

    /// Reads the files, adds the usable ones to Media and, if asked, to the end of the timeline.
    func importFiles(_ urls: [URL], addToTimeline: Bool) {
        importFiles(urls, to: addToTimeline ? .timelineEnd : .media)
    }

    /// Reads the files, adds the usable ones to Media, and puts them where `destination` says.
    func importFiles(
        _ urls: [URL], to destination: ImportDestination, actionName customName: String? = nil,
        then: ((inout Project, [MediaAsset.ID]) -> Void)? = nil
    ) {
        let addToTimeline = destination == .timelineEnd
        // A project file dropped or opened opens that Short instead.
        if let projectFile = urls.first(where: { $0.pathExtension.lowercased() == ProjectFile.fileExtension }) {
            openProject(projectFile)
            return
        }
        guard !urls.isEmpty else { return }
        // Media opened or dropped on the home window starts a new Short with it.
        if screen == .home { newShort() }
        // Files still being read when the user goes back to All Shorts (or opens another Short)
        // belong to the Short they were added to, not to whatever is open by then.
        let shortID = openShortID
        let reading = tasks.start(.importing, title: urls.count == 1 ? "Adding “\(urls[0].lastPathComponent)”" : "Adding \(urls.count) files") {
            [self] progress in
            var probed: [MediaAsset] = []
            var failures: [String] = []
            for (index, url) in urls.enumerated() {
                progress(Double(index) / Double(urls.count))
                // Keep access to files the user handed us while the Short is open.
                media.open(url)
                if let existing = project.assets.first(where: { $0.url.standardizedFileURL == url.standardizedFileURL }) {
                    probed.append(existing)
                    continue
                }
                do {
                    probed.append(try await MediaProbe.probe(url))
                } catch {
                    Log.media.failure("Reading a file to add", error)
                    failures.append(url.lastPathComponent)
                }
            }
            return (probed, failures)
        }
        Task {
            guard let (probed, failures) = try? await reading.value, openShortID == shortID else { return }

            let songs = probed.filter { !$0.hasVideo }
            var overlayIDs: [Clip.ID] = []
            let actionName =
                switch destination {
                case .media: "Import"
                case .timelineEnd: probed.allSatisfy { !$0.hasVideo } ? "Add Music" : "Add to Timeline"
                case .overlay: "Add Over Clips"
                case .sound: "Add Sound"
                }
            apply(customName ?? actionName) { project in
                var importedIDs: [MediaAsset.ID] = []
                defer { then?(&project, importedIDs) }
                var overlayStart: CMTime?
                if case .overlay(let time) = destination { overlayStart = time }
                for asset in probed {
                    let id = project.addAsset(asset)
                    importedIDs.append(id)
                    if addToTimeline, asset.hasVideo { project.appendClip(of: id) }
                    if case .sound(let time) = destination, !asset.hasVideo, let soundID = project.addSound(of: id, at: time) {
                        overlayIDs.append(soundID)
                    }
                    // Several dropped together go one after another.
                    if let start = overlayStart, asset.hasVideo, let overlayID = project.addOverlay(of: id, at: start) {
                        overlayIDs.append(overlayID)
                        overlayStart = project.overlay(id: overlayID)?.end
                    }
                }
                // A sound file dropped on the timeline or viewer becomes the music.
                if addToTimeline, let song = songs.first,
                    let id = project.assets.first(where: { $0.url.standardizedFileURL == song.url.standardizedFileURL })?.id
                {
                    project.setMusic(id)
                }
            }
            if addToTimeline, !songs.isEmpty { selection = .music }
            if overlayIDs.count == 1 {
                if case .sound = destination { selection = .sound(overlayIDs[0]) } else { selection = .overlay(overlayIDs[0]) }
            }
            for asset in probed { loadPreviews(for: asset) }
            if !failures.isEmpty {
                alert = AlertMessage(
                    title: failures.count == 1 ? "This file can't be used" : "These files can't be used",
                    message: failures.joined(separator: "\n") + "\n\nOnly videos, pictures and sound files can be added."
                )
            }
        }
    }
}
