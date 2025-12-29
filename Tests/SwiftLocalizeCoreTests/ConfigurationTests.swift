//
//  ConfigurationTests.swift
//  SwiftLocalize
//

import Foundation
@testable import SwiftLocalizeCore
import Testing

@Suite("Configuration Tests")
struct ConfigurationTests {
    // MARK: - Default Configuration

    @Test("Default configuration has sensible defaults")
    func defaultConfiguration() {
        let loader = ConfigurationLoader()
        let config = loader.defaultConfiguration()

        #expect(config.sourceLanguage.code == "en")
        #expect(!config.targetLanguages.isEmpty)
        #expect(!config.providers.isEmpty)
        #expect(config.translation.batchSize > 0)
        #expect(config.translation.retries > 0)
    }

    @Test("Default configuration includes Apple Translation provider")
    func defaultConfigurationProviders() {
        let loader = ConfigurationLoader()
        let config = loader.defaultConfiguration()

        let appleProvider = config.providers.first { $0.name == ProviderName.appleTranslation }
        #expect(appleProvider != nil)
        #expect(appleProvider?.enabled == true)
    }

    // MARK: - Configuration Validation

    @Test("Validate warns about missing API keys")
    func validateMissingAPIKeys() {
        let loader = ConfigurationLoader()
        let config = Configuration(
            sourceLanguage: LanguageCode("en"),
            targetLanguages: [LanguageCode("fr")],
            providers: [
                ProviderConfiguration(name: .openai, enabled: true, priority: 1),
            ],
        )

        let issues = loader.validate(config)
        let warnings = issues.filter { !$0.isError }
        #expect(!warnings.isEmpty)
    }

    // MARK: - LanguageCode

    @Test("LanguageCode equality")
    func languageCodeEquality() {
        let en1 = LanguageCode("en")
        let en2 = LanguageCode("en")
        let fr = LanguageCode("fr")

        #expect(en1 == en2)
        #expect(en1 != fr)
    }

    @Test("LanguageCode hashable")
    func languageCodeHashable() {
        let set: Set<LanguageCode> = [
            LanguageCode("en"),
            LanguageCode("en"),
            LanguageCode("fr"),
        ]

        #expect(set.count == 2)
    }

    @Test("LanguageCode code property")
    func languageCodeProperty() {
        let en = LanguageCode("en")
        let enUS = LanguageCode("en-US")
        let fr = LanguageCode("fr")

        #expect(en.code == "en")
        #expect(enUS.code == "en-US")
        #expect(fr.code == "fr")
    }

    @Test("LanguageCode static constants")
    func languageCodeConstants() {
        #expect(LanguageCode.english.code == "en")
        #expect(LanguageCode.spanish.code == "es")
        #expect(LanguageCode.french.code == "fr")
        #expect(LanguageCode.german.code == "de")
        #expect(LanguageCode.japanese.code == "ja")
        #expect(LanguageCode.chineseSimplified.code == "zh-Hans")
    }

    // MARK: - Provider Configuration

    @Test("Provider name enum values")
    func providerNames() {
        #expect(ProviderName.openai.rawValue == "openai")
        #expect(ProviderName.anthropic.rawValue == "anthropic")
        #expect(ProviderName.gemini.rawValue == "gemini")
        #expect(ProviderName.deepl.rawValue == "deepl")
        #expect(ProviderName.ollama.rawValue == "ollama")
        #expect(ProviderName.appleTranslation.rawValue == "apple-translation")
        #expect(ProviderName.foundationModels.rawValue == "foundation-models")
    }

    @Test("Formality levels")
    func formalityLevels() {
        #expect(Formality.default.rawValue == "default")
        #expect(Formality.more.rawValue == "more")
        #expect(Formality.less.rawValue == "less")
        #expect(Formality.preferMore.rawValue == "prefer_more")
        #expect(Formality.preferLess.rawValue == "prefer_less")
    }

    @Test("Provider configuration defaults")
    func providerConfigDefaults() {
        let provider = ProviderConfiguration(name: .openai, priority: 1)

        #expect(provider.name == ProviderName.openai)
        #expect(provider.enabled == true)
        #expect(provider.priority == 1)
    }

    // MARK: - Configuration Issue

    @Test("Configuration issue types")
    func configurationIssueTypes() {
        let warning = ConfigurationIssue.warning("Test warning")
        let error = ConfigurationIssue.error("Test error")

        #expect(warning.isError == false)
        #expect(error.isError == true)
        #expect(warning.message == "Test warning")
        #expect(error.message == "Test error")
    }

    // MARK: - File Patterns

    @Test("File patterns default values")
    func filePatternsDefaults() {
        let loader = ConfigurationLoader()
        let config = loader.defaultConfiguration()

        #expect(!config.files.include.isEmpty)
    }
}
