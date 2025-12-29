//
//  ServiceTests.swift
//  SwiftLocalize
//

import Foundation
@testable import SwiftLocalizeCore
import Testing

// MARK: - MockTranslationProvider

/// Mock provider for testing TranslationService.
final class MockTranslationProvider: TranslationProvider, @unchecked Sendable {
    // MARK: Lifecycle

    init(identifier: String = "mock", displayName: String = "Mock Provider") {
        self.identifier = identifier
        self.displayName = displayName
    }

    // MARK: Internal

    let identifier: String
    let displayName: String

    var translations: [String: String] = [:]
    var shouldFail = false
    var failureError: TranslationError = .providerError(provider: "mock", message: "Mock failure")
    var delay: Duration = .zero
    var isAvailableValue = true
    var translateCallCount = 0

    func isAvailable() async -> Bool {
        isAvailableValue
    }

    func supportedLanguages() async throws -> [LanguagePair] {
        [] // All languages supported
    }

    func translate(
        _ strings: [String],
        from source: LanguageCode,
        to target: LanguageCode,
        context: TranslationContext?,
    ) async throws -> [TranslationResult] {
        translateCallCount += 1

        if shouldFail {
            throw failureError
        }

        if delay != .zero {
            try await Task.sleep(for: delay)
        }

        return strings.map { string in
            TranslationResult(
                original: string,
                translated: translations[string] ?? "[\(target.code)] \(string)",
                confidence: translations[string] != nil ? 1.0 : 0.8,
                provider: identifier,
            )
        }
    }
}

// MARK: - RateLimiterTests

@Suite("RateLimiter Tests")
struct RateLimiterTests {
    @Test("Rate limiter initializes with correct token count")
    func initialization() async {
        let limiter = RateLimiter(requestsPerMinute: 60)
        // Should start with full tokens - we can acquire immediately
        await limiter.acquire()
        // If we got here without waiting, it worked
    }

    @Test("Rate limiter allows bursts up to limit")
    func burstAllowed() async {
        let limiter = RateLimiter(requestsPerMinute: 10)

        // Should be able to acquire 10 tokens quickly
        for _ in 0 ..< 10 {
            await limiter.acquire()
        }
    }

    @Test("Rate limiter refills tokens over time")
    func tokenRefill() async throws {
        let limiter = RateLimiter(requestsPerMinute: 60) // 1 token per second

        // Exhaust all tokens
        for _ in 0 ..< 60 {
            await limiter.acquire()
        }

        // Wait for refill
        try await Task.sleep(for: .milliseconds(100))

        // Should be able to acquire again (tokens refilled)
        await limiter.acquire()
    }
}

// MARK: - ProviderRegistryTests

@Suite("ProviderRegistry Tests")
struct ProviderRegistryTests {
    @Test("Register and retrieve provider")
    func registerAndRetrieve() async {
        let registry = ProviderRegistry()
        let provider = MockTranslationProvider(identifier: "test-provider")

        await registry.register(provider)

        let retrieved = await registry.provider(for: "test-provider")
        #expect(retrieved?.identifier == "test-provider")
    }

    @Test("Get all providers")
    func getAllProviders() async {
        let registry = ProviderRegistry()

        await registry.register(MockTranslationProvider(identifier: "provider1"))
        await registry.register(MockTranslationProvider(identifier: "provider2"))

        let all = await registry.allProviders()
        #expect(all.count == 2)
    }

    @Test("Get available providers filters unavailable")
    func getAvailableProviders() async {
        let registry = ProviderRegistry()

        let available = MockTranslationProvider(identifier: "available")
        available.isAvailableValue = true

        let unavailable = MockTranslationProvider(identifier: "unavailable")
        unavailable.isAvailableValue = false

        await registry.register(available)
        await registry.register(unavailable)

        let result = await registry.availableProviders()
        #expect(result.count == 1)
        #expect(result.first?.identifier == "available")
    }

    @Test("Provider not found returns nil")
    func providerNotFound() async {
        let registry = ProviderRegistry()
        let retrieved = await registry.provider(for: "nonexistent")
        #expect(retrieved == nil)
    }
}

// MARK: - ChangeDetectorTests

@Suite("ChangeDetector Tests")
struct ChangeDetectorTests {
    @Test("Detect new strings")
    func detectNewStrings() async throws {
        let tempDir = FileManager.default.temporaryDirectory
        let cacheURL = tempDir.appendingPathComponent("test-cache-\(UUID()).json")

        let detector = ChangeDetector(cacheFile: cacheURL)

        let xcstrings = XCStrings(
            sourceLanguage: "en",
            strings: [
                "hello": StringEntry(
                    localizations: [
                        "en": Localization(value: "Hello"),
                    ],
                ),
                "world": StringEntry(
                    localizations: [
                        "en": Localization(value: "World"),
                    ],
                ),
            ],
        )

        let result = await detector.detectChanges(
            in: xcstrings,
            targetLanguages: [LanguageCode("fr")],
        )

        #expect(result.newStrings.count == 2)
        #expect(result.totalStringsToTranslate == 2)
        #expect(result.hasChanges)

        // Cleanup
        try? FileManager.default.removeItem(at: cacheURL)
    }

    @Test("Detect unchanged strings after marking translated")
    func detectUnchangedStrings() async throws {
        let tempDir = FileManager.default.temporaryDirectory
        let cacheURL = tempDir.appendingPathComponent("test-cache-\(UUID()).json")

        let detector = ChangeDetector(cacheFile: cacheURL)

        let xcstrings = XCStrings(
            sourceLanguage: "en",
            strings: [
                "hello": StringEntry(
                    localizations: [
                        "en": Localization(value: "Hello"),
                        "fr": Localization(value: "Bonjour", state: .translated),
                    ],
                ),
            ],
        )

        // Mark as translated in cache
        await detector.markTranslated(
            key: "hello",
            sourceValue: "Hello",
            languages: ["fr"],
            provider: "test",
        )

        let result = await detector.detectChanges(
            in: xcstrings,
            targetLanguages: [LanguageCode("fr")],
        )

        #expect(result.unchanged.contains("hello"))
        #expect(!result.hasChanges)

        // Cleanup
        try? FileManager.default.removeItem(at: cacheURL)
    }

    @Test("Detect modified strings when source changes")
    func detectModifiedStrings() async throws {
        let tempDir = FileManager.default.temporaryDirectory
        let cacheURL = tempDir.appendingPathComponent("test-cache-\(UUID()).json")

        let detector = ChangeDetector(cacheFile: cacheURL)

        // Mark original translation
        await detector.markTranslated(
            key: "hello",
            sourceValue: "Hello",
            languages: ["fr"],
            provider: "test",
        )

        // Now check with modified source
        let xcstrings = XCStrings(
            sourceLanguage: "en",
            strings: [
                "hello": StringEntry(
                    localizations: [
                        "en": Localization(value: "Hello World"), // Changed!
                        "fr": Localization(value: "Bonjour", state: .translated),
                    ],
                ),
            ],
        )

        let result = await detector.detectChanges(
            in: xcstrings,
            targetLanguages: [LanguageCode("fr")],
        )

        #expect(result.modifiedStrings.contains("hello"))
        #expect(result.hasChanges)

        // Cleanup
        try? FileManager.default.removeItem(at: cacheURL)
    }

    @Test("Force retranslate marks all strings")
    func forceRetranslate() async throws {
        let tempDir = FileManager.default.temporaryDirectory
        let cacheURL = tempDir.appendingPathComponent("test-cache-\(UUID()).json")

        let detector = ChangeDetector(cacheFile: cacheURL)

        let xcstrings = XCStrings(
            sourceLanguage: "en",
            strings: [
                "hello": StringEntry(
                    localizations: [
                        "en": Localization(value: "Hello"),
                        "fr": Localization(value: "Bonjour", state: .translated),
                    ],
                ),
            ],
        )

        let result = await detector.detectChanges(
            in: xcstrings,
            targetLanguages: [LanguageCode("fr")],
            forceRetranslate: true,
        )

        #expect(result.newStrings.contains("hello"))
        #expect(result.hasChanges)

        // Cleanup
        try? FileManager.default.removeItem(at: cacheURL)
    }

    @Test("Save and load cache")
    func saveAndLoadCache() async throws {
        let tempDir = FileManager.default.temporaryDirectory
        let cacheURL = tempDir.appendingPathComponent("test-cache-\(UUID()).json")

        // Create and save
        let detector = ChangeDetector(cacheFile: cacheURL)
        await detector.markTranslated(
            key: "hello",
            sourceValue: "Hello",
            languages: ["fr", "de"],
            provider: "test",
        )
        try await detector.save()

        // Load in new instance
        let detector2 = ChangeDetector(cacheFile: cacheURL)
        try await detector2.load()

        let stats = await detector2.statistics
        #expect(stats.totalEntries == 1)

        // Cleanup
        try? FileManager.default.removeItem(at: cacheURL)
    }

    @Test("Clear cache removes all entries")
    func clearCache() async throws {
        let tempDir = FileManager.default.temporaryDirectory
        let cacheURL = tempDir.appendingPathComponent("test-cache-\(UUID()).json")

        let detector = ChangeDetector(cacheFile: cacheURL)
        await detector.markTranslated(
            key: "hello",
            sourceValue: "Hello",
            languages: ["fr"],
            provider: "test",
        )

        await detector.clear()

        let stats = await detector.statistics
        #expect(stats.totalEntries == 0)

        // Cleanup
        try? FileManager.default.removeItem(at: cacheURL)
    }

    @Test("Remove entry from cache")
    func removeEntry() async {
        let tempDir = FileManager.default.temporaryDirectory
        let cacheURL = tempDir.appendingPathComponent("test-cache-\(UUID()).json")

        let detector = ChangeDetector(cacheFile: cacheURL)
        await detector.markTranslated(
            key: "hello",
            sourceValue: "Hello",
            languages: ["fr"],
            provider: "test",
        )
        await detector.markTranslated(
            key: "world",
            sourceValue: "World",
            languages: ["fr"],
            provider: "test",
        )

        await detector.remove(key: "hello")

        let stats = await detector.statistics
        #expect(stats.totalEntries == 1)

        // Cleanup
        try? FileManager.default.removeItem(at: cacheURL)
    }

    @Test("Detect missing languages for partially translated string")
    func detectMissingLanguages() async {
        let tempDir = FileManager.default.temporaryDirectory
        let cacheURL = tempDir.appendingPathComponent("test-cache-\(UUID()).json")

        let detector = ChangeDetector(cacheFile: cacheURL)

        // Mark only French as translated
        await detector.markTranslated(
            key: "hello",
            sourceValue: "Hello",
            languages: ["fr"],
            provider: "test",
        )

        let xcstrings = XCStrings(
            sourceLanguage: "en",
            strings: [
                "hello": StringEntry(
                    localizations: [
                        "en": Localization(value: "Hello"),
                        "fr": Localization(value: "Bonjour", state: .translated),
                    ],
                ),
            ],
        )

        // Check for French and German
        let result = await detector.detectChanges(
            in: xcstrings,
            targetLanguages: [LanguageCode("fr"), LanguageCode("de")],
        )

        // German should need translation, French should not
        let helloLanguages = result.stringsToTranslate["hello"] ?? []
        #expect(helloLanguages.contains(LanguageCode("de")))
        #expect(!helloLanguages.contains(LanguageCode("fr")))

        // Cleanup
        try? FileManager.default.removeItem(at: cacheURL)
    }
}

// MARK: - TranslationServiceTests

@Suite("TranslationService Tests")
struct TranslationServiceTests {
    @Test("Service initializes with configuration")
    func initialization() async {
        let config = Configuration(
            sourceLanguage: LanguageCode("en"),
            targetLanguages: [LanguageCode("fr")],
        )

        let service = TranslationService(configuration: config)
        // Service should initialize without error
        #expect(service != nil)
    }

    @Test("Register provider")
    func registerProvider() async {
        let config = Configuration(
            sourceLanguage: LanguageCode("en"),
            targetLanguages: [LanguageCode("fr")],
        )

        let service = TranslationService(configuration: config)
        let provider = MockTranslationProvider(identifier: "test")

        await service.register(provider)
        // Should not throw
    }

    @Test("Translate batch with mock provider")
    func translateBatch() async throws {
        let config = Configuration(
            sourceLanguage: LanguageCode("en"),
            targetLanguages: [LanguageCode("fr")],
            providers: [
                ProviderConfiguration(name: .openai, enabled: true, priority: 1),
            ],
        )

        let registry = ProviderRegistry()
        let mockProvider = MockTranslationProvider(identifier: "openai")
        mockProvider.translations = [
            "Hello": "Bonjour",
            "World": "Monde",
        ]
        await registry.register(mockProvider)

        let service = TranslationService(configuration: config, registry: registry)

        let results = try await service.translateBatch(
            ["Hello", "World"],
            from: LanguageCode("en"),
            to: LanguageCode("fr"),
        )

        #expect(results.count == 2)
        #expect(results[0].translated == "Bonjour")
        #expect(results[1].translated == "Monde")
        #expect(mockProvider.translateCallCount == 1)
    }

    @Test("Translation falls back to next provider on failure")
    func providerFallback() async throws {
        let config = Configuration(
            sourceLanguage: LanguageCode("en"),
            targetLanguages: [LanguageCode("fr")],
            providers: [
                ProviderConfiguration(name: .openai, enabled: true, priority: 1),
                ProviderConfiguration(name: .anthropic, enabled: true, priority: 2),
            ],
        )

        let registry = ProviderRegistry()

        // First provider fails
        let failingProvider = MockTranslationProvider(identifier: "openai")
        failingProvider.shouldFail = true
        await registry.register(failingProvider)

        // Second provider succeeds
        let successProvider = MockTranslationProvider(identifier: "anthropic")
        successProvider.translations = ["Hello": "Bonjour"]
        await registry.register(successProvider)

        let service = TranslationService(configuration: config, registry: registry)

        let results = try await service.translateBatch(
            ["Hello"],
            from: LanguageCode("en"),
            to: LanguageCode("fr"),
        )

        #expect(results.count == 1)
        #expect(results[0].translated == "Bonjour")
        #expect(results[0].provider == "anthropic")
    }

    @Test("No providers available throws error")
    func noProvidersError() async {
        let config = Configuration(
            sourceLanguage: LanguageCode("en"),
            targetLanguages: [LanguageCode("fr")],
            providers: [],
        )

        let registry = ProviderRegistry()
        let service = TranslationService(configuration: config, registry: registry)

        await #expect(throws: TranslationError.self) {
            try await service.translateBatch(
                ["Hello"],
                from: LanguageCode("en"),
                to: LanguageCode("fr"),
            )
        }
    }

    @Test("Empty strings array returns empty results")
    func emptyStringsArray() async throws {
        let config = Configuration(
            sourceLanguage: LanguageCode("en"),
            targetLanguages: [LanguageCode("fr")],
        )

        let service = TranslationService(configuration: config)

        let results = try await service.translateBatch(
            [],
            from: LanguageCode("en"),
            to: LanguageCode("fr"),
        )

        #expect(results.isEmpty)
    }
}

// MARK: - ChangeDetectionResultTests

@Suite("ChangeDetectionResult Tests")
struct ChangeDetectionResultTests {
    @Test("Total translation operations calculated correctly")
    func totalOperations() {
        let result = ChangeDetectionResult(
            stringsToTranslate: [
                "hello": Set([LanguageCode("fr"), LanguageCode("de")]),
                "world": Set([LanguageCode("fr")]),
            ],
            unchanged: [],
            newStrings: ["hello", "world"],
            modifiedStrings: [],
        )

        #expect(result.totalTranslationOperations == 3) // 2 + 1
        #expect(result.totalStringsToTranslate == 2)
    }

    @Test("Has changes returns true when strings to translate")
    func hasChangesTrue() {
        let result = ChangeDetectionResult(
            stringsToTranslate: ["hello": Set([LanguageCode("fr")])],
            unchanged: [],
            newStrings: ["hello"],
            modifiedStrings: [],
        )

        #expect(result.hasChanges)
    }

    @Test("Has changes returns false when no strings to translate")
    func hasChangesFalse() {
        let result = ChangeDetectionResult(
            stringsToTranslate: [:],
            unchanged: ["hello"],
            newStrings: [],
            modifiedStrings: [],
        )

        #expect(!result.hasChanges)
    }
}

// MARK: - CacheStatisticsTests

@Suite("CacheStatistics Tests")
struct CacheStatisticsTests {
    @Test("Statistics reflect cache state")
    func statisticsReflectState() async {
        let tempDir = FileManager.default.temporaryDirectory
        let cacheURL = tempDir.appendingPathComponent("test-cache-\(UUID()).json")

        let detector = ChangeDetector(cacheFile: cacheURL)

        await detector.markTranslated(
            key: "hello",
            sourceValue: "Hello",
            languages: ["fr"],
            provider: "test",
        )
        await detector.markTranslated(
            key: "world",
            sourceValue: "World",
            languages: ["de"],
            provider: "test2",
        )

        let stats = await detector.statistics
        #expect(stats.totalEntries == 2)
        #expect(stats.cacheVersion == "1.0")
        #expect(stats.lastUpdated != nil)

        // Cleanup
        try? FileManager.default.removeItem(at: cacheURL)
    }
}

// MARK: - TranslationCacheTests

@Suite("TranslationCache Tests")
struct TranslationCacheTests {
    @Test("Cache entry stores all properties")
    func cacheEntryProperties() {
        let entry = CacheEntry(
            sourceHash: "abc123",
            translatedLanguages: ["fr", "de"],
            lastModified: Date(),
            provider: "openai",
        )

        #expect(entry.sourceHash == "abc123")
        #expect(entry.translatedLanguages.count == 2)
        #expect(entry.translatedLanguages.contains("fr"))
        #expect(entry.translatedLanguages.contains("de"))
        #expect(entry.provider == "openai")
    }

    @Test("Translation cache codable")
    func cacheCodable() throws {
        let cache = TranslationCache(
            version: "1.0",
            entries: [
                "hello": CacheEntry(
                    sourceHash: "abc",
                    translatedLanguages: ["fr"],
                    lastModified: Date(),
                    provider: "test",
                ),
            ],
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(cache)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(TranslationCache.self, from: data)

        #expect(decoded.version == "1.0")
        #expect(decoded.entries.count == 1)
        #expect(decoded.entries["hello"]?.sourceHash == "abc")
    }
}

// MARK: - TranslationPromptBuilderTests

@Suite("TranslationPromptBuilder Tests")
struct TranslationPromptBuilderTests {
    @Test("System prompt includes app context")
    func systemPromptIncludesContext() {
        let builder = TranslationPromptBuilder()
        let context = TranslationContext(
            appDescription: "A fuel tracking app",
            domain: "automotive",
        )

        let prompt = builder.buildSystemPrompt(
            context: context,
            targetLanguage: LanguageCode("fr"),
        )

        #expect(prompt.contains("fuel tracking"))
        #expect(prompt.contains("automotive"))
    }

    @Test("System prompt includes glossary terms")
    func systemPromptIncludesGlossary() {
        let builder = TranslationPromptBuilder()
        let context = TranslationContext(
            glossaryTerms: [
                GlossaryTerm(
                    term: "LotoFuel",
                    doNotTranslate: true,
                ),
                GlossaryTerm(
                    term: "Fill-up",
                    translations: ["fr": "Plein"],
                ),
            ],
        )

        let prompt = builder.buildSystemPrompt(
            context: context,
            targetLanguage: LanguageCode("fr"),
        )

        #expect(prompt.contains("LotoFuel"))
        #expect(prompt.contains("do not translate"))
        #expect(prompt.contains("Fill-up"))
        #expect(prompt.contains("Plein"))
    }

    @Test("User prompt includes strings to translate")
    func userPromptIncludesStrings() {
        let builder = TranslationPromptBuilder()

        let prompt = builder.buildUserPrompt(
            strings: ["Hello", "World"],
            context: nil,
            targetLanguage: LanguageCode("fr"),
        )

        #expect(prompt.contains("Hello"))
        #expect(prompt.contains("World"))
        #expect(prompt.contains("French"))
    }

    @Test("Parse valid JSON response")
    func parseValidResponse() throws {
        let builder = TranslationPromptBuilder()
        let response = """
        {"Hello": "Bonjour", "World": "Monde"}
        """

        let results = try builder.parseResponse(
            response,
            originalStrings: ["Hello", "World"],
            provider: "test",
        )

        #expect(results.count == 2)
        #expect(results[0].translated == "Bonjour")
        #expect(results[1].translated == "Monde")
    }

    @Test("Parse JSON wrapped in code block")
    func parseCodeBlockResponse() throws {
        let builder = TranslationPromptBuilder()
        let response = """
        ```json
        {"Hello": "Bonjour"}
        ```
        """

        let results = try builder.parseResponse(
            response,
            originalStrings: ["Hello"],
            provider: "test",
        )

        #expect(results.count == 1)
        #expect(results[0].translated == "Bonjour")
    }

    @Test("Parse response returns original for missing translations")
    func parseResponseMissingTranslations() throws {
        let builder = TranslationPromptBuilder()
        let response = """
        {"Hello": "Bonjour"}
        """

        let results = try builder.parseResponse(
            response,
            originalStrings: ["Hello", "World"],
            provider: "test",
        )

        #expect(results.count == 2)
        #expect(results[0].translated == "Bonjour")
        #expect(results[1].translated == "World") // Original returned
        #expect(results[1].confidence == 0.0) // Low confidence for missing
    }

    @Test("Parse invalid JSON throws error")
    func parseInvalidJSON() {
        let builder = TranslationPromptBuilder()

        #expect(throws: TranslationError.self) {
            try builder.parseResponse(
                "not valid json",
                originalStrings: ["Hello"],
                provider: "test",
            )
        }
    }
}
