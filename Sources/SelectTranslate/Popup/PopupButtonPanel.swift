import AppKit
import SwiftUI

/// The small "Translate" pill that appears next to a fresh selection.
@MainActor
final class PopupButtonPanel: NSPanel {
    private var hideTimer: Timer?
    private var moveMonitor: Any?

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 120, height: 36),
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        level = .statusBar
        hidesOnDeactivate = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        animationBehavior = .utilityWindow
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    func show(for snapshot: SelectionSnapshot, action: @escaping () -> Void) {
        let hosting = FirstMouseHostingView(rootView: PopupButtonView(action: action))
        let size = hosting.fittingSize
        hosting.frame = NSRect(origin: .zero, size: size)
        contentView = hosting
        setContentSize(size)
        setFrameOrigin(origin(for: snapshot, size: size))
        orderFrontRegardless()
        scheduleAutoHide()
        watchMouse()
    }

    func hide() {
        hideTimer?.invalidate()
        hideTimer = nil
        if let moveMonitor {
            NSEvent.removeMonitor(moveMonitor)
            self.moveMonitor = nil
        }
        orderOut(nil)
    }

    private func origin(for snapshot: SelectionSnapshot, size: NSSize) -> NSPoint {
        let mouse = snapshot.mouseLocation
        let bounds = screenBounds(containing: mouse)
        var x = mouse.x - size.width / 2
        var y: CGFloat
        if let rect = snapshot.anchorRect, bounds.intersects(rect) {
            y = rect.minY - size.height - 4
            if y < bounds.minY { y = rect.maxY + 4 }
        } else {
            y = mouse.y - size.height - 16
            if y < bounds.minY { y = mouse.y + 16 }
        }
        x = min(max(x, bounds.minX + 4), bounds.maxX - size.width - 4)
        y = min(max(y, bounds.minY + 4), bounds.maxY - size.height - 4)
        return NSPoint(x: x, y: y)
    }

    private func scheduleAutoHide() {
        hideTimer?.invalidate()
        hideTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.hide() }
        }
    }

    private func watchMouse() {
        if let moveMonitor { NSEvent.removeMonitor(moveMonitor) }
        moveMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved]) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.isVisible else { return }
                let center = NSPoint(x: self.frame.midX, y: self.frame.midY)
                let mouse = NSEvent.mouseLocation
                if hypot(mouse.x - center.x, mouse.y - center.y) > 180 { self.hide() }
            }
        }
    }
}

struct PopupButtonView: View {
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: "translate")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(Circle().fill(hovering ? Brand.accentHover : Brand.accent))
                .overlay(Circle().strokeBorder(.white.opacity(0.18)))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help("Translate")
        .padding(4)
    }
}
