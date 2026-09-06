import AppKit
import SwiftUI

/// Lets SwiftUI buttons inside a non-key panel react to the very first click.
final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

func screenBounds(containing point: NSPoint) -> NSRect {
    let screen = NSScreen.screens.first { $0.frame.contains(point) } ?? NSScreen.main
    return screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
}
