//
//  OpenAIProvider.swift
//  SwiftLocalize
//

import Foundation

// MARK: - OpenAIProvider

/// Translation provider using OpenAI's Chat Completions API.
public final class OpenAIProvider: TranslationProvider, @unchecked Sendable {
    // MARK: Lifecycle

    public init(config: OpenAIProviderConfig, httpClient: HTTPClient = HTTPClient()) {
        self.config = config
        self.httpClient = httpClient
        promptBuilder = TranslationPromptBuilder()
    }

    /// Convenience initializer that reads API key from environment.
    public convenience init(
        apiKeyEnvVar: String = "OPENAI_API_KEY",
        model: String = OpenAIProviderConfig.Model.gpt5_2_chat,
    ) throws {
        guard let apiKey = ProcessInfo.processInfo.environment[apiKeyEnvVar] else {
            throw ConfigurationError.environmentVariableNotFound(apiKeyEnvVar)
        }
        let config = OpenAIProviderConfig(apiKey: apiKey, model: model)
        self.init(config: config)
    }

    // MARK: Public

    /// Configuration for the OpenAI provider.
    public struct OpenAIProviderConfig: Sendable {
        // MARK: Lifecycle

        public init(
            apiKey: String,
            model: String = Model.gpt5_2_chat,
            baseURL: String = "https://api.openai.com/v1",
            maxTokens: Int = 4096,
            temperature: Double = 0.3,
        ) {
            self.apiKey = apiKey
            self.model = model
            self.baseURL = baseURL
            self.maxTokens = maxTokens
            self.temperature = temperature
        }

        // MARK: Public

        /// Available OpenAI models for translation.
        public enum Model {
            /// GPT-5.2 - Flagship model for coding and agentic tasks (released Dec 2025)
            public static let gpt5_2 = "gpt-5.2"
            /// GPT-5.2 Chat Latest - Fast version for writing and information seeking
            public static let gpt5_2_chat = "gpt-5.2-chat-latest"
            /// GPT-5.2 Pro - Most accurate answers with configurable reasoning
            public static let gpt5_2_pro = "gpt-5.2-pro"
            /// GPT-5.1 - Balanced intelligence and speed (released Nov 2025)
            public static let gpt5_1 = "gpt-5.1"
            /// o4-mini - Fast, cost-efficient reasoning (strong in math/coding)
            public static let o4_mini = "o4-mini"
            /// GPT-4.1 Mini - Previous generation, cost-effective
            public static let gpt4_1_mini = "gpt-4.1-mini"
        }

        /// API key for authentication.
        public let apiKey: String

        /// Model to use for translation.
        public let model: String

        /// Base URL for the API (allows for Azure OpenAI or proxies).
        public let baseURL: String

        /// Maximum tokens in response.
        public let maxTokens: Int

        /// Temperature for generation (0.0 to 2.0).
        public let temperature: Double

        /// Create config from provider configuration.
        public static func from(
            providerConfig: ProviderConfig?,
            apiKey: String,
        ) -> OpenAIProviderConfig {
            OpenAIProviderConfig(
                apiKey: apiKey,
                model: providerConfig?.model ?? Model.gpt5_2_chat,
                baseURL: providerConfig?.baseURL ?? "https://api.openai.com/v1",
            )
        }
    }

    public let identifier = "openai"
    public let displayName = "OpenAI GPT"

    // MARK: - TranslationProvider

    public func isAvailable() async -> Bool {
        !config.apiKey.isEmpty
    }

    public func supportedLanguages() async throws -> [LanguagePair] {
        // OpenAI GPT models support virtually all language pairs
        []
    }

    public func translate(
        _ strings: [String],
        from source: LanguageCode,
        to target: LanguageCode,
        context: TranslationContext?,
    ) async throws -> [TranslationResult] {
        guard !strings.isEmpty else { return [] }

        let systemPrompt = promptBuilder.buildSystemPrompt(
            context: context,
            targetLanguage: target,
        )
        let userPrompt = promptBuilder.buildUserPrompt(
            strings: strings,
            context: context,
            targetLanguage: target,
        )

        let request = ChatCompletionRequest(
            model: config.model,
            messages: [
                .init(role: "system", content: systemPrompt),
                .init(role: "user", content: userPrompt),
            ],
            temperature: config.temperature,
            maxTokens: config.maxTokens,
            responseFormat: ResponseFormat(type: "json_object"),
        )

        let response: ChatCompletionResponse
        do {
            response = try await httpClient.post(
                url: "\(config.baseURL)/chat/completions",
                body: request,
                headers: [
                    "Authorization": "Bearer \(config.apiKey)",
                    "Content-Type": "application/json",
                ],
            )
        } catch {
            throw mapHTTPError(error)
        }

        guard let content = response.choices.first?.message.content else {
            throw TranslationError.invalidResponse("No content in response")
        }

        return try promptBuilder.parseResponse(
            content,
            originalStrings: strings,
            provider: identifier,
        )
    }

    // MARK: Private

    private let httpClient: HTTPClient
    private let config: OpenAIProviderConfig
    private let promptBuilder: TranslationPromptBuilder

    // MARK: - Error Mapping

    private func mapHTTPError(_ error: HTTPError) -> TranslationError {
        switch error {
        case .statusCode(429, _):
            return .rateLimitExceeded(provider: identifier, retryAfter: nil)

        case let .statusCode(code, data):
            let message = httpClient.extractErrorMessage(from: data) ?? "HTTP \(code)"
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
}

// MARK: - ChatCompletionRequest

/// Request body for chat completions.
private struct ChatCompletionRequest: Encodable {
    struct Message: Encodable {
        let role: String
        let content: String
    }

    enum CodingKeys: String, CodingKey {
        case model
        case messages
        case temperature
        case maxTokens = "max_tokens"
        case responseFormat = "response_format"
    }

    let model: String
    let messages: [Message]
    let temperature: Double
    let maxTokens: Int
    let responseFormat: ResponseFormat?
}

// MARK: - ResponseFormat

/// Response format specification.
private struct ResponseFormat: Encodable {
    let type: String
}

// MARK: - ChatCompletionResponse

/// Response body from chat completions.
private struct ChatCompletionResponse: Decodable {
    struct Choice: Decodable {
        enum CodingKeys: String, CodingKey {
            case index
            case message
            case finishReason = "finish_reason"
        }

        let index: Int
        let message: Message
        let finishReason: String?
    }

    struct Message: Decodable {
        let role: String
        let content: String?
    }

    struct Usage: Decodable {
        enum CodingKeys: String, CodingKey {
            case promptTokens = "prompt_tokens"
            case completionTokens = "completion_tokens"
            case totalTokens = "total_tokens"
        }

        let promptTokens: Int
        let completionTokens: Int
        let totalTokens: Int
    }

    let id: String
    let object: String
    let created: Int
    let model: String
    let choices: [Choice]
    let usage: Usage?
}
