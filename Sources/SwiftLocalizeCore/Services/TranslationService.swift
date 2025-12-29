//
//  TranslationService.swift
//  SwiftLocalize
//

import Foundation

// MARK: - TranslationService

/// Main orchestration service for translating xcstrings files.
///
/// Coordinates between providers, handles batching, rate limiting, and fallback logic.
public actor TranslationService {
    // MARK: Lifecycle

    public init(
        configuration: Configuration,
        registry: ProviderRegistry? = nil,
        enableAuditing: Bool = false,
    ) {
        self.configuration = configuration
        self.registry = registry ?? ProviderRegistry()
        rateLimiter = RateLimiter(
            requestsPerMinute: configuration.translation.rateLimit,
        )
        promptBuilder = TranslationPromptBuilder()
        fileAccessAuditor = enableAuditing ? FileAccessAuditor() : nil

        if configuration.context.sourceCode?.enabled == true {
            sourceCodeAnalyzer = SourceCodeAnalyzer()
        } else {
            sourceCodeAnalyzer = nil
        }
    }

    // MARK: Public

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

    // MARK: - File Translation

    /// Translate all pending strings in xcstrings files.
    public func translateFiles(
        at urls: [URL],
        progress: (@Sendable (TranslationProgress) -> Void)? = nil,
    ) async throws -> TranslationReport {
        let startTime = ContinuousClock.now

        var totalStrings = 0
        var translatedCount = 0
        var failedCount = 0
        var skippedCount = 0
        var byLanguage: [LanguageCode: LanguageReport] = [:]
        var errors: [TranslationReportError] = []

        for url in urls {
            // Record file read for auditing
            await fileAccessAuditor?.recordRead(url: url, purpose: "Load xcstrings for translation")

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

                // Analyze source code usage if enabled
                var stringContexts: [String: StringTranslationContext] = [:]
                if let analyzer = sourceCodeAnalyzer {
                    let projectRoot = resolveProjectRoot(from: url)
                    if let usageData = try? await analyzer.analyzeUsage(
                        keys: Array(keysToTranslate),
                        in: projectRoot,
                    ) {
                        // Map usage data to contexts
                        for (key, usage) in usageData {
                            // Find the value for this key to map it correctly
                            guard let entry = xcstrings.strings[key],
                                  let sourceLocalization = entry.localizations?[sourceLanguage.code],
                                  let value = sourceLocalization.stringUnit?.value
                            else {
                                continue
                            }

                            stringContexts[value] = StringTranslationContext(
                                key: key,
                                comment: entry.comment,
                                uiElementTypes: usage.elementTypes,
                                codeSnippets: usage.codeSnippets,
                            )
                        }
                    }
                } else {
                    // Just populate comments if no analysis
                    for key in keysToTranslate {
                        guard let entry = xcstrings.strings[key],
                              let sourceLocalization = entry.localizations?[sourceLanguage.code],
                              let value = sourceLocalization.stringUnit?.value
                        else {
                            continue
                        }

                        stringContexts[value] = StringTranslationContext(
                            key: key,
                            comment: entry.comment,
                        )
                    }
                }

                // Get source strings
                let stringsToTranslate = keysToTranslate.compactMap { key -> (key: String, value: String)? in
                    guard let entry = xcstrings.strings[key],
                          let sourceLocalization = entry.localizations?[sourceLanguage.code],
                          let value = sourceLocalization.stringUnit?.value
                    else {
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
                    currentProvider: nil,
                ))

                // Translate in batches
                let batches = stringsToTranslate.chunked(into: configuration.translation.batchSize)

                for batch in batches {
                    do {
                        // Build context for this batch
                        var batchContext = buildDefaultContext()
                        // Merge with analyzed contexts
                        if let existing = batchContext.stringContexts {
                            let merged = existing.merging(stringContexts) { _, new in new }
                            batchContext = TranslationContext(
                                appDescription: batchContext.appDescription,
                                domain: batchContext.domain,
                                preserveFormatters: batchContext.preserveFormatters,
                                preserveMarkdown: batchContext.preserveMarkdown,
                                additionalInstructions: batchContext.additionalInstructions,
                                glossaryTerms: batchContext.glossaryTerms,
                                translationMemoryMatches: batchContext.translationMemoryMatches,
                                stringContexts: merged,
                            )
                        } else {
                            batchContext = TranslationContext(
                                appDescription: batchContext.appDescription,
                                domain: batchContext.domain,
                                preserveFormatters: batchContext.preserveFormatters,
                                preserveMarkdown: batchContext.preserveMarkdown,
                                additionalInstructions: batchContext.additionalInstructions,
                                glossaryTerms: batchContext.glossaryTerms,
                                translationMemoryMatches: batchContext.translationMemoryMatches,
                                stringContexts: stringContexts,
                            )
                        }

                        let results = try await translateBatch(
                            batch.map(\.value),
                            from: sourceLanguage,
                            to: targetLanguage,
                            context: batchContext,
                        )

                        // Apply translations
                        for (index, result) in results.enumerated() {
                            let key = batch[index].key
                            applyTranslation(
                                result: result,
                                key: key,
                                language: targetLanguage,
                                to: &xcstrings,
                            )
                            translatedCount += 1
                        }

                        // Update language report
                        let existingReport = byLanguage[targetLanguage]
                        byLanguage[targetLanguage] = LanguageReport(
                            language: targetLanguage,
                            translatedCount: (existingReport?.translatedCount ?? 0) + results.count,
                            failedCount: existingReport?.failedCount ?? 0,
                            provider: results.first?.provider ?? existingReport?.provider ?? "unknown",
                        )
                    } catch {
                        failedCount += batch.count
                        for item in batch {
                            errors.append(TranslationReportError(
                                key: item.key,
                                language: targetLanguage,
                                message: error.localizedDescription,
                            ))
                        }
                    }

                    progress?(TranslationProgress(
                        total: totalStrings,
                        completed: translatedCount,
                        failed: failedCount,
                        currentLanguage: targetLanguage,
                        currentProvider: nil,
                    ))
                }
            }

            // Record file write for auditing
            await fileAccessAuditor?.recordWrite(url: url, purpose: "Save translated xcstrings")

            // Write updated xcstrings
            try xcstrings.write(
                to: url,
                prettyPrint: configuration.output.prettyPrint,
                sortKeys: configuration.output.sortKeys,
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
            errors: errors,
        )
    }

    // MARK: - File Access Auditing

    /// Get the file access audit report.
    ///
    /// Only available when auditing is enabled during initialization.
    /// - Returns: The file access report, or nil if auditing is disabled.
    public func getFileAccessReport() async -> FileAccessReport? {
        await fileAccessAuditor?.generateReport()
    }

    /// Validate file writes against allowed patterns.
    ///
    /// - Parameter allowedPatterns: Glob patterns for allowed write targets.
    /// - Returns: Array of violations, or nil if auditing is disabled.
    public func validateFileAccess(allowedPatterns: [String]) async throws -> [Violation]? {
        try await fileAccessAuditor?.validateWrites(allowedPatterns: allowedPatterns)
    }

    // MARK: - Batch Translation

    /// Translate a batch of strings with provider fallback.
    public func translateBatch(
        _ strings: [String],
        from source: LanguageCode,
        to target: LanguageCode,
        context: TranslationContext? = nil,
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
                    provider: provider,
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
                message: error.localizedDescription,
            )
        } else {
            throw TranslationError.noProvidersAvailable
        }
    }

    // MARK: Private

    private let registry: ProviderRegistry
    private let configuration: Configuration
    private let rateLimiter: RateLimiter
    private let promptBuilder: TranslationPromptBuilder
    private let sourceCodeAnalyzer: SourceCodeAnalyzer?
    private let fileAccessAuditor: FileAccessAuditor?

    private func createProvider(for config: ProviderConfiguration) async -> (any TranslationProvider)? {
        switch config.name {
        case .openai:
            guard let apiKey = configuration.resolveAPIKey(for: .openai) else { return nil }
            let providerConfig = OpenAIProvider.OpenAIProviderConfig.from(
                providerConfig: config.config,
                apiKey: apiKey,
            )
            return OpenAIProvider(config: providerConfig)

        case .anthropic:
            guard let apiKey = configuration.resolveAPIKey(for: .anthropic) else { return nil }
            let providerConfig = AnthropicProvider.AnthropicProviderConfig.from(
                providerConfig: config.config,
                apiKey: apiKey,
            )
            return AnthropicProvider(config: providerConfig)

        case .gemini:
            guard let apiKey = configuration.resolveAPIKey(for: .gemini) else { return nil }
            let providerConfig = GeminiProvider.GeminiProviderConfig.from(
                providerConfig: config.config,
                apiKey: apiKey,
            )
            return GeminiProvider(config: providerConfig)

        case .deepl:
            guard let apiKey = configuration.resolveAPIKey(for: .deepl) else { return nil }
            let providerConfig = DeepLProvider.DeepLProviderConfig.from(
                providerConfig: config.config,
                apiKey: apiKey,
            )
            return DeepLProvider(config: providerConfig)

        case .ollama:
            let providerConfig = OllamaProvider.OllamaProviderConfig.from(
                providerConfig: config.config,
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
                providerConfig: config.config,
            )
            return GeminiCLIProvider(config: providerConfig)

        case .cliCopilot:
            let providerConfig = CopilotCLIProvider.CopilotCLIConfig.from(
                providerConfig: config.config,
            )
            return CopilotCLIProvider(config: providerConfig)

        case .cliCodex:
            let providerConfig = CodexCLIProvider.CodexCLIConfig.from(
                providerConfig: config.config,
            )
            return CodexCLIProvider(config: providerConfig)

        case .cliGeneric:
            // Generic CLI requires explicit configuration
            return nil
        }
    }

    private func translateWithRetries(
        strings: [String],
        from source: LanguageCode,
        to target: LanguageCode,
        context: TranslationContext?,
        provider: any TranslationProvider,
    ) async throws -> [TranslationResult] {
        var lastError: Error?

        for attempt in 1 ... configuration.translation.retries {
            do {
                return try await provider.translate(
                    strings,
                    from: source,
                    to: target,
                    context: context,
                )
            } catch let error as TranslationError {
                lastError = error

                // Don't retry on certain errors
                switch error {
                case .cancelled,
                     .unsupportedLanguagePair:
                    throw error

                case let .rateLimitExceeded(_, retryAfter):
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
            message: "Translation failed after \(configuration.translation.retries) retries",
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
            stringContexts: nil,
        )
    }

    private func applyTranslation(
        result: TranslationResult,
        key: String,
        language: LanguageCode,
        to xcstrings: inout XCStrings,
    ) {
        var entry = xcstrings.strings[key] ?? StringEntry()
        var localizations = entry.localizations ?? [:]

        localizations[language.code] = Localization(
            value: result.translated,
            state: .translated,
        )

        entry.localizations = localizations
        xcstrings.strings[key] = entry
    }

    /// Resolve project root from a file URL.
    ///
    /// Searches up the directory tree for project markers (Package.swift, .xcodeproj, .git).
    /// Falls back to the current working directory if no project root is found.
    ///
    /// - Parameter url: The file URL to start searching from.
    /// - Returns: The resolved project root URL.
    private func resolveProjectRoot(from url: URL) -> URL {
        let fileManager = FileManager.default

        // If config specifies an absolute project root, use it
        if let projectRoot = configuration.context.projectRoot {
            let projectURL = URL(fileURLWithPath: projectRoot)
            if fileManager.fileExists(atPath: projectURL.path) {
                return projectURL
            }
        }

        // Try to find project markers up the directory tree
        var current = url.deletingLastPathComponent()
        let rootPath = "/"

        while current.path != rootPath {
            // Check for Package.swift (Swift Package)
            let packageSwift = current.appendingPathComponent("Package.swift")
            if fileManager.fileExists(atPath: packageSwift.path) {
                return current
            }

            // Check for .xcodeproj (Xcode project)
            if let contents = try? fileManager.contentsOfDirectory(at: current, includingPropertiesForKeys: nil),
               contents.contains(where: { $0.pathExtension == "xcodeproj" }) {
                return current
            }

            // Check for .xcworkspace (Xcode workspace)
            if let contents = try? fileManager.contentsOfDirectory(at: current, includingPropertiesForKeys: nil),
               contents.contains(where: { $0.pathExtension == "xcworkspace" }) {
                return current
            }

            // Check for .git (git repository root)
            let gitDir = current.appendingPathComponent(".git")
            if fileManager.fileExists(atPath: gitDir.path) {
                return current
            }

            // Check for .swiftlocalize.json (config file as marker)
            let configFile = current.appendingPathComponent(".swiftlocalize.json")
            if fileManager.fileExists(atPath: configFile.path) {
                return current
            }

            current = current.deletingLastPathComponent()
        }

        // Default to current working directory
        return URL(fileURLWithPath: fileManager.currentDirectoryPath)
    }
}

// MARK: - RateLimiter

/// Token bucket rate limiter for API requests.
public actor RateLimiter {
    // MARK: Lifecycle

    public init(requestsPerMinute: Int) {
        self.requestsPerMinute = requestsPerMinute
        tokens = Double(requestsPerMinute)
        lastRefill = ContinuousClock.now
        refillRate = Double(requestsPerMinute) / 60.0 // tokens per second
    }

    // MARK: Public

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

    // MARK: Private

    private let requestsPerMinute: Int
    private var tokens: Double
    private var lastRefill: ContinuousClock.Instant
    private let refillRate: Double

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
            Array(self[$0 ..< Swift.min($0 + size, count)])
        }
    }
}
