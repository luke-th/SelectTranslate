// Renders the app icon (indigo squircle with "A" / "文") into an .icns file.
// Usage: swift scripts/make-icon.swift Resources/AppIcon.icns
import AppKit

let output = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.icns"

func render(pixels: Int) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
        samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
        bytesPerRow: 0, bitsPerPixel: 0
    )!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let size = CGFloat(pixels)
    let inset = size * 0.09
    let squircle = NSBezierPath(
        roundedRect: NSRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2),
        xRadius: size * 0.185, yRadius: size * 0.185
    )
    let gradient = NSGradient(colors: [
        NSColor(red: 0.30, green: 0.28, blue: 0.94, alpha: 1),
        NSColor(red: 0.47, green: 0.36, blue: 0.97, alpha: 1),
        NSColor(red: 0.62, green: 0.45, blue: 0.98, alpha: 1),
    ])!
    gradient.draw(in: squircle, angle: 55)

    func glyph(_ text: String, fontSize: CGFloat, center: NSPoint, weight: NSFont.Weight) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: fontSize, weight: weight),
            .foregroundColor: NSColor.white,
        ]
        let string = NSAttributedString(string: text, attributes: attributes)
        let bounds = string.size()
        string.draw(at: NSPoint(x: center.x - bounds.width / 2, y: center.y - bounds.height / 2))
    }
    glyph("A", fontSize: size * 0.40, center: NSPoint(x: size * 0.37, y: size * 0.56), weight: .bold)
    glyph("文", fontSize: size * 0.34, center: NSPoint(x: size * 0.64, y: size * 0.43), weight: .semibold)
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
let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = ["-c", "icns", iconset.path, "-o", output]
try! process.run()
process.waitUntilExit()
try? FileManager.default.removeItem(at: iconset)
print(process.terminationStatus == 0 ? "Wrote \(output)" : "iconutil failed")
exit(process.terminationStatus)
