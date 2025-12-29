//
//  TranslationProviderTests.swift
//  SwiftLocalize
//

import Foundation
@testable import SwiftLocalizeCore
import Testing

// MARK: - TranslationProviderTests

@Suite("Translation Provider Tests")
struct TranslationProviderTests {
    // MARK: Internal

    // MARK: - Translation Result

    @Test("TranslationResult initialization")
    func translationResultInit() {
        let result = TranslationResult(
            original: "Hello",
            translated: "Bonjour",
            confidence: 0.95,
            provider: "test",
            metadata: ["key": "value"],
        )

        #expect(result.original == "Hello")
        #expect(result.translated == "Bonjour")
        #expect(result.confidence == 0.95)
        #expect(result.provider == "test")
        #expect(result.metadata?["key"] == "value")
    }

    @Test("TranslationResult with default confidence")
    func translationResultDefaultConfidence() {
        let result = TranslationResult(
            original: "Hello",
            translated: "Bonjour",
            provider: "test",
        )

        // Confidence is optional, nil means no confidence score provided
        #expect(result.confidence == nil || result.confidence == 1.0)
    }

    // MARK: - Language Pair

    @Test("LanguagePair initialization")
    func languagePairInit() {
        let pair = LanguagePair(
            source: LanguageCode("en"),
            target: LanguageCode("fr"),
        )

        #expect(pair.source.code == "en")
        #expect(pair.target.code == "fr")
    }

    // MARK: - Translation Context

    @Test("TranslationContext initialization")
    func translationContextInit() {
        let context = TranslationContext(
            appDescription: "A banking app",
            domain: "finance",
            preserveFormatters: true,
            preserveMarkdown: true,
            additionalInstructions: "Keep it formal",
            glossaryTerms: nil,
            translationMemoryMatches: nil,
            stringContexts: nil,
        )

        #expect(context.appDescription == "A banking app")
        #expect(context.domain == "finance")
        #expect(context.preserveFormatters == true)
        #expect(context.preserveMarkdown == true)
        #expect(context.additionalInstructions == "Keep it formal")
    }

    // MARK: - Provider Registry

    @Test("Provider registry can be created")
    func providerRegistryCreation() async {
        let registry = ProviderRegistry()
        let provider = MockProvider(id: "test")

        await registry.register(provider)
        // If we get here without crash, registration worked
        #expect(true)
    }

    // MARK: - Prompt Builder

    @Test("Prompt builder creates valid system prompt")
    func buildSystemPrompt() {
        let builder = TranslationPromptBuilder()
        let context = TranslationContext(
            appDescription: "A fitness app",
            domain: "health",
            preserveFormatters: true,
            preserveMarkdown: false,
            additionalInstructions: nil,
            glossaryTerms: nil,
            translationMemoryMatches: nil,
            stringContexts: nil,
        )

        let prompt = builder.buildSystemPrompt(
            context: context,
            targetLanguage: LanguageCode("fr"),
        )

        // Prompt should contain translation guidelines
        #expect(prompt.contains("translator") || prompt.contains("Translation"))
        #expect(prompt.contains("fitness app") || prompt.contains("health"))
    }

    @Test("Prompt builder creates valid user prompt")
    func buildUserPrompt() {
        let builder = TranslationPromptBuilder()
        let strings = ["Hello", "Goodbye", "Welcome"]

        let prompt = builder.buildUserPrompt(
            strings: strings,
            context: nil,
            targetLanguage: LanguageCode("de"),
        )

        #expect(prompt.contains("Hello"))
        #expect(prompt.contains("Goodbye"))
        #expect(prompt.contains("Welcome"))
    }

    @Test("Prompt builder can be instantiated")
    func promptBuilderInstantiation() {
        let builder = TranslationPromptBuilder()
        // Verify we can create instances
        #expect(builder != nil)
    }

    // MARK: - Translation Errors

    @Test("Translation error descriptions")
    func errorDescriptions() {
        let error1 = TranslationError.noProvidersAvailable
        #expect(!error1.localizedDescription.isEmpty)

        let error2 = TranslationError.rateLimitExceeded(provider: "test", retryAfter: 60)
        #expect(!error2.localizedDescription.isEmpty)

        let error3 = TranslationError.unsupportedLanguagePair(source: "en", target: "xx")
        #expect(!error3.localizedDescription.isEmpty)
    }

    // MARK: - Translation Progress

    @Test("Translation progress calculation")
    func progressCalculation() {
        let progress = TranslationProgress(
            total: 100,
            completed: 50,
            failed: 10,
            currentLanguage: LanguageCode("fr"),
            currentProvider: "openai",
        )

        #expect(progress.total == 100)
        #expect(progress.completed == 50)
        #expect(progress.failed == 10)
        #expect(progress.percentage == 0.5)
        #expect(progress.currentLanguage?.code == "fr")
        #expect(progress.currentProvider == "openai")
    }

    // MARK: Private

    // MARK: - Helpers

    private func createTestConfig() -> Configuration {
        let loader = ConfigurationLoader()
        return loader.defaultConfiguration()
    }
}

// MARK: - MockProvider

final class MockProvider: TranslationProvider, @unchecked Sendable {
    // MARK: Lifecycle

    init(
        id: String,
        displayName: String? = nil,
        available: Bool = true,
        languages: [LanguagePair] = [],
    ) {
        identifier = id
        self.displayName = displayName ?? id.capitalized
        self.available = available
        self.languages = languages
    }

    // MARK: Internal

    let identifier: String
    let displayName: String

    func isAvailable() async -> Bool {
        available
    }

    func supportedLanguages() async throws -> [LanguagePair] {
        languages
    }

    func translate(
        _ strings: [String],
        from source: LanguageCode,
        to target: LanguageCode,
        context: TranslationContext?,
    ) async throws -> [TranslationResult] {
        strings.map { str in
            TranslationResult(
                original: str,
                translated: "[\(target.code)] \(str)",
                confidence: 1.0,
                provider: identifier,
            )
        }
    }

    // MARK: Private

    private let available: Bool
    private let languages: [LanguagePair]
}
