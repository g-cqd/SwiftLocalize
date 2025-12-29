//
//  DeepLProvider.swift
//  SwiftLocalize
//

import Foundation

// MARK: - DeepLProvider

/// Translation provider using DeepL's Translation API.
///
/// DeepL is a dedicated translation service that provides high-quality translations
/// without using LLM prompts. It supports formality settings for some languages.
public final class DeepLProvider: TranslationProvider, @unchecked Sendable {
    // MARK: Lifecycle

    public init(config: DeepLProviderConfig, httpClient: HTTPClient = HTTPClient()) {
        self.config = config
        self.httpClient = httpClient
    }

    /// Convenience initializer that reads API key from environment.
    public convenience init(
        apiKeyEnvVar: String = "DEEPL_API_KEY",
        formality: Formality = .default,
    ) throws {
        guard let apiKey = ProcessInfo.processInfo.environment[apiKeyEnvVar] else {
            throw ConfigurationError.environmentVariableNotFound(apiKeyEnvVar)
        }
        let tier: DeepLProviderConfig.Tier = apiKey.hasSuffix(":fx") ? .free : .pro
        let config = DeepLProviderConfig(apiKey: apiKey, tier: tier, formality: formality)
        self.init(config: config)
    }

    // MARK: Public

    /// Configuration for the DeepL provider.
    public struct DeepLProviderConfig: Sendable {
        // MARK: Lifecycle

        public init(
            apiKey: String,
            tier: Tier = .free,
            formality: Formality = .default,
            preserveFormatting: Bool = true,
        ) {
            self.apiKey = apiKey
            baseURL = tier.baseURL
            self.formality = formality
            self.preserveFormatting = preserveFormatting
        }

        public init(
            apiKey: String,
            baseURL: String,
            formality: Formality = .default,
            preserveFormatting: Bool = true,
        ) {
            self.apiKey = apiKey
            self.baseURL = baseURL
            self.formality = formality
            self.preserveFormatting = preserveFormatting
        }

        // MARK: Public

        /// Tier (free or pro) - determines API base URL.
        public enum Tier: String, Sendable {
            case free
            case pro

            // MARK: Internal

            var baseURL: String {
                switch self {
                case .free: "https://api-free.deepl.com/v2"
                case .pro: "https://api.deepl.com/v2"
                }
            }
        }

        /// API key for authentication.
        public let apiKey: String

        /// Base URL for the API (free or pro tier).
        public let baseURL: String

        /// Formality level for translations.
        public let formality: Formality

        /// Whether to preserve formatting.
        public let preserveFormatting: Bool

        /// Create config from provider configuration.
        public static func from(
            providerConfig: ProviderConfig?,
            apiKey: String,
        ) -> DeepLProviderConfig {
            let tier: Tier = apiKey.hasSuffix(":fx") ? .free : .pro
            return DeepLProviderConfig(
                apiKey: apiKey,
                tier: tier,
                formality: providerConfig?.formality ?? .default,
            )
        }
    }

    public let identifier = "deepl"
    public let displayName = "DeepL"

    // MARK: - TranslationProvider

    public func isAvailable() async -> Bool {
        !config.apiKey.isEmpty
    }

    public func supportedLanguages() async throws -> [LanguagePair] {
        // DeepL supports many but not all language pairs
        // Returning empty to indicate "check at translation time"
        []
    }

    public func translate(
        _ strings: [String],
        from source: LanguageCode,
        to target: LanguageCode,
        context: TranslationContext?,
    ) async throws -> [TranslationResult] {
        guard !strings.isEmpty else { return [] }

        // Convert language codes to DeepL format
        let sourceLang = convertToDeepLCode(source)
        let targetLang = convertToDeepLCode(target)

        let request = TranslateRequest(
            text: strings,
            sourceLang: sourceLang,
            targetLang: targetLang,
            formality: mapFormality(config.formality, for: targetLang),
            preserveFormatting: config.preserveFormatting,
        )

        let response: TranslateResponse
        do {
            response = try await httpClient.post(
                url: "\(config.baseURL)/translate",
                body: request,
                headers: [
                    "Authorization": "DeepL-Auth-Key \(config.apiKey)",
                    "Content-Type": "application/json",
                ],
            )
        } catch {
            throw mapHTTPError(error)
        }

        guard response.translations.count == strings.count else {
            throw TranslationError.invalidResponse(
                "Expected \(strings.count) translations, got \(response.translations.count)",
            )
        }

        return zip(strings, response.translations).map { original, translation in
            TranslationResult(
                original: original,
                translated: translation.text,
                confidence: 1.0, // DeepL doesn't provide confidence scores
                provider: identifier,
                metadata: [
                    "detected_source_language": translation.detectedSourceLanguage ?? sourceLang,
                ],
            )
        }
    }

    // MARK: Private

    private let httpClient: HTTPClient
    private let config: DeepLProviderConfig

    // MARK: - Language Code Conversion

    private func convertToDeepLCode(_ code: LanguageCode) -> String {
        // DeepL uses uppercase ISO codes, with some exceptions
        let upperCode = code.code.uppercased()

        // Handle regional variants
        switch upperCode {
        case "EN-GB",
             "EN-US": return upperCode
        case "PT-BR",
             "PT-PT": return upperCode
        case "ZH-CN",
             "ZH-HANS": return "ZH-HANS"
        case "ZH-HANT",
             "ZH-TW": return "ZH-HANT"
        default:
            // For source language, DeepL only wants the base code
            let base = upperCode.split(separator: "-").first.map(String.init) ?? upperCode
            return base
        }
    }

    private func mapFormality(_ formality: Formality, for targetLang: String) -> String? {
        // Formality is only supported for certain languages
        let formalityLanguages = Set(["DE", "FR", "IT", "ES", "NL", "PL", "PT-PT", "PT-BR", "RU", "JA", "KO"])

        let baseTargetLang = targetLang.split(separator: "-").first.map(String.init) ?? targetLang

        guard formalityLanguages.contains(baseTargetLang) || formalityLanguages.contains(targetLang) else {
            return nil
        }

        switch formality {
        case .default: return nil
        case .more: return "more"
        case .less: return "less"
        case .preferMore: return "prefer_more"
        case .preferLess: return "prefer_less"
        }
    }

    // MARK: - Error Mapping

    private func mapHTTPError(_ error: HTTPError) -> TranslationError {
        switch error {
        case .statusCode(403, _):
            return .providerError(provider: identifier, message: "Authentication failed - check API key")

        case .statusCode(429, _):
            return .rateLimitExceeded(provider: identifier, retryAfter: nil)

        case .statusCode(456, _):
            return .providerError(provider: identifier, message: "Quota exceeded")

        case .statusCode(503, _):
            return .providerError(provider: identifier, message: "Service temporarily unavailable")

        case let .statusCode(code, data):
            let message = extractDeepLError(from: data) ?? "HTTP \(code)"
            return .providerError(provider: identifier, message: message)

        case .timeout:
            return .providerError(provider: identifier, message: "Request timed out")

        case let .connectionFailed(msg):
            return .providerError(provider: identifier, message: "Connection failed: \(msg)")

        case let .decodingFailed(msg):
            return .invalidResponse("Failed to decode response: \(msg)")

        default:
            return .providerError(provider: identifier, message: error.localizedDescription)
        }
    }

    private func extractDeepLError(from data: Data) -> String? {
        struct DeepLError: Decodable {
            let message: String?
        }

        guard let errorResponse = try? JSONDecoder().decode(DeepLError.self, from: data) else {
            return String(data: data, encoding: .utf8)
        }
        return errorResponse.message
    }
}

// MARK: - TranslateRequest

/// Request body for translate endpoint.
private struct TranslateRequest: Encodable {
    enum CodingKeys: String, CodingKey {
        case text
        case sourceLang = "source_lang"
        case targetLang = "target_lang"
        case formality
        case preserveFormatting = "preserve_formatting"
    }

    let text: [String]
    let sourceLang: String
    let targetLang: String
    let formality: String?
    let preserveFormatting: Bool?

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(text, forKey: .text)
        try container.encode(sourceLang, forKey: .sourceLang)
        try container.encode(targetLang, forKey: .targetLang)
        try container.encodeIfPresent(formality, forKey: .formality)
        try container.encodeIfPresent(preserveFormatting, forKey: .preserveFormatting)
    }
}

// MARK: - TranslateResponse

/// Response body from translate endpoint.
private struct TranslateResponse: Decodable {
    struct Translation: Decodable {
        enum CodingKeys: String, CodingKey {
            case text
            case detectedSourceLanguage = "detected_source_language"
        }

        let text: String
        let detectedSourceLanguage: String?
    }

    let translations: [Translation]
}
