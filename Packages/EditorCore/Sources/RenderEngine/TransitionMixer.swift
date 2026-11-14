import CoreImage
import EditorCore

/// Mixes the picture going out and the picture coming in during a transition.
nonisolated enum TransitionMixer {
    /// `from` and `to` are whole frames of the two clips (Core Image coordinates), `progress` runs
    /// from 0 (only `from`) to 1 (only `to`), `region` is the part of the canvas the clips fill.
    static func mix(_ kind: TransitionKind, from: CIImage, to: CIImage, progress: Double, in region: CGRect) -> CIImage {
        let p = min(max(progress, 0), 1)
        let eased = p * p * (3 - 2 * p)
        let from = from.cropped(to: region), to = to.cropped(to: region)
        switch kind {
        case .dissolve:
            return dissolve(from, to, p)
        case .throughBlack, .throughWhite:
            let colour = CIImage(color: kind == .throughBlack ? .black : .white).cropped(to: region)
            return p < 0.5 ? dissolve(from, colour, p * 2) : dissolve(colour, to, p * 2 - 1)
        case .slide:
            return pushed(from, to, dx: -region.width, dy: 0, amount: eased, in: region)
        case .slideUp:
            // Core Image's y goes up.
            return pushed(from, to, dx: 0, dy: region.height, amount: eased, in: region)
        case .whip:
            // Fast in the middle, blurred along the way it moves.
            let fast = eased * eased * (3 - 2 * eased)
            let moved = pushed(from, to, dx: -region.width, dy: 0, amount: fast, in: region)
            let blur = 90 * sin(.pi * p)
            guard blur > 1 else { return moved }
            return moved.clampedToExtent()
                .applyingFilter("CIMotionBlur", parameters: [kCIInputRadiusKey: blur, kCIInputAngleKey: 0])
                .cropped(to: region)
        case .zoom:
            // The old clip rushes closer, the new one settles back from close; they swap in the middle.
            let closer = scaled(from, 1 + 0.9 * eased, in: region)
            let settling = scaled(to, 1 + 0.9 * (1 - eased), in: region)
            let swap = min(max((p - 0.35) / 0.3, 0), 1)
            let mixed = dissolve(closer, settling, swap)
            let blur = 22 * sin(.pi * p)
            guard blur > 1 else { return mixed }
            return mixed.clampedToExtent()
                .applyingFilter("CIZoomBlur", parameters: [kCIInputCenterKey: CIVector(x: region.midX, y: region.midY), "inputAmount": blur])
                .cropped(to: region)
        case .wipe:
            let shown = CGRect(x: region.minX, y: region.minY, width: region.width * eased, height: region.height)
            return to.cropped(to: shown).composited(over: from)
        }
    }

    private static func dissolve(_ a: CIImage, _ b: CIImage, _ time: Double) -> CIImage {
        if time <= 0 { return a }
        if time >= 1 { return b }
        return a.applyingFilter("CIDissolveTransition", parameters: [kCIInputTargetImageKey: b, kCIInputTimeKey: time])
    }

    /// `from` moves out by (dx, dy) while `to` follows it in from the other side.
    private static func pushed(_ from: CIImage, _ to: CIImage, dx: CGFloat, dy: CGFloat, amount: Double, in region: CGRect) -> CIImage {
        let out = from.transformed(by: CGAffineTransform(translationX: dx * amount, y: dy * amount))
        let coming = to.transformed(by: CGAffineTransform(translationX: -dx * (1 - amount), y: -dy * (1 - amount)))
        return coming.composited(over: out).composited(over: CIImage(color: .black).cropped(to: region)).cropped(to: region)
    }

    private static func scaled(_ image: CIImage, _ scale: Double, in region: CGRect) -> CIImage {
        image.transformed(
            by: CGAffineTransform(translationX: -region.midX, y: -region.midY)
                .concatenating(CGAffineTransform(scaleX: scale, y: scale))
                .concatenating(CGAffineTransform(translationX: region.midX, y: region.midY))
        )
        .cropped(to: region)
    }
}
