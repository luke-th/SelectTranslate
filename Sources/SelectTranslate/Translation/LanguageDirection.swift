import Foundation

struct TranslationPlan {
    var source: Locale.Language?
    var target: Locale.Language
}

enum LanguageDirection {
    /// Foreign text → primary language. Text already in the primary language → second language (if enabled).
    /// Text in the second language → back to the primary language.
    @MainActor
    static func plan(detected: Locale.Language?, settings: AppSettings) -> TranslationPlan {
        let primary = settings.targetLanguage
        guard let detected else { return TranslationPlan(source: nil, target: primary) }

        if let second = settings.secondLanguage {
            if detected.isEquivalent(to: primary) { return TranslationPlan(source: detected, target: second) }
            if detected.isEquivalent(to: second) { return TranslationPlan(source: detected, target: primary) }
        }
        if detected.isEquivalent(to: primary) {
            // Our detector may be wrong on short text; let Apple decide the source language.
            return TranslationPlan(source: nil, target: primary)
        }
        return TranslationPlan(source: detected, target: primary)
    }
}
