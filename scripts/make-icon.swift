// Renders the app icon: Resources/AppIcon.svg (white glyphs, transparent background) on a
// gradient squircle sized to macOS's icon grid, with a frosted-glass treatment on the glyphs
// (translucent body, bright top rims, darker bottom rims, drop shadow, sheen).
// Usage: swift scripts/make-icon.swift Resources/AppIcon.icns [Resources/AppIcon.svg] [docs/icon.png]
import AppKit
import CoreImage

let args = CommandLine.arguments
let output = args.count > 1 ? args[1] : "AppIcon.icns"
let glyphPath = args.count > 2 ? args[2] : "Resources/AppIcon.svg"
let previewPath = args.count > 3 ? args[3] : nil
guard let glyphs = NSImage(contentsOfFile: glyphPath) else { print("Could not load \(glyphPath)"); exit(1) }

func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
    CGColor(colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!, components: [r, g, b, a])!
}

/// Grayscale (no alpha) image: white where the glyphs are. The SVG renderer only draws into RGBA
/// contexts, so rasterize there first and convert.
func glyphMask(pixels: Int, box: CGRect, dy: CGFloat = 0) -> CGImage {
    let ctx = CGContext(data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    let ns = NSGraphicsContext(cgContext: ctx, flipped: false)
    NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = ns
    ns.imageInterpolation = .high
    glyphs.draw(in: box.offsetBy(dx: 0, dy: dy), from: .zero, operation: .sourceOver, fraction: 1)
    NSGraphicsContext.restoreGraphicsState()
    return grayImage(ctx.makeImage()!, pixels: pixels)
}

func grayImage(_ image: CGImage, pixels: Int) -> CGImage {
    let ctx = CGContext(data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)!
    ctx.setFillColor(gray: 0, alpha: 1); ctx.fill(CGRect(x: 0, y: 0, width: pixels, height: pixels))
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: pixels, height: pixels))
    return ctx.makeImage()!
}

let ciContext = CIContext()
func blur(_ image: CGImage, radius: CGFloat) -> CGImage {
    guard radius >= 0.3 else { return image }
    let ci = CIImage(cgImage: image).clampedToExtent()
        .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: radius])
        .cropped(to: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    return ciContext.createCGImage(ci, from: ci.extent)!
}

/// mask * (1 - shifted): the band of glyph edge uncovered when the glyph is shifted by dy.
func edgeBand(pixels: Int, box: CGRect, dy: CGFloat) -> CGImage {
    let full = CGRect(x: 0, y: 0, width: pixels, height: pixels)
    let ctx = CGContext(data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)!
    ctx.setFillColor(gray: 1, alpha: 1); ctx.fill(full)
    ctx.setBlendMode(.difference); ctx.draw(glyphMask(pixels: pixels, box: box, dy: dy), in: full)   // 1 - shifted
    ctx.setBlendMode(.multiply); ctx.draw(glyphMask(pixels: pixels, box: box), in: full)              // * mask
    return ctx.makeImage()!
}

func fillThrough(_ ctx: CGContext, mask: CGImage, full: CGRect, _ body: () -> Void) {
    ctx.saveGState(); ctx.clip(to: full, mask: mask); body(); ctx.restoreGState()
}

func render(pixels: Int) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    let ns = NSGraphicsContext(bitmapImageRep: rep)!
    let ctx = ns.cgContext
    let size = CGFloat(pixels)
    let full = CGRect(x: 0, y: 0, width: size, height: size)
    let inset = size * 0.09
    let box = full.insetBy(dx: inset, dy: inset)

    // 1. Gradient squircle (top-right #8F65FF → bottom-left #4333FF)
    let squircle = CGPath(roundedRect: box, cornerWidth: box.width * 0.225, cornerHeight: box.width * 0.225, transform: nil)
    ctx.saveGState(); ctx.addPath(squircle); ctx.clip()
    let bg = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: [rgb(0.56, 0.40, 1.0), rgb(0.26, 0.20, 1.0)] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(bg, start: CGPoint(x: box.maxX, y: box.maxY), end: CGPoint(x: box.minX, y: box.minY), options: [])
    ctx.restoreGState()

    let mask = glyphMask(pixels: pixels, box: box)

    // 2. Soft drop shadow under the glyphs
    let shadowCtx = CGContext(data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0,
                              space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    fillThrough(shadowCtx, mask: mask, full: full) { shadowCtx.setFillColor(rgb(0.12, 0.05, 0.45, 0.55)); shadowCtx.fill(full) }
    let shadow = blur(shadowCtx.makeImage()!, radius: size * 0.018)
    ctx.saveGState(); ctx.addPath(squircle); ctx.clip()
    ctx.draw(shadow, in: full.offsetBy(dx: 0, dy: -size * 0.016))
    ctx.restoreGState()

    // 3. Frosted glass body: white fading to translucent so the purple shows through at the bottom
    fillThrough(ctx, mask: mask, full: full) {
        let glass = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: [rgb(1, 1, 1, 0.98), rgb(1, 1, 1, 0.70)] as CFArray, locations: [0, 1])!
        ctx.drawLinearGradient(glass, start: CGPoint(x: 0, y: box.maxY), end: CGPoint(x: 0, y: box.minY), options: [])
    }

    // 4. Bright rim along the top edges, darker rim along the bottom edges
    let rimTop = grayImage(blur(edgeBand(pixels: pixels, box: box, dy: -size * 0.016), radius: size * 0.005), pixels: pixels)
    fillThrough(ctx, mask: rimTop, full: full) { ctx.setFillColor(rgb(1, 1, 1, 0.95)); ctx.fill(full) }
    let rimBottom = grayImage(blur(edgeBand(pixels: pixels, box: box, dy: size * 0.014), radius: size * 0.006), pixels: pixels)
    fillThrough(ctx, mask: rimBottom, full: full) { ctx.setFillColor(rgb(0.30, 0.20, 0.85, 0.35)); ctx.fill(full) }

    // 5. Sheen: soft highlight sweeping from the upper left
    fillThrough(ctx, mask: mask, full: full) {
        let sheen = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: [rgb(1, 1, 1, 0.35), rgb(1, 1, 1, 0.0)] as CFArray, locations: [0, 1])!
        ctx.drawRadialGradient(sheen, startCenter: CGPoint(x: box.minX + box.width * 0.25, y: box.maxY - box.height * 0.15), startRadius: 0,
                               endCenter: CGPoint(x: box.minX + box.width * 0.25, y: box.maxY - box.height * 0.15), endRadius: box.width * 0.75, options: [])
    }
    return rep
}

let iconset = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("SelectTranslate.iconset")
try? FileManager.default.removeItem(at: iconset)
try! FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = scale == 1 ? "icon_\(base)x\(base).png" : "icon_\(base)x\(base)@2x.png"
        try! render(pixels: base * scale).representation(using: .png, properties: [:])!.write(to: iconset.appendingPathComponent(name))
    }
}
if let previewPath { try! render(pixels: 512).representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: previewPath)) }
let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil"); p.arguments = ["-c", "icns", iconset.path, "-o", output]
try! p.run(); p.waitUntilExit(); try? FileManager.default.removeItem(at: iconset)
print(p.terminationStatus == 0 ? "Wrote \(output)" : "iconutil failed"); exit(p.terminationStatus)
