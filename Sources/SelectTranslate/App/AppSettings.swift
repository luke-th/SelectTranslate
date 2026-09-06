import Combine
import Foundation

enum OnlineTranslationMode: String, CaseIterable, Identifiable {
    case whenNeeded, always, never

    var id: String { rawValue }

    var title: String {
        switch self {
        case .whenNeeded: return "Only when the offline language pack isn't downloaded"
        case .always: return "Always"
        case .never: return "Never"
        }
    }
}

@MainActor
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    private enum Key {
        static let popupEnabled = "popupEnabled"
        static let popupDelay = "popupDelay"
        static let bubbleFontSize = "bubbleFontSize"
        static let excludedBundleIDs = "excludedBundleIDs"
        static let targetLanguageID = "targetLanguageID"
        static let secondLanguageEnabled = "secondLanguageEnabled"
        static let secondLanguageID = "secondLanguageID"
        static let doubleCopyEnabled = "doubleCopyEnabled"
        static let onlineMode = "onlineMode"
        static let onlineModelID = "onlineModelID"
        static let onlineModelName = "onlineModelName"
        static let onlineInstructions = "onlineInstructions"
        static let dismissedPackSuggestions = "dismissedPackSuggestions"
    }

    static let defaultModelID = "google/gemini-2.5-flash-lite"
    static let defaultModelName = "Gemini 2.5 Flash Lite"

    private let defaults: UserDefaults

    @Published var popupEnabled: Bool { didSet { defaults.set(popupEnabled, forKey: Key.popupEnabled) } }
    /// Seconds between finishing a selection and showing the button.
    @Published var popupDelay: Double { didSet { defaults.set(popupDelay, forKey: Key.popupDelay) } }
    @Published var bubbleFontSize: Double { didSet { defaults.set(bubbleFontSize, forKey: Key.bubbleFontSize) } }
    @Published var excludedBundleIDs: [String] { didSet { defaults.set(excludedBundleIDs, forKey: Key.excludedBundleIDs) } }
    /// Empty string means "follow the system language".
    @Published var targetLanguageID: String { didSet { defaults.set(targetLanguageID, forKey: Key.targetLanguageID) } }
    @Published var secondLanguageEnabled: Bool { didSet { defaults.set(secondLanguageEnabled, forKey: Key.secondLanguageEnabled) } }
    @Published var secondLanguageID: String { didSet { defaults.set(secondLanguageID, forKey: Key.secondLanguageID) } }
    @Published var doubleCopyEnabled: Bool { didSet { defaults.set(doubleCopyEnabled, forKey: Key.doubleCopyEnabled) } }
    /// Stored in the Keychain, never in UserDefaults.
    @Published var openRouterAPIKey: String { didSet { KeychainStore.write(openRouterAPIKey, account: "openrouter") } }
    @Published var onlineMode: OnlineTranslationMode { didSet { defaults.set(onlineMode.rawValue, forKey: Key.onlineMode) } }
    @Published var onlineModelID: String { didSet { defaults.set(onlineModelID, forKey: Key.onlineModelID) } }
    @Published var onlineModelName: String { didSet { defaults.set(onlineModelName, forKey: Key.onlineModelName) } }
    @Published var onlineInstructions: String { didSet { defaults.set(onlineInstructions, forKey: Key.onlineInstructions) } }
    /// Language codes the user doesn't want offline-pack suggestions for.
    @Published var dismissedPackSuggestions: [String] { didSet { defaults.set(dismissedPackSuggestions, forKey: Key.dismissedPackSuggestions) } }
    @Published var launchAtLogin: Bool {
        didSet {
            guard launchAtLogin != LaunchAtLogin.isEnabled else { return }
            do {
                try LaunchAtLogin.set(launchAtLogin)
            } catch {
                launchAtLogin = LaunchAtLogin.isEnabled
            }
        }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [
            Key.popupEnabled: true,
            Key.popupDelay: 0.5,
            Key.bubbleFontSize: 15.0,
            Key.excludedBundleIDs: [String](),
            Key.targetLanguageID: "",
            Key.secondLanguageEnabled: false,
            Key.secondLanguageID: "",
            Key.doubleCopyEnabled: true,
            Key.onlineMode: OnlineTranslationMode.whenNeeded.rawValue,
            Key.onlineModelID: Self.defaultModelID,
            Key.onlineModelName: Self.defaultModelName,
            Key.onlineInstructions: "",
            Key.dismissedPackSuggestions: [String](),
        ])
        popupEnabled = defaults.bool(forKey: Key.popupEnabled)
        popupDelay = defaults.double(forKey: Key.popupDelay)
        bubbleFontSize = defaults.double(forKey: Key.bubbleFontSize)
        excludedBundleIDs = defaults.stringArray(forKey: Key.excludedBundleIDs) ?? []
        targetLanguageID = defaults.string(forKey: Key.targetLanguageID) ?? ""
        secondLanguageEnabled = defaults.bool(forKey: Key.secondLanguageEnabled)
        secondLanguageID = defaults.string(forKey: Key.secondLanguageID) ?? ""
        doubleCopyEnabled = defaults.bool(forKey: Key.doubleCopyEnabled)
        openRouterAPIKey = KeychainStore.read("openrouter") ?? ""
        onlineMode = OnlineTranslationMode(rawValue: defaults.string(forKey: Key.onlineMode) ?? "") ?? .whenNeeded
        onlineModelID = defaults.string(forKey: Key.onlineModelID) ?? Self.defaultModelID
        onlineModelName = defaults.string(forKey: Key.onlineModelName) ?? Self.defaultModelName
        onlineInstructions = defaults.string(forKey: Key.onlineInstructions) ?? ""
        dismissedPackSuggestions = defaults.stringArray(forKey: Key.dismissedPackSuggestions) ?? []
        launchAtLogin = LaunchAtLogin.isEnabled
    }

    var onlineTranslationAvailable: Bool { !openRouterAPIKey.isEmpty && onlineMode != .never }

    var systemLanguage: Locale.Language { Locale.current.language }

    var targetLanguage: Locale.Language {
        if targetLanguageID.isEmpty {
            return LanguageCatalog.shared.match(systemLanguage) ?? systemLanguage
        }
        return Locale.Language(identifier: targetLanguageID)
    }

    var secondLanguage: Locale.Language? {
        guard secondLanguageEnabled, !secondLanguageID.isEmpty else { return nil }
        return Locale.Language(identifier: secondLanguageID)
    }
}
