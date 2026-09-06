import AppKit
import Combine
import SwiftUI

/// Floating result bubble. Width is fixed; height follows the content up to a cap, then scrolls.
@MainActor
final class TranslationPanel: NSPanel {
    static let width: CGFloat = 380
    static let maxHeight: CGFloat = 520

    let model = TranslationPanelModel()
    private var cancellables = Set<AnyCancellable>()
    private var topLeft = NSPoint.zero

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: Self.width, height: 180),
            styleMask: [.nonactivatingPanel, .borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        level = .floating
        hidesOnDeactivate = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        isMovableByWindowBackground = true
        becomesKeyOnlyIfNeeded = true
        acceptsMouseMovedEvents = true
        animationBehavior = .utilityWindow

        let root = TranslationView(model: model, settings: AppSettings.shared, catalog: LanguageCatalog.shared)
        contentView = FirstMouseHostingView(rootView: root)

        model.$contentHeight
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] height in self?.resize(toContentHeight: height) }
            .store(in: &cancellables)
        model.onClose = { [weak self] in self?.hide() }
    }

    override var canBecomeKey: Bool { true }
    override func cancelOperation(_ sender: Any?) { hide() }

    func show(anchoredTo snapshot: SelectionSnapshot) {
        let mouse = snapshot.mouseLocation
        let bounds = screenBounds(containing: mouse)
        let height = max(min(frame.height, Self.maxHeight), 160)
        var x = mouse.x - Self.width / 2
        x = min(max(x, bounds.minX + 8), bounds.maxX - Self.width - 8)

        var top: CGFloat
        if let rect = snapshot.anchorRect, bounds.intersects(rect) {
            top = rect.minY - 8
            if top - height < bounds.minY { top = min(rect.maxY + 8 + height, bounds.maxY - 8) }
        } else {
            top = mouse.y - 18
            if top - height < bounds.minY { top = min(mouse.y + 18 + height, bounds.maxY - 8) }
        }
        topLeft = NSPoint(x: x, y: top)
        setFrame(NSRect(x: x, y: top - height, width: Self.width, height: height), display: true)
        orderFrontRegardless()
    }

    func hide() {
        orderOut(nil)
    }

    private func resize(toContentHeight contentHeight: CGFloat) {
        guard contentHeight > 0 else { return }
        let height = min(contentHeight, Self.maxHeight)
        guard abs(height - frame.height) > 0.5 else { return }
        var origin = NSPoint(x: topLeft.x, y: topLeft.y - height)
        if let bounds = (screen ?? NSScreen.main)?.visibleFrame, origin.y < bounds.minY {
            origin.y = bounds.minY + 8
        }
        setFrame(NSRect(origin: origin, size: NSSize(width: Self.width, height: height)), display: true)
        invalidateShadow()
    }
}
