import AVFoundation
import EditorCore
import RenderEngine
import SwiftUI

/// Cut-outs (Stage K): Remove Background, green screen, masks, blend modes and the colour
/// behind a picture.
extension EditorModel {
    // MARK: Remove Background

    /// Whether a clip's background can be removed: a picture or a video (not a sound).
    func canCutOut(_ clip: Clip) -> Bool {
        project.asset(id: clip.assetID)?.hasVideo == true
    }

    /// Keeps only `subject` of the clips (nil: shows the whole picture again). The see-through
    /// copy is made in the background; until then the clips show their whole picture.
    func setRemoveBackground(_ subject: CutoutSubject?, for clipIDs: [Clip.ID]) {
        apply(subject == nil ? "Show Background" : "Remove Background") { project in
            for id in clipIDs { project.updateCutout(of: id) { $0.removeBackground = subject } }
        }
    }

    /// The key under which a file's copy is being made.
    func cutoutJob(_ assetID: MediaAsset.ID, _ subject: CutoutSubject) -> String { "\(assetID.uuidString)|\(subject.rawValue)" }

    /// How far the see-through copy for `clip` has got (0…1), while it is being made.
    func cutoutProgress(of clip: Clip) -> Double? {
        guard let subject = clip.cutout.removeBackground else { return nil }
        return cuttingOut[cutoutJob(clip.assetID, subject)]
    }

    /// Makes the see-through copy of every file a clip removes the background of that hasn't
    /// been made yet (in the background, with progress in the inspector), then rebuilds.
    func prepareMissingCutouts() {
        let clips = project.timeline.clips + project.overlays.map(\.clip)
        var needed: [String: (url: URL, subject: CutoutSubject, isImage: Bool)] = [:]
        for clip in clips {
            guard let subject = clip.cutout.removeBackground, let media = project.asset(id: clip.assetID), media.hasVideo,
                  !missingAssets.contains(media.id) else { continue }
            let job = cutoutJob(media.id, subject)
            guard cuttingOut[job] == nil, !uncuttable.contains(job),
                  CutoutCache.existingCopy(of: media.url, subject: subject, isImage: media.isImage) == nil else { continue }
            needed[job] = (media.url, subject, media.isImage)
        }
        guard !needed.isEmpty else { return }
        for job in needed.keys { cuttingOut[job] = 0 }
        Task {
            for (job, item) in needed {
                do {
                    _ = try await CutoutCache.make(item.url, subject: item.subject, isImage: item.isImage) { fraction in
                        Task { @MainActor in if self.cuttingOut[job] != nil { self.cuttingOut[job] = fraction } }
                    }
                } catch is CancellationError {
                } catch {
                    uncuttable.insert(job)
                    alert = AlertMessage(title: "The background couldn't be removed", message: error.localizedDescription)
                }
                cuttingOut[job] = nil
            }
            refreshPlayback()
        }
    }

    // MARK: Green screen

    /// Turns the green screen on for a clip, with the screen's colour found in its picture (or
    /// green when no strong colour stands out), or off.
    func setColorKey(_ on: Bool, for clipID: Clip.ID) {
        guard on else {
            apply("Remove Green Screen") { $0.updateCutout(of: clipID) { $0.key = nil } }
            return
        }
        guard let clip = project.anyClip(id: clipID) else { return }
        Task {
            var color = ColorKey.green
            if let frame = await lookFrame(of: clip, maxSize: CGSize(width: 160, height: 160)) {
                let pixels = LookRenderer.pixels(of: frame).map { clip.look.apply($0) }.map { ($0.r, $0.g, $0.b) }
                if let found = ColorKey.screenColor(in: pixels) { color = found }
            }
            apply("Green Screen") { $0.updateCutout(of: clipID) { $0.key = ColorKey(color: color) } }
        }
    }

    /// Waits for a click in the viewer on the screen's colour.
    func beginKeyColorPick(for clipID: Clip.ID) {
        let pick = ColorPick(clipID: clipID, target: .white, forKey: true)
        if colorPick == pick {
            colorPick = nil
            return
        }
        player.pause()
        if let range = project.timeline.range(of: clipID) ?? project.overlay(id: clipID)?.visibleRange(in: project), !range.containsTime(currentTime) {
            seek(to: range.start)
        }
        colorPick = pick
    }

    /// The click for the green screen: reads the colour there with the key off (the clip's
    /// colours kept, as the key works on them) and keys it out. `point` is in canvas pixels.
    func pickKeyColor(at point: CGPoint, for clipID: Clip.ID) {
        var plain = project
        plain.updateCutout(of: clipID) { $0.key = nil }
        // Only this clip and what is under it: nothing over it may be read by mistake.
        plain.titles = []
        plain.transcripts = [:]
        if let index = plain.overlays.firstIndex(where: { $0.id == clipID }) {
            plain.overlays = Array(plain.overlays.prefix(through: index))
        } else {
            plain.overlays = []
        }
        let time = currentTime
        Task {
            guard let image = try? await ProjectPoster.frame(of: plain, at: time),
                  let sample = LookRenderer.sample(image, at: CGPoint(x: point.x * CGFloat(image.width) / Project.canvasSize.width,
                                                                       y: point.y * CGFloat(image.height) / Project.canvasSize.height))
            else {
                NSSound.beep()
                return
            }
            apply("Pick Screen Colour") { project in
                project.updateCutout(of: clipID) { cutout in
                    var key = cutout.key ?? ColorKey()
                    key.color = RGBA(sample.r, sample.g, sample.b)
                    cutout.key = key
                }
            }
        }
    }

    // MARK: Changing settings

    /// One change to a clip's cut-out settings, as one undo step.
    func updateCutout(of clipID: Clip.ID, _ actionName: String, _ change: @escaping (inout ClipCutout) -> Void) {
        apply(actionName) { $0.updateCutout(of: clipID, change) }
    }

    /// While a slider is dragged: shows the settings it would give straight away (nil stops).
    func previewCutout(_ cutout: ClipCutout?, for clipID: Clip.ID) {
        LivePreview.setCutout(cutout, for: clipID)
        redrawCurrentFrame()
    }

    func setMask(_ shape: ClipMask.Shape?, for clipID: Clip.ID) {
        apply(shape == nil ? "Remove Mask" : "Mask") { project in
            project.updateCutout(of: clipID) { cutout in
                guard let shape else {
                    cutout.mask = nil
                    return
                }
                // A new shape keeps where the old one was and how soft it was.
                if var mask = cutout.mask {
                    mask.shape = shape
                    if !shape.hasSize { mask.size = ClipMask(shape: shape).size }
                    cutout.mask = mask
                } else {
                    cutout.mask = ClipMask(shape: shape)
                }
            }
        }
    }

    func setBackgroundColor(_ color: RGBA, for clipIDs: [Clip.ID]) {
        apply("Background Colour") { project in
            for id in clipIDs {
                project.updateAnyClip(id) {
                    $0.background = .color
                    $0.backgroundColor = color
                }
            }
        }
    }
}
