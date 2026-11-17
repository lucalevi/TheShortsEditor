// Draws the app icon (App/Assets.xcassets/AppIcon.appiconset) with Core Graphics, so it can be
// changed and remade: `swift Tools/icon/make-icon.swift`.
// A vertical 9:16 frame with a play sign (a Short), over a timeline strip with a playhead.
import AppKit
import CoreGraphics

let size: CGFloat = 1024
let space = CGColorSpace(name: CGColorSpace.sRGB)!

func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor { CGColor(colorSpace: space, components: [r / 255, g / 255, b / 255, a])! }

func draw() -> CGImage {
    let context = CGContext(
        data: nil, width: Int(size), height: Int(size), bitsPerComponent: 8, bytesPerRow: 0, space: space,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    // macOS icon grid: the body is 824 points with a 100-point margin.
    let body = CGRect(x: 100, y: 100, width: 824, height: 824)
    let shape = CGPath(roundedRect: body, cornerWidth: 185, cornerHeight: 185, transform: nil)
    // Shadow under the body.
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: color(0, 0, 0, 0.45))
    context.addPath(shape)
    context.setFillColor(color(30, 31, 36))
    context.fillPath()
    context.restoreGState()
    // Background: dark grey, lighter at the top, like the editor.
    context.saveGState()
    context.addPath(shape)
    context.clip()
    let gradient = CGGradient(colorsSpace: space, colors: [color(58, 60, 70), color(22, 23, 28)] as CFArray, locations: [0, 1])!
    context.drawLinearGradient(gradient, start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 100), options: [])

    // The timeline strip: three clips and a playhead.
    let stripY: CGFloat = 196, stripHeight: CGFloat = 92
    let clips: [(CGFloat, CGFloat, CGColor)] = [(176, 230, color(64, 132, 255)), (414, 170, color(48, 176, 170)), (592, 256, color(142, 98, 230))]
    for (x, width, fill) in clips {
        let rect = CGRect(x: x, y: stripY, width: width, height: stripHeight)
        context.addPath(CGPath(roundedRect: rect, cornerWidth: 18, cornerHeight: 18, transform: nil))
        context.setFillColor(fill)
        context.fillPath()
    }
    // Playhead.
    context.setFillColor(color(255, 69, 58))
    context.fill(CGRect(x: 505, y: stripY - 26, width: 14, height: stripHeight + 52))
    context.move(to: CGPoint(x: 484, y: stripY + stripHeight + 26))
    context.addLine(to: CGPoint(x: 540, y: stripY + stripHeight + 26))
    context.addLine(to: CGPoint(x: 512, y: stripY + stripHeight - 4))
    context.closePath()
    context.fillPath()

    // The Short: a vertical 9:16 frame.
    let frameHeight: CGFloat = 520, frameWidth = frameHeight * 9 / 16
    let frame = CGRect(x: 512 - frameWidth / 2, y: 352, width: frameWidth, height: frameHeight)
    let framePath = CGPath(roundedRect: frame, cornerWidth: 44, cornerHeight: 44, transform: nil)
    context.addPath(framePath)
    context.setFillColor(color(245, 245, 247))
    context.fillPath()
    let screen = frame.insetBy(dx: 18, dy: 18)
    context.addPath(CGPath(roundedRect: screen, cornerWidth: 30, cornerHeight: 30, transform: nil))
    let screenGradient = CGGradient(colorsSpace: space, colors: [color(94, 92, 230), color(255, 55, 140)] as CFArray, locations: [0, 1])!
    context.saveGState()
    context.clip()
    context.drawLinearGradient(screenGradient, start: CGPoint(x: screen.minX, y: screen.maxY), end: CGPoint(x: screen.maxX, y: screen.minY), options: [])
    context.restoreGState()
    // Play sign.
    let triangle = CGMutablePath()
    let cx = frame.midX + 12, cy = frame.midY
    triangle.move(to: CGPoint(x: cx - 58, y: cy + 78))
    triangle.addLine(to: CGPoint(x: cx + 74, y: cy))
    triangle.addLine(to: CGPoint(x: cx - 58, y: cy - 78))
    triangle.closeSubpath()
    context.addPath(triangle)
    context.setFillColor(color(255, 255, 255))
    context.fillPath()
    context.restoreGState()
    return context.makeImage()!
}

let folder = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "App/Assets.xcassets/AppIcon.appiconset")
try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
let image = draw()
var entries: [String] = []
for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = points * scale
        let name = "icon_\(points)x\(points)\(scale == 2 ? "@2x" : "").png"
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSGraphicsContext.current?.imageInterpolation = .high
        NSImage(cgImage: image, size: NSSize(width: size, height: size)).draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels))
        NSGraphicsContext.restoreGraphicsState()
        try rep.representation(using: .png, properties: [:])!.write(to: folder.appending(path: name))
        entries.append(#"{"idiom":"mac","scale":"\#(scale)x","size":"\#(points)x\#(points)","filename":"\#(name)"}"#)
    }
}
let contents = #"{"images":[\#(entries.joined(separator: ","))],"info":{"author":"xcode","version":1}}"#
try Data(contents.utf8).write(to: folder.appending(path: "Contents.json"))
try Data(#"{"info":{"author":"xcode","version":1}}"#.utf8).write(to: folder.deletingLastPathComponent().appending(path: "Contents.json"))
print("Wrote \(entries.count) icons to \(folder.path)")
