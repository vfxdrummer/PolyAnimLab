// Renders Sources/Assets.xcassets/LaunchLogo.imageset (@2x, @3x).
// The same image is used by the static iOS launch screen (Info.plist UILaunchScreen) AND by
// HelmetLaunchView, so the handoff from launch screen → animated splash is pixel-identical.
// Run: swift scripts/render_launch_logo.swift
import AppKit

let out = "Sources/Assets.xcassets/LaunchLogo.imageset"
let white = NSColor(white: 1, alpha: 0.92)
let font = NSFont.systemFont(ofSize: 30, weight: .semibold)
let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: white]
let text = "Polymarket" as NSString
let textSize = text.size(withAttributes: attrs)
let size = CGSize(width: ceil(44 + textSize.width), height: 34)

for scale in [2, 3] {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width) * scale, pixelsHigh: Int(size.height) * scale,
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = size
    let base = NSGraphicsContext(bitmapImageRep: rep)!
    let ctx = base.cgContext
    ctx.translateBy(x: 0, y: size.height)
    ctx.scaleBy(x: 1, y: -1) // top-left origin, like UIKit
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)

    // Mark: slanted quad with an inner chevron (28×32 box, 1pt from the top).
    let mark = NSBezierPath()
    let p: (CGFloat, CGFloat) -> NSPoint = { NSPoint(x: $0, y: $1 + 1) }
    mark.move(to: p(2, 6)); mark.line(to: p(26, 1)); mark.line(to: p(26, 31)); mark.line(to: p(2, 26)); mark.close()
    mark.move(to: p(2, 6)); mark.line(to: p(26, 16)); mark.line(to: p(2, 26))
    mark.lineWidth = 3.2
    mark.lineJoinStyle = .miter
    white.setStroke()
    mark.stroke()

    text.draw(at: NSPoint(x: 44, y: (size.height - textSize.height) / 2), withAttributes: attrs)
    NSGraphicsContext.restoreGraphicsState()

    let png = rep.representation(using: .png, properties: [:])!
    try! png.write(to: URL(fileURLWithPath: "\(out)/LaunchLogo@\(scale)x.png"))
}
print("Rendered \(size) pt logo")
