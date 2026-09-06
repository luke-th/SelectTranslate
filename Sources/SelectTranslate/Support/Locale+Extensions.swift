import Foundation

extension Locale.Language {
    /// Identifier built only from explicit subtags, e.g. "en", "zh-Hans", "pt-BR".
    var compactIdentifier: String {
        var parts: [String] = []
        if let code = languageCode?.identifier { parts.append(code) }
        if let script = script?.identifier { parts.append(script) }
        if let region = region?.identifier { parts.append(region) }
        return parts.isEmpty ? minimalIdentifier : parts.joined(separator: "-")
    }

    /// Language + script only — the shape NaturalLanguage uses ("zh-Hans", "en").
    var languageAndScriptIdentifier: String {
        [languageCode?.identifier, script?.identifier].compactMap { $0 }.joined(separator: "-")
    }

    /// "Spanish" rather than "Spanish (Latin, Spain)": the region or script is only mentioned when it
    /// differs from the language's default (English (United Kingdom), Chinese (Taiwan), Chinese (Traditional)).
    var displayName: String {
        guard let code = languageCode?.identifier else { return minimalIdentifier }
        let base = Locale.current.localizedString(forLanguageCode: code) ?? code
        let defaults = Locale.Language(identifier: Locale.Language(identifier: code).maximalIdentifier)
        if let region, region != defaults.region,
           let name = Locale.current.localizedString(forRegionCode: region.identifier) {
            return "\(base) (\(name))"
        }
        if let script, script != defaults.script,
           let name = Locale.current.localizedString(forScriptCode: script.identifier) {
            return "\(base) (\(name))"
        }
        return base
    }

    /// Same language code, and same script when both specify one. Region is ignored.
    func isEquivalent(to other: Locale.Language) -> Bool {
        guard let a = languageCode?.identifier, let b = other.languageCode?.identifier, a == b else { return false }
        if let s1 = script, let s2 = other.script { return s1 == s2 }
        return true
    }
}
