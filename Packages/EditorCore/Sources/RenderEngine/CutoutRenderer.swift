import CoreImage
import EditorCore
import Synchronization

/// Draws the cut-out settings of a layer (Stage K): the green screen keyed out, the mask, and
/// B-roll blended into what is under it. Remove Background needs nothing here: the layer plays a
/// copy of its file that is already see-through (see `CutoutMaker`).
public nonisolated enum CutoutRenderer {
    /// Points along each side of the keying table: finer than a look's, for clean edges.
    static let keyCubeSize = 48
    private static let cubes = Mutex<[Int: Data]>([:])
    private static let shapes = Mutex<[String: CGImage]>([:])

    // MARK: Green screen

    /// `image` with the colour of `key` taken out (see `ColorKey.keyed`, sampled into a table).
    public static func keyed(_ image: CIImage, by key: ColorKey) -> CIImage {
        let data = cube(for: key)
        return image.applyingFilter("CIColorCube", parameters: ["inputCubeDimension": keyCubeSize, "inputCubeData": data])
            .cropped(to: image.extent)
    }

    static func cube(for key: ColorKey) -> Data {
        let hash = key.hashValue
        if let known = cubes.withLock({ $0[hash] }) { return known }
        let n = keyCubeSize
        var values = [Float](repeating: 1, count: n * n * n * 4)
        // Red changes fastest, then green, then blue; colours premultiplied by their alpha.
        for b in 0..<n {
            for g in 0..<n {
                for r in 0..<n {
                    let out = key.keyed(Double(r) / Double(n - 1), Double(g) / Double(n - 1), Double(b) / Double(n - 1))
                    let i = ((b * n + g) * n + r) * 4
                    values[i] = Float(out.red * out.alpha)
                    values[i + 1] = Float(out.green * out.alpha)
                    values[i + 2] = Float(out.blue * out.alpha)
                    values[i + 3] = Float(out.alpha)
                }
            }
        }
        let data = values.withUnsafeBufferPointer { Data(buffer: $0) }
        cubes.withLock { cubes in
            if cubes.count > 12 { cubes.removeAll() }
            cubes[hash] = data
        }
        return data
    }

    // MARK: Masks

    /// The mask as a grey picture on the canvas (white where the picture shows, Core Image's
    /// coordinates), cut to `ciRegion`. `pictureSize` is the upright picture's size and
    /// `pictureToCanvas` takes its pixels (origin top left) to the canvas (origin top left).
    public static func maskImage(_ mask: ClipMask, pictureSize: CGSize, pictureToCanvas: CGAffineTransform, in ciRegion: CGRect) -> CIImage {
        let canvasHeight = Project.canvasSize.height
        let feather = max(mask.featherWidth(in: pictureSize), 0.75)
        let box = mask.shapeSize(in: pictureSize)
        let black = CIImage(color: .black)
        let white = CIImage(color: .white)
        // Drawn around 0, 0 with y going up; inside is white.
        var shape: CIImage
        switch mask.shape {
        case .line:
            shape = gradient(from: -feather / 2, to: feather / 2)
        case .band:
            let half = box.height / 2
            shape = gradient(from: -half - feather / 2, to: -half + feather / 2)
                .applyingFilter("CIMinimumCompositing", parameters: [kCIInputBackgroundImageKey: gradient(from: half + feather / 2, to: half - feather / 2)])
        case .circle:
            let radius = max(box.height / 2, 0.5)
            shape = CIFilter(name: "CIRadialGradient", parameters: [
                "inputCenter": CIVector(x: 0, y: 0),
                "inputRadius0": max(radius - feather / 2, 0),
                "inputRadius1": radius + feather / 2,
                "inputColor0": CIColor.white, "inputColor1": CIColor.black,
            ])!.outputImage!
            shape = shape.transformed(by: CGAffineTransform(scaleX: box.width / box.height, y: 1))
        case .rectangle:
            let corner = min(max(mask.roundness, 0), 1) * min(box.width, box.height) / 2
            let rect = CGRect(x: -box.width / 2, y: -box.height / 2, width: box.width, height: box.height)
            shape = CIFilter(name: "CIRoundedRectangleGenerator", parameters: [
                "inputExtent": CIVector(cgRect: rect), "inputRadius": corner, "inputColor": CIColor.white,
            ])!.outputImage!.composited(over: black)
            shape = softened(shape, feather: feather)
        case .heart, .star:
            guard let picture = shapePicture(mask.shape, side: box.width) else { return white.cropped(to: ciRegion) }
            let scale = box.width / CGFloat(picture.width)
            shape = CIImage(cgImage: picture)
                .transformed(by: CGAffineTransform(scaleX: scale, y: scale).translatedBy(x: -CGFloat(picture.width) / 2, y: -CGFloat(picture.height) / 2))
                .composited(over: black)
            shape = softened(shape, feather: feather)
        }
        if mask.inverted { shape = shape.applyingFilter("CIColorInvert") }
        // Shape's frame (y up) → picture (y down, turned clockwise, moved to its middle) → canvas → Core Image.
        let toPicture = CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: 0)
            .concatenating(CGAffineTransform(rotationAngle: mask.rotation * .pi / 180))
            .concatenating(CGAffineTransform(translationX: mask.centerX * pictureSize.width, y: mask.centerY * pictureSize.height))
        let toCI = CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: canvasHeight)
        // Beyond the picture nothing shows anyway; outside the shape's own extent, black (or white inverted).
        let outside = mask.inverted ? white : black
        return shape.transformed(by: toPicture.concatenating(pictureToCanvas).concatenating(toCI))
            .composited(over: mask.shape == .line || mask.shape == .band ? black : outside)
            .cropped(to: ciRegion)
    }

    /// `image` kept where `mask` is white, see-through where it is black.
    public static func masked(_ image: CIImage, by mask: CIImage) -> CIImage {
        image.applyingFilter("CIBlendWithMask", parameters: [
            kCIInputBackgroundImageKey: CIImage(color: .clear).cropped(to: image.extent),
            kCIInputMaskImageKey: mask,
        ]).cropped(to: image.extent)
    }

    /// Black below `from`, white above `to` (along y), smoothly in between.
    private static func gradient(from: CGFloat, to: CGFloat) -> CIImage {
        CIFilter(name: "CISmoothLinearGradient", parameters: [
            "inputPoint0": CIVector(x: 0, y: from), "inputPoint1": CIVector(x: 0, y: to),
            "inputColor0": CIColor.black, "inputColor1": CIColor.white,
        ])!.outputImage!
    }

    private static func softened(_ image: CIImage, feather: CGFloat) -> CIImage {
        guard feather > 1 else { return image }
        return image.applyingGaussianBlur(sigma: feather / 2.5)
    }

    /// A heart or star, white on transparent, drawn once at up to 1024 pixels wide.
    private static func shapePicture(_ shape: ClipMask.Shape, side: CGFloat) -> CGImage? {
        let pixels = Int(min(max(side, 16), 1024).rounded())
        let key = "\(shape.rawValue)|\(pixels)"
        if let known = shapes.withLock({ $0[key] }) { return known }
        guard let context = CGContext(data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return nil }
        let s = CGFloat(pixels)
        context.setFillColor(gray: 1, alpha: 1)
        // Core Graphics' y goes up, like the shape's frame.
        let path = CGMutablePath()
        switch shape {
        case .heart:
            path.move(to: CGPoint(x: 0.5 * s, y: 0.05 * s))
            path.addCurve(to: CGPoint(x: 0.03 * s, y: 0.62 * s), control1: CGPoint(x: 0.3 * s, y: 0.25 * s), control2: CGPoint(x: 0.03 * s, y: 0.42 * s))
            path.addCurve(to: CGPoint(x: 0.5 * s, y: 0.76 * s), control1: CGPoint(x: 0.03 * s, y: 0.92 * s), control2: CGPoint(x: 0.42 * s, y: 0.98 * s))
            path.addCurve(to: CGPoint(x: 0.97 * s, y: 0.62 * s), control1: CGPoint(x: 0.58 * s, y: 0.98 * s), control2: CGPoint(x: 0.97 * s, y: 0.92 * s))
            path.addCurve(to: CGPoint(x: 0.5 * s, y: 0.05 * s), control1: CGPoint(x: 0.97 * s, y: 0.42 * s), control2: CGPoint(x: 0.7 * s, y: 0.25 * s))
        default:
            for i in 0..<10 {
                let angle = CGFloat.pi / 2 + CGFloat(i) * .pi / 5
                let radius = (i.isMultiple(of: 2) ? 0.5 : 0.2) * s
                let point = CGPoint(x: 0.5 * s + radius * cos(angle), y: 0.53 * s + radius * sin(angle))
                if i == 0 { path.move(to: point) } else { path.addLine(to: point) }
            }
        }
        path.closeSubpath()
        context.addPath(path)
        context.fillPath()
        guard let image = context.makeImage() else { return nil }
        shapes.withLock { shapes in
            if shapes.count > 16 { shapes.removeAll() }
            shapes[key] = image
        }
        return image
    }

    // MARK: Blend modes

    /// `top` mixed into `bottom` the way `mode` says.
    public static func blend(_ top: CIImage, over bottom: CIImage, mode: BlendMode) -> CIImage {
        let name: String
        switch mode {
        case .normal: return top.composited(over: bottom)
        case .multiply: name = "CIMultiplyBlendMode"
        case .screen: name = "CIScreenBlendMode"
        case .overlay: name = "CIOverlayBlendMode"
        case .softLight: name = "CISoftLightBlendMode"
        case .hardLight: name = "CIHardLightBlendMode"
        // (Not CIAdditionCompositing: it adds the alphas too, past 1.)
        case .add: name = "CILinearDodgeBlendMode"
        case .difference: name = "CIDifferenceBlendMode"
        case .darken: name = "CIDarkenBlendMode"
        case .lighten: name = "CILightenBlendMode"
        case .colorBurn: name = "CIColorBurnBlendMode"
        case .colorDodge: name = "CIColorDodgeBlendMode"
        }
        // Outside the top picture the bottom stays exactly as it is.
        let mixed = top.applyingFilter(name, parameters: [kCIInputBackgroundImageKey: bottom]).cropped(to: top.extent)
        return mixed.composited(over: bottom)
    }
}
