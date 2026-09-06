import AppKit

/// Watches global mouse/keyboard events to spot "the user just selected something" gestures.
/// Reading the selection itself happens in `SelectionReader`.
@MainActor
final class SelectionMonitor {
    var onSelectionGesture: ((NSPoint) -> Void)?
    var onDoubleCopy: (() -> Void)?

    private var monitors: [Any] = []
    private var dragEvents = 0
    private var mouseDownLocation = NSPoint.zero
    private var lastCopyAt: TimeInterval = 0

    func start() {
        guard monitors.isEmpty else { return }
        add([.leftMouseDown]) { [weak self] _ in self?.mouseDown() }
        add([.leftMouseDragged]) { [weak self] _ in self?.dragEvents += 1 }
        add([.leftMouseUp]) { [weak self] event in self?.mouseUp(event) }
        add([.keyDown]) { [weak self] event in self?.keyDown(event) }
    }

    func stop() {
        monitors.forEach { NSEvent.removeMonitor($0) }
        monitors.removeAll()
    }

    private func add(_ mask: NSEvent.EventTypeMask, _ handler: @escaping @MainActor (NSEvent) -> Void) {
        let monitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { event in
            MainActor.assumeIsolated { handler(event) }
        }
        if let monitor { monitors.append(monitor) }
    }

    private func mouseDown() {
        dragEvents = 0
        mouseDownLocation = NSEvent.mouseLocation
    }

    private func mouseUp(_ event: NSEvent) {
        let location = NSEvent.mouseLocation
        let distance = hypot(location.x - mouseDownLocation.x, location.y - mouseDownLocation.y)
        let dragged = dragEvents >= 2 && distance >= 3
        let multiClick = event.clickCount >= 2
        dragEvents = 0
        if dragged || multiClick { onSelectionGesture?(location) }
    }

    private func keyDown(_ event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard flags.contains(.command),
              flags.isDisjoint(with: [.shift, .option, .control]),
              event.charactersIgnoringModifiers?.lowercased() == "c" else { return }
        let now = ProcessInfo.processInfo.systemUptime
        if now - lastCopyAt < 0.45 {
            lastCopyAt = 0
            onDoubleCopy?()
        } else {
            lastCopyAt = now
        }
    }
}
