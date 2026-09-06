import Foundation
import Translation

/// Languages Apple's on-device translation can handle on this Mac.
@MainActor
final class LanguageCatalog: ObservableObject {
    static let shared = LanguageCatalog()

    @Published private(set) var supported: [Locale.Language] = []

    private init() {
        Task { await refresh() }
    }

    func refresh() async {
        let languages = await LanguageAvailability().supportedLanguages
        supported = languages.sorted {
            $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
        }
    }

    func match(_ language: Locale.Language) -> Locale.Language? {
        supported.first { $0.isEquivalent(to: language) }
    }
}
