//
//  ConfigurationLoader.swift
//  SwiftLocalize
//

import Foundation

// MARK: - ConfigurationLoader

/// Loads and validates SwiftLocalize configuration files.
public struct ConfigurationLoader: Sendable {
    // MARK: Lifecycle

    public init() {}

    // MARK: Public

    /// Default configuration file names in search order.
    public static let defaultFileNames = [
        ".swiftlocalize.json",
        "swiftlocalize.json",
        ".swiftlocalize.yml",
        ".swiftlocalize.yaml",
    ]

    // MARK: - Loading

    /// Load configuration from a specific file path.
    public func load(from path: URL) throws(ConfigurationError) -> Configuration {
        guard FileManager.default.fileExists(atPath: path.path) else {
            throw .fileNotFound(path.path)
        }

        let data: Data
        do {
            data = try Data(contentsOf: path)
        } catch {
            throw .invalidFormat("Failed to read file: \(error.localizedDescription)")
        }

        return try parse(data: data, path: path)
    }

    /// Load configuration by searching for default config files in the given directory.
    public func load(searchingIn directory: URL) throws(ConfigurationError) -> Configuration {
        for fileName in Self.defaultFileNames {
            let filePath = directory.appendingPathComponent(fileName)
            if FileManager.default.fileExists(atPath: filePath.path) {
                return try load(from: filePath)
            }
        }

        throw .fileNotFound("No configuration file found in \(directory.path)")
    }

    /// Create a default configuration.
    public func defaultConfiguration() -> Configuration {
        Configuration(
            sourceLanguage: .english,
            targetLanguages: [.spanish, .french, .german],
            providers: [
                ProviderConfiguration(name: .appleTranslation, priority: 1),
                ProviderConfiguration(
                    name: .openai,
                    enabled: false,
                    priority: 2,
                    config: ProviderConfig(model: "gpt-4o", apiKeyEnv: "OPENAI_API_KEY"),
                ),
                ProviderConfiguration(
                    name: .anthropic,
                    enabled: false,
                    priority: 3,
                    config: ProviderConfig(model: "claude-sonnet-4-20250514", apiKeyEnv: "ANTHROPIC_API_KEY"),
                ),
            ],
        )
    }

    // MARK: - Validation

    /// Validate a configuration and return any issues.
    public func validate(_ config: Configuration) -> [ConfigurationIssue] {
        var issues: [ConfigurationIssue] = []

        // Check for target languages
        if config.targetLanguages.isEmpty {
            issues.append(.warning("No target languages specified"))
        }

        // Check for enabled providers
        let enabledProviders = config.providers.filter(\.enabled)
        if enabledProviders.isEmpty {
            issues.append(.error("No translation providers are enabled"))
        }

        // Validate provider configurations
        for provider in enabledProviders {
            issues.append(contentsOf: validateProvider(provider))
        }

        // Validate translation settings
        if config.translation.batchSize < 1 {
            issues.append(.error("Batch size must be at least 1"))
        }

        if config.translation.concurrency < 1 {
            issues.append(.error("Concurrency must be at least 1"))
        }

        if config.translation.rateLimit < 1 {
            issues.append(.error("Rate limit must be at least 1"))
        }

        // Validate context settings
        if let tm = config.context.translationMemory, tm.enabled {
            if tm.minSimilarity < 0 || tm.minSimilarity > 1 {
                issues.append(.error("Translation memory minSimilarity must be between 0 and 1"))
            }
        }

        return issues
    }

    // MARK: - Writing

    /// Write a configuration to a JSON file.
    public func write(_ config: Configuration, to path: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]

        let data = try encoder.encode(config)
        try data.write(to: path)
    }

    // MARK: Private

    // MARK: - Parsing

    private func parse(data: Data, path: URL) throws(ConfigurationError) -> Configuration {
        let ext = path.pathExtension.lowercased()

        switch ext {
        case "json":
            return try parseJSON(data: data)
        case "yaml",
             "yml":
            throw .invalidFormat("YAML configuration files are not yet supported. Please use JSON.")

        default:
            // Try JSON first
            if let config = try? parseJSON(data: data) {
                return config
            }
            throw .invalidFormat("Unsupported configuration file format: \(ext)")
        }
    }

    private func parseJSON(data: Data) throws(ConfigurationError) -> Configuration {
        let decoder = JSONDecoder()
        do {
            return try decoder.decode(Configuration.self, from: data)
        } catch let decodingError as DecodingError {
            throw .invalidFormat(formatDecodingError(decodingError))
        } catch {
            throw .invalidFormat(error.localizedDescription)
        }
    }

    private func formatDecodingError(_ error: DecodingError) -> String {
        switch error {
        case let .keyNotFound(key, context):
            let path = context.codingPath.map(\.stringValue).joined(separator: ".")
            return "Missing key '\(key.stringValue)' at path '\(path)'"

        case let .typeMismatch(type, context):
            let path = context.codingPath.map(\.stringValue).joined(separator: ".")
            return "Type mismatch at '\(path)': expected \(type)"

        case let .valueNotFound(type, context):
            let path = context.codingPath.map(\.stringValue).joined(separator: ".")
            return "Missing value of type \(type) at '\(path)'"

        case let .dataCorrupted(context):
            return "Corrupted data: \(context.debugDescription)"

        @unknown default:
            return error.localizedDescription
        }
    }

    private func validateProvider(_ provider: ProviderConfiguration) -> [ConfigurationIssue] {
        var issues: [ConfigurationIssue] = []

        switch provider.name {
        case .anthropic,
             .deepl,
             .gemini,
             .openai:
            // These require API keys
            if let apiKeyEnv = provider.config?.apiKeyEnv {
                if ProcessInfo.processInfo.environment[apiKeyEnv] == nil {
                    issues.append(.warning(
                        "Environment variable '\(apiKeyEnv)' for provider '\(provider.name.rawValue)' is not set",
                    ))
                }
            } else {
                issues.append(.warning(
                    "Provider '\(provider.name.rawValue)' has no API key environment variable configured",
                ))
            }

        case .ollama:
            // Ollama requires a base URL
            if provider.config?.baseURL == nil {
                issues.append(.warning(
                    "Provider 'ollama' has no baseURL configured, will use default",
                ))
            }

        case .cliCodex,
             .cliCopilot,
             .cliGemini:
            // CLI tools will auto-detect binary if path not configured
            break

        case .cliGeneric:
            // Generic CLI requires explicit path
            if provider.config?.path == nil {
                issues.append(.warning(
                    "Provider 'generic-cli' requires a 'path' configuration",
                ))
            }

        case .appleTranslation,
             .foundationModels:
            // No special configuration needed
            break
        }

        return issues
    }
}

// MARK: - ConfigurationIssue

/// An issue found during configuration validation.
public enum ConfigurationIssue: Sendable, Equatable {
    case warning(String)
    case error(String)

    // MARK: Public

    public var message: String {
        switch self {
        case let .error(msg),
             let .warning(msg):
            msg
        }
    }

    public var isError: Bool {
        switch self {
        case .error:
            true

        case .warning:
            false
        }
    }
}

// MARK: - Environment Variable Resolution

public extension Configuration {
    /// Resolve API keys from environment variables.
    func resolveAPIKey(for provider: ProviderName) -> String? {
        guard let providerConfig = providers.first(where: { $0.name == provider }),
              let apiKeyEnv = providerConfig.config?.apiKeyEnv
        else {
            return nil
        }
        return ProcessInfo.processInfo.environment[apiKeyEnv]
    }
}
