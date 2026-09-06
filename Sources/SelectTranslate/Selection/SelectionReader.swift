import AppKit
import SelectedTextKit
import os

struct SelectionSnapshot {
    let text: String
    /// Screen rect of the selected text in AppKit coordinates, when the app exposes it via Accessibility.
    let anchorRect: NSRect?
    let mouseLocation: NSPoint
}

@MainActor
enum SelectionReader {
    private static let log = Logger(subsystem: "app.selecttranslate", category: "selection")

    static func readText(strategies: [TextStrategy]) async -> String? {
        do {
            let text = try await SelectedTextManager.shared.getSelectedText(strategies: strategies)
            let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return trimmed.isEmpty ? nil : trimmed
        } catch {
            log.debug("Selection read failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    static func snapshot(text: String, mouse: NSPoint) -> SelectionSnapshot {
        SelectionSnapshot(text: text, anchorRect: selectionRect(), mouseLocation: mouse)
    }

    static func selectionRect() -> NSRect? {
        guard let value = try? AXManager.shared.getSelectedTextFrame() else { return nil }
        let rect = value.rectValue
        guard rect.width > 0, rect.height > 0 else { return nil }
        return flipped(rect)
    }

    /// Accessibility bounds use a top-left origin on the primary display; AppKit uses bottom-left.
    private static func flipped(_ rect: NSRect) -> NSRect {
        guard let primary = NSScreen.screens.first else { return rect }
        return NSRect(x: rect.minX, y: primary.frame.maxY - rect.maxY, width: rect.width, height: rect.height)
    }
}
