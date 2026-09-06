import Foundation

struct OpenRouterModel: Identifiable, Hashable {
    let id: String
    let name: String
    /// USD per 1M tokens; negative means "varies" (router models).
    let promptPricePerMillion: Double
    let completionPricePerMillion: Double
    let contextLength: Int

    /// "Gemini 2.5 Flash Lite" from "Google: Gemini 2.5 Flash Lite".
    var shortName: String {
        if let range = name.range(of: ": ") { return String(name[range.upperBound...]) }
        return name
    }

    var priceDescription: String {
        guard promptPricePerMillion >= 0 else { return "price varies" }
        return String(format: "$%.2f in · $%.2f out / 1M tokens", promptPricePerMillion, completionPricePerMillion)
    }
}

struct OpenRouterKeyInfo: Decodable {
    let label: String
    let limit: Double?
    let usage: Double
    let limitRemaining: Double?
    let isFreeTier: Bool

    enum CodingKeys: String, CodingKey {
        case label, limit, usage
        case limitRemaining = "limit_remaining"
        case isFreeTier = "is_free_tier"
    }
}

enum OpenRouterError: LocalizedError {
    case missingKey
    case http(Int, String)
    case badResponse

    var errorDescription: String? {
        switch self {
        case .missingKey:
            return "Add an OpenRouter API key in Settings → Online to translate online."
        case .http(let status, let message):
            switch status {
            case 401: return "OpenRouter rejected the API key."
            case 402: return "The OpenRouter account is out of credits."
            case 429: return "OpenRouter rate limit reached — try again in a moment."
            default: return "OpenRouter error \(status): \(message)"
            }
        case .badResponse:
            return "Unexpected response from OpenRouter."
        }
    }
}

enum OpenRouterEvent {
    case sourceLanguage(Locale.Language?)
    case delta(String)
}

/// Minimal OpenRouter client: model list, key check, and a streaming translation call.
struct OpenRouterClient {
    static let baseURL = URL(string: "https://openrouter.ai/api/v1")!
    var apiKey: String

    // MARK: Models (public endpoint)

    static func fetchModels() async throws -> [OpenRouterModel] {
        var request = URLRequest(url: baseURL.appending(path: "models"))
        request.setValue("SelectTranslate", forHTTPHeaderField: "X-OpenRouter-Title")
        let (data, response) = try await URLSession.shared.data(for: request)
        try check(response, data: data)
        let decoded = try JSONDecoder().decode(ModelsResponse.self, from: data)
        return decoded.data.compactMap { entry -> OpenRouterModel? in
            guard !entry.id.contains(":batch") else { return nil }
            let outputs = entry.architecture?.output_modalities ?? ["text"]
            guard outputs.contains("text"), !outputs.contains("image") else { return nil }
            let prompt = Double(entry.pricing?.prompt ?? "") ?? 0
            let completion = Double(entry.pricing?.completion ?? "") ?? 0
            return OpenRouterModel(
                id: entry.id,
                name: entry.name,
                promptPricePerMillion: prompt < 0 ? -1 : prompt * 1_000_000,
                completionPricePerMillion: completion < 0 ? -1 : completion * 1_000_000,
                contextLength: entry.context_length ?? 0
            )
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    // MARK: Key

    func keyInfo() async throws -> OpenRouterKeyInfo {
        let (data, response) = try await URLSession.shared.data(for: request(path: "key"))
        try Self.check(response, data: data)
        return try JSONDecoder().decode(KeyResponse.self, from: data).data
    }

    // MARK: Translation

    /// Streams the translation. The model is asked to start with a `LANG: xx` line naming the
    /// source language; that line is parsed out and delivered as `.sourceLanguage`.
    func streamTranslation(
        _ text: String,
        target: Locale.Language,
        sourceHint: Locale.Language?,
        model: String,
        instructions: String
    ) -> AsyncThrowingStream<OpenRouterEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var request = self.request(path: "chat/completions", method: "POST")
                    let body = ChatRequest(model: model, stream: true, messages: [
                        .init(role: "system", content: Self.systemPrompt(target: target, hint: sourceHint, instructions: instructions)),
                        .init(role: "user", content: text),
                    ])
                    request.httpBody = try JSONEncoder().encode(body)

                    let (bytes, response) = try await URLSession.shared.bytes(for: request)
                    guard let http = response as? HTTPURLResponse else { throw OpenRouterError.badResponse }
                    if http.statusCode != 200 {
                        var data = Data()
                        for try await byte in bytes { data.append(byte) }
                        throw OpenRouterError.http(http.statusCode, Self.errorMessage(from: data))
                    }

                    var header = ""
                    var headerDone = false
                    for try await line in bytes.lines {
                        try Task.checkCancellation()
                        guard line.hasPrefix("data:") else { continue }
                        let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
                        if payload == "[DONE]" { break }
                        guard let data = payload.data(using: .utf8),
                              let chunk = try? JSONDecoder().decode(StreamChunk.self, from: data) else { continue }
                        if let error = chunk.error { throw OpenRouterError.http(error.code ?? 500, error.message) }
                        guard let content = chunk.choices?.first?.delta?.content, !content.isEmpty else { continue }

                        if headerDone {
                            continuation.yield(.delta(content))
                            continue
                        }
                        header += content
                        guard let newline = header.firstIndex(of: "\n") else {
                            if header.count > 48 {
                                // No header is coming; treat everything as translation.
                                headerDone = true
                                continuation.yield(.sourceLanguage(nil))
                                continuation.yield(.delta(header))
                            }
                            continue
                        }
                        headerDone = true
                        let firstLine = String(header[..<newline])
                        let rest = String(header[header.index(after: newline)...])
                        if let language = Self.parseLanguageHeader(firstLine) {
                            continuation.yield(.sourceLanguage(language))
                        } else {
                            continuation.yield(.sourceLanguage(nil))
                            continuation.yield(.delta(firstLine + "\n"))
                        }
                        if !rest.isEmpty { continuation.yield(.delta(rest)) }
                    }
                    if !headerDone {
                        if let language = Self.parseLanguageHeader(header) {
                            continuation.yield(.sourceLanguage(language))
                        } else {
                            continuation.yield(.sourceLanguage(nil))
                            continuation.yield(.delta(header))
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    // MARK: Helpers

    private func request(path: String, method: String = "GET") -> URLRequest {
        var request = URLRequest(url: Self.baseURL.appending(path: path))
        request.httpMethod = method
        request.timeoutInterval = 30
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("SelectTranslate", forHTTPHeaderField: "X-OpenRouter-Title")
        return request
    }

    private static func check(_ response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else { throw OpenRouterError.badResponse }
        guard http.statusCode == 200 else { throw OpenRouterError.http(http.statusCode, errorMessage(from: data)) }
    }

    private static func errorMessage(from data: Data) -> String {
        if let decoded = try? JSONDecoder().decode(ErrorResponse.self, from: data) { return decoded.error.message }
        return String(decoding: data.prefix(200), as: UTF8.self)
    }

    static func parseLanguageHeader(_ line: String) -> Locale.Language? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.uppercased().hasPrefix("LANG:") else { return nil }
        let code = trimmed.dropFirst(5)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "`*\"'."))
        guard code.range(of: #"^[A-Za-z]{2,3}(-[A-Za-z0-9]{2,8})*$"#, options: .regularExpression) != nil else { return nil }
        return Locale.Language(identifier: code)
    }

    static func systemPrompt(target: Locale.Language, hint: Locale.Language?, instructions: String) -> String {
        var lines = [
            "You are a professional translator embedded in a macOS app. Translate the text the user sends into \(target.displayName) (\(target.compactIdentifier)).",
            "Rules:",
            "- Reply in exactly this format: first line \"LANG: <BCP-47 code of the text's original language>\", then a newline, then the translation and nothing else.",
            "- Output only the translation — no explanations, notes, or quotation marks.",
            "- Preserve line breaks, lists, punctuation style, names, numbers, URLs, and code exactly.",
            "- If the text is already in \(target.displayName), return it unchanged after the LANG line.",
        ]
        if let hint {
            lines.append("- The text is probably in \(hint.displayName), but trust the text itself.")
        }
        let extra = instructions.trimmingCharacters(in: .whitespacesAndNewlines)
        if !extra.isEmpty {
            lines.append("Additional instructions from the user:")
            lines.append(extra)
        }
        return lines.joined(separator: "\n")
    }
}

// MARK: - Wire types

private struct ModelsResponse: Decodable {
    struct Entry: Decodable {
        struct Pricing: Decodable { let prompt: String?; let completion: String? }
        struct Architecture: Decodable { let output_modalities: [String]? }
        let id: String
        let name: String
        let context_length: Int?
        let pricing: Pricing?
        let architecture: Architecture?
    }
    let data: [Entry]
}

private struct KeyResponse: Decodable { let data: OpenRouterKeyInfo }

private struct ChatRequest: Encodable {
    struct Message: Encodable { let role: String; let content: String }
    let model: String
    let stream: Bool
    let messages: [Message]
}

private struct StreamChunk: Decodable {
    struct Choice: Decodable {
        struct Delta: Decodable { let content: String? }
        let delta: Delta?
    }
    let choices: [Choice]?
    let error: APIError?
}

private struct APIError: Decodable { let message: String; let code: Int? }
private struct ErrorResponse: Decodable { let error: APIError }
