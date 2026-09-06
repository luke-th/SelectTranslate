import Foundation
import Translation

@MainActor
final class TranslationPanelModel: ObservableObject {
    enum Phase: Equatable {
        case translating
        case result(String)
        case failure(String)
    }

    enum Provider: Equatable {
        case apple
        case online(model: String)
    }

    @Published var phase: Phase = .translating
    @Published var provider: Provider = .apple
    @Published var isStreaming = false
    /// Source language Apple could translate offline after a download.
    @Published var packSuggestion: Locale.Language?
    @Published var isDownloadingPack = false
    @Published var packDownloaded = false
    @Published var sourceText = ""
    @Published var sourceLanguage: Locale.Language?
    @Published var targetLanguage: Locale.Language = Locale.current.language
    @Published var contentHeight: CGFloat = 0

    var onRetarget: ((Locale.Language) -> Void)?
    var onRetry: (() -> Void)?
    var onClose: (() -> Void)?
    var onDownloadPack: (() -> Void)?
    var onDismissPackSuggestion: (() -> Void)?

    var resultText: String? {
        if case .result(let text) = phase { return text }
        return nil
    }

    func begin(text: String, source: Locale.Language?, target: Locale.Language) {
        sourceText = text
        sourceLanguage = source
        targetLanguage = target
        phase = .translating
        provider = .apple
        isStreaming = false
        packSuggestion = nil
        isDownloadingPack = false
        packDownloaded = false
    }

    func finish(_ response: TranslationSession.Response) {
        sourceLanguage = response.sourceLanguage
        targetLanguage = response.targetLanguage
        phase = .result(response.targetText)
    }

    func fail(_ message: String) {
        phase = .failure(message)
    }
}
