// Placeholder icon for Syphon Viewer.
// Two overlapping frames stand for what Syphon does: video handed from one
// window to another. Only the front frame is coloured, as the live image.
import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

func roundedRect(_ r: CGRect, _ radius: CGFloat) -> CGPath {
    CGPath(roundedRect: r, cornerWidth: radius, cornerHeight: radius, transform: nil)
}

func drawIcon(size: CGFloat) -> CGImage {
    let cs = CGColorSpace(name: CGColorSpace.sRGB)!
    let ctx = CGContext(data: nil, width: Int(size), height: Int(size),
                        bitsPerComponent: 8, bytesPerRow: 0, space: cs,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    let s = size

    // Background: a near-black rounded square that holds up in either theme.
    ctx.addPath(roundedRect(CGRect(x: 0, y: 0, width: s, height: s), s * 0.22))
    ctx.setFillColor(CGColor(srgbRed: 0.09, green: 0.09, blue: 0.11, alpha: 1))
    ctx.fillPath()

    // Tight margins keep the composition large enough to survive small sizes.
    // The back frame is slightly smaller so the overlap hides more of it and
    // leaves no thin slivers.
    let inset = s * 0.11
    let backW = s * 0.50, backH = s * 0.385
    let frontW = s * 0.60, frontH = s * 0.46
    let radius = s * 0.06

    // Back frame: the sender. Outline only.
    let back = CGRect(x: inset, y: s - inset - backH, width: backW, height: backH)
    ctx.addPath(roundedRect(back, radius))
    ctx.setStrokeColor(CGColor(srgbRed: 0.72, green: 0.74, blue: 0.82, alpha: 0.85))
    ctx.setLineWidth(s * 0.045)
    ctx.strokePath()

    // Front frame: the receiver. This is where the video shows.
    let front = CGRect(x: s - inset - frontW, y: inset, width: frontW, height: frontH)

    ctx.saveGState()
    ctx.addPath(roundedRect(front, radius))
    ctx.clip()
    // A saturated gradient, in the spirit of VJ material
    let grad = CGGradient(colorsSpace: cs, colors: [
        CGColor(srgbRed: 1.00, green: 0.18, blue: 0.52, alpha: 1),
        CGColor(srgbRed: 0.62, green: 0.30, blue: 1.00, alpha: 1),
        CGColor(srgbRed: 0.10, green: 0.85, blue: 0.96, alpha: 1),
    ] as CFArray, locations: [0, 0.5, 1])!
    ctx.drawLinearGradient(grad,
        start: CGPoint(x: front.minX, y: front.maxY),
        end: CGPoint(x: front.maxX, y: front.minY),
        options: [])
    ctx.restoreGState()

    // Draw the front frame's edge in the background colour to lift it clear
    // of the frame behind.
    ctx.addPath(roundedRect(front.insetBy(dx: -s * 0.028, dy: -s * 0.028), radius * 1.2))
    ctx.setStrokeColor(CGColor(srgbRed: 0.09, green: 0.09, blue: 0.11, alpha: 1))
    ctx.setLineWidth(s * 0.056)
    ctx.strokePath()

    return ctx.makeImage()!
}

func write(_ image: CGImage, to path: String) {
    let url = URL(fileURLWithPath: path) as CFURL
    let dst = CGImageDestinationCreateWithURL(url, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dst, image, nil)
    CGImageDestinationFinalize(dst)
}

// Run from the repository root:
//   swift scripts/make-icon.swift
write(drawIcon(size: 256), to: "media/icon.png")

// Render a strip of sizes to check how it holds up when small
let sheetW = 256 + 128 + 64 + 42 + 60
let cs = CGColorSpace(name: CGColorSpace.sRGB)!
let sheet = CGContext(data: nil, width: sheetW, height: 280, bitsPerComponent: 8,
                      bytesPerRow: 0, space: cs,
                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
sheet.setFillColor(CGColor(srgbRed: 0.13, green: 0.13, blue: 0.14, alpha: 1))
sheet.fill(CGRect(x: 0, y: 0, width: sheetW, height: 280))
var x: CGFloat = 12
for size in [256.0, 128.0, 64.0, 42.0] as [CGFloat] {
    sheet.draw(drawIcon(size: size), in: CGRect(x: x, y: 12, width: size, height: size))
    x += size + 12
}
// Uncomment to inspect the size strip.
// write(sheet.makeImage()!, to: "icon-sizes.png")
print("wrote media/icon.png (256x256)")
