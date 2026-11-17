import EditorCore
import RenderEngine
import SwiftUI

/// Following the subject of a horizontal clip, split screen and picture-in-picture.
extension EditorModel {
    // MARK: Following the subject

    /// Makes a horizontal clip vertical by following its subject (a face, or what stands out):
    /// it fills the screen and glides to keep the subject in the middle.
    func followSubject(_ clipID: Clip.ID) {
        guard !tasks.isRunning(kind: .reframe), let clip = project.anyClip(id: clipID), let media = project.asset(id: clip.assetID) else { return }
        playback.player.pause()
        let finding = tasks.start(.reframe(clipID), title: "Finding the subject of “\(media.name)”") { progress in
            try await Reframer.samples(for: clip, media: media) { progress($0) }
        }
        Task {
            do {
                let samples = try await finding.value
                var filled = clip
                filled.framing = .fill
                filled.placement = .identity
                let keyframes = Reframe.keyframes(for: filled, displaySize: media.displaySize, samples: samples)
                guard !keyframes.isEmpty else {
                    alert = AlertMessage(title: "Nothing to follow", message: "This clip already fills the screen across, so there's no room to move.")
                    return
                }
                apply("Follow the Subject") { project in
                    project.updateAnyClip(clipID) { clip in
                        clip.framing = .fill
                        clip.placement = keyframes.count == 1 ? keyframes[0].placement : .identity
                        clip.keyframes = keyframes.count == 1 ? [] : keyframes
                    }
                }
            } catch is CancellationError {
            } catch {
                Log.audio.failure("followSubject", error)
                alert = AlertMessage("The subject couldn't be found", error: error, retry: { self.followSubject(clipID) })
            }
        }
    }

    // MARK: Split screen and picture-in-picture

    func setLayout(_ layout: OverlayLayout, for overlayID: Clip.ID) {
        guard project.overlay(id: overlayID)?.layout != layout else { return }
        apply(layout == .free ? "Full Screen" : "Split Screen") { project in
            project.updateOverlay(overlayID) { overlay in
                overlay.layout = layout
                overlay.clip.framing = .fill
                overlay.clip.placement = .identity
                overlay.clip.keyframes = []
            }
        }
    }

    func putInCorner(_ corner: PictureCorner, overlayID: Clip.ID) {
        guard let overlay = project.overlay(id: overlayID), let media = project.asset(id: overlay.clip.assetID) else { return }
        let placement = Placement.pictureInPicture(corner, displaySize: media.displaySize, framing: overlay.clip.framing)
        apply("Picture in Picture") { project in
            project.updateOverlay(overlayID) { overlay in
                overlay.layout = .free
                overlay.clip.placement = placement
                overlay.clip.keyframes = []
            }
        }
    }
}
