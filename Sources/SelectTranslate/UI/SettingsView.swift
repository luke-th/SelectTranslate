import AppKit
import KeyboardShortcuts
import SwiftUI
import UniformTypeIdentifiers

struct GeneralSettingsView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var updates = UpdateManager.shared

    var body: some View {
        Form {
            Section {
                Toggle("Launch at login", isOn: $settings.launchAtLogin)
                Toggle("Check for updates automatically", isOn: $updates.automaticallyChecks)
                Toggle("Show Translate button when text is selected", isOn: $settings.popupEnabled)
                Toggle("Translate clipboard when ⌘C is pressed twice", isOn: $settings.doubleCopyEnabled)
            }
            Section {
                LabeledContent("Popup delay") {
                    VStack(alignment: .trailing, spacing: 2) {
                        Slider(value: $settings.popupDelay, in: 0.1...2.0, step: 0.1)
                        Text(String(format: "%.1f s after selecting", settings.popupDelay))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                LabeledContent("Bubble font size") {
                    VStack(alignment: .trailing, spacing: 2) {
                        Slider(value: $settings.bubbleFontSize, in: 11...28, step: 1)
                        Text("\(Int(settings.bubbleFontSize)) pt").font(.caption).foregroundStyle(.secondary)
                    }
                }
                LabeledContent("Preview") {
                    Text("สวัสดี → Hello")
                        .font(.system(size: settings.bubbleFontSize))
                        .foregroundStyle(Brand.accent)
                }
            }
        }
        .formStyle(.grouped)
    }
}

struct LanguageSettingsView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var catalog: LanguageCatalog

    var body: some View {
        Form {
            Section {
                Picker("Translate into", selection: $settings.targetLanguageID) {
                    Text("System language (\(settings.systemLanguage.displayName))").tag("")
                    Divider()
                    ForEach(catalog.supported, id: \.compactIdentifier) { language in
                        Text(language.displayName).tag(language.compactIdentifier)
                    }
                }
            } footer: {
                Text("Selected text in any other language is translated into this language.")
            }
            Section {
                Toggle("Also translate text that is already in \(settings.targetLanguage.displayName)", isOn: $settings.secondLanguageEnabled)
                Picker("Translate it into", selection: $settings.secondLanguageID) {
                    Text("Choose a language…").tag("")
                    Divider()
                    ForEach(catalog.supported.filter { !$0.isEquivalent(to: settings.targetLanguage) }, id: \.compactIdentifier) { language in
                        Text(language.displayName).tag(language.compactIdentifier)
                    }
                }
                .disabled(!settings.secondLanguageEnabled)
            } footer: {
                Text("Great for learning a language: select text in your own language and see it in the one you're studying. Text in the second language is translated back.")
            }
            Section("Language packs") {
                Text("Apple's on-device translation downloads a small language pack the first time you use a language. Packs can be managed in System Settings → General → Language & Region → Translation Languages.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Button("Open Language & Region Settings…") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.Localization-Settings.extension") {
                        NSWorkspace.shared.open(url)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}

struct ExclusionsSettingsView: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        Form {
            Section {
                if settings.excludedBundleIDs.isEmpty {
                    VStack(spacing: 6) {
                        Image(systemName: "hand.raised")
                            .font(.system(size: 28))
                            .foregroundStyle(.tertiary)
                        Text("No apps excluded").font(.headline)
                        Text("Add apps where you never want the Translate button.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 28)
                } else {
                    ForEach(settings.excludedBundleIDs, id: \.self) { bundleID in
                        HStack(spacing: 10) {
                            Image(nsImage: ExcludedApp.icon(for: bundleID))
                                .resizable()
                                .frame(width: 24, height: 24)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(ExcludedApp.name(for: bundleID))
                                Text(bundleID).font(.caption2).foregroundStyle(.tertiary)
                            }
                            Spacer()
                            Button {
                                settings.excludedBundleIDs.removeAll { $0 == bundleID }
                            } label: {
                                Image(systemName: "minus.circle.fill").foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                            .help("Remove")
                        }
                    }
                }
            } footer: {
                Text("SelectTranslate stays out of the way in these apps: no Translate button, and shortcuts and double ⌘C are ignored while they're in front.")
            }
            Section {
                HStack {
                    Button("Add App…") { chooseApps() }
                    Menu("Add Running App") {
                        ForEach(runningApps, id: \.bundleIdentifier) { app in
                            Button(app.localizedName ?? app.bundleIdentifier ?? "App") {
                                add(app.bundleIdentifier)
                            }
                        }
                    }
                    .fixedSize()
                    Spacer()
                }
            }
        }
        .formStyle(.grouped)
    }

    private var runningApps: [NSRunningApplication] {
        NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.bundleIdentifier != nil && $0.bundleIdentifier != Bundle.main.bundleIdentifier }
            .sorted { ($0.localizedName ?? "").localizedCaseInsensitiveCompare($1.localizedName ?? "") == .orderedAscending }
    }

    private func chooseApps() {
        let panel = NSOpenPanel()
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.message = "Choose apps where SelectTranslate should stay hidden."
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            add(Bundle(url: url)?.bundleIdentifier)
        }
    }

    private func add(_ bundleID: String?) {
        guard let bundleID, !settings.excludedBundleIDs.contains(bundleID) else { return }
        settings.excludedBundleIDs.append(bundleID)
    }
}

enum ExcludedApp {
    static func url(for bundleID: String) -> URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
    }

    static func name(for bundleID: String) -> String {
        guard let url = url(for: bundleID) else { return bundleID }
        return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
    }

    static func icon(for bundleID: String) -> NSImage {
        guard let url = url(for: bundleID) else {
            return NSImage(systemSymbolName: "app.dashed", accessibilityDescription: nil) ?? NSImage()
        }
        return NSWorkspace.shared.icon(forFile: url.path)
    }
}

struct ShortcutsSettingsView: View {
    var body: some View {
        Form {
            Section {
                KeyboardShortcuts.Recorder("Translate selected text", name: .translateSelection)
            } footer: {
                Text("Press the shortcut while text is selected in any app to translate it right away, without waiting for the button.")
            }
            Section {
                LabeledContent("Double ⌘C", value: "Press ⌘C twice quickly")
            } footer: {
                Text("Copies the selection as usual, then translates it. Can be turned off in General.")
            }
        }
        .formStyle(.grouped)
    }
}

struct AboutView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 96, height: 96)
            Text(AppInfo.name).font(.title.weight(.semibold))
            Text("Version \(AppInfo.version)").foregroundStyle(.secondary)
            Text("Select text anywhere, click Translate. Translation runs on your Mac with Apple's Translation framework — no accounts, no subscription. Optionally add an OpenRouter key for instant online translation of languages you haven't downloaded.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 400)
            HStack(spacing: 16) {
                if let url = AppInfo.repositoryURL {
                    Link("Source code on GitHub", destination: url)
                }
                Button("Check for Updates…") { UpdateManager.shared.checkForUpdates() }
            }
            Text("Open source under the MIT License.").font(.caption).foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
