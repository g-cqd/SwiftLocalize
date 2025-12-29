//
//  GeminiProvider.swift
//  SwiftLocalize
//

import Foundation

// MARK: - Gemini Provider

/// Translation provider using Google's Gemini API.
public final class GeminiProvider: TranslationProvider, @unchecked Sendable {
    public let identifier = "gemini"
    public let displayName = "Google Gemini"

    private let httpClient: HTTPClient
    private let config: GeminiProviderConfig
    private let promptBuilder: TranslationPromptBuilder

    /// Configuration for the Gemini provider.
    public struct GeminiProviderConfig: Sendable {
        /// API key for authentication.
        public let apiKey: String

        /// Model to use for translation.
        public let model: String

        /// Base URL for the API.
        public let baseURL: String

        /// Temperature for generation (0.0 to 2.0).
        public let temperature: Double

        /// Maximum output tokens.
        public let maxOutputTokens: Int

        /// Available Gemini models for translation.
        public enum Model {
            /// Gemini 3 Flash - Frontier intelligence with Flash-level speed (released Dec 2025)
            public static let gemini3_flash = "gemini-3-flash-preview"
            /// Gemini 3 Pro - Reasoning-first model for complex agentic workflows
            public static let gemini3_pro = "gemini-3-pro"
            /// Gemini 2.0 Flash - Stable multimodal model
            public static let gemini2_0_flash = "gemini-2.0-flash"
            /// Gemini 2.0 Flash Lite - Ultra-efficient for high-frequency tasks
            public static let gemini2_0_flash_lite = "gemini-2.0-flash-lite"
        }

        public init(
            apiKey: String,
            model: String = Model.gemini3_flash,
            baseURL: String = "https://generativelanguage.googleapis.com/v1beta",
            temperature: Double = 0.3,
            maxOutputTokens: Int = 4096
        ) {
            self.apiKey = apiKey
            self.model = model
            self.baseURL = baseURL
            self.temperature = temperature
            self.maxOutputTokens = maxOutputTokens
        }

        /// Create config from provider configuration.
        public static func from(
            providerConfig: ProviderConfig?,
            apiKey: String
        ) -> GeminiProviderConfig {
            GeminiProviderConfig(
                apiKey: apiKey,
                model: providerConfig?.model ?? Model.gemini3_flash,
                baseURL: providerConfig?.baseURL ?? "https://generativelanguage.googleapis.com/v1beta"
            )
        }
    }

    public init(config: GeminiProviderConfig, httpClient: HTTPClient = HTTPClient()) {
        self.config = config
        self.httpClient = httpClient
        self.promptBuilder = TranslationPromptBuilder()
    }

    /// Convenience initializer that reads API key from environment.
    public convenience init(
        apiKeyEnvVar: String = "GEMINI_API_KEY",
        model: String = GeminiProviderConfig.Model.gemini3_flash
    ) throws {
        guard let apiKey = ProcessInfo.processInfo.environment[apiKeyEnvVar] else {
            throw ConfigurationError.environmentVariableNotFound(apiKeyEnvVar)
        }
        let config = GeminiProviderConfig(apiKey: apiKey, model: model)
        self.init(config: config)
    }

    // MARK: - TranslationProvider

    public func isAvailable() async -> Bool {
        !config.apiKey.isEmpty
    }

    public func supportedLanguages() async throws -> [LanguagePair] {
        // Gemini supports virtually all language pairs
        []
    }

    public func translate(
        _ strings: [String],
        from source: LanguageCode,
        to target: LanguageCode,
        context: TranslationContext?
    ) async throws -> [TranslationResult] {
        guard !strings.isEmpty else { return [] }

        let systemPrompt = promptBuilder.buildSystemPrompt(
            context: context,
            targetLanguage: target
        )
        let userPrompt = promptBuilder.buildUserPrompt(
            strings: strings,
            context: context,
            targetLanguage: target
        )

        // Combine system and user prompts for Gemini
        let combinedPrompt = """
        \(systemPrompt)

        ---

        \(userPrompt)
        """

        let request = GenerateContentRequest(
            contents: [
                .init(parts: [.init(text: combinedPrompt)])
            ],
            generationConfig: GenerationConfig(
                temperature: config.temperature,
                maxOutputTokens: config.maxOutputTokens,
                responseMimeType: "application/json"
            )
        )

        let url = "\(config.baseURL)/models/\(config.model):generateContent?key=\(config.apiKey)"

        let response: GenerateContentResponse
        do {
            response = try await httpClient.post(
                url: url,
                body: request,
                headers: ["Content-Type": "application/json"]
            )
        } catch {
            throw mapHTTPError(error)
        }

        guard let candidate = response.candidates?.first,
              let part = candidate.content.parts.first,
              let text = part.text else {
            throw TranslationError.invalidResponse("No content in response")
        }

        return try promptBuilder.parseResponse(
            text,
            originalStrings: strings,
            provider: identifier
        )
    }

    // MARK: - Error Mapping

    private func mapHTTPError(_ error: HTTPError) -> TranslationError {
        switch error {
        case .statusCode(429, _):
            return .rateLimitExceeded(provider: identifier, retryAfter: nil)
        case .statusCode(503, _):
            return .providerError(provider: identifier, message: "Service temporarily unavailable")
        case let .statusCode(code, data):
            let message = extractGeminiError(from: data) ?? "HTTP \(code)"
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

    private func extractGeminiError(from data: Data) -> String? {
        struct GeminiError: Decodable {
            let error: ErrorDetail

            struct ErrorDetail: Decodable {
                let code: Int
                let message: String
                let status: String?
            }
        }

        guard let errorResponse = try? JSONDecoder().decode(GeminiError.self, from: data) else {
            return String(data: data, encoding: .utf8)
        }
        return errorResponse.error.message
    }
}

// MARK: - Gemini API Models

/// Request body for generateContent endpoint.
private struct GenerateContentRequest: Encodable {
    let contents: [Content]
    let generationConfig: GenerationConfig?

    struct Content: Encodable {
        let parts: [Part]
        let role: String?

        init(parts: [Part], role: String? = "user") {
            self.parts = parts
            self.role = role
        }
    }

    struct Part: Encodable {
        let text: String?

        init(text: String) {
            self.text = text
        }
    }
}

/// Generation configuration.
private struct GenerationConfig: Encodable {
    let temperature: Double?
    let maxOutputTokens: Int?
    let responseMimeType: String?

    enum CodingKeys: String, CodingKey {
        case temperature
        case maxOutputTokens
        case responseMimeType
    }
}

/// Response body from generateContent endpoint.
private struct GenerateContentResponse: Decodable {
    let candidates: [Candidate]?
    let usageMetadata: UsageMetadata?

    struct Candidate: Decodable {
        let content: Content
        let finishReason: String?
        let index: Int?

        enum CodingKeys: String, CodingKey {
            case content
            case finishReason
            case index
        }
    }

    struct Content: Decodable {
        let parts: [Part]
        let role: String?
    }

    struct Part: Decodable {
        let text: String?
    }

    struct UsageMetadata: Decodable {
        let promptTokenCount: Int?
        let candidatesTokenCount: Int?
        let totalTokenCount: Int?
    }
}
