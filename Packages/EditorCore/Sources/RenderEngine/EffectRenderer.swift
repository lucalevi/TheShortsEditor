import CoreImage
import EditorCore
import Synchronization

/// Draws the effects of `Effects.swift` with Core Image, on one layer's picture as drawn in its
/// region (Core Image coordinates, origin at the bottom left). Nothing here keeps state between
/// frames: what changes "at random" is worked out from the frame number, so preview and export
/// look the same. Thread-safe: the video compositor calls it on its own queues.
public nonisolated enum EffectRenderer {
    /// Applies the effects playing now to `image`, cut to `region`.
    static func apply(_ moments: [EffectMoment], to image: CIImage, in region: CGRect) -> CIImage {
        var image = image
        for moment in moments {
            image = apply(moment, to: image, in: region).cropped(to: region)
        }
        return image
    }

    /// A number 0…1 that is the same for the same frame and salt, and jumps from frame to frame.
    static func random(_ frame: Int, _ salt: Int) -> Double {
        var x = UInt64(bitPattern: Int64(frame &* 7919 &+ salt &* 104_729))
        x = (x ^ (x >> 30)) &* 0xBF58_476D_1CE4_E5B9
        x = (x ^ (x >> 27)) &* 0x94D0_49BB_1331_11EB
        x ^= x >> 31
        return Double(x % 1_000_000) / 1_000_000
    }

    /// A quick beat: 1 at each multiple of `period`, falling to 0 within `fall` seconds.
    private static func beat(_ seconds: Double, period: Double, fall: Double) -> Double {
        exp(-seconds.truncatingRemainder(dividingBy: period) / fall)
    }

    /// Scaled (and turned, moved) around the middle of `region`.
    private static func around(_ region: CGRect, scale: CGFloat = 1, dx: CGFloat = 0, dy: CGFloat = 0, angle: CGFloat = 0) -> CGAffineTransform {
        CGAffineTransform(translationX: -region.midX, y: -region.midY)
            .concatenating(CGAffineTransform(scaleX: scale, y: scale))
            .concatenating(CGAffineTransform(rotationAngle: angle))
            .concatenating(CGAffineTransform(translationX: region.midX + dx, y: region.midY + dy))
    }

    private static func faded(_ image: CIImage, _ alpha: Double) -> CIImage {
        image.applyingFilter("CIColorMatrix", parameters: ["inputAVector": CIVector(x: 0, y: 0, z: 0, w: CGFloat(alpha))])
    }

    /// One colour channel of `image` (0 red, 1 green, 2 blue), the others black.
    private static func channel(_ image: CIImage, _ index: Int) -> CIImage {
        let keep = { (i: Int) in CIVector(x: i == 0 && index == 0 ? 1 : 0, y: i == 1 && index == 1 ? 1 : 0, z: i == 2 && index == 2 ? 1 : 0, w: 0) }
        return image.applyingFilter(
            "CIColorMatrix",
            parameters: [
                "inputRVector": keep(0), "inputGVector": keep(1), "inputBVector": keep(2), "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1),
            ])
    }

    /// Red moved one way, blue the other, by `distance` pixels.
    private static func split(_ image: CIImage, distance: CGFloat, vertical: CGFloat = 0) -> CIImage {
        let red = channel(image, 0).transformed(by: CGAffineTransform(translationX: -distance, y: vertical))
        let green = channel(image, 1)
        let blue = channel(image, 2).transformed(by: CGAffineTransform(translationX: distance, y: -vertical))
        // The brightest of the three in each channel: each has only its own, so they combine
        // into the picture, as solid as it was (adding would add up its opacity too).
        return red.applyingFilter("CIMaximumCompositing", parameters: [kCIInputBackgroundImageKey: green])
            .applyingFilter("CIMaximumCompositing", parameters: [kCIInputBackgroundImageKey: blue])
    }

    private static func apply(_ moment: EffectMoment, to image: CIImage, in region: CGRect) -> CIImage {
        let s = moment.effect.strength, t = moment.seconds, p = moment.progress, frame = moment.frame
        let part = moment.effect.part
        // How much the effect shows now: the start fades out, the end fades in.
        let ramp: Double =
            switch part {
            case .wholeClip: 1
            case .start: 1 - p
            case .end: p
            }
        let width = region.width, height = region.height

        switch moment.effect.kind {
        case .shake:
            let amount = 0.035 * s * (part == .wholeClip ? 1 : ramp)
            let dx = (random(frame, 1) - 0.5) * 2 * amount * width
            let dy = (random(frame, 2) - 0.5) * 2 * amount * width
            let angle = (random(frame, 3) - 0.5) * 0.03 * s
            // A little bigger, so the moving edges stay outside.
            return image.transformed(by: around(region, scale: 1 + 2.4 * amount, dx: dx, dy: dy, angle: angle))

        case .flash:
            let alpha: Double =
                switch part {
                case .start: s * pow(1 - p, 2)
                case .end: s * pow(p, 2)
                case .wholeClip: s * beat(t, period: 1, fall: 0.12)
                }
            let white = CIImage(color: CIColor(red: 1, green: 1, blue: 1, alpha: CGFloat(min(alpha, 1)))).cropped(to: region)
            return white.composited(over: image)

        case .zoomPulse:
            let pulse = beat(t, period: 0.5, fall: 0.12) * ramp
            return image.transformed(by: around(region, scale: 1 + 0.14 * s * pulse))

        case .glitch:
            // Bursts on about a third of the frames: bands jump sideways and the colours split.
            guard random(frame, 10) < 0.25 + 0.3 * s * ramp else { return image }
            var out = split(image, distance: 10 * s * width / 1080)
            for band in 0..<4 {
                let y = region.minY + random(frame, 20 + band) * height
                let h = (0.02 + 0.08 * random(frame, 30 + band)) * height
                let dx = (random(frame, 40 + band) - 0.5) * 0.16 * s * width
                let slice = out.cropped(to: CGRect(x: region.minX, y: y, width: width, height: h))
                out = slice.transformed(by: CGAffineTransform(translationX: dx, y: 0)).composited(over: out)
            }
            return out

        case .rgbSplit:
            let distance = 16 * s * ramp * (0.6 + 0.4 * sin(2 * .pi * t * 1.5)) * width / 1080
            return split(image, distance: distance, vertical: distance * 0.3)

        case .vhs:
            let amount = s * ramp
            var out = split(image, distance: 5 * amount * width / 1080)
                .applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 1 - 0.3 * amount, kCIInputContrastKey: 1 + 0.08 * amount])
            // Now and then the picture wobbles sideways.
            if random(frame, 50) < 0.12 * amount {
                out = out.transformed(by: CGAffineTransform(translationX: (random(frame, 51) - 0.5) * 0.03 * width, y: 0))
            }
            // Fine lines across the picture.
            let lines = CIFilter(
                name: "CIStripesGenerator",
                parameters: [
                    "inputColor0": CIColor(red: 0, green: 0, blue: 0, alpha: CGFloat(0.22 * amount)), "inputColor1": CIColor.clear,
                    "inputWidth": 2.0, "inputSharpness": 0.5, "inputCenter": CIVector(x: 0, y: 0),
                ])?.outputImage?.transformed(by: CGAffineTransform(rotationAngle: .pi / 2)).cropped(to: region)
            if let lines { out = lines.composited(over: out) }
            // A band of noise rolling up from the bottom.
            let bandY = region.minY + (t * 0.25).truncatingRemainder(dividingBy: 1) * height
            if let noise = CIFilter(name: "CIRandomGenerator")?.outputImage?
                .transformed(by: CGAffineTransform(translationX: CGFloat(frame * 37 % 500), y: CGFloat(frame * 91 % 500)))
                .applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 0])
            {
                let band = faded(noise.cropped(to: CGRect(x: region.minX, y: bandY, width: width, height: 0.03 * height)), 0.35 * amount)
                out = band.composited(over: out)
            }
            return out

        case .filmGrain:
            let amount = s * ramp
            guard let noise = CIFilter(name: "CIRandomGenerator")?.outputImage else { return image }
            let grain =
                noise
                .transformed(by: CGAffineTransform(translationX: CGFloat(frame * 53 % 800), y: CGFloat(frame * 29 % 800)))
                .applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 0, kCIInputContrastKey: 1.6])
                .cropped(to: region)
            let warm = image.applyingFilter(
                "CITemperatureAndTint",
                parameters: [
                    "inputNeutral": CIVector(x: 6500, y: 0), "inputTargetNeutral": CIVector(x: 6500 - 900 * amount, y: 0),
                ])
            let grained = faded(grain, 0.45 * amount).applyingFilter("CISoftLightBlendMode", parameters: [kCIInputBackgroundImageKey: warm])
            return grained.applyingFilter("CIVignette", parameters: [kCIInputIntensityKey: 0.6 * amount, kCIInputRadiusKey: 1.6]).cropped(to: region)

        case .lightLeak:
            let amount = s * ramp
            // A warm glow drifting across, slowly.
            let phase = (t / 4).truncatingRemainder(dividingBy: 1)
            let centre = CIVector(x: region.minX + width * (-0.2 + 1.4 * phase), y: region.minY + height * (0.7 - 0.3 * sin(2 * .pi * phase)))
            guard
                let glow = CIFilter(
                    name: "CIRadialGradient",
                    parameters: [
                        "inputCenter": centre, "inputRadius0": 0.05 * width, "inputRadius1": 0.75 * width,
                        "inputColor0": CIColor(red: 1, green: 0.45, blue: 0.15, alpha: CGFloat(0.85 * amount)),
                        "inputColor1": CIColor(red: 1, green: 0.2, blue: 0.5, alpha: 0),
                    ])?.outputImage?.cropped(to: region)
            else { return image }
            return glow.applyingFilter("CIScreenBlendMode", parameters: [kCIInputBackgroundImageKey: image])

        case .blur:
            let radius = 30 * s * ramp * width / 1080
            guard radius > 0.3 else { return image }
            return image.clampedToExtent().applyingGaussianBlur(sigma: radius).cropped(to: region)

        case .vignettePulse:
            let pulse = 0.5 + 0.5 * sin(2 * .pi * t / 1.2)
            return image.applyingFilter(
                "CIVignetteEffect",
                parameters: [
                    kCIInputCenterKey: CIVector(x: region.midX, y: region.midY),
                    kCIInputRadiusKey: height * (0.55 - 0.12 * pulse * s),
                    kCIInputIntensityKey: (0.6 + 0.4 * pulse) * s * ramp,
                    "inputFalloff": 0.6,
                ])

        case .mirror:
            // The left half, flipped onto the right.
            let left = image.cropped(to: CGRect(x: region.minX, y: region.minY, width: width / 2, height: height))
            let flipped = left.transformed(
                by: CGAffineTransform(translationX: -region.midX, y: 0)
                    .concatenating(CGAffineTransform(scaleX: -1, y: 1))
                    .concatenating(CGAffineTransform(translationX: region.midX, y: 0)))
            let mirrored = flipped.composited(over: image)
            return ramp >= 1 ? mirrored : faded(mirrored, ramp).composited(over: image)

        case .colorPop:
            guard let cube = colorPopCube() else { return image }
            let popped = image.applyingFilter(
                "CIColorCubeWithColorSpace",
                parameters: [
                    "inputCubeDimension": colorPopSize, "inputCubeData": cube, "inputColorSpace": NSNull(),
                ])
            let amount = s * ramp
            return amount >= 1 ? popped : faded(popped, amount).composited(over: image)
        }
    }

    // MARK: Colour pop

    private static let colorPopSize = 32
    private static let colorPopTable = Mutex<Data?>(nil)

    /// Every colour turned grey unless it is strongly coloured (then it stays, a little richer).
    private static func colorPopCube() -> Data? {
        if let table = colorPopTable.withLock({ $0 }) { return table }
        let n = colorPopSize
        var values = [Float](repeating: 0, count: n * n * n * 4)
        for b in 0..<n {
            for g in 0..<n {
                for r in 0..<n {
                    let red = Float(r) / Float(n - 1), green = Float(g) / Float(n - 1), blue = Float(b) / Float(n - 1)
                    let high = max(red, green, blue), low = min(red, green, blue)
                    let saturation = high > 0 ? (high - low) / high : 0
                    // Smoothly from grey (dull colours) to full colour (strong ones).
                    let x = min(max((saturation - 0.35) / 0.25, 0), 1)
                    let keep = x * x * (3 - 2 * x)
                    let grey = 0.299 * red + 0.587 * green + 0.114 * blue
                    let i = ((b * n + g) * n + r) * 4
                    values[i] = grey + (red - grey) * keep * 1.1
                    values[i + 1] = grey + (green - grey) * keep * 1.1
                    values[i + 2] = grey + (blue - grey) * keep * 1.1
                    values[i + 3] = 1
                }
            }
        }
        let data = values.withUnsafeBufferPointer { Data(buffer: $0) }
        colorPopTable.withLock { $0 = data }
        return data
    }

    // MARK: Previews

    private static let previewContext = CIContext(options: [.workingColorSpace: NSNull(), .outputColorSpace: NSNull()])

    /// `kind` on `image` (a frame of the clip), at a moment where it shows well, for the effect grid.
    public static func preview(_ image: CGImage, kind: EffectKind) -> CGImage? {
        let input = CIImage(cgImage: image)
        let region = input.extent
        var effect = ClipEffect(kind, strength: 0.85)
        effect.part = .wholeClip
        // A moment that shows it: right on a beat, in a glitch burst, part way through a drift.
        let seconds: Double =
            switch kind {
            case .lightLeak: 1.6
            case .vignettePulse: 0.3
            default: 0.02
            }
        let frame = kind == .glitch ? (0..<200).first { random($0, 10) < 0.2 } ?? 0 : 7
        if kind == .blur { effect.strength = 0.35 }
        let moment = EffectMoment(effect: effect, seconds: seconds, progress: 0.3, frame: frame)
        let output = apply([moment], to: input, in: region)
        return previewContext.createCGImage(output, from: region)
    }
}
