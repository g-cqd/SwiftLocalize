//
//  TranslationService.swift
//  SwiftLocalize
//

import Foundation

// MARK: - Translation Service

/// Main orchestration service for translating xcstrings files.
///
/// Coordinates between providers, handles batching, rate limiting, and fallback logic.
public actor TranslationService {
    private let registry: ProviderRegistry
    private let configuration: Configuration
    private let rateLimiter: RateLimiter
    private let promptBuilder: TranslationPromptBuilder

    public init(
        configuration: Configuration,
        registry: ProviderRegistry? = nil
    ) {
        self.configuration = configuration
        self.registry = registry ?? ProviderRegistry()
        self.rateLimiter = RateLimiter(
            requestsPerMinute: configuration.translation.rateLimit
        )
        self.promptBuilder = TranslationPromptBuilder()
    }

    // MARK: - Provider Registration

    /// Register a translation provider.
    public func register(_ provider: any TranslationProvider) async {
        await registry.register(provider)
    }

    /// Register default providers based on configuration.
    public func registerDefaultProviders() async {
        for providerConfig in configuration.providers where providerConfig.enabled {
            guard let provider = await createProvider(for: providerConfig) else { continue }
            await registry.register(provider)
        }
    }

    private func createProvider(for config: ProviderConfiguration) async -> (any TranslationProvider)? {
        switch config.name {
        case .openai:
            guard let apiKey = configuration.resolveAPIKey(for: .openai) else { return nil }
            let providerConfig = OpenAIProvider.OpenAIProviderConfig.from(
                providerConfig: config.config,
                apiKey: apiKey
            )
            return OpenAIProvider(config: providerConfig)

        case .anthropic:
            guard let apiKey = configuration.resolveAPIKey(for: .anthropic) else { return nil }
            let providerConfig = AnthropicProvider.AnthropicProviderConfig.from(
                providerConfig: config.config,
                apiKey: apiKey
            )
            return AnthropicProvider(config: providerConfig)

        case .gemini:
            guard let apiKey = configuration.resolveAPIKey(for: .gemini) else { return nil }
            let providerConfig = GeminiProvider.GeminiProviderConfig.from(
                providerConfig: config.config,
                apiKey: apiKey
            )
            return GeminiProvider(config: providerConfig)

        case .deepl:
            guard let apiKey = configuration.resolveAPIKey(for: .deepl) else { return nil }
            let providerConfig = DeepLProvider.DeepLProviderConfig.from(
                providerConfig: config.config,
                apiKey: apiKey
            )
            return DeepLProvider(config: providerConfig)

        case .ollama:
            let providerConfig = OllamaProvider.OllamaProviderConfig.from(
                providerConfig: config.config
            )
            return OllamaProvider(config: providerConfig)

        case .foundationModels:
            if #available(macOS 26, iOS 26, *) {
                return FoundationModelsProvider()
            } else {
                return nil
            }

        case .appleTranslation:
            // Apple Translation requires special handling
            return nil

        case .cliGemini:
            let providerConfig = GeminiCLIProvider.GeminiCLIConfig.from(
                providerConfig: config.config
            )
            return GeminiCLIProvider(config: providerConfig)

        case .cliCopilot:
            let providerConfig = CopilotCLIProvider.CopilotCLIConfig.from(
                providerConfig: config.config
            )
            return CopilotCLIProvider(config: providerConfig)

        case .cliCodex:
            let providerConfig = CodexCLIProvider.CodexCLIConfig.from(
                providerConfig: config.config
            )
            return CodexCLIProvider(config: providerConfig)

        case .cliGeneric:
            // Generic CLI requires explicit configuration
            return nil
        }
    }

    // MARK: - File Translation

    /// Translate all pending strings in xcstrings files.
    public func translateFiles(
        at urls: [URL],
        progress: (@Sendable (TranslationProgress) -> Void)? = nil
    ) async throws -> TranslationReport {
        let startTime = ContinuousClock.now

        var totalStrings = 0
        var translatedCount = 0
        var failedCount = 0
        var skippedCount = 0
        var byLanguage: [LanguageCode: LanguageReport] = [:]
        var errors: [TranslationReportError] = []

        for url in urls {
            var xcstrings = try XCStrings.parse(from: url)
            let sourceLanguage = LanguageCode(xcstrings.sourceLanguage)

            for targetLanguage in configuration.targetLanguages {
                // Skip source language
                guard targetLanguage != sourceLanguage else { continue }

                // Find strings needing translation
                let keysToTranslate = xcstrings.keysNeedingTranslation(for: targetLanguage.code)

                if keysToTranslate.isEmpty {
                    skippedCount += xcstrings.strings.count
                    continue
                }

                totalStrings += keysToTranslate.count

                // Get source strings
                let stringsToTranslate = keysToTranslate.compactMap { key -> (key: String, value: String)? in
                    guard let entry = xcstrings.strings[key],
                          let sourceLocalization = entry.localizations?[sourceLanguage.code],
                          let value = sourceLocalization.stringUnit?.value else {
                        // Use key as fallback if no source value
                        return (key: key, value: key)
                    }
                    return (key: key, value: value)
                }

                progress?(TranslationProgress(
                    total: totalStrings,
                    completed: translatedCount,
                    failed: failedCount,
                    currentLanguage: targetLanguage,
                    currentProvider: nil
                ))

                // Translate in batches
                let batches = stringsToTranslate.chunked(into: configuration.translation.batchSize)

                for batch in batches {
                    do {
                        let results = try await translateBatch(
                            batch.map(\.value),
                            from: sourceLanguage,
                            to: targetLanguage
                        )

                        // Apply translations
                        for (index, result) in results.enumerated() {
                            let key = batch[index].key
                            applyTranslation(
                                result: result,
                                key: key,
                                language: targetLanguage,
                                to: &xcstrings
                            )
                            translatedCount += 1
                        }

                        // Update language report
                        let existingReport = byLanguage[targetLanguage]
                        byLanguage[targetLanguage] = LanguageReport(
                            language: targetLanguage,
                            translatedCount: (existingReport?.translatedCount ?? 0) + results.count,
                            failedCount: existingReport?.failedCount ?? 0,
                            provider: results.first?.provider ?? existingReport?.provider ?? "unknown"
                        )

                    } catch {
                        failedCount += batch.count
                        for item in batch {
                            errors.append(TranslationReportError(
                                key: item.key,
                                language: targetLanguage,
                                message: error.localizedDescription
                            ))
                        }
                    }

                    progress?(TranslationProgress(
                        total: totalStrings,
                        completed: translatedCount,
                        failed: failedCount,
                        currentLanguage: targetLanguage,
                        currentProvider: nil
                    ))
                }
            }

            // Write updated xcstrings
            try xcstrings.write(
                to: url,
                prettyPrint: configuration.output.prettyPrint,
                sortKeys: configuration.output.sortKeys
            )
        }

        let duration = ContinuousClock.now - startTime

        return TranslationReport(
            totalStrings: totalStrings,
            translatedCount: translatedCount,
            failedCount: failedCount,
            skippedCount: skippedCount,
            byLanguage: byLanguage,
            duration: duration,
            errors: errors
        )
    }

    // MARK: - Batch Translation

    /// Translate a batch of strings with provider fallback.
    public func translateBatch(
        _ strings: [String],
        from source: LanguageCode,
        to target: LanguageCode,
        context: TranslationContext? = nil
    ) async throws -> [TranslationResult] {
        guard !strings.isEmpty else { return [] }

        let providers = await registry.providers(for: configuration)

        guard !providers.isEmpty else {
            throw TranslationError.noProvidersAvailable
        }

        var lastError: Error?

        for provider in providers {
            // Rate limiting
            await rateLimiter.acquire()

            do {
                // Check if provider supports this language pair
                let supports = try await provider.supports(source: source, target: target)
                guard supports else { continue }

                // Build context from configuration if not provided
                let translationContext = context ?? buildDefaultContext()

                // Attempt translation with retries
                let results = try await translateWithRetries(
                    strings: strings,
                    from: source,
                    to: target,
                    context: translationContext,
                    provider: provider
                )

                return results

            } catch {
                lastError = error
                // Continue to next provider
            }
        }

        // All providers failed
        if let error = lastError as? TranslationError {
            throw error
        } else if let error = lastError {
            throw TranslationError.providerError(
                provider: "all",
                message: error.localizedDescription
            )
        } else {
            throw TranslationError.noProvidersAvailable
        }
    }

    private func translateWithRetries(
        strings: [String],
        from source: LanguageCode,
        to target: LanguageCode,
        context: TranslationContext?,
        provider: any TranslationProvider
    ) async throws -> [TranslationResult] {
        var lastError: Error?

        for attempt in 1...configuration.translation.retries {
            do {
                return try await provider.translate(
                    strings,
                    from: source,
                    to: target,
                    context: context
                )
            } catch let error as TranslationError {
                lastError = error

                // Don't retry on certain errors
                switch error {
                case .unsupportedLanguagePair, .cancelled:
                    throw error
                case .rateLimitExceeded(_, let retryAfter):
                    let delay = retryAfter ?? configuration.translation.retryDelay
                    try await Task.sleep(for: .seconds(delay))
                default:
                    if attempt < configuration.translation.retries {
                        try await Task.sleep(for: .seconds(configuration.translation.retryDelay))
                    }
                }
            } catch {
                lastError = error
                if attempt < configuration.translation.retries {
                    try await Task.sleep(for: .seconds(configuration.translation.retryDelay))
                }
            }
        }

        throw lastError ?? TranslationError.providerError(
            provider: provider.identifier,
            message: "Translation failed after \(configuration.translation.retries) retries"
        )
    }

    // MARK: - Helpers

    private func buildDefaultContext() -> TranslationContext {
        TranslationContext(
            appDescription: configuration.context.app?.description,
            domain: configuration.context.app?.domain,
            preserveFormatters: configuration.translation.preserveFormatters,
            preserveMarkdown: configuration.translation.preserveMarkdown,
            additionalInstructions: configuration.translation.context,
            glossaryTerms: configuration.context.glossary?.terms,
            translationMemoryMatches: nil,
            stringContexts: nil
        )
    }

    private func applyTranslation(
        result: TranslationResult,
        key: String,
        language: LanguageCode,
        to xcstrings: inout XCStrings
    ) {
        var entry = xcstrings.strings[key] ?? StringEntry()
        var localizations = entry.localizations ?? [:]

        localizations[language.code] = Localization(
            value: result.translated,
            state: .translated
        )

        entry.localizations = localizations
        xcstrings.strings[key] = entry
    }
}

// MARK: - Rate Limiter

/// Token bucket rate limiter for API requests.
public actor RateLimiter {
    private let requestsPerMinute: Int
    private var tokens: Double
    private var lastRefill: ContinuousClock.Instant
    private let refillRate: Double

    public init(requestsPerMinute: Int) {
        self.requestsPerMinute = requestsPerMinute
        self.tokens = Double(requestsPerMinute)
        self.lastRefill = ContinuousClock.now
        self.refillRate = Double(requestsPerMinute) / 60.0 // tokens per second
    }

    /// Acquire a token, waiting if necessary.
    public func acquire() async {
        refill()

        while tokens < 1 {
            // Wait for token to become available
            let waitTime = (1.0 - tokens) / refillRate
            try? await Task.sleep(for: .seconds(waitTime))
            refill()
        }

        tokens -= 1
    }

    private func refill() {
        let now = ContinuousClock.now
        let elapsed = now - lastRefill
        let elapsedSeconds = Double(elapsed.components.seconds) +
            Double(elapsed.components.attoseconds) / 1_000_000_000_000_000_000

        tokens = min(Double(requestsPerMinute), tokens + elapsedSeconds * refillRate)
        lastRefill = now
    }
}

// MARK: - Array Extension

extension Array {
    /// Split array into chunks of specified size.
    func chunked(into size: Int) -> [[Element]] {
        guard size > 0 else { return [self] }
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}
