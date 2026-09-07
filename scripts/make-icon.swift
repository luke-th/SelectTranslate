// Renders Resources/AppIcon.svg into an .icns, placing the artwork on macOS's icon grid
// (the squircle fills ~82% of the canvas, leaving the standard transparent margin).
// Usage: swift scripts/make-icon.swift Resources/AppIcon.icns [Resources/AppIcon.svg] [docs/icon.png]
import AppKit

let args = CommandLine.arguments
let output = args.count > 1 ? args[1] : "AppIcon.icns"
let svgPath = args.count > 2 ? args[2] : "Resources/AppIcon.svg"
let previewPath = args.count > 3 ? args[3] : nil

guard let artwork = NSImage(contentsOfFile: svgPath) else {
    print("Could not load \(svgPath)")
    exit(1)
}

func render(pixels: Int) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
        samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
        bytesPerRow: 0, bitsPerPixel: 0
    )!
    NSGraphicsContext.saveGraphicsState()
    let context = NSGraphicsContext(bitmapImageRep: rep)!
    context.imageInterpolation = .high
    NSGraphicsContext.current = context
    let size = CGFloat(pixels)
    let inset = size * 0.09
    artwork.draw(
        in: NSRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2),
        from: .zero, operation: .sourceOver, fraction: 1
    )
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

let iconset = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("SelectTranslate.iconset")
try? FileManager.default.removeItem(at: iconset)
try! FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = scale == 1 ? "icon_\(base)x\(base).png" : "icon_\(base)x\(base)@2x.png"
        let data = render(pixels: base * scale).representation(using: .png, properties: [:])!
        try! data.write(to: iconset.appendingPathComponent(name))
    }
}
if let previewPath {
    try! render(pixels: 512).representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: previewPath))
}

let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = ["-c", "icns", iconset.path, "-o", output]
try! process.run()
process.waitUntilExit()
try? FileManager.default.removeItem(at: iconset)
print(process.terminationStatus == 0 ? "Wrote \(output)" : "iconutil failed")
exit(process.terminationStatus)
