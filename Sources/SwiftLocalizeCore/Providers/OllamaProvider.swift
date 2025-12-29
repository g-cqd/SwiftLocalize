//
//  OllamaProvider.swift
//  SwiftLocalize
//

import Foundation

// MARK: - Ollama Provider

/// Translation provider using a local Ollama server.
///
/// Ollama runs LLMs locally, providing free, private translation without API keys.
/// Requires Ollama to be installed and running: https://ollama.ai
public final class OllamaProvider: TranslationProvider, @unchecked Sendable {
    public let identifier = "ollama"
    public let displayName = "Ollama (Local)"

    private let httpClient: HTTPClient
    private let config: OllamaProviderConfig
    private let promptBuilder: TranslationPromptBuilder

    /// Configuration for the Ollama provider.
    public struct OllamaProviderConfig: Sendable {
        /// Base URL for the Ollama server.
        public let baseURL: String

        /// Model to use for translation.
        public let model: String

        /// Temperature for generation (0.0 to 2.0).
        public let temperature: Double

        /// Number of context tokens.
        public let numCtx: Int

        /// Request timeout in seconds.
        public let timeout: TimeInterval

        public init(
            baseURL: String = "http://localhost:11434",
            model: String = "llama3.2",
            temperature: Double = 0.3,
            numCtx: Int = 8192,
            timeout: TimeInterval = 120
        ) {
            self.baseURL = baseURL
            self.model = model
            self.temperature = temperature
            self.numCtx = numCtx
            self.timeout = timeout
        }

        /// Create config from provider configuration.
        public static func from(providerConfig: ProviderConfig?) -> OllamaProviderConfig {
            OllamaProviderConfig(
                baseURL: providerConfig?.baseURL ?? "http://localhost:11434",
                model: providerConfig?.model ?? "llama3.2"
            )
        }
    }

    public init(config: OllamaProviderConfig) {
        self.config = config
        // Use longer timeout for local models
        self.httpClient = HTTPClient(timeout: config.timeout)
        self.promptBuilder = TranslationPromptBuilder()
    }

    public convenience init(
        baseURL: String = "http://localhost:11434",
        model: String = "llama3.2"
    ) {
        let config = OllamaProviderConfig(baseURL: baseURL, model: model)
        self.init(config: config)
    }

    // MARK: - TranslationProvider

    public func isAvailable() async -> Bool {
        // Check if Ollama server is running
        do {
            let _: TagsResponse = try await httpClient.get(
                url: "\(config.baseURL)/api/tags"
            )
            return true
        } catch {
            return false
        }
    }

    public func supportedLanguages() async throws -> [LanguagePair] {
        // Local LLMs support virtually all language pairs
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

        // Combine prompts for Ollama's generate endpoint
        let fullPrompt = """
        \(systemPrompt)

        ---

        \(userPrompt)
        """

        let request = GenerateRequest(
            model: config.model,
            prompt: fullPrompt,
            stream: false,
            options: GenerateOptions(
                temperature: config.temperature,
                numCtx: config.numCtx
            ),
            format: "json"
        )

        do {
            let response: GenerateResponse = try await httpClient.post(
                url: "\(config.baseURL)/api/generate",
                body: request,
                headers: ["Content-Type": "application/json"]
            )
            return try promptBuilder.parseResponse(
                response.response,
                originalStrings: strings,
                provider: identifier
            )
        } catch let httpError as HTTPError {
            throw mapHTTPError(httpError)
        } catch {
            throw TranslationError.providerError(
                provider: identifier,
                message: error.localizedDescription
            )
        }
    }

    /// List available models on the Ollama server.
    public func listModels() async throws -> [String] {
        do {
            let response: TagsResponse = try await httpClient.get(
                url: "\(config.baseURL)/api/tags"
            )
            return response.models.map(\.name)
        } catch let httpError as HTTPError {
            throw mapHTTPError(httpError)
        } catch {
            throw TranslationError.providerError(
                provider: identifier,
                message: error.localizedDescription
            )
        }
    }

    /// Pull a model to the local Ollama instance.
    public func pullModel(_ modelName: String) async throws {
        struct PullRequest: Encodable {
            let name: String
            let stream: Bool
        }

        struct PullResponse: Decodable {
            let status: String
        }

        let request = PullRequest(name: modelName, stream: false)

        do {
            let _: PullResponse = try await httpClient.post(
                url: "\(config.baseURL)/api/pull",
                body: request,
                headers: ["Content-Type": "application/json"]
            )
        } catch let httpError as HTTPError {
            throw mapHTTPError(httpError)
        } catch {
            throw TranslationError.providerError(
                provider: identifier,
                message: error.localizedDescription
            )
        }
    }

    // MARK: - Error Mapping

    private func mapHTTPError(_ error: HTTPError) -> TranslationError {
        switch error {
        case .timeout:
            return .providerError(
                provider: identifier,
                message: "Request timed out - model may be loading or too slow"
            )
        case let .connectionFailed(msg):
            if msg.contains("Connection refused") || msg.contains("Could not connect") {
                return .providerError(
                    provider: identifier,
                    message: "Cannot connect to Ollama server. Is it running? (ollama serve)"
                )
            }
            return .providerError(provider: identifier, message: "Connection failed: \(msg)")
        case .statusCode(404, _):
            return .providerError(
                provider: identifier,
                message: "Model '\(config.model)' not found. Try: ollama pull \(config.model)"
            )
        case let .statusCode(code, data):
            let message = String(data: data, encoding: .utf8) ?? "HTTP \(code)"
            return .providerError(provider: identifier, message: message)
        case let .decodingFailed(msg):
            return .invalidResponse("Failed to decode response: \(msg)")
        default:
            return .providerError(provider: identifier, message: error.localizedDescription)
        }
    }
}

// MARK: - Ollama API Models

/// Request body for generate endpoint.
private struct GenerateRequest: Encodable {
    let model: String
    let prompt: String
    let stream: Bool
    let options: GenerateOptions?
    let format: String?
}

/// Generation options for Ollama.
private struct GenerateOptions: Encodable {
    let temperature: Double?
    let numCtx: Int?

    enum CodingKeys: String, CodingKey {
        case temperature
        case numCtx = "num_ctx"
    }
}

/// Response body from generate endpoint.
private struct GenerateResponse: Decodable {
    let model: String
    let createdAt: String
    let response: String
    let done: Bool
    let totalDuration: Int?
    let loadDuration: Int?
    let promptEvalCount: Int?
    let promptEvalDuration: Int?
    let evalCount: Int?
    let evalDuration: Int?

    enum CodingKeys: String, CodingKey {
        case model
        case createdAt = "created_at"
        case response
        case done
        case totalDuration = "total_duration"
        case loadDuration = "load_duration"
        case promptEvalCount = "prompt_eval_count"
        case promptEvalDuration = "prompt_eval_duration"
        case evalCount = "eval_count"
        case evalDuration = "eval_duration"
    }
}

/// Response from tags (list models) endpoint.
private struct TagsResponse: Decodable {
    let models: [Model]

    struct Model: Decodable {
        let name: String
        let size: Int?
        let digest: String?
        let modifiedAt: String?

        enum CodingKeys: String, CodingKey {
            case name
            case size
            case digest
            case modifiedAt = "modified_at"
        }
    }
}
