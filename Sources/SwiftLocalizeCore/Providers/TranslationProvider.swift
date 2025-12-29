//
//  TranslationProvider.swift
//  SwiftLocalize
//

import Foundation

// MARK: - TranslationProvider

/// Protocol for translation providers.
///
/// Conforming types must be `Sendable` to support concurrent translation operations.
/// Each provider implementation should handle its own rate limiting, retries, and error handling.
public protocol TranslationProvider: Sendable {
    /// Unique identifier for this provider.
    var identifier: String { get }

    /// Human-readable display name.
    var displayName: String { get }

    /// Check if the provider is available and properly configured.
    ///
    /// This should verify:
    /// - Required dependencies are available (e.g., frameworks, CLI tools)
    /// - API keys are configured (if required)
    /// - Network connectivity (optional, for graceful degradation)
    func isAvailable() async -> Bool

    /// Get the list of supported language pairs.
    ///
    /// Returns an empty array if the provider supports all language pairs.
    func supportedLanguages() async throws -> [LanguagePair]

    /// Translate a batch of strings.
    ///
    /// - Parameters:
    ///   - strings: The strings to translate.
    ///   - source: The source language code.
    ///   - target: The target language code.
    ///   - context: Optional context for better translation quality.
    /// - Returns: Translation results in the same order as input strings.
    /// - Throws: `TranslationError` if translation fails.
    func translate(
        _ strings: [String],
        from source: LanguageCode,
        to target: LanguageCode,
        context: TranslationContext?,
    ) async throws -> [TranslationResult]
}

// MARK: - Default Implementations

public extension TranslationProvider {
    /// Default implementation returns all pairs as supported.
    func supportedLanguages() async throws -> [LanguagePair] {
        []
    }

    /// Translate a single string.
    func translate(
        _ string: String,
        from source: LanguageCode,
        to target: LanguageCode,
        context: TranslationContext? = nil,
    ) async throws -> TranslationResult {
        let results = try await translate([string], from: source, to: target, context: context)
        guard let result = results.first else {
            throw TranslationError.invalidResponse("No translation returned")
        }
        return result
    }

    /// Check if a language pair is supported.
    func supports(source: LanguageCode, target: LanguageCode) async throws -> Bool {
        let supported = try await supportedLanguages()
        // Empty array means all pairs are supported
        if supported.isEmpty {
            return true
        }
        return supported.contains(LanguagePair(source: source, target: target))
    }
}

// MARK: - ProviderRegistry

/// Registry for available translation providers.
public actor ProviderRegistry {
    // MARK: Lifecycle

    public init() {}

    // MARK: Public

    /// Register a provider.
    public func register(_ provider: any TranslationProvider) {
        providers[provider.identifier] = provider
    }

    /// Get a provider by identifier.
    public func provider(for identifier: String) -> (any TranslationProvider)? {
        providers[identifier]
    }

    /// Get all registered providers.
    public func allProviders() -> [any TranslationProvider] {
        Array(providers.values)
    }

    /// Get available providers (configured and ready to use).
    public func availableProviders() async -> [any TranslationProvider] {
        var available: [any TranslationProvider] = []
        for provider in providers.values {
            if await provider.isAvailable() {
                available.append(provider)
            }
        }
        return available
    }

    /// Get providers sorted by priority from configuration.
    public func providers(
        for config: Configuration,
    ) async -> [any TranslationProvider] {
        let enabledConfigs = config.providers
            .filter(\.enabled)
            .sorted { $0.priority < $1.priority }

        var result: [any TranslationProvider] = []
        for providerConfig in enabledConfigs {
            if let provider = providers[providerConfig.name.rawValue] {
                if await provider.isAvailable() {
                    result.append(provider)
                }
            }
        }
        return result
    }

    // MARK: Private

    private var providers: [String: any TranslationProvider] = [:]
}

// MARK: - TranslationPromptBuilder

/// Builds prompts for LLM-based translation providers.
public struct TranslationPromptBuilder: Sendable {
    // MARK: Lifecycle

    public init() {}

    // MARK: Public

    /// Build a system prompt for translation.
    public func buildSystemPrompt(
        context: TranslationContext?,
        targetLanguage: LanguageCode,
    ) -> String {
        var parts: [String] = []

        parts.append("You are an expert translator for iOS/macOS applications.")

        if let appDesc = context?.appDescription {
            parts.append("Application: \(appDesc)")
        }

        if let domain = context?.domain {
            parts.append("Domain: \(domain)")
        }

        // Glossary terms
        if let terms = context?.glossaryTerms, !terms.isEmpty {
            parts.append("\nTerminology (use these exact translations):")
            for term in terms {
                if term.doNotTranslate == true {
                    parts.append("- \"\(term.term)\" → Keep unchanged (do not translate)")
                } else if let translation = term.translations?[targetLanguage.code] {
                    parts.append("- \"\(term.term)\" → \"\(translation)\"")
                }
            }
        }

        // Translation memory matches
        if let matches = context?.translationMemoryMatches, !matches.isEmpty {
            parts.append("\nPrevious translations for consistency:")
            for match in matches.prefix(5) {
                parts.append("- \"\(match.source)\" → \"\(match.translation)\"")
            }
        }

        // Guidelines
        var guidelines: [String] = []

        if context?.preserveFormatters ?? true {
            guidelines.append("Preserve format specifiers: %@, %lld, %.1f, %d, etc.")
        }

        if context?.preserveMarkdown ?? true {
            guidelines.append("Preserve Markdown syntax: ^[], **, _, ~~, etc.")
        }

        guidelines.append("Preserve placeholders: {name}, {{value}}")
        guidelines.append("Maintain the same punctuation style")
        guidelines.append("Keep the same formality level")
        guidelines.append("Consider UI element type for appropriate length/style")

        if let additional = context?.additionalInstructions {
            guidelines.append(additional)
        }

        parts.append("\nTranslation Guidelines:")
        for guideline in guidelines {
            parts.append("- \(guideline)")
        }

        return parts.joined(separator: "\n")
    }

    /// Build a user prompt with strings to translate.
    public func buildUserPrompt(
        strings: [String],
        context: TranslationContext?,
        targetLanguage: LanguageCode,
    ) -> String {
        let languageName = targetLanguage.displayName()

        var prompt = "Translate the following strings to \(languageName) (\(targetLanguage.code)):\n\n"

        for string in strings {
            prompt += "- \"\(string)\"\n"

            // Add string-specific context if available
            if let stringContext = context?.stringContexts?[string] {
                if let comment = stringContext.comment {
                    prompt += "  Developer note: \(comment)\n"
                }
                if let uiTypes = stringContext.uiElementTypes, !uiTypes.isEmpty {
                    let types = uiTypes.map(\.rawValue).joined(separator: ", ")
                    prompt += "  UI context: \(types)\n"
                }
            }
        }

        prompt += """

        Return ONLY a JSON object mapping the original strings to their translations.
        Example format: {"original1": "translation1", "original2": "translation2"}
        Do not include any explanation or additional text.
        """

        return prompt
    }

    /// Parse a JSON response from an LLM into translation results.
    public func parseResponse(
        _ response: String,
        originalStrings: [String],
        provider: String,
    ) throws -> [TranslationResult] {
        // Extract JSON from response (handle markdown code blocks)
        let jsonString = extractJSON(from: response)

        guard let data = jsonString.data(using: .utf8) else {
            throw TranslationError.invalidResponse("Response is not valid UTF-8")
        }

        let translations: [String: String]
        do {
            translations = try JSONDecoder().decode([String: String].self, from: data)
        } catch {
            throw TranslationError.invalidResponse("Failed to parse JSON: \(error.localizedDescription)")
        }

        return originalStrings.map { original in
            let translated = translations[original] ?? original
            return TranslationResult(
                original: original,
                translated: translated,
                confidence: translations[original] != nil ? 0.9 : 0.0,
                provider: provider,
            )
        }
    }

    // MARK: Private

    private func extractJSON(from response: String) -> String {
        var text = response.trimmingCharacters(in: .whitespacesAndNewlines)

        // Remove markdown code blocks
        if text.hasPrefix("```json") {
            text = String(text.dropFirst(7))
        } else if text.hasPrefix("```") {
            text = String(text.dropFirst(3))
        }

        if text.hasSuffix("```") {
            text = String(text.dropLast(3))
        }

        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
