import AVFoundation
import Foundation

@MainActor
final class Speaker {
    static let shared = Speaker()
    private let synthesizer = AVSpeechSynthesizer()

    func speak(_ text: String, language: Locale.Language?) {
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
            return
        }
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = voice(for: language)
        synthesizer.speak(utterance)
    }

    private func voice(for language: Locale.Language?) -> AVSpeechSynthesisVoice? {
        guard let code = language?.languageCode?.identifier.lowercased() else { return nil }
        let candidates = AVSpeechSynthesisVoice.speechVoices().filter { $0.language.lowercased().hasPrefix(code) }
        return candidates.max { $0.quality.rawValue < $1.quality.rawValue }
    }
}
