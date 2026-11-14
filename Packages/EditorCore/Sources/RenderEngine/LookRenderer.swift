import CoreImage
import EditorCore
import Synchronization

/// Draws a clip's look (colour sliders and filter) or the whole Short's filter onto a picture.
///
/// The colour part is the pure function in `EditorCore` (`ClipLook.apply`), sampled once into a
/// 3D lookup table and applied with `CIColorCube` on every frame, so the maths is tested in the
/// model and what is drawn matches it. Vignette and glow are drawn on top.
public nonisolated enum LookRenderer {
    /// Points along each side of the lookup table.
    static let cubeSize = 32
    private static let cubes = Mutex<[Int: Data]>([:])

    /// A clip's look over `image` (its own picture, before it is placed on the canvas).
    public static func apply(_ look: ClipLook, to image: CIImage) -> CIImage {
        guard !look.isNeutral else { return image }
        var out = colored(image, key: look.hashValue, look.apply)
        out = glowing(out, amount: look.glow)
        return vignetted(out, amount: look.vignette)
    }

    /// The whole Short's filter over `image` (the canvas, before titles and captions).
    public static func apply(_ choice: FilterChoice, to image: CIImage) -> CIImage {
        guard choice.strength > 0 else { return image }
        var out = colored(image, key: choice.hashValue &+ 1, choice.apply)
        out = glowing(out, amount: choice.glow)
        return vignetted(out, amount: choice.vignette)
    }

    /// `image` with every colour sent through `map`, using a lookup table kept under `key`.
    private static func colored(_ image: CIImage, key: Int, _ map: (RGB) -> RGB) -> CIImage {
        let data = cube(key: key, map)
        let extent = image.extent
        return image.applyingFilter("CIColorCube", parameters: ["inputCubeDimension": cubeSize, "inputCubeData": data])
            .cropped(to: extent)
    }

    static func cube(key: Int, _ map: (RGB) -> RGB) -> Data {
        if let known = cubes.withLock({ $0[key] }) { return known }
        let n = cubeSize
        var values = [Float](repeating: 1, count: n * n * n * 4)
        // Red changes fastest, then green, then blue, as CIColorCube reads it.
        for b in 0..<n {
            for g in 0..<n {
                for r in 0..<n {
                    let out = map(RGB(Double(r) / Double(n - 1), Double(g) / Double(n - 1), Double(b) / Double(n - 1)))
                    let i = ((b * n + g) * n + r) * 4
                    values[i] = Float(out.r)
                    values[i + 1] = Float(out.g)
                    values[i + 2] = Float(out.b)
                }
            }
        }
        let data = values.withUnsafeBufferPointer { Data(buffer: $0) }
        cubes.withLock { cubes in
            if cubes.count > 48 { cubes.removeAll() }
            cubes[key] = data
        }
        return data
    }

    /// Bright parts bleed softly into their surroundings.
    private static func glowing(_ image: CIImage, amount: Double) -> CIImage {
        guard amount > 0, !image.extent.isInfinite else { return image }
        let extent = image.extent
        let radius = max(extent.width, extent.height) * 0.012
        return image.clampedToExtent()
            .applyingFilter("CIBloom", parameters: [kCIInputRadiusKey: radius, kCIInputIntensityKey: amount])
            .cropped(to: extent)
    }

    /// The corners darkened, gently from the middle out.
    private static func vignetted(_ image: CIImage, amount: Double) -> CIImage {
        guard amount > 0, !image.extent.isInfinite else { return image }
        let extent = image.extent
        let half = hypot(extent.width, extent.height) / 2
        let edge = 1 - 0.75 * min(amount, 1)
        let shade = CIFilter(
            name: "CIRadialGradient",
            parameters: [
                "inputCenter": CIVector(x: extent.midX, y: extent.midY),
                "inputRadius0": half * 0.45,
                "inputRadius1": half,
                "inputColor0": CIColor(red: 1, green: 1, blue: 1),
                "inputColor1": CIColor(red: edge, green: edge, blue: edge),
            ])!.outputImage!.cropped(to: extent)
        return image.applyingFilter("CIMultiplyCompositing", parameters: [kCIInputBackgroundImageKey: shade]).cropped(to: extent)
    }

    // MARK: Small pictures for the inspector

    private static let context = CIContext(options: [.workingColorSpace: NSNull(), .outputColorSpace: NSNull(), .cacheIntermediates: false])

    /// `image` with `look`, for the filter grid.
    public static func preview(_ image: CGImage, look: ClipLook) -> CGImage? {
        let input = CIImage(cgImage: image)
        return context.createCGImage(apply(look, to: input), from: input.extent)
    }

    // MARK: Measuring

    /// The pixels of a small copy of `image` (its long side at most `maxSide`), for Enhance and Match Color.
    public static func pixels(of image: CGImage, maxSide: Int = 96) -> [RGB] {
        let scale = min(1, Double(maxSide) / Double(max(image.width, image.height)))
        let width = max(1, Int(Double(image.width) * scale)), height = max(1, Int(Double(image.height) * scale))
        var data = [UInt8](repeating: 0, count: width * height * 4)
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
            let context = CGContext(
                data: &data, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
        else { return [] }
        context.interpolationQuality = .medium
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return stride(from: 0, to: data.count, by: 4).map { i in
            RGB(Double(data[i]) / 255, Double(data[i + 1]) / 255, Double(data[i + 2]) / 255)
        }
    }

    /// The average colour of a square `radius` pixels around `point` (top-left origin) of `image`.
    public static func sample(_ image: CGImage, at point: CGPoint, radius: Int = 6) -> RGB? {
        let size = radius * 2 + 1
        var data = [UInt8](repeating: 0, count: size * size * 4)
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
            let context = CGContext(
                data: &data, width: size, height: size, bitsPerComponent: 8, bytesPerRow: size * 4,
                space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
        else { return nil }
        let x = Int(point.x.rounded()) - radius, y = Int(point.y.rounded()) - radius
        // Bitmap contexts have their origin at the bottom left.
        context.draw(image, in: CGRect(x: -x, y: -(image.height - y - size), width: image.width, height: image.height))
        var sum = RGB(gray: 0)
        for i in stride(from: 0, to: data.count, by: 4) {
            sum = RGB(sum.r + Double(data[i]) / 255, sum.g + Double(data[i + 1]) / 255, sum.b + Double(data[i + 2]) / 255)
        }
        let n = Double(size * size)
        return RGB(sum.r / n, sum.g / n, sum.b / n)
    }
}
