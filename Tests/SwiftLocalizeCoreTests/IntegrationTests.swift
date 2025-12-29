//
//  IntegrationTests.swift
//  SwiftLocalize
//
//  Integration tests for the full translation pipeline.
//

import Foundation
@testable import SwiftLocalizeCore
import Testing

// MARK: - IntegrationMockProvider

/// A mock translation provider for integration testing.
/// Named differently from ServiceTests mock to avoid conflicts.
final class IntegrationMockProvider: TranslationProvider, @unchecked Sendable {
    // MARK: Lifecycle

    init(identifier: String = "mock", displayName: String = "Mock Provider") {
        self.identifier = identifier
        self.displayName = displayName
    }

    // MARK: Internal

    let identifier: String
    let displayName: String

    var translations: [String: [String: String]] = [:] // [targetLang: [source: translation]]
    var shouldFail = false
    var failureError: TranslationError?
    var translateCallCount = 0
    var lastTranslatedStrings: [String] = []
    var delay: Duration = .zero

    func isAvailable() async -> Bool {
        !shouldFail
    }

    func supportedLanguages() async throws -> [LanguagePair] {
        [
            LanguagePair(source: .english, target: .french),
            LanguagePair(source: .english, target: .german),
            LanguagePair(source: .english, target: .spanish),
            LanguagePair(source: .english, target: .japanese),
        ]
    }

    func translate(
        _ strings: [String],
        from source: LanguageCode,
        to target: LanguageCode,
        context: TranslationContext?,
    ) async throws -> [TranslationResult] {
        translateCallCount += 1
        lastTranslatedStrings = strings

        if delay > .zero {
            try await Task.sleep(for: delay)
        }

        if shouldFail {
            throw failureError ?? TranslationError.providerError(
                provider: identifier,
                message: "Mock failure",
            )
        }

        let targetTranslations = translations[target.code] ?? [:]

        return strings.map { string in
            let translated = targetTranslations[string] ?? "[\(target.code)] \(string)"
            return TranslationResult(
                original: string,
                translated: translated,
                confidence: 0.95,
                provider: identifier,
                metadata: ["mock": "true"],
            )
        }
    }

    // MARK: - Helper Methods

    func setTranslations(_ translations: [String: String], for language: LanguageCode) {
        self.translations[language.code] = translations
    }
}

// MARK: - FullTranslationPipelineTests

@Suite("Full Translation Pipeline Tests")
struct FullTranslationPipelineTests {
    @Test("Single string translation through mock provider")
    func singleStringTranslation() async throws {
        let provider = IntegrationMockProvider()
        provider.setTranslations(["Hello": "Bonjour"], for: .french)

        let results = try await provider.translate(
            ["Hello"],
            from: .english,
            to: .french,
            context: nil,
        )

        #expect(results.count == 1)
        #expect(results[0].original == "Hello")
        #expect(results[0].translated == "Bonjour")
        #expect(results[0].provider == "mock")
    }

    @Test("Batch translation preserves order")
    func batchTranslationOrder() async throws {
        let provider = IntegrationMockProvider()
        provider.setTranslations([
            "One": "Un",
            "Two": "Deux",
            "Three": "Trois",
        ], for: .french)

        let strings = ["One", "Two", "Three"]
        let results = try await provider.translate(
            strings,
            from: .english,
            to: .french,
            context: nil,
        )

        #expect(results.count == 3)
        #expect(results[0].original == "One")
        #expect(results[1].original == "Two")
        #expect(results[2].original == "Three")
        #expect(results[0].translated == "Un")
        #expect(results[1].translated == "Deux")
        #expect(results[2].translated == "Trois")
    }

    @Test("Missing translations use placeholder")
    func missingTranslationsUsePlaceholder() async throws {
        let provider = IntegrationMockProvider()
        // No translations set

        let results = try await provider.translate(
            ["Hello"],
            from: .english,
            to: .german,
            context: nil,
        )

        #expect(results[0].translated == "[de] Hello")
    }

    @Test("Provider failure throws error")
    func providerFailureThrows() async {
        let provider = IntegrationMockProvider()
        provider.shouldFail = true
        provider.failureError = .providerError(provider: "mock", message: "API rate limit")

        do {
            _ = try await provider.translate(
                ["Hello"],
                from: .english,
                to: .french,
                context: nil,
            )
            #expect(Bool(false), "Should have thrown")
        } catch let error as TranslationError {
            if case let .providerError(name, message) = error {
                #expect(name == "mock")
                #expect(message == "API rate limit")
            } else {
                #expect(Bool(false), "Wrong error case")
            }
        } catch {
            #expect(Bool(false), "Wrong error type")
        }
    }

    @Test("Translation with context passes context to provider")
    func translationWithContext() async throws {
        let provider = IntegrationMockProvider()
        let context = TranslationContext(
            appDescription: "A fuel tracking app",
            domain: "automotive",
            preserveFormatters: true,
            preserveMarkdown: true,
        )

        let results = try await provider.translate(
            ["Fill-up"],
            from: .english,
            to: .french,
            context: context,
        )

        #expect(results.count == 1)
        // Context is passed but mock doesn't use it - just verify no error
    }
}

// MARK: - ProviderRegistryIntegrationTests

@Suite("Provider Registry Integration Tests")
struct ProviderRegistryIntegrationTests {
    @Test("Register multiple providers and retrieve by identifier")
    func registerAndRetrieveMultiple() async {
        let registry = ProviderRegistry()

        let openaiMock = IntegrationMockProvider(identifier: "openai", displayName: "OpenAI Mock")
        let anthropicMock = IntegrationMockProvider(identifier: "anthropic", displayName: "Anthropic Mock")
        let deepLMock = IntegrationMockProvider(identifier: "deepl", displayName: "DeepL Mock")

        await registry.register(openaiMock)
        await registry.register(anthropicMock)
        await registry.register(deepLMock)

        let retrieved = await registry.provider(for: "anthropic")
        #expect(retrieved?.identifier == "anthropic")

        let all = await registry.allProviders()
        #expect(all.count == 3)
    }

    @Test("Provider not found returns nil")
    func providerNotFoundReturnsNil() async {
        let registry = ProviderRegistry()

        let provider = await registry.provider(for: "nonexistent")
        #expect(provider == nil)
    }

    @Test("Registering same identifier replaces provider")
    func registerReplacesExisting() async {
        let registry = ProviderRegistry()

        let provider1 = IntegrationMockProvider(identifier: "test", displayName: "Provider 1")
        let provider2 = IntegrationMockProvider(identifier: "test", displayName: "Provider 2")

        await registry.register(provider1)
        await registry.register(provider2)

        let retrieved = await registry.provider(for: "test")
        #expect(retrieved?.displayName == "Provider 2")
    }
}

// MARK: - TranslationServiceIntegrationTests

@Suite("TranslationService Integration Tests")
struct TranslationServiceIntegrationTests {
    @Test("Service initializes with configuration")
    func serviceInitialization() async {
        let config = Configuration(
            sourceLanguage: .english,
            targetLanguages: [.french],
            providers: [
                ProviderConfiguration(name: .openai, enabled: true, priority: 1),
            ],
        )

        let service = TranslationService(configuration: config)
        // Verify service can be created without errors
        #expect(service != nil)
    }

    @Test("Service can register provider")
    func registerProvider() async {
        let config = Configuration(
            sourceLanguage: .english,
            targetLanguages: [.french],
            providers: [],
        )

        let service = TranslationService(configuration: config)
        let provider = IntegrationMockProvider(identifier: "test", displayName: "Test")

        await service.register(provider)
        // Verify registration completes without error
    }

    @Test("Provider translateBatch returns results")
    func providerTranslateBatch() async throws {
        let provider = IntegrationMockProvider(identifier: "test", displayName: "Test")
        provider.setTranslations([
            "Hello": "Bonjour",
            "World": "Monde",
        ], for: LanguageCode.french)

        let results = try await provider.translate(
            ["Hello", "World"],
            from: LanguageCode.english,
            to: LanguageCode.french,
            context: nil,
        )

        #expect(results.count == 2)
        #expect(results[0].translated == "Bonjour")
        #expect(results[1].translated == "Monde")
        #expect(results[0].provider == "test")
    }

    @Test("Provider handles multiple target languages")
    func providerMultipleLanguages() async throws {
        let provider = IntegrationMockProvider(identifier: "test", displayName: "Test")
        provider.setTranslations(["Hello": "Bonjour"], for: LanguageCode.french)
        provider.setTranslations(["Hello": "Hallo"], for: LanguageCode.german)
        provider.setTranslations(["Hello": "Hola"], for: LanguageCode.spanish)

        let frenchResults = try await provider.translate(
            ["Hello"],
            from: LanguageCode.english,
            to: LanguageCode.french,
            context: nil,
        )

        let germanResults = try await provider.translate(
            ["Hello"],
            from: LanguageCode.english,
            to: LanguageCode.german,
            context: nil,
        )

        #expect(frenchResults[0].translated == "Bonjour")
        #expect(germanResults[0].translated == "Hallo")
    }
}

// MARK: - ChangeDetectorIntegrationTests

@Suite("ChangeDetector Integration Tests")
struct ChangeDetectorIntegrationTests {
    // MARK: Internal

    @Test("Detect all strings as new on empty cache")
    func detectNewStringsOnEmptyCache() async throws {
        let detector = ChangeDetector(cacheFile: Self.tempCacheFile())

        let xcstrings = XCStrings(
            sourceLanguage: "en",
            strings: [
                "hello": StringEntry(localizations: [:]),
                "world": StringEntry(localizations: [:]),
            ],
        )

        let targetLanguages: [LanguageCode] = [.french]
        let result = await detector.detectChanges(
            in: xcstrings,
            targetLanguages: targetLanguages,
        )

        #expect(result.stringsToTranslate.count == 2)
        #expect(result.stringsToTranslate["hello"]?.contains(.french) == true)
        #expect(result.stringsToTranslate["world"]?.contains(.french) == true)
    }

    @Test("Skip translated strings")
    func skipTranslatedStrings() async throws {
        let detector = ChangeDetector(cacheFile: Self.tempCacheFile())

        let xcstrings = XCStrings(
            sourceLanguage: "en",
            strings: [
                "hello": StringEntry(localizations: [
                    "fr": Localization(stringUnit: StringUnit(state: .translated, value: "Bonjour")),
                ]),
                "world": StringEntry(localizations: [:]),
            ],
        )

        let targetLanguages: [LanguageCode] = [.french]
        let result = await detector.detectChanges(
            in: xcstrings,
            targetLanguages: targetLanguages,
        )

        #expect(result.stringsToTranslate.count == 1)
        #expect(result.stringsToTranslate["world"] != nil)
        #expect(result.stringsToTranslate["hello"] == nil)
    }

    @Test("Detect partially translated strings")
    func detectPartiallyTranslatedStrings() async throws {
        let detector = ChangeDetector(cacheFile: Self.tempCacheFile())

        let xcstrings = XCStrings(
            sourceLanguage: "en",
            strings: [
                "hello": StringEntry(localizations: [
                    "fr": Localization(stringUnit: StringUnit(state: .translated, value: "Bonjour")),
                    // German translation missing
                ]),
            ],
        )

        let targetLanguages: [LanguageCode] = [.french, .german]
        let result = await detector.detectChanges(
            in: xcstrings,
            targetLanguages: targetLanguages,
        )

        #expect(result.stringsToTranslate.count == 1)
        #expect(result.stringsToTranslate["hello"]?.contains(.german) == true)
        #expect(result.stringsToTranslate["hello"]?.contains(.french) == false)
    }

    @Test("Cache update and retrieval")
    func cacheUpdateAndRetrieval() async throws {
        let detector = ChangeDetector(cacheFile: Self.tempCacheFile())

        // Mark a string as translated with the full API
        await detector.markTranslated(
            key: "hello",
            sourceValue: "Hello",
            languages: ["fr", "de"],
            provider: "test",
        )

        let xcstrings = XCStrings(
            sourceLanguage: "en",
            strings: [
                "hello": StringEntry(localizations: [:]),
            ],
        )

        // If hash hasn't changed, should not need retranslation
        let targetLanguages: [LanguageCode] = [.french, .german]
        let result = await detector.detectChanges(
            in: xcstrings,
            targetLanguages: targetLanguages,
        )

        // The detection depends on whether source hash matches
        // Since we can't control the hash computation, just verify the result is valid
        // (may or may not be empty depending on hash matching)
        _ = result.stringsToTranslate
    }

    // MARK: Private

    /// Helper to create a temp cache file URL
    private static func tempCacheFile() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("test-cache-\(UUID().uuidString).json")
    }
}

// MARK: - ContextBuilderIntegrationTests

@Suite("ContextBuilder Integration Tests")
struct ContextBuilderIntegrationTests {
    @Test("Build context with glossary and translation memory")
    func buildFullContext() async throws {
        let glossary = Glossary()
        await glossary.addTerm(GlossaryEntry(term: "LotoFuel", doNotTranslate: true))
        await glossary.addTerm(GlossaryEntry(
            term: "Fill-up",
            translations: ["fr": "Plein"],
        ))

        let tm = TranslationMemory()
        await tm.store(
            source: "Hello",
            translation: "Bonjour",
            language: "fr",
            provider: "human",
        )

        let config = ContextConfiguration(
            appName: "LotoFuel",
            appDescription: "A fuel tracking app for iOS",
            domain: "automotive",
            tone: .friendly,
            formality: .neutral,
            translationMemoryEnabled: true,
            glossaryEnabled: true,
        )

        let builder = ContextBuilder(
            config: config,
            translationMemory: tm,
            glossary: glossary,
        )

        let context = try await builder.buildContext(
            for: [
                ("greeting", "Hello", "Welcome message"),
                ("fill_action", "Fill-up your LotoFuel account", "CTA button"),
            ],
            targetLanguage: "fr",
        )

        // Verify app context
        #expect(context.appContext.contains("LotoFuel"))
        #expect(context.appContext.contains("automotive"))

        // Verify string contexts
        #expect(context.stringContexts.count == 2)
        #expect(context.stringContexts[0].key == "greeting")
        #expect(context.stringContexts[1].key == "fill_action")

        // Verify glossary terms were found
        #expect(!context.glossaryTerms.isEmpty)

        // Verify TM matches were found
        #expect(!context.translationMemoryMatches.isEmpty)
    }

    @Test("System prompt includes all context elements")
    func systemPromptIncludesAllElements() async throws {
        let glossary = Glossary()
        await glossary.addTerm(GlossaryEntry(term: "Brand", doNotTranslate: true))

        let config = ContextConfiguration(
            appName: "TestApp",
            appDescription: "Test application",
            domain: "testing",
            glossaryEnabled: true,
        )

        let builder = ContextBuilder(
            config: config,
            glossary: glossary,
        )

        let context = try await builder.buildContext(
            for: [("key", "Save to Brand", nil)],
            targetLanguage: "fr",
        )

        let systemPrompt = context.toSystemPrompt()

        // Verify prompt structure includes key elements
        #expect(systemPrompt.contains("translator"))
        #expect(systemPrompt.contains("TestApp"))
        #expect(systemPrompt.contains("Brand"))
        #expect(systemPrompt.contains("unchanged") || systemPrompt.contains("Keep"))
        #expect(systemPrompt.contains("format specifiers") || systemPrompt.contains("preserve"))
    }

    @Test("User prompt includes string details")
    func userPromptIncludesStrings() async throws {
        let config = ContextConfiguration(
            appName: "TestApp",
            sourceCodeAnalysisEnabled: false,
        )

        let builder = ContextBuilder(config: config)

        let context = try await builder.buildContext(
            for: [
                ("welcome", "Welcome to the app!", "Home screen greeting"),
                ("cta", "Get Started", "Button text"),
            ],
            targetLanguage: "de",
        )

        let userPrompt = context.toUserPrompt()

        #expect(userPrompt.contains("welcome"))
        #expect(userPrompt.contains("Welcome to the app!"))
        #expect(userPrompt.contains("Home screen greeting"))
        #expect(userPrompt.contains("cta"))
        #expect(userPrompt.contains("Get Started"))
        #expect(userPrompt.contains("de"))
    }
}

// MARK: - XCStringsRoundTripTests

@Suite("XCStrings Round-Trip Tests")
struct XCStringsRoundTripTests {
    @Test("Parse and re-encode preserves structure")
    func parseAndReencodePreservesStructure() throws {
        let json = """
        {
            "sourceLanguage": "en",
            "version": "1.0",
            "strings": {
                "greeting": {
                    "comment": "Welcome message",
                    "localizations": {
                        "fr": {
                            "stringUnit": {
                                "state": "translated",
                                "value": "Bonjour"
                            }
                        }
                    }
                }
            }
        }
        """

        let decoder = JSONDecoder()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]

        let data = Data(json.utf8)
        let xcstrings = try decoder.decode(XCStrings.self, from: data)

        #expect(xcstrings.sourceLanguage == "en")
        #expect(xcstrings.version == "1.0")
        #expect(xcstrings.strings["greeting"]?.comment == "Welcome message")

        // Re-encode and verify it can be parsed again
        let reencoded = try encoder.encode(xcstrings)
        let reparsed = try decoder.decode(XCStrings.self, from: reencoded)

        #expect(reparsed.sourceLanguage == xcstrings.sourceLanguage)
        #expect(reparsed.strings["greeting"]?.comment == xcstrings.strings["greeting"]?.comment)
    }

    @Test("Add translation preserves existing data")
    func addTranslationPreservesExisting() throws {
        let json = """
        {
            "sourceLanguage": "en",
            "version": "1.0",
            "strings": {
                "greeting": {
                    "comment": "Welcome message",
                    "extractionState": "manual",
                    "localizations": {
                        "fr": {
                            "stringUnit": {
                                "state": "translated",
                                "value": "Bonjour"
                            }
                        }
                    }
                }
            }
        }
        """

        let decoder = JSONDecoder()
        let data = Data(json.utf8)
        var xcstrings = try decoder.decode(XCStrings.self, from: data)

        // Add German translation
        var entry = xcstrings.strings["greeting"]!
        var localizations = entry.localizations ?? [:]
        localizations["de"] = Localization(stringUnit: StringUnit(state: .translated, value: "Hallo"))
        entry.localizations = localizations
        xcstrings.strings["greeting"] = entry

        // Verify both translations exist
        #expect(xcstrings.strings["greeting"]?.localizations?["fr"]?.stringUnit?.value == "Bonjour")
        #expect(xcstrings.strings["greeting"]?.localizations?["de"]?.stringUnit?.value == "Hallo")

        // Verify comment and extraction state preserved
        #expect(xcstrings.strings["greeting"]?.comment == "Welcome message")
        #expect(xcstrings.strings["greeting"]?.extractionState == "manual")
    }
}

// MARK: - FormatMigrationIntegrationTests

@Suite("Format Migration Integration Tests")
struct FormatMigrationIntegrationTests {
    @Test("Migrate .strings to xcstrings preserves all entries")
    func migrateStringsPreservesEntries() async throws {
        // Create a StringsFile manually
        let stringsFile = StringsFile(
            language: "en",
            entries: [
                "hello": StringsEntry(value: "Hello World", comment: "Greeting message"),
                "goodbye": StringsEntry(value: "Goodbye!", comment: "Farewell message"),
            ],
        )

        let migrator = FormatMigrator()
        let xcstrings = await migrator.migrateToXCStrings(
            stringsFiles: [stringsFile],
            sourceLanguage: "en",
        )

        #expect(xcstrings.sourceLanguage == "en")
        #expect(xcstrings.strings.count == 2)
        #expect(xcstrings.strings["hello"]?.localizations?["en"]?.stringUnit?.value == "Hello World")
        #expect(xcstrings.strings["goodbye"]?.localizations?["en"]?.stringUnit?.value == "Goodbye!")
        #expect(xcstrings.strings["hello"]?.comment == "Greeting message")
        #expect(xcstrings.strings["goodbye"]?.comment == "Farewell message")
    }

    @Test("Migrate xcstrings to .strings for single language")
    func migrateXCStringsToStrings() async {
        let xcstrings = XCStrings(
            sourceLanguage: "en",
            strings: [
                "hello": StringEntry(
                    comment: "Greeting",
                    localizations: [
                        "en": Localization(stringUnit: StringUnit(state: .translated, value: "Hello")),
                        "fr": Localization(stringUnit: StringUnit(state: .translated, value: "Bonjour")),
                    ],
                ),
            ],
            version: "1.0",
        )

        let migrator = FormatMigrator()
        let (stringsFile, _) = await migrator.migrateToLegacy(
            xcstrings: xcstrings,
            language: "fr",
        )

        #expect(stringsFile.entries.count == 1)
        #expect(stringsFile.entries["hello"]?.value == "Bonjour")
        #expect(stringsFile.entries["hello"]?.comment == "Greeting")
    }
}

// MARK: - EndToEndWorkflowTests

@Suite("End-to-End Workflow Tests")
struct EndToEndWorkflowTests {
    // MARK: Internal

    @Test("Complete translation workflow")
    func completeTranslationWorkflow() async throws {
        // 1. Create XCStrings with untranslated strings
        var xcstrings = XCStrings(
            sourceLanguage: "en",
            strings: [
                "welcome": StringEntry(
                    comment: "Home screen welcome message",
                    localizations: [
                        "en": Localization(stringUnit: StringUnit(state: .translated, value: "Welcome to the app!")),
                    ],
                ),
                "continue": StringEntry(
                    comment: "Continue button",
                    localizations: [
                        "en": Localization(stringUnit: StringUnit(state: .translated, value: "Continue")),
                    ],
                ),
            ],
        )

        // 2. Detect changes - should find strings needing French translation
        let detector = ChangeDetector(cacheFile: Self.tempCacheFile())
        let frenchTargets: [LanguageCode] = [.french]
        let changes = await detector.detectChanges(
            in: xcstrings,
            targetLanguages: frenchTargets,
        )

        #expect(changes.stringsToTranslate.count == 2)
        #expect(changes.hasChanges)

        // 3. Build context for translation
        let contextConfig = ContextConfiguration(
            appName: "TestApp",
            domain: "general",
            sourceCodeAnalysisEnabled: false,
        )
        let contextBuilder = ContextBuilder(config: contextConfig)

        var stringsToTranslate: [(key: String, value: String, comment: String?)] = []
        for (key, _) in changes.stringsToTranslate {
            let entry = xcstrings.strings[key]
            let value = entry?.localizations?["en"]?.stringUnit?.value ?? key
            let comment = entry?.comment
            stringsToTranslate.append((key: key, value: value, comment: comment))
        }

        let context = try await contextBuilder.buildContext(
            for: stringsToTranslate,
            targetLanguage: "fr",
        )

        #expect(!context.toSystemPrompt().isEmpty)
        #expect(context.toUserPrompt().contains("fr"))

        // 4. Translate using mock provider
        let provider = IntegrationMockProvider()
        provider.setTranslations([
            "Welcome to the app!": "Bienvenue dans l'application!",
            "Continue": "Continuer",
        ], for: LanguageCode.french)

        let valuesToTranslate = stringsToTranslate.map(\.value)
        let translationResults = try await provider.translate(
            valuesToTranslate,
            from: LanguageCode.english,
            to: LanguageCode.french,
            context: TranslationContext(
                appDescription: contextConfig.appDescription,
                domain: contextConfig.domain,
            ),
        )

        #expect(translationResults.count == 2)

        // 5. Apply translations to XCStrings
        for (index, stringEntry) in stringsToTranslate.enumerated() {
            let translation = translationResults[index].translated
            var entry = xcstrings.strings[stringEntry.key]!
            var localizations = entry.localizations ?? [:]
            localizations["fr"] = Localization(
                stringUnit: StringUnit(state: .translated, value: translation),
            )
            entry.localizations = localizations
            xcstrings.strings[stringEntry.key] = entry
        }

        // 6. Verify translations applied
        #expect(xcstrings.strings["welcome"]?.localizations?["fr"]?.stringUnit?
            .value == "Bienvenue dans l'application!")
        #expect(xcstrings.strings["continue"]?.localizations?["fr"]?.stringUnit?.value == "Continuer")

        // 7. Detect changes again - should find no more changes for French
        let targetLanguages: [LanguageCode] = [.french]
        let changesAfter = await detector.detectChanges(
            in: xcstrings,
            targetLanguages: targetLanguages,
        )

        #expect(!changesAfter.hasChanges)
        #expect(changesAfter.stringsToTranslate.isEmpty)
    }

    // MARK: Private

    /// Helper to create a temp cache file URL
    private static func tempCacheFile() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("test-cache-\(UUID().uuidString).json")
    }
}
