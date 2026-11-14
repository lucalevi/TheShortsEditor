import AVFoundation
import EditorCore
import RenderEngine
import SwiftUI

/// A click in the viewer that is about to set a clip's white balance or skin tone.
struct ColorPick: Equatable {
    var clipID: Clip.ID
    var target: ColorAdjustments.BalanceTarget
    /// Picks the green screen's colour instead (Stage K).
    var forKey = false

    var prompt: String {
        if forKey { return "Click the green or blue screen in the picture" }
        return switch target {
        case .white: "Click something white or grey in the picture"
        case .skin: "Click someone's skin in the picture"
        }
    }
}

/// How clips look: Enhance, colour sliders, picking white or skin, Match Color, filters (per
/// clip and over the whole Short), before/after, and Stabilize.
extension EditorModel {
    // MARK: Which clips

    /// The clips a look command works on: the selected main clips and B-roll, or the clip at the playhead.
    var lookTargets: [Clip] {
        let selected = timelineSelection.items.compactMap { item -> Clip? in
            switch item {
            case .clip(let id), .overlay(let id): project.anyClip(id: id)
            default: nil
            }
        }
        let clips = selected.isEmpty ? (clipAtPlayhead.map { [$0] } ?? []) : selected
        return clips.filter { project.asset(id: $0.assetID)?.hasVideo == true }
    }

    // MARK: Sliders and filters

    func setLook(_ look: ClipLook, for clipIDs: [Clip.ID], actionName: String) {
        apply(actionName) { project in
            for id in clipIDs { project.updateLook(of: id) { $0 = look } }
        }
    }

    /// Shows `look` on a clip straight away while a slider is dragged (nil: back to its own).
    func previewLook(_ look: ClipLook?, for clipID: Clip.ID) {
        LivePreview.setLook(look, for: clipID)
        redrawCurrentFrame()
    }

    /// Changes the colour sliders of the clips (each keeps its filter).
    func editColor(of clipIDs: [Clip.ID], _ actionName: String, _ change: @escaping (inout ColorAdjustments) -> Void) {
        apply(actionName) { project in
            for id in clipIDs {
                project.updateLook(of: id) { look in
                    change(&look.color)
                    look.color = look.color.tidied
                }
            }
        }
    }

    /// Puts `filter` on the clips at their present strength (full when they had none); nil removes it.
    func setFilter(_ filter: LookFilter?, for clipIDs: [Clip.ID]) {
        apply(filter.map { "Filter: \($0.displayName)" } ?? "Remove Filter") { project in
            for id in clipIDs {
                project.updateLook(of: id) { look in
                    look.filter = filter.map { FilterChoice($0, strength: look.filter?.strength ?? 1) }
                }
            }
        }
        if filter != nil { showTip(.looks) }
    }

    func setFilterStrength(_ strength: Double, for clipIDs: [Clip.ID]) {
        apply("Filter Strength") { project in
            for id in clipIDs { project.updateLook(of: id) { $0.filter?.strength = (strength * 20).rounded() / 20 } }
        }
    }

    /// The clip's filter on every clip of the Short.
    func setFilterOnEveryClip(_ choice: FilterChoice?) {
        apply(choice == nil ? "Remove All Filters" : "Filter on Every Clip") { $0.setFilterOnEveryClip(choice) }
    }

    func resetLook(of clipIDs: [Clip.ID]) {
        resetSettings([.look], of: clipIDs)
    }

    // MARK: The whole Short

    func setShortFilter(_ filter: LookFilter?) {
        apply(filter.map { "Short Filter: \($0.displayName)" } ?? "Remove Short Filter") { project in
            project.look = filter.map { FilterChoice($0, strength: project.look?.strength ?? 1) }
        }
    }

    func setShortFilterStrength(_ strength: Double) {
        apply("Short Filter Strength") { $0.look?.strength = (strength * 20).rounded() / 20 }
    }

    /// Shows the whole Short's filter at `strength` while its slider is dragged (nil: back to the Short's).
    func previewShortFilterStrength(_ strength: Double?) {
        if let strength, var choice = project.look {
            choice.strength = strength
            LivePreview.setShortLook(.some(choice))
        } else {
            LivePreview.setShortLook(nil)
        }
        redrawCurrentFrame()
    }

    // MARK: Before and after

    func toggleOriginalLook() {
        showsOriginalLook.toggle()
    }

    // MARK: Enhance and Match Color

    /// A small picture of what a clip shows: at the playhead when it is on screen, else its middle.
    func lookFrame(of clip: Clip, maxSize: CGSize = CGSize(width: 360, height: 640)) async -> CGImage? {
        guard let media = project.asset(id: clip.assetID), media.hasVideo, !missingAssets.contains(media.id) else { return nil }
        if media.isImage { return StillImages.image(at: media.url) }
        var time = clip.sourceTime(atOffset: CMTimeMultiplyByFloat64(clip.duration, multiplier: 0.5))
        if let atPlayhead = project.sourceTime(ofClip: clip.id, at: currentTime), clip.sourceRange.containsTime(atPlayhead) || clip.isFrozen {
            time = atPlayhead
        }
        return try? await MediaProbe.frame(of: media.url, at: time, maxSize: maxSize)
    }

    /// One click: colour, brightness and contrast set for each clip from what it shows.
    func enhance(_ clipIDs: [Clip.ID]) {
        let clips = clipIDs.compactMap(project.anyClip(id:))
        guard !clips.isEmpty else {
            NSSound.beep()
            return
        }
        analysingLook.formUnion(clipIDs)
        Task {
            defer { analysingLook.subtract(clipIDs) }
            var results: [Clip.ID: ColorAdjustments] = [:]
            for clip in clips {
                guard let image = await lookFrame(of: clip), let stats = FrameStats(pixels: LookRenderer.pixels(of: image)) else { continue }
                results[clip.id] = ColorAdjustments.auto(for: stats)
            }
            guard !results.isEmpty else {
                alert = AlertMessage(title: "Nothing to enhance", message: "The picture of the clip couldn't be read.")
                return
            }
            apply("Enhance") { project in
                for (id, color) in results { project.updateLook(of: id) { $0.color = color } }
            }
            showTip(.looks)
        }
    }

    /// Gives a clip the colours of another (its average colour, brightness, contrast and colourfulness).
    func matchColor(of clipID: Clip.ID, to referenceID: Clip.ID) {
        guard let clip = project.anyClip(id: clipID), let reference = project.anyClip(id: referenceID) else { return }
        analysingLook.insert(clipID)
        Task {
            defer { analysingLook.remove(clipID) }
            // The reference as it looks now (its own sliders and filter included).
            guard let referenceImage = await lookFrame(of: reference), let image = await lookFrame(of: clip) else {
                alert = AlertMessage(title: "Colours couldn't be matched", message: "The picture of one of the clips couldn't be read.")
                return
            }
            let wanted = LookRenderer.pixels(of: referenceImage).map(reference.look.apply)
            guard let stats = FrameStats(pixels: wanted) else { return }
            let color = ColorAdjustments.matching(LookRenderer.pixels(of: image), to: stats)
            apply("Match Color") { $0.updateLook(of: clipID) { $0.color = color } }
        }
    }

    /// The other clips whose colours a clip can take: main clips and B-roll with a picture, in timeline order.
    func matchCandidates(for clipID: Clip.ID) -> [(id: Clip.ID, label: String)] {
        let main = project.timeline.clips.enumerated().compactMap { index, clip -> (Clip.ID, String)? in
            guard clip.id != clipID, let media = project.asset(id: clip.assetID), media.hasVideo else { return nil }
            let start = project.timeline.range(of: clip.id)?.start ?? .zero
            return (clip.id, "Clip \(index + 1) at \(TimeFormat.string(start)) · \(media.name)")
        }
        let over = project.overlays.compactMap { overlay -> (Clip.ID, String)? in
            guard overlay.id != clipID, let media = project.asset(id: overlay.clip.assetID), media.hasVideo else { return nil }
            return (overlay.id, "Over the clips at \(TimeFormat.string(overlay.start)) · \(media.name)")
        }
        return (main + over).map { (id: $0.0, label: $0.1) }
    }

    // MARK: Picking white or skin in the viewer

    /// Waits for a click in the viewer; Escape or clicking the button again cancels.
    func beginColorPick(_ target: ColorAdjustments.BalanceTarget, for clipID: Clip.ID) {
        if colorPick?.clipID == clipID, colorPick?.target == target {
            colorPick = nil
            return
        }
        player.pause()
        // The spot is read where the clip is on screen.
        if let range = project.timeline.range(of: clipID) ?? project.overlay(id: clipID)?.visibleRange(in: project), !range.containsTime(currentTime) {
            seek(to: range.start)
        }
        colorPick = ColorPick(clipID: clipID, target: target)
    }

    /// The click: reads the colour there as filmed (without the clip's look) and sets the clip's
    /// warmth and tint so it becomes white or a natural skin colour. `point` is in canvas pixels.
    func pickColor(at point: CGPoint) {
        guard let pick = colorPick else { return }
        colorPick = nil
        if pick.forKey {
            pickKeyColor(at: point, for: pick.clipID)
            return
        }
        var plain = project
        plain.updateLook(of: pick.clipID) { $0 = ClipLook() }
        plain.look = nil
        let time = currentTime
        Task {
            guard let image = try? await ProjectPoster.frame(of: plain, at: time),
                let sample = LookRenderer.sample(
                    image,
                    at: CGPoint(
                        x: point.x * CGFloat(image.width) / Project.canvasSize.width,
                        y: point.y * CGFloat(image.height) / Project.canvasSize.height))
            else {
                NSSound.beep()
                return
            }
            guard let clip = project.anyClip(id: pick.clipID) else { return }
            let balanced = clip.look.color.balanced(sample, toward: pick.target)
            guard balanced != clip.look.color else {
                alert = AlertMessage(
                    title: "Pick another spot",
                    message:
                        "That spot is too dark, too bright or one strong colour, so there is nothing to balance. Click something white, grey or light that is lit but not glaring."
                )
                return
            }
            apply(pick.target == .white ? "Pick White" : "Pick Skin Tone") { $0.updateLook(of: pick.clipID) { $0.color = balanced } }
        }
    }

    // MARK: Stabilize

    /// Turns Stabilize on (at `steadiness`) or off (0) for the clips.
    func setSteadiness(_ steadiness: Double, for clipIDs: [Clip.ID]) {
        let value = (steadiness.clamped(0, 1) * 20).rounded() / 20
        apply(value == 0 ? "Stop Stabilizing" : "Stabilize") { project in
            for id in clipIDs { project.updateAnyClip(id) { $0.steadiness = value } }
        }
    }

    /// Whether a clip can be steadied: a moving picture (not a photo or freeze frame).
    func canStabilize(_ clip: Clip) -> Bool {
        guard let media = project.asset(id: clip.assetID) else { return false }
        return media.hasVideo && !media.isImage && !clip.isFrozen
    }

    /// Measures the shake of every file a steadied clip uses that hasn't been measured yet (in
    /// the background, with progress on the clips), then rebuilds so it shows.
    func prepareMissingSteadiness() {
        let clips = project.timeline.clips + project.overlays.map(\.clip)
        var needed: [MediaAsset.ID: URL] = [:]
        for clip in clips where clip.steadiness > 0 && steadying[clip.assetID] == nil && !unsteadiable.contains(clip.assetID) {
            guard let media = project.asset(id: clip.assetID), canStabilize(clip), !missingAssets.contains(media.id),
                ShakeCache.path(for: media.url) == nil
            else { continue }
            needed[media.id] = media.url
        }
        guard !needed.isEmpty else { return }
        for id in needed.keys { steadying[id] = 0 }
        Task {
            for (id, url) in needed {
                do {
                    _ = try await ShakeCache.measure(url) { fraction in
                        Task { @MainActor in if self.steadying[id] != nil { self.steadying[id] = fraction } }
                    }
                } catch {
                    Log.render.failure("prepareMissingSteadiness", error)
                    unsteadiable.insert(id)
                    alert = AlertMessage(title: "The clip couldn't be steadied", message: error.localizedDescription)
                }
                steadying[id] = nil
            }
            refreshPlayback()
        }
    }
}

extension Double {
    func clamped(_ low: Double, _ high: Double) -> Double { Swift.min(Swift.max(self, low), high) }
}
