//
//  AnthropicProvider.swift
//  SwiftLocalize
//

import Foundation

// MARK: - Anthropic Provider

/// Translation provider using Anthropic's Messages API.
public final class AnthropicProvider: TranslationProvider, @unchecked Sendable {
    public let identifier = "anthropic"
    public let displayName = "Anthropic Claude"

    private let httpClient: HTTPClient
    private let config: AnthropicProviderConfig
    private let promptBuilder: TranslationPromptBuilder

    /// Configuration for the Anthropic provider.
    public struct AnthropicProviderConfig: Sendable {
        /// API key for authentication.
        public let apiKey: String

        /// Model to use for translation.
        public let model: String

        /// Base URL for the API.
        public let baseURL: String

        /// Maximum tokens in response.
        public let maxTokens: Int

        /// API version header value.
        public let apiVersion: String

        /// Available Anthropic Claude models for translation.
        public enum Model {
            /// Claude Opus 4.5 - Most intelligent, best for complex tasks (Nov 2025)
            public static let opus4_5 = "claude-opus-4-5-20251124"
            /// Claude Sonnet 4.5 - Balanced performance (Sep 2025)
            public static let sonnet4_5 = "claude-sonnet-4-5-20250929"
            /// Claude Sonnet 4 - Previous generation, cost-effective (May 2025)
            public static let sonnet4 = "claude-sonnet-4-20250514"
            /// Claude Haiku 4.5 - Fast and efficient
            public static let haiku4_5 = "claude-haiku-4-5-20251124"
        }

        public init(
            apiKey: String,
            model: String = Model.sonnet4,
            baseURL: String = "https://api.anthropic.com",
            maxTokens: Int = 4096,
            apiVersion: String = "2023-06-01"
        ) {
            self.apiKey = apiKey
            self.model = model
            self.baseURL = baseURL
            self.maxTokens = maxTokens
            self.apiVersion = apiVersion
        }

        /// Create config from provider configuration.
        public static func from(
            providerConfig: ProviderConfig?,
            apiKey: String
        ) -> AnthropicProviderConfig {
            AnthropicProviderConfig(
                apiKey: apiKey,
                model: providerConfig?.model ?? Model.sonnet4,
                baseURL: providerConfig?.baseURL ?? "https://api.anthropic.com"
            )
        }
    }

    public init(config: AnthropicProviderConfig, httpClient: HTTPClient = HTTPClient()) {
        self.config = config
        self.httpClient = httpClient
        self.promptBuilder = TranslationPromptBuilder()
    }

    /// Convenience initializer that reads API key from environment.
    public convenience init(
        apiKeyEnvVar: String = "ANTHROPIC_API_KEY",
        model: String = AnthropicProviderConfig.Model.sonnet4
    ) throws {
        guard let apiKey = ProcessInfo.processInfo.environment[apiKeyEnvVar] else {
            throw ConfigurationError.environmentVariableNotFound(apiKeyEnvVar)
        }
        let config = AnthropicProviderConfig(apiKey: apiKey, model: model)
        self.init(config: config)
    }

    // MARK: - TranslationProvider

    public func isAvailable() async -> Bool {
        !config.apiKey.isEmpty
    }

    public func supportedLanguages() async throws -> [LanguagePair] {
        // Claude supports virtually all language pairs
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

        let request = MessagesRequest(
            model: config.model,
            maxTokens: config.maxTokens,
            system: systemPrompt,
            messages: [
                .init(role: "user", content: userPrompt)
            ]
        )

        let response: MessagesResponse
        do {
            response = try await httpClient.post(
                url: "\(config.baseURL)/v1/messages",
                body: request,
                headers: [
                    "x-api-key": config.apiKey,
                    "anthropic-version": config.apiVersion,
                    "Content-Type": "application/json"
                ]
            )
        } catch {
            throw mapHTTPError(error)
        }

        guard let textBlock = response.content.first(where: { $0.type == "text" }),
              let content = textBlock.text else {
            throw TranslationError.invalidResponse("No text content in response")
        }

        return try promptBuilder.parseResponse(
            content,
            originalStrings: strings,
            provider: identifier
        )
    }

    // MARK: - Error Mapping

    private func mapHTTPError(_ error: HTTPError) -> TranslationError {
        switch error {
        case .statusCode(429, _):
            return .rateLimitExceeded(provider: identifier, retryAfter: nil)
        case .statusCode(529, _):
            return .providerError(provider: identifier, message: "API overloaded, please retry")
        case let .statusCode(code, data):
            let message = extractAnthropicError(from: data) ?? "HTTP \(code)"
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

    private func extractAnthropicError(from data: Data) -> String? {
        struct AnthropicError: Decodable {
            let type: String
            let error: ErrorDetail

            struct ErrorDetail: Decodable {
                let type: String
                let message: String
            }
        }

        guard let errorResponse = try? JSONDecoder().decode(AnthropicError.self, from: data) else {
            return String(data: data, encoding: .utf8)
        }
        return errorResponse.error.message
    }
}

// MARK: - Anthropic API Models

/// Request body for messages endpoint.
private struct MessagesRequest: Encodable {
    let model: String
    let maxTokens: Int
    let system: String?
    let messages: [Message]

    struct Message: Encodable {
        let role: String
        let content: String
    }

    enum CodingKeys: String, CodingKey {
        case model
        case maxTokens = "max_tokens"
        case system
        case messages
    }
}

/// Response body from messages endpoint.
private struct MessagesResponse: Decodable {
    let id: String
    let type: String
    let role: String
    let content: [ContentBlock]
    let model: String
    let stopReason: String?
    let usage: Usage

    struct ContentBlock: Decodable {
        let type: String
        let text: String?
    }

    struct Usage: Decodable {
        let inputTokens: Int
        let outputTokens: Int

        enum CodingKeys: String, CodingKey {
            case inputTokens = "input_tokens"
            case outputTokens = "output_tokens"
        }
    }

    enum CodingKeys: String, CodingKey {
        case id
        case type
        case role
        case content
        case model
        case stopReason = "stop_reason"
        case usage
    }
}
