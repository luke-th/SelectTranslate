import AppKit
import Foundation
import Translation
import os

enum TranslationEngineError: LocalizedError {
    case unsupportedPair(Locale.Language?, Locale.Language)
    case sameLanguage(Locale.Language)
    case timeout
    case empty
    case superseded
    case unexpected

    var errorDescription: String? {
        switch self {
        case .unsupportedPair(let source, let target):
            if let source {
                return "Translating \(source.displayName) to \(target.displayName) isn't supported by Apple Translation."
            }
            return "Translating to \(target.displayName) isn't supported by Apple Translation."
        case .sameLanguage(let language):
            return "This text is already in \(language.displayName). Turn on a second language in Settings → Languages to translate it anyway."
        case .timeout:
            return "Translation timed out. Please try again."
        case .empty:
            return "Nothing to translate."
        case .superseded:
            return "Replaced by a newer translation."
        case .unexpected:
            return "Translation failed unexpectedly."
        }
    }
}

/// Fully on-device translation via Apple's Translation framework.
@MainActor
final class TranslationEngine {
    static let shared = TranslationEngine()

    private let host = TranslationHost()
    private let availability = LanguageAvailability()
    private let log = Logger(subsystem: "app.selecttranslate", category: "engine")

    /// Whether Apple can translate this pair right now (`installed`), after a download (`supported`), or not at all.
    func appleStatus(text: String, source: Locale.Language?, target: Locale.Language) async -> LanguageAvailability.Status {
        if let source { return await availability.status(from: source, to: target) }
        return (try? await availability.status(for: text, to: target)) ?? .unsupported
    }

    /// Triggers macOS's language-pack download sheet for the pair.
    func downloadPack(source: Locale.Language, target: Locale.Language) async throws {
        try await host.prepare(source: source, target: target)
    }

    func translate(_ text: String, from source: Locale.Language?, to target: Locale.Language) async throws -> TranslationSession.Response {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw TranslationEngineError.empty }
        if let source, source.isEquivalent(to: target) { throw TranslationEngineError.sameLanguage(target) }

        let status: LanguageAvailability.Status
        if let source {
            status = await availability.status(from: source, to: target)
        } else {
            status = (try? await availability.status(for: trimmed, to: target)) ?? .supported
        }

        switch status {
        case .unsupported:
            throw TranslationEngineError.unsupportedPair(source, target)
        case .installed:
            if #available(macOS 26.0, *), let source {
                // macOS 26 lets us skip the SwiftUI-hosted session entirely when the pack is installed.
                let session = TranslationSession(installedSource: source, target: target)
                do {
                    return try await session.translate(trimmed)
                } catch {
                    log.error("Direct session failed, falling back to hosted session: \(error.localizedDescription, privacy: .public)")
                }
            }
            return try await host.translate(trimmed, source: source, target: target, needsDownload: false)
        case .supported:
            return try await host.translate(trimmed, source: source, target: target, needsDownload: true)
        @unknown default:
            return try await host.translate(trimmed, source: source, target: target, needsDownload: true)
        }
    }
}
