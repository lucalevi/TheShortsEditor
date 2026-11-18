// Draws the app icon (App/Assets.xcassets/AppIcon.appiconset) with Core Graphics, so it can be
// changed and remade: `swift Tools/icon/make-icon.swift` (a folder as argument writes there
// instead, plus a 1024-pixel `preview.png`).
// Red, with a red circle and a play sign in the middle. Kept apart from YouTube's logo on purpose:
// a circle with a white ring, not a wide rounded rectangle, on the Mac's rounded-square body.
import AppKit
import CoreGraphics

let size: CGFloat = 1024
let space = CGColorSpace(name: CGColorSpace.sRGB)!

func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor { CGColor(colorSpace: space, components: [r / 255, g / 255, b / 255, a])! }

func gradient(_ colors: [CGColor]) -> CGGradient { CGGradient(colorsSpace: space, colors: colors as CFArray, locations: nil)! }

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
    context.setFillColor(color(150, 10, 18))
    context.fillPath()
    context.restoreGState()
    // Background: deep red, lighter at the top.
    context.saveGState()
    context.addPath(shape)
    context.clip()
    context.drawLinearGradient(gradient([color(236, 38, 44), color(150, 8, 18)]), start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 100), options: [])

    let center = CGPoint(x: 512, y: 512)
    // The circle's shadow on the background.
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -16), blur: 36, color: color(70, 0, 6, 0.55))
    context.addEllipse(in: CGRect(x: center.x - 300, y: center.y - 300, width: 600, height: 600))
    context.setFillColor(color(255, 255, 255))
    context.fillPath()
    context.restoreGState()
    // White ring, then the red circle inside it, brighter than the background.
    context.addEllipse(in: CGRect(x: center.x - 300, y: center.y - 300, width: 600, height: 600))
    context.setFillColor(color(255, 255, 255))
    context.fillPath()
    let inner = CGRect(x: center.x - 262, y: center.y - 262, width: 524, height: 524)
    context.saveGState()
    context.addEllipse(in: inner)
    context.clip()
    context.drawLinearGradient(
        gradient([color(255, 72, 64), color(208, 16, 30)]), start: CGPoint(x: 512, y: inner.maxY), end: CGPoint(x: 512, y: inner.minY), options: [])
    context.restoreGState()

    // Play sign: a rounded triangle, its visual centre on the circle's centre.
    let triangle = CGMutablePath()
    let cx = center.x + 26, cy = center.y
    triangle.move(to: CGPoint(x: cx - 92, y: cy + 128))
    triangle.addLine(to: CGPoint(x: cx + 128, y: cy))
    triangle.addLine(to: CGPoint(x: cx - 92, y: cy - 128))
    triangle.closeSubpath()
    context.saveGState()
    // Fill and rounded outline as one layer, so the shadow falls only outside the sign.
    context.setShadow(offset: CGSize(width: 0, height: -6), blur: 14, color: color(90, 0, 8, 0.4))
    context.beginTransparencyLayer(auxiliaryInfo: nil)
    context.addPath(triangle)
    context.setFillColor(color(255, 255, 255))
    context.setStrokeColor(color(255, 255, 255))
    context.setLineWidth(44)
    context.setLineJoin(.round)
    context.drawPath(using: .fillStroke)
    context.endTransparencyLayer()
    context.restoreGState()
    context.restoreGState()
    return context.makeImage()!
}

let folder = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "App/Assets.xcassets/AppIcon.appiconset")
try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
let image = draw()
if CommandLine.arguments.count > 1 {
    try NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])!.write(to: folder.appending(path: "preview.png"))
}
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
if CommandLine.arguments.count == 1 {
    try Data(#"{"info":{"author":"xcode","version":1}}"#.utf8).write(to: folder.deletingLastPathComponent().appending(path: "Contents.json"))
}
print("Wrote \(entries.count) icons to \(folder.path)")
