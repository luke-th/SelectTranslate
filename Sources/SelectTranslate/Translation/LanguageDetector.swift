import Foundation
import NaturalLanguage

enum LanguageDetector {
    /// Returns nil when the recognizer isn't confident; the Translation framework then auto-detects.
    static func detect(_ text: String, hints: [Locale.Language] = [], minimumConfidence: Double = 0.35) -> Locale.Language? {
        let recognizer = NLLanguageRecognizer()
        if !hints.isEmpty {
            var weights: [NLLanguage: Double] = [:]
            for hint in hints {
                weights[NLLanguage(rawValue: hint.languageAndScriptIdentifier)] = 0.4
            }
            recognizer.languageHints = weights
        }
        recognizer.processString(text)
        guard let dominant = recognizer.dominantLanguage else { return nil }
        let confidence = recognizer.languageHypotheses(withMaximum: 1)[dominant] ?? 0
        guard confidence >= minimumConfidence else { return nil }
        return Locale.Language(identifier: dominant.rawValue)
    }
}
