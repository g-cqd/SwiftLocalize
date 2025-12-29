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
        var state = FileTranslationState()

        for url in urls {
            try await processFile(at: url, state: &state, progress: progress)
        }

        let duration = ContinuousClock.now - startTime
        return state.buildReport(duration: duration)
    }

    // MARK: - File Access Auditing

    /// Get the file access audit report.
    public func getFileAccessReport() async -> FileAccessReport? {
        await fileAccessAuditor?.generateReport()
    }

    /// Validate file writes against allowed patterns.
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

        return try await attemptTranslationWithProviders(
            strings: strings,
            from: source,
            to: target,
            context: context,
            providers: providers,
        )
    }

    // MARK: Private

    private let registry: ProviderRegistry
    private let configuration: Configuration
    private let rateLimiter: RateLimiter
    private let promptBuilder: TranslationPromptBuilder
    private let sourceCodeAnalyzer: SourceCodeAnalyzer?
    private let fileAccessAuditor: FileAccessAuditor?
}

// MARK: - File Processing

private extension TranslationService {
    /// Process a single xcstrings file for translation.
    func processFile(
        at url: URL,
        state: inout FileTranslationState,
        progress: (@Sendable (TranslationProgress) -> Void)?,
    ) async throws {
        await fileAccessAuditor?.recordRead(url: url, purpose: "Load xcstrings for translation")

        var xcstrings = try XCStrings.parse(from: url)
        let sourceLanguage = LanguageCode(xcstrings.sourceLanguage)

        for targetLanguage in configuration.targetLanguages {
            guard targetLanguage != sourceLanguage else { continue }

            try await processLanguage(
                targetLanguage: targetLanguage,
                sourceLanguage: sourceLanguage,
                xcstrings: &xcstrings,
                url: url,
                state: &state,
                progress: progress,
            )
        }

        await fileAccessAuditor?.recordWrite(url: url, purpose: "Save translated xcstrings")
        try xcstrings.write(
            to: url,
            prettyPrint: configuration.output.prettyPrint,
            sortKeys: configuration.output.sortKeys,
        )
    }

    /// Process translation for a single target language.
    func processLanguage(
        targetLanguage: LanguageCode,
        sourceLanguage: LanguageCode,
        xcstrings: inout XCStrings,
        url: URL,
        state: inout FileTranslationState,
        progress: (@Sendable (TranslationProgress) -> Void)?,
    ) async throws {
        let keysToTranslate = xcstrings.keysNeedingTranslation(for: targetLanguage.code)

        if keysToTranslate.isEmpty {
            state.skippedCount += xcstrings.strings.count
            return
        }

        state.totalStrings += keysToTranslate.count

        let stringContexts = await buildStringContexts(
            keys: keysToTranslate,
            sourceLanguage: sourceLanguage,
            xcstrings: xcstrings,
            projectURL: url,
        )

        let stringsToTranslate = extractStringsToTranslate(
            keys: keysToTranslate,
            sourceLanguage: sourceLanguage,
            xcstrings: xcstrings,
        )

        reportProgress(state: state, targetLanguage: targetLanguage, progress: progress)

        try await processBatches(
            stringsToTranslate: stringsToTranslate,
            stringContexts: stringContexts,
            sourceLanguage: sourceLanguage,
            targetLanguage: targetLanguage,
            xcstrings: &xcstrings,
            state: &state,
            progress: progress,
        )
    }
}

// MARK: - Context Building

private extension TranslationService {
    /// Build string contexts with optional source code analysis.
    func buildStringContexts(
        keys: [String],
        sourceLanguage: LanguageCode,
        xcstrings: XCStrings,
        projectURL: URL,
    ) async -> [String: StringTranslationContext] {
        if let analyzer = sourceCodeAnalyzer {
            return await buildAnalyzedContexts(
                keys: keys,
                sourceLanguage: sourceLanguage,
                xcstrings: xcstrings,
                projectURL: projectURL,
                analyzer: analyzer,
            )
        }
        return buildBasicContexts(keys: keys, sourceLanguage: sourceLanguage, xcstrings: xcstrings)
    }

    /// Build contexts with source code analysis.
    func buildAnalyzedContexts(
        keys: [String],
        sourceLanguage: LanguageCode,
        xcstrings: XCStrings,
        projectURL: URL,
        analyzer: SourceCodeAnalyzer,
    ) async -> [String: StringTranslationContext] {
        let projectRoot = resolveProjectRoot(from: projectURL)

        guard let usageData = try? await analyzer.analyzeUsage(
            keys: keys,
            in: projectRoot,
        ) else {
            return buildBasicContexts(keys: keys, sourceLanguage: sourceLanguage, xcstrings: xcstrings)
        }

        var contexts: [String: StringTranslationContext] = [:]
        for (key, usage) in usageData {
            guard let value = extractSourceValue(key: key, sourceLanguage: sourceLanguage, xcstrings: xcstrings),
                  let entry = xcstrings.strings[key]
            else {
                continue
            }

            contexts[value] = StringTranslationContext(
                key: key,
                comment: entry.comment,
                uiElementTypes: usage.elementTypes,
                codeSnippets: usage.codeSnippets,
            )
        }
        return contexts
    }

    /// Build basic contexts without source code analysis.
    func buildBasicContexts(
        keys: [String],
        sourceLanguage: LanguageCode,
        xcstrings: XCStrings,
    ) -> [String: StringTranslationContext] {
        var contexts: [String: StringTranslationContext] = [:]
        for key in keys {
            guard let value = extractSourceValue(key: key, sourceLanguage: sourceLanguage, xcstrings: xcstrings),
                  let entry = xcstrings.strings[key]
            else {
                continue
            }
            contexts[value] = StringTranslationContext(key: key, comment: entry.comment)
        }
        return contexts
    }

    /// Extract source value for a key.
    func extractSourceValue(key: String, sourceLanguage: LanguageCode, xcstrings: XCStrings) -> String? {
        guard let entry = xcstrings.strings[key],
              let sourceLocalization = entry.localizations?[sourceLanguage.code]
        else {
            return nil
        }
        return sourceLocalization.stringUnit?.value
    }

    /// Extract strings to translate with their keys.
    func extractStringsToTranslate(
        keys: [String],
        sourceLanguage: LanguageCode,
        xcstrings: XCStrings,
    ) -> [(key: String, value: String)] {
        keys.compactMap { key -> (key: String, value: String)? in
            guard let entry = xcstrings.strings[key],
                  let sourceLocalization = entry.localizations?[sourceLanguage.code],
                  let value = sourceLocalization.stringUnit?.value
            else {
                return (key: key, value: key)
            }
            return (key: key, value: value)
        }
    }
}

// MARK: - Batch Processing

private extension TranslationService {
    /// Process all batches for a language translation.
    func processBatches(
        stringsToTranslate: [(key: String, value: String)],
        stringContexts: [String: StringTranslationContext],
        sourceLanguage: LanguageCode,
        targetLanguage: LanguageCode,
        xcstrings: inout XCStrings,
        state: inout FileTranslationState,
        progress: (@Sendable (TranslationProgress) -> Void)?,
    ) async throws {
        let batches = stringsToTranslate.chunked(into: configuration.translation.batchSize)

        for batch in batches {
            await processSingleBatch(
                batch: batch,
                stringContexts: stringContexts,
                sourceLanguage: sourceLanguage,
                targetLanguage: targetLanguage,
                xcstrings: &xcstrings,
                state: &state,
            )
            reportProgress(state: state, targetLanguage: targetLanguage, progress: progress)
        }
    }

    /// Process a single batch of strings.
    func processSingleBatch(
        batch: [(key: String, value: String)],
        stringContexts: [String: StringTranslationContext],
        sourceLanguage: LanguageCode,
        targetLanguage: LanguageCode,
        xcstrings: inout XCStrings,
        state: inout FileTranslationState,
    ) async {
        do {
            let batchContext = buildBatchContext(stringContexts: stringContexts)

            let results = try await translateBatch(
                batch.map(\.value),
                from: sourceLanguage,
                to: targetLanguage,
                context: batchContext,
            )

            applyBatchResults(
                results: results,
                batch: batch,
                targetLanguage: targetLanguage,
                xcstrings: &xcstrings,
                state: &state,
            )
        } catch {
            recordBatchFailure(batch: batch, targetLanguage: targetLanguage, error: error, state: &state)
        }
    }

    /// Build context for a batch translation.
    func buildBatchContext(stringContexts: [String: StringTranslationContext]) -> TranslationContext {
        let defaultContext = buildDefaultContext()

        guard let existing = defaultContext.stringContexts else {
            return TranslationContext(
                appDescription: defaultContext.appDescription,
                domain: defaultContext.domain,
                preserveFormatters: defaultContext.preserveFormatters,
                preserveMarkdown: defaultContext.preserveMarkdown,
                additionalInstructions: defaultContext.additionalInstructions,
                glossaryTerms: defaultContext.glossaryTerms,
                translationMemoryMatches: defaultContext.translationMemoryMatches,
                stringContexts: stringContexts,
            )
        }

        let merged = existing.merging(stringContexts) { _, new in new }
        return TranslationContext(
            appDescription: defaultContext.appDescription,
            domain: defaultContext.domain,
            preserveFormatters: defaultContext.preserveFormatters,
            preserveMarkdown: defaultContext.preserveMarkdown,
            additionalInstructions: defaultContext.additionalInstructions,
            glossaryTerms: defaultContext.glossaryTerms,
            translationMemoryMatches: defaultContext.translationMemoryMatches,
            stringContexts: merged,
        )
    }

    /// Apply batch translation results to xcstrings.
    func applyBatchResults(
        results: [TranslationResult],
        batch: [(key: String, value: String)],
        targetLanguage: LanguageCode,
        xcstrings: inout XCStrings,
        state: inout FileTranslationState,
    ) {
        for (index, result) in results.enumerated() {
            let key = batch[index].key
            applyTranslation(result: result, key: key, language: targetLanguage, to: &xcstrings)
            state.translatedCount += 1
        }

        state.updateLanguageReport(
            language: targetLanguage,
            translatedCount: results.count,
            provider: results.first?.provider,
        )
    }

    /// Record batch translation failure.
    func recordBatchFailure(
        batch: [(key: String, value: String)],
        targetLanguage: LanguageCode,
        error: Error,
        state: inout FileTranslationState,
    ) {
        state.failedCount += batch.count
        for item in batch {
            state.errors.append(TranslationReportError(
                key: item.key,
                language: targetLanguage,
                message: error.localizedDescription,
            ))
        }
    }
}

// MARK: - Provider Management

private extension TranslationService {
    /// Attempt translation with available providers (with fallback).
    func attemptTranslationWithProviders(
        strings: [String],
        from source: LanguageCode,
        to target: LanguageCode,
        context: TranslationContext?,
        providers: [any TranslationProvider],
    ) async throws -> [TranslationResult] {
        var lastError: Error?

        for provider in providers {
            await rateLimiter.acquire()

            do {
                let supports = try await provider.supports(source: source, target: target)
                guard supports else { continue }

                let translationContext = context ?? buildDefaultContext()
                return try await translateWithRetries(
                    strings: strings,
                    from: source,
                    to: target,
                    context: translationContext,
                    provider: provider,
                )
            } catch {
                lastError = error
            }
        }

        throw mapProviderError(lastError)
    }

    /// Map provider error to appropriate TranslationError.
    func mapProviderError(_ error: Error?) -> TranslationError {
        if let translationError = error as? TranslationError {
            return translationError
        }
        if let error {
            return .providerError(provider: "all", message: error.localizedDescription)
        }
        return .noProvidersAvailable
    }

    /// Translate with retry logic.
    func translateWithRetries(
        strings: [String],
        from source: LanguageCode,
        to target: LanguageCode,
        context: TranslationContext?,
        provider: any TranslationProvider,
    ) async throws -> [TranslationResult] {
        var lastError: Error?

        for attempt in 1 ... configuration.translation.retries {
            do {
                return try await provider.translate(strings, from: source, to: target, context: context)
            } catch let error as TranslationError {
                lastError = error
                try await handleTranslationError(error, attempt: attempt)
            } catch {
                lastError = error
                try await handleGenericRetry(attempt: attempt)
            }
        }

        throw lastError ?? TranslationError.providerError(
            provider: provider.identifier,
            message: "Translation failed after \(configuration.translation.retries) retries",
        )
    }

    /// Handle translation error during retry.
    func handleTranslationError(_ error: TranslationError, attempt: Int) async throws {
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
    }

    /// Handle generic retry delay.
    func handleGenericRetry(attempt: Int) async throws {
        if attempt < configuration.translation.retries {
            try await Task.sleep(for: .seconds(configuration.translation.retryDelay))
        }
    }

    /// Create a provider from configuration.
    func createProvider(for config: ProviderConfiguration) async -> (any TranslationProvider)? {
        switch config.name {
        case .openai:
            createOpenAIProvider(config: config)

        case .anthropic:
            createAnthropicProvider(config: config)

        case .gemini:
            createGeminiProvider(config: config)

        case .deepl:
            createDeepLProvider(config: config)

        case .ollama:
            createOllamaProvider(config: config)

        case .foundationModels:
            createFoundationModelsProvider()

        case .appleTranslation:
            nil

        case .cliGemini:
            createGeminiCLIProvider(config: config)

        case .cliCopilot:
            createCopilotCLIProvider(config: config)

        case .cliCodex:
            createCodexCLIProvider(config: config)

        case .cliGeneric:
            nil
        }
    }

    func createOpenAIProvider(config: ProviderConfiguration) -> OpenAIProvider? {
        guard let apiKey = configuration.resolveAPIKey(for: .openai) else { return nil }
        let providerConfig = OpenAIProvider.OpenAIProviderConfig.from(
            providerConfig: config.config,
            apiKey: apiKey,
        )
        return OpenAIProvider(config: providerConfig)
    }

    func createAnthropicProvider(config: ProviderConfiguration) -> AnthropicProvider? {
        guard let apiKey = configuration.resolveAPIKey(for: .anthropic) else { return nil }
        let providerConfig = AnthropicProvider.AnthropicProviderConfig.from(
            providerConfig: config.config,
            apiKey: apiKey,
        )
        return AnthropicProvider(config: providerConfig)
    }

    func createGeminiProvider(config: ProviderConfiguration) -> GeminiProvider? {
        guard let apiKey = configuration.resolveAPIKey(for: .gemini) else { return nil }
        let providerConfig = GeminiProvider.GeminiProviderConfig.from(
            providerConfig: config.config,
            apiKey: apiKey,
        )
        return GeminiProvider(config: providerConfig)
    }

    func createDeepLProvider(config: ProviderConfiguration) -> DeepLProvider? {
        guard let apiKey = configuration.resolveAPIKey(for: .deepl) else { return nil }
        let providerConfig = DeepLProvider.DeepLProviderConfig.from(
            providerConfig: config.config,
            apiKey: apiKey,
        )
        return DeepLProvider(config: providerConfig)
    }

    func createOllamaProvider(config: ProviderConfiguration) -> OllamaProvider {
        let providerConfig = OllamaProvider.OllamaProviderConfig.from(providerConfig: config.config)
        return OllamaProvider(config: providerConfig)
    }

    func createFoundationModelsProvider() -> (any TranslationProvider)? {
        if #available(macOS 26, iOS 26, *) {
            return FoundationModelsProvider()
        }
        return nil
    }

    func createGeminiCLIProvider(config: ProviderConfiguration) -> GeminiCLIProvider {
        let providerConfig = GeminiCLIProvider.GeminiCLIConfig.from(providerConfig: config.config)
        return GeminiCLIProvider(config: providerConfig)
    }

    func createCopilotCLIProvider(config: ProviderConfiguration) -> CopilotCLIProvider {
        let providerConfig = CopilotCLIProvider.CopilotCLIConfig.from(providerConfig: config.config)
        return CopilotCLIProvider(config: providerConfig)
    }

    func createCodexCLIProvider(config: ProviderConfiguration) -> CodexCLIProvider {
        let providerConfig = CodexCLIProvider.CodexCLIConfig.from(providerConfig: config.config)
        return CodexCLIProvider(config: providerConfig)
    }
}

// MARK: - Helpers

private extension TranslationService {
    /// Build default translation context from configuration.
    func buildDefaultContext() -> TranslationContext {
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

    /// Apply a translation result to xcstrings.
    func applyTranslation(
        result: TranslationResult,
        key: String,
        language: LanguageCode,
        to xcstrings: inout XCStrings,
    ) {
        var entry = xcstrings.strings[key] ?? StringEntry()
        var localizations = entry.localizations ?? [:]

        localizations[language.code] = Localization(value: result.translated, state: .translated)

        entry.localizations = localizations
        xcstrings.strings[key] = entry
    }

    /// Report translation progress.
    func reportProgress(
        state: FileTranslationState,
        targetLanguage: LanguageCode,
        progress: (@Sendable (TranslationProgress) -> Void)?,
    ) {
        progress?(TranslationProgress(
            total: state.totalStrings,
            completed: state.translatedCount,
            failed: state.failedCount,
            currentLanguage: targetLanguage,
            currentProvider: nil,
        ))
    }

    /// Resolve project root from a file URL.
    func resolveProjectRoot(from url: URL) -> URL {
        let fileManager = FileManager.default

        if let projectRoot = configuration.context.projectRoot {
            let projectURL = URL(fileURLWithPath: projectRoot)
            if fileManager.fileExists(atPath: projectURL.path) {
                return projectURL
            }
        }

        var current = url.deletingLastPathComponent()
        let rootPath = "/"

        while current.path != rootPath {
            if let marker = findProjectMarker(in: current, fileManager: fileManager) {
                return marker
            }
            current = current.deletingLastPathComponent()
        }

        return URL(fileURLWithPath: fileManager.currentDirectoryPath)
    }

    /// Find project marker in directory.
    func findProjectMarker(in directory: URL, fileManager: FileManager) -> URL? {
        let packageSwift = directory.appendingPathComponent("Package.swift")
        if fileManager.fileExists(atPath: packageSwift.path) {
            return directory
        }

        if let contents = try? fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) {
            if contents.contains(where: { $0.pathExtension == "xcodeproj" }) {
                return directory
            }
            if contents.contains(where: { $0.pathExtension == "xcworkspace" }) {
                return directory
            }
        }

        let gitDir = directory.appendingPathComponent(".git")
        if fileManager.fileExists(atPath: gitDir.path) {
            return directory
        }

        let configFile = directory.appendingPathComponent(".swiftlocalize.json")
        if fileManager.fileExists(atPath: configFile.path) {
            return directory
        }

        return nil
    }
}

// MARK: - FileTranslationState

/// Internal state for tracking translation progress.
private struct FileTranslationState {
    var totalStrings = 0
    var translatedCount = 0
    var failedCount = 0
    var skippedCount = 0
    var byLanguage: [LanguageCode: LanguageReport] = [:]
    var errors: [TranslationReportError] = []

    mutating func updateLanguageReport(
        language: LanguageCode,
        translatedCount: Int,
        provider: String?,
    ) {
        let existing = byLanguage[language]
        byLanguage[language] = LanguageReport(
            language: language,
            translatedCount: (existing?.translatedCount ?? 0) + translatedCount,
            failedCount: existing?.failedCount ?? 0,
            provider: provider ?? existing?.provider ?? "unknown",
        )
    }

    func buildReport(duration: Duration) -> TranslationReport {
        TranslationReport(
            totalStrings: totalStrings,
            translatedCount: translatedCount,
            failedCount: failedCount,
            skippedCount: skippedCount,
            byLanguage: byLanguage,
            duration: duration,
            errors: errors,
        )
    }
}
