import AppKit
import SwiftUI

/// Classic macOS preferences window: toolbar tabs with an icon above each label.
final class SettingsWindowController: NSWindowController {
    static let tabSize = NSSize(width: 560, height: 540)

    init() {
        let tabs = NSTabViewController()
        tabs.tabStyle = .toolbar

        let settings = AppSettings.shared
        let catalog = LanguageCatalog.shared
        Self.add(to: tabs, "General", "gearshape", GeneralSettingsView(settings: settings))
        Self.add(to: tabs, "Languages", "globe", LanguageSettingsView(settings: settings, catalog: catalog))
        Self.add(to: tabs, "Online", "cloud", OnlineSettingsView(settings: settings))
        Self.add(to: tabs, "Exclusions", "hand.raised", ExclusionsSettingsView(settings: settings))
        Self.add(to: tabs, "Shortcuts", "keyboard", ShortcutsSettingsView())
        Self.add(to: tabs, "About", "info.circle", AboutView())

        let window = NSWindow(contentViewController: tabs)
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.toolbarStyle = .preference
        window.isReleasedWhenClosed = false
        window.center()
        super.init(window: window)
    }

    required init?(coder: NSCoder) { fatalError("Not supported") }

    private static func add(to tabs: NSTabViewController, _ title: String, _ symbol: String, _ view: some View) {
        let padded = view
            .padding(EdgeInsets(top: 12, leading: 28, bottom: 24, trailing: 28))
            .frame(width: tabSize.width, height: tabSize.height)
        let host = NSHostingController(rootView: padded)
        host.title = title
        let item = NSTabViewItem(viewController: host)
        item.label = title
        item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
        tabs.addTabViewItem(item)
    }
}
