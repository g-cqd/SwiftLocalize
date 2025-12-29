//
//  CLIFeatureTests.swift
//  SwiftLocalize
//
//  Tests for CLI-related features: migrate, glossary, cache commands

import Foundation
@testable import SwiftLocalizeCore
import Testing

// MARK: - GlossaryCLITests

@Suite("Glossary CLI Feature Tests")
struct GlossaryCLITests {
    @Test("Create glossary and add terms programmatically")
    func createAndAddTerms() async throws {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("test-glossary-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let glossary = Glossary(storageURL: tempURL)

        // Add brand name (do not translate)
        await glossary.addTerm(GlossaryEntry(
            term: "SwiftLocalize",
            definition: "The app name",
            doNotTranslate: true,
        ))

        // Add translated term
        await glossary.addTerm(GlossaryEntry(
            term: "Settings",
            translations: ["fr": "Paramètres", "de": "Einstellungen"],
            caseSensitive: false,
        ))

        try await glossary.forceSave()

        // Verify persistence
        let loaded = Glossary(storageURL: tempURL)
        try await loaded.load()

        let allTerms = await loaded.allTerms
        #expect(allTerms.count == 2)

        let brandTerm = await loaded.getTerm("SwiftLocalize")
        #expect(brandTerm?.doNotTranslate == true)

        let settingsTerm = await loaded.getTerm("Settings")
        #expect(settingsTerm?.translations["fr"] == "Paramètres")
    }

    @Test("Remove term from glossary")
    func removeTerm() async throws {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("test-glossary-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let glossary = Glossary(storageURL: tempURL)

        await glossary.addTerm(GlossaryEntry(term: "Term1"))
        await glossary.addTerm(GlossaryEntry(term: "Term2"))
        await glossary.addTerm(GlossaryEntry(term: "Term3"))

        #expect(await glossary.count == 3)

        await glossary.removeTerm("Term2")

        #expect(await glossary.count == 2)
        #expect(await glossary.getTerm("Term2") == nil)
        #expect(await glossary.getTerm("Term1") != nil)
    }

    @Test("Find terms needing translation")
    func findTermsNeedingTranslation() async throws {
        let glossary = Glossary()

        await glossary.addTerm(GlossaryEntry(
            term: "Hello",
            translations: ["fr": "Bonjour"], // Has French, missing German
        ))

        await glossary.addTerm(GlossaryEntry(
            term: "Goodbye",
            translations: [:], // Missing all translations
        ))

        await glossary.addTerm(GlossaryEntry(
            term: "AppName",
            doNotTranslate: true, // Should be excluded
        ))

        let needsFrench = await glossary.termsNeedingTranslation(for: "fr")
        let needsGerman = await glossary.termsNeedingTranslation(for: "de")

        #expect(needsFrench.count == 1)
        #expect(needsFrench.first?.term == "Goodbye")

        #expect(needsGerman.count == 2)
    }

    @Test("Glossary generates prompt instructions")
    func generatePromptInstructions() async throws {
        let glossary = Glossary()

        await glossary.addTerm(GlossaryEntry(
            term: "SwiftLocalize",
            doNotTranslate: true,
        ))

        await glossary.addTerm(GlossaryEntry(
            term: "Settings",
            translations: ["fr": "Paramètres"],
        ))

        let matches = await glossary.findTerms(in: "Open SwiftLocalize Settings")
        let instructions = await glossary.toPromptInstructions(matches: matches, targetLanguage: "fr")

        #expect(instructions.contains("SwiftLocalize"))
        #expect(instructions.contains("do not translate"))
        #expect(instructions.contains("Paramètres"))
    }
}

// MARK: - CacheCLITests

@Suite("Cache CLI Feature Tests")
struct CacheCLITests {
    // MARK: Internal

    @Test("Cache statistics show correct counts")
    func cacheStatistics() async throws {
        let cacheURL = tempCacheFile()
        defer { try? FileManager.default.removeItem(at: cacheURL) }

        let detector = ChangeDetector(cacheFile: cacheURL)

        // Mark some strings as translated
        await detector.markTranslated(
            key: "Hello",
            sourceValue: "Hello",
            languages: ["fr", "de"],
            provider: "openai",
        )

        await detector.markTranslated(
            key: "Goodbye",
            sourceValue: "Goodbye",
            languages: ["fr"],
            provider: "anthropic",
        )

        try await detector.save()

        let stats = await detector.statistics
        #expect(stats.totalEntries == 2)
        #expect(stats.cacheVersion == "1.0")
        #expect(stats.lastUpdated != nil)
    }

    @Test("Cache clear removes all entries")
    func cacheClear() async throws {
        let cacheURL = tempCacheFile()
        defer { try? FileManager.default.removeItem(at: cacheURL) }

        let detector = ChangeDetector(cacheFile: cacheURL)

        await detector.markTranslated(
            key: "Test",
            sourceValue: "Test",
            languages: ["fr"],
            provider: "test",
        )

        #expect(await detector.statistics.totalEntries == 1)

        await detector.clear()

        #expect(await detector.statistics.totalEntries == 0)
    }

    @Test("Cache persists across loads")
    func cachePersistence() async throws {
        let cacheURL = tempCacheFile()
        defer { try? FileManager.default.removeItem(at: cacheURL) }

        // Create and save
        let detector1 = ChangeDetector(cacheFile: cacheURL)
        await detector1.markTranslated(
            key: "Persistent",
            sourceValue: "Persistent",
            languages: ["fr", "de", "es"],
            provider: "test",
        )
        try await detector1.save()

        // Load in new instance
        let detector2 = ChangeDetector(cacheFile: cacheURL)
        try await detector2.load()

        let stats = await detector2.statistics
        #expect(stats.totalEntries == 1)
    }

    // MARK: Private

    private func tempCacheFile() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("test-cache-\(UUID().uuidString).json")
    }
}

// MARK: - MigrationCLITests

@Suite("Migration CLI Feature Tests")
struct MigrationCLITests {
    @Test("Migrate multiple language files to xcstrings")
    func migrateMultipleLanguages() async throws {
        let enFile = StringsFile(
            language: "en",
            entries: [
                "welcome": StringsEntry(value: "Welcome", comment: "Main screen greeting"),
                "logout": StringsEntry(value: "Log Out"),
            ],
        )

        let frFile = StringsFile(
            language: "fr",
            entries: [
                "welcome": StringsEntry(value: "Bienvenue"),
                "logout": StringsEntry(value: "Déconnexion"),
            ],
        )

        let deFile = StringsFile(
            language: "de",
            entries: [
                "welcome": StringsEntry(value: "Willkommen"),
                "logout": StringsEntry(value: "Abmelden"),
            ],
        )

        let migrator = FormatMigrator()
        let xcstrings = await migrator.migrateToXCStrings(
            stringsFiles: [enFile, frFile, deFile],
            sourceLanguage: "en",
        )

        #expect(xcstrings.strings.count == 2)
        #expect(xcstrings.presentLanguages.contains("en"))
        #expect(xcstrings.presentLanguages.contains("fr"))
        #expect(xcstrings.presentLanguages.contains("de"))

        // Verify translations
        #expect(xcstrings.strings["welcome"]?.localizations?["fr"]?.stringUnit?.value == "Bienvenue")
        #expect(xcstrings.strings["welcome"]?.localizations?["de"]?.stringUnit?.value == "Willkommen")

        // Verify comment preserved from source
        #expect(xcstrings.strings["welcome"]?.comment == "Main screen greeting")
    }

    @Test("Migrate xcstrings to all languages")
    func migrateToAllLanguages() async throws {
        let xcstrings = XCStrings(
            sourceLanguage: "en",
            strings: [
                "hello": StringEntry(
                    comment: "Greeting",
                    localizations: [
                        "en": Localization(value: "Hello"),
                        "fr": Localization(value: "Bonjour"),
                        "de": Localization(value: "Hallo"),
                    ],
                ),
            ],
        )

        let migrator = FormatMigrator()

        // Migrate each language
        for lang in ["en", "fr", "de"] {
            let (stringsFile, _) = await migrator.migrateToLegacy(
                xcstrings: xcstrings,
                language: lang,
            )

            #expect(stringsFile.language == lang)
            #expect(stringsFile.entries.count == 1)
            #expect(stringsFile.entries["hello"]?.comment == "Greeting")
        }
    }

    @Test("Migration preserves format specifiers")
    func migrationPreservesFormatters() async throws {
        let enFile = StringsFile(
            language: "en",
            entries: [
                "items_count": StringsEntry(value: "You have %lld items"),
                "percentage": StringsEntry(value: "%.1f%% complete"),
                "greeting": StringsEntry(value: "Hello, %@!"),
            ],
        )

        let migrator = FormatMigrator()
        let xcstrings = await migrator.migrateToXCStrings(
            stringsFiles: [enFile],
            sourceLanguage: "en",
        )

        #expect(xcstrings.strings["items_count"]?.localizations?["en"]?.stringUnit?.value == "You have %lld items")
        #expect(xcstrings.strings["percentage"]?.localizations?["en"]?.stringUnit?.value == "%.1f%% complete")
        #expect(xcstrings.strings["greeting"]?.localizations?["en"]?.stringUnit?.value == "Hello, %@!")
    }

    @Test("Migration handles empty files gracefully")
    func migrationHandlesEmptyFiles() async throws {
        let emptyFile = StringsFile(language: "en", entries: [:])

        let migrator = FormatMigrator()
        let xcstrings = await migrator.migrateToXCStrings(
            stringsFiles: [emptyFile],
            sourceLanguage: "en",
        )

        #expect(xcstrings.strings.isEmpty)
        #expect(xcstrings.sourceLanguage == "en")
    }
}

// MARK: - TranslateFeatureTests

@Suite("Translate Command Feature Tests")
struct TranslateFeatureTests {
    @Test("XCStrings backup and restore")
    func backupAndRestore() async throws {
        let tempDir = FileManager.default.temporaryDirectory
        let originalURL = tempDir.appendingPathComponent("test-\(UUID().uuidString).xcstrings")
        let backupURL = originalURL.appendingPathExtension("bak")

        defer {
            try? FileManager.default.removeItem(at: originalURL)
            try? FileManager.default.removeItem(at: backupURL)
        }

        // Create original file
        let original = XCStrings(
            sourceLanguage: "en",
            strings: [
                "Hello": StringEntry(localizations: ["en": Localization(value: "Hello")]),
            ],
        )
        try original.write(to: originalURL)

        // Create backup
        try FileManager.default.copyItem(at: originalURL, to: backupURL)

        // Modify original
        var modified = original
        modified.strings["Goodbye"] = StringEntry(localizations: ["en": Localization(value: "Goodbye")])
        try modified.write(to: originalURL)

        // Verify backup is unchanged
        let loadedBackup = try XCStrings.parse(from: backupURL)
        #expect(loadedBackup.strings.count == 1)
        #expect(loadedBackup.strings["Hello"] != nil)
        #expect(loadedBackup.strings["Goodbye"] == nil)

        // Restore from backup
        try FileManager.default.removeItem(at: originalURL)
        try FileManager.default.copyItem(at: backupURL, to: originalURL)

        let restored = try XCStrings.parse(from: originalURL)
        #expect(restored.strings.count == 1)
    }

    @Test("Keys needing translation for preview")
    func keysNeedingTranslationForPreview() throws {
        let xcstrings = XCStrings(
            sourceLanguage: "en",
            strings: [
                "translated": StringEntry(
                    localizations: [
                        "en": Localization(value: "Translated"),
                        "fr": Localization(value: "Traduit", state: .translated),
                    ],
                ),
                "untranslated": StringEntry(
                    localizations: [
                        "en": Localization(value: "Untranslated"),
                        // No French translation
                    ],
                ),
                "partial": StringEntry(
                    localizations: [
                        "en": Localization(value: "Partial"),
                        "de": Localization(value: "Teilweise"), // Has German, but no French
                    ],
                ),
                "do_not_translate": StringEntry(
                    shouldTranslate: false,
                    localizations: [
                        "en": Localization(value: "DO NOT TRANSLATE"),
                    ],
                ),
            ],
        )

        let needsTranslationFr = xcstrings.keysNeedingTranslation(for: "fr")
        let needsTranslationDe = xcstrings.keysNeedingTranslation(for: "de")

        // French: untranslated and partial need translation
        #expect(needsTranslationFr.contains("untranslated"))
        #expect(needsTranslationFr.contains("partial"))
        #expect(!needsTranslationFr.contains("translated"))
        #expect(!needsTranslationFr.contains("do_not_translate"))

        // German: only untranslated needs translation (partial already has German)
        #expect(needsTranslationDe.contains("untranslated"))
        #expect(!needsTranslationDe.contains("partial"))
    }
}

// MARK: - ProviderRegistryCLITests

@Suite("Provider Registry CLI Tests")
struct ProviderRegistryCLITests {
    @Test("List all registered providers")
    func listAllProviders() async throws {
        let registry = ProviderRegistry()

        // Register some mock providers
        let mock1 = CLITestMockProvider(id: "mock1")
        let mock2 = CLITestMockProvider(id: "mock2")

        await registry.register(mock1)
        await registry.register(mock2)

        let all = await registry.allProviders()
        #expect(all.count == 2)

        let identifiers = all.map(\.identifier)
        #expect(identifiers.contains("mock1"))
        #expect(identifiers.contains("mock2"))
    }

    @Test("Check provider availability")
    func checkProviderAvailability() async throws {
        let registry = ProviderRegistry()

        let availableMock = CLITestMockProvider(id: "available", available: true)
        let unavailableMock = CLITestMockProvider(id: "unavailable", available: false)

        await registry.register(availableMock)
        await registry.register(unavailableMock)

        let available = await registry.availableProviders()
        #expect(available.count == 1)
        #expect(available.first?.identifier == "available")
    }
}

// MARK: - CLITestMockProvider

private final class CLITestMockProvider: TranslationProvider, @unchecked Sendable {
    // MARK: Lifecycle

    init(id: String, available: Bool = true) {
        identifier = id
        displayName = "CLI Mock \(id)"
        _isAvailable = available
    }

    // MARK: Internal

    let identifier: String
    let displayName: String

    func isAvailable() async -> Bool {
        _isAvailable
    }

    func supportedLanguages() async throws -> [LanguagePair] {
        []
    }

    func translate(
        _ strings: [String],
        from source: LanguageCode,
        to target: LanguageCode,
        context: TranslationContext?,
    ) async throws -> [TranslationResult] {
        strings.map { TranslationResult(original: $0, translated: "[\(target.code)] \($0)", provider: identifier) }
    }

    // MARK: Private

    private let _isAvailable: Bool
}
