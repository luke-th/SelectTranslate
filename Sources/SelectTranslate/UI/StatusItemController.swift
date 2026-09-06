import AppKit
import KeyboardShortcuts

@MainActor
final class StatusItemController: NSObject, NSMenuDelegate {
    private let statusItem: NSStatusItem
    private let menu = NSMenu()
    private let openSettings: () -> Void
    private let translateSelection: () -> Void
    private let requestAccessibility: () -> Void
    private let checkForUpdates: () -> Void
    private let settings = AppSettings.shared

    init(openSettings: @escaping () -> Void, translateSelection: @escaping () -> Void, requestAccessibility: @escaping () -> Void, checkForUpdates: @escaping () -> Void) {
        self.openSettings = openSettings
        self.translateSelection = translateSelection
        self.requestAccessibility = requestAccessibility
        self.checkForUpdates = checkForUpdates
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()

        let image = NSImage(systemSymbolName: "translate", accessibilityDescription: AppInfo.name)
            ?? NSImage(systemSymbolName: "globe", accessibilityDescription: AppInfo.name)
        image?.isTemplate = true
        statusItem.button?.image = image
        statusItem.button?.toolTip = AppInfo.name
        menu.delegate = self
        statusItem.menu = menu
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        if !AccessibilityPermission.isTrusted {
            let item = NSMenuItem(title: "Grant Accessibility Access…", action: #selector(grantAccess), keyEquivalent: "")
            item.target = self
            item.image = NSImage(systemSymbolName: "exclamationmark.triangle.fill", accessibilityDescription: nil)
            menu.addItem(item)
            menu.addItem(.separator())
        }

        let translate = NSMenuItem(title: "Translate Selected Text", action: #selector(translateAction), keyEquivalent: "")
        translate.target = self
        translate.setShortcut(for: .translateSelection)
        menu.addItem(translate)

        let popup = NSMenuItem(title: "Show Translate Button on Selection", action: #selector(togglePopup), keyEquivalent: "")
        popup.target = self
        popup.state = settings.popupEnabled ? .on : .off
        menu.addItem(popup)

        menu.addItem(.separator())
        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(settingsAction), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        let updates = NSMenuItem(title: "Check for Updates…", action: #selector(updatesAction), keyEquivalent: "")
        updates.target = self
        updates.isEnabled = UpdateManager.shared.canCheckForUpdates
        menu.addItem(updates)

        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit \(AppInfo.name)", action: #selector(quitAction), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
    }

    @objc private func grantAccess() { requestAccessibility() }
    @objc private func translateAction() { translateSelection() }
    @objc private func togglePopup() { settings.popupEnabled.toggle() }
    @objc private func settingsAction() { openSettings() }
    @objc private func updatesAction() { checkForUpdates() }
    @objc private func quitAction() { NSApp.terminate(nil) }
}
