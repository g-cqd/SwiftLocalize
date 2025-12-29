//
//  LegacyFormatTests.swift
//  SwiftLocalize
//

import Foundation
import Testing
@testable import SwiftLocalizeCore

// MARK: - StringsFile Tests

@Suite("StringsFile Parsing Tests")
struct StringsFileTests {

    // MARK: - Parsing

    @Test("Parse simple .strings content")
    func parseSimpleStrings() async throws {
        let content = """
        /* Greeting */
        "Hello" = "Hello";

        /* Farewell */
        "Goodbye" = "Goodbye";
        """

        let parser = StringsFileParser()
        let file = try await parser.parse(content: content, language: "en")

        #expect(file.language == "en")
        #expect(file.entries.count == 2)
        #expect(file.entries["Hello"]?.value == "Hello")
        #expect(file.entries["Hello"]?.comment == "Greeting")
        #expect(file.entries["Goodbye"]?.value == "Goodbye")
        #expect(file.entries["Goodbye"]?.comment == "Farewell")
    }

    @Test("Parse .strings with escaped characters")
    func parseEscapedCharacters() async throws {
        let content = """
        "newline" = "Line1\\nLine2";
        "tab" = "Col1\\tCol2";
        "quote" = "He said \\"Hello\\"";
        "backslash" = "path\\\\to\\\\file";
        """

        let parser = StringsFileParser()
        let file = try await parser.parse(content: content, language: "en")

        #expect(file.entries["newline"]?.value == "Line1\nLine2")
        #expect(file.entries["tab"]?.value == "Col1\tCol2")
        #expect(file.entries["quote"]?.value == "He said \"Hello\"")
        #expect(file.entries["backslash"]?.value == "path\\to\\file")
    }

    @Test("Parse .strings with Unicode escapes")
    func parseUnicodeEscapes() async throws {
        let content = """
        "heart" = "I \\U2764 Swift";
        "smile" = "\\u263A";
        """

        let parser = StringsFileParser()
        let file = try await parser.parse(content: content, language: "en")

        #expect(file.entries["heart"]?.value == "I \u{2764} Swift")
        #expect(file.entries["smile"]?.value == "\u{263A}")
    }

    @Test("Parse .strings with multi-line comments")
    func parseMultiLineComments() async throws {
        let content = """
        /*
         This is a multi-line comment
         that spans multiple lines
         */
        "key" = "value";
        """

        let parser = StringsFileParser()
        let file = try await parser.parse(content: content, language: "en")

        #expect(file.entries["key"]?.value == "value")
        #expect(file.entries["key"]?.comment?.contains("multi-line") == true)
    }

    @Test("Parse .strings with C++ style comments")
    func parseCppStyleComments() async throws {
        let content = """
        // This is a C++ style comment
        "key" = "value";
        """

        let parser = StringsFileParser()
        let file = try await parser.parse(content: content, language: "en")

        #expect(file.entries["key"]?.value == "value")
        #expect(file.entries["key"]?.comment == "This is a C++ style comment")
    }

    @Test("Parse .strings without comments")
    func parseWithoutComments() async throws {
        let content = """
        "key1" = "value1";
        "key2" = "value2";
        """

        let parser = StringsFileParser()
        let file = try await parser.parse(content: content, language: "en")

        #expect(file.entries.count == 2)
        #expect(file.entries["key1"]?.comment == nil)
        #expect(file.entries["key2"]?.comment == nil)
    }

    @Test("Parse .strings with format specifiers")
    func parseFormatSpecifiers() async throws {
        let content = """
        "greeting" = "Hello, %@!";
        "count" = "%lld items remaining";
        "percent" = "%.1f%% complete";
        """

        let parser = StringsFileParser()
        let file = try await parser.parse(content: content, language: "en")

        #expect(file.entries["greeting"]?.value == "Hello, %@!")
        #expect(file.entries["count"]?.value == "%lld items remaining")
        #expect(file.entries["percent"]?.value == "%.1f%% complete")
    }

    // MARK: - Serialization

    @Test("Serialize and round-trip .strings")
    func serializeRoundTrip() async throws {
        let original = StringsFile(
            language: "en",
            entries: [
                "Hello": StringsEntry(value: "Hello", comment: "Greeting"),
                "Goodbye": StringsEntry(value: "Goodbye"),
            ]
        )

        let parser = StringsFileParser()
        let serialized = await parser.serialize(original, sortKeys: true)

        #expect(serialized.contains("/* Greeting */"))
        #expect(serialized.contains("\"Hello\" = \"Hello\";"))
        #expect(serialized.contains("\"Goodbye\" = \"Goodbye\";"))

        // Round-trip
        let parsed = try await parser.parse(content: serialized, language: "en")
        #expect(parsed.entries["Hello"]?.value == "Hello")
        #expect(parsed.entries["Hello"]?.comment == "Greeting")
        #expect(parsed.entries["Goodbye"]?.value == "Goodbye")
    }

    @Test("Serialize escapes special characters")
    func serializeEscapesSpecialChars() async throws {
        let file = StringsFile(
            language: "en",
            entries: [
                "special": StringsEntry(value: "Line1\nLine2\t\"quoted\""),
            ]
        )

        let parser = StringsFileParser()
        let serialized = await parser.serialize(file)

        #expect(serialized.contains("\\n"))
        #expect(serialized.contains("\\t"))
        #expect(serialized.contains("\\\""))
    }

    // MARK: - Sorted Keys

    @Test("Sorted keys returns alphabetical order")
    func sortedKeys() {
        let file = StringsFile(
            language: "en",
            entries: [
                "Zebra": StringsEntry(value: "Zebra"),
                "Apple": StringsEntry(value: "Apple"),
                "Mango": StringsEntry(value: "Mango"),
            ]
        )

        #expect(file.sortedKeys == ["Apple", "Mango", "Zebra"])
    }

    // MARK: - Error Cases

    @Test("Parse error on unterminated string")
    func parseUnterminatedString() async throws {
        let content = """
        "key" = "value without closing quote;
        """

        let parser = StringsFileParser()
        await #expect(throws: LegacyFormatError.self) {
            try await parser.parse(content: content, language: "en")
        }
    }

    @Test("Parse error on missing equals")
    func parseMissingEquals() async throws {
        let content = """
        "key" "value";
        """

        let parser = StringsFileParser()
        await #expect(throws: LegacyFormatError.self) {
            try await parser.parse(content: content, language: "en")
        }
    }
}

// MARK: - StringsdictFile Tests

@Suite("StringsdictFile Parsing Tests")
struct StringsdictFileTests {

    // MARK: - Parsing

    @Test("Parse simple plural stringsdict")
    func parseSimplePlural() async throws {
        let plist: [String: Any] = [
            "%lld items": [
                "NSStringLocalizedFormatKey": "%#@count@",
                "count": [
                    "NSStringFormatSpecTypeKey": "NSStringPluralRuleType",
                    "NSStringFormatValueTypeKey": "lld",
                    "one": "%lld item",
                    "other": "%lld items",
                ],
            ],
        ]

        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        let parser = StringsdictFileParser()
        let file = try await parser.parse(data: data, language: "en")

        #expect(file.language == "en")
        #expect(file.entries.count == 1)

        let entry = try #require(file.entries["%lld items"])
        #expect(entry.formatKey == "%#@count@")

        let variable = try #require(entry.variables["count"])
        #expect(variable.formatSpecifier == "lld")
        #expect(variable.pluralForms[.one] == "%lld item")
        #expect(variable.pluralForms[.other] == "%lld items")
    }

    @Test("Parse stringsdict with multiple plural categories")
    func parseMultiplePluralCategories() async throws {
        let plist: [String: Any] = [
            "messages": [
                "NSStringLocalizedFormatKey": "%#@count@",
                "count": [
                    "NSStringFormatSpecTypeKey": "NSStringPluralRuleType",
                    "NSStringFormatValueTypeKey": "d",
                    "zero": "No messages",
                    "one": "One message",
                    "two": "Two messages",
                    "few": "Few messages",
                    "many": "Many messages",
                    "other": "%d messages",
                ],
            ],
        ]

        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        let parser = StringsdictFileParser()
        let file = try await parser.parse(data: data, language: "ar")

        let entry = try #require(file.entries["messages"])
        let variable = try #require(entry.variables["count"])

        #expect(variable.pluralForms[.zero] == "No messages")
        #expect(variable.pluralForms[.one] == "One message")
        #expect(variable.pluralForms[.two] == "Two messages")
        #expect(variable.pluralForms[.few] == "Few messages")
        #expect(variable.pluralForms[.many] == "Many messages")
        #expect(variable.pluralForms[.other] == "%d messages")
    }

    // MARK: - Serialization

    @Test("Serialize and round-trip stringsdict")
    func serializeRoundTrip() async throws {
        let original = StringsdictFile(
            language: "en",
            entries: [
                "%lld items": StringsdictEntry(
                    formatKey: "%#@count@",
                    variables: [
                        "count": PluralVariable(
                            formatSpecifier: "lld",
                            pluralForms: [
                                .one: "%lld item",
                                .other: "%lld items",
                            ]
                        ),
                    ]
                ),
            ]
        )

        // Round-trip by writing to temp file
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("stringsdict")

        let parser = StringsdictFileParser()
        try await parser.write(original, to: tempURL)

        // Parse back
        let parsed = try await parser.parse(at: tempURL, language: "en")

        // Cleanup
        try? FileManager.default.removeItem(at: tempURL)

        #expect(parsed.entries.count == 1)
        let entry = try #require(parsed.entries["%lld items"])
        #expect(entry.formatKey == "%#@count@")
        #expect(entry.variables["count"]?.pluralForms[.one] == "%lld item")
    }

    // MARK: - Plural Categories

    @Test("Plural categories for different languages")
    func pluralCategoriesForLanguages() {
        // Japanese uses only "other"
        let japanese = PluralCategory.required(for: "ja")
        #expect(japanese == [.other])

        // English uses "one" and "other"
        let english = PluralCategory.required(for: "en")
        #expect(english == [.one, .other])

        // Russian uses multiple forms
        let russian = PluralCategory.required(for: "ru")
        #expect(russian.contains(.one))
        #expect(russian.contains(.few))
        #expect(russian.contains(.many))
        #expect(russian.contains(.other))

        // Arabic uses all forms
        let arabic = PluralCategory.required(for: "ar")
        #expect(arabic.count == 6)
    }

    // MARK: - Error Cases

    @Test("Parse error on missing other form")
    func parseMissingOtherForm() async throws {
        let plist: [String: Any] = [
            "items": [
                "NSStringLocalizedFormatKey": "%#@count@",
                "count": [
                    "NSStringFormatSpecTypeKey": "NSStringPluralRuleType",
                    "NSStringFormatValueTypeKey": "d",
                    "one": "One item",
                    // Missing "other"
                ],
            ],
        ]

        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        let parser = StringsdictFileParser()

        await #expect(throws: LegacyFormatError.self) {
            try await parser.parse(data: data, language: "en")
        }
    }

    @Test("Parse error on missing format key")
    func parseMissingFormatKey() async throws {
        let plist: [String: Any] = [
            "items": [
                // Missing NSStringLocalizedFormatKey
                "count": [
                    "NSStringFormatSpecTypeKey": "NSStringPluralRuleType",
                    "NSStringFormatValueTypeKey": "d",
                    "other": "%d items",
                ],
            ],
        ]

        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        let parser = StringsdictFileParser()

        await #expect(throws: LegacyFormatError.self) {
            try await parser.parse(data: data, language: "en")
        }
    }
}

// MARK: - LocalizationCatalog Tests

@Suite("LocalizationCatalog Tests")
struct LocalizationCatalogTests {

    @Test("XCStrings conforms to LocalizationCatalog")
    func xcstringsConformsToProtocol() {
        let xcstrings = XCStrings(
            sourceLanguage: "en",
            strings: [
                "Hello": StringEntry(
                    localizations: [
                        "en": Localization(value: "Hello"),
                        "fr": Localization(value: "Bonjour"),
                    ]
                ),
            ]
        )

        let catalog: any LocalizationCatalog = xcstrings

        #expect(catalog.sourceLanguage == "en")
        #expect(catalog.allKeys == ["Hello"])
        #expect(catalog.sourceValue(for: "Hello") == "Hello")
        #expect(catalog.translation(for: "Hello", language: "fr") == "Bonjour")
        #expect(catalog.hasTranslation(for: "Hello", language: "fr"))
        #expect(!catalog.hasTranslation(for: "Hello", language: "de"))
    }

    @Test("UnifiedCatalog wraps XCStrings")
    func unifiedCatalogWrapsXCStrings() {
        let xcstrings = XCStrings(
            sourceLanguage: "en",
            strings: [
                "Test": StringEntry(
                    localizations: [
                        "en": Localization(value: "Test"),
                    ]
                ),
            ]
        )

        let unified = UnifiedCatalog(xcstrings)

        #expect(unified.format == .xcstrings)
        #expect(unified.sourceLanguage == "en")
        #expect(unified.allKeys == ["Test"])
    }

    @Test("UnifiedCatalog wraps StringsFile")
    func unifiedCatalogWrapsStringsFile() {
        let stringsFile = StringsFile(
            language: "fr",
            entries: [
                "Hello": StringsEntry(value: "Bonjour"),
            ]
        )

        let unified = UnifiedCatalog(stringsFile, sourceLanguage: "en")

        #expect(unified.format == .strings)
        #expect(unified.sourceLanguage == "en")
        #expect(unified.translation(for: "Hello", language: "fr") == "Bonjour")
    }

    @Test("MultiLanguageStringsCatalog combines files")
    func multiLanguageStringsCatalogCombinesFiles() {
        let enFile = StringsFile(
            language: "en",
            entries: [
                "Hello": StringsEntry(value: "Hello"),
                "Goodbye": StringsEntry(value: "Goodbye"),
            ]
        )

        let frFile = StringsFile(
            language: "fr",
            entries: [
                "Hello": StringsEntry(value: "Bonjour"),
            ]
        )

        let catalog = MultiLanguageStringsCatalog(
            sourceLanguage: "en",
            files: [enFile, frFile]
        )

        #expect(catalog.allKeys.count == 2)
        #expect(catalog.presentLanguages == ["en", "fr"])
        #expect(catalog.sourceValue(for: "Hello") == "Hello")
        #expect(catalog.translation(for: "Hello", language: "fr") == "Bonjour")
        #expect(catalog.keysNeedingTranslation(for: "fr") == ["Goodbye"])
    }

    @Test("Format detection from URL")
    func formatDetectionFromURL() {
        let xcstringsURL = URL(fileURLWithPath: "/path/to/Localizable.xcstrings")
        let stringsURL = URL(fileURLWithPath: "/path/to/Localizable.strings")
        let stringsdictURL = URL(fileURLWithPath: "/path/to/Localizable.stringsdict")
        let unknownURL = URL(fileURLWithPath: "/path/to/file.txt")

        #expect(LocalizationFormat.detect(from: xcstringsURL) == .xcstrings)
        #expect(LocalizationFormat.detect(from: stringsURL) == .strings)
        #expect(LocalizationFormat.detect(from: stringsdictURL) == .stringsdict)
        #expect(LocalizationFormat.detect(from: unknownURL) == nil)
    }
}

// MARK: - FormatMigrator Tests

@Suite("FormatMigrator Tests")
struct FormatMigratorTests {

    @Test("Migrate strings to xcstrings")
    func migrateStringsToXCStrings() async throws {
        let enFile = StringsFile(
            language: "en",
            entries: [
                "Hello": StringsEntry(value: "Hello", comment: "Greeting"),
                "Goodbye": StringsEntry(value: "Goodbye"),
            ]
        )

        let frFile = StringsFile(
            language: "fr",
            entries: [
                "Hello": StringsEntry(value: "Bonjour"),
                "Goodbye": StringsEntry(value: "Au revoir"),
            ]
        )

        let migrator = FormatMigrator()
        let xcstrings = await migrator.migrateToXCStrings(
            stringsFiles: [enFile, frFile],
            sourceLanguage: "en"
        )

        #expect(xcstrings.sourceLanguage == "en")
        #expect(xcstrings.strings.count == 2)
        #expect(xcstrings.strings["Hello"]?.comment == "Greeting")
        #expect(xcstrings.strings["Hello"]?.localizations?["en"]?.stringUnit?.value == "Hello")
        #expect(xcstrings.strings["Hello"]?.localizations?["fr"]?.stringUnit?.value == "Bonjour")
    }

    @Test("Migrate xcstrings to legacy")
    func migrateXCStringsToLegacy() async throws {
        let xcstrings = XCStrings(
            sourceLanguage: "en",
            strings: [
                "Hello": StringEntry(
                    comment: "Greeting",
                    localizations: [
                        "en": Localization(value: "Hello"),
                        "fr": Localization(value: "Bonjour"),
                    ]
                ),
            ]
        )

        let migrator = FormatMigrator()
        let (stringsFile, stringsdictFile) = await migrator.migrateToLegacy(
            xcstrings: xcstrings,
            language: "fr"
        )

        #expect(stringsFile.language == "fr")
        #expect(stringsFile.entries["Hello"]?.value == "Bonjour")
        #expect(stringsFile.entries["Hello"]?.comment == "Greeting")
        #expect(stringsdictFile == nil)
    }

    @Test("Migrate stringsdict to xcstrings plurals")
    func migrateStringsdictToXCStrings() async throws {
        let stringsdictFile = StringsdictFile(
            language: "en",
            entries: [
                "%lld items": StringsdictEntry(
                    formatKey: "%#@count@",
                    variables: [
                        "count": PluralVariable(
                            formatSpecifier: "lld",
                            pluralForms: [
                                .one: "%lld item",
                                .other: "%lld items",
                            ]
                        ),
                    ]
                ),
            ]
        )

        let migrator = FormatMigrator()
        let xcstrings = await migrator.migrateToXCStrings(
            stringsFiles: [],
            stringsdictFiles: [stringsdictFile],
            sourceLanguage: "en"
        )

        #expect(xcstrings.strings.count == 1)
        let entry = try #require(xcstrings.strings["%lld items"])
        let localization = try #require(entry.localizations?["en"])
        #expect(localization.variations?.plural != nil)
    }
}
