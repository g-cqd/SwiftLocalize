//
//  FormatMigrator.swift
//  SwiftLocalize
//

import Foundation

// MARK: - FormatMigrator

/// Migrates localization files between formats.
///
/// Supports conversions:
/// - `.strings` + `.stringsdict` → `.xcstrings`
/// - `.xcstrings` → `.strings` + `.stringsdict`
///
/// ## Usage
/// ```swift
/// let migrator = FormatMigrator()
///
/// // Migrate legacy to xcstrings
/// let xcstrings = try await migrator.migrateToXCStrings(
///     stringsFiles: [enStrings, frStrings],
///     stringsdictFiles: [enStringsdict, frStringsdict],
///     sourceLanguage: "en"
/// )
///
/// // Migrate xcstrings to legacy
/// let (strings, stringsdict) = try await migrator.migrateToLegacy(
///     xcstrings: catalog,
///     language: "fr"
/// )
/// ```
public actor FormatMigrator {
    // MARK: Lifecycle

    public init() {}

    // MARK: Public

    // MARK: - Legacy to XCStrings

    /// Migrate .strings and .stringsdict files to a single .xcstrings file.
    ///
    /// - Parameters:
    ///   - stringsFiles: Array of .strings files for different languages.
    ///   - stringsdictFiles: Array of .stringsdict files for different languages.
    ///   - sourceLanguage: The source language code.
    /// - Returns: A complete XCStrings catalog.
    public func migrateToXCStrings(
        stringsFiles: [StringsFile],
        stringsdictFiles: [StringsdictFile] = [],
        sourceLanguage: String,
    ) -> XCStrings {
        var xcstrings = XCStrings(sourceLanguage: sourceLanguage)

        // Index files by language
        let stringsByLang = Dictionary(
            uniqueKeysWithValues: stringsFiles.map { ($0.language, $0) },
        )
        let stringsdictByLang = Dictionary(
            uniqueKeysWithValues: stringsdictFiles.map { ($0.language, $0) },
        )

        // Collect all unique keys
        var allKeys: Set<String> = []
        for file in stringsFiles {
            allKeys.formUnion(file.entries.keys)
        }
        for file in stringsdictFiles {
            allKeys.formUnion(file.entries.keys)
        }

        // Build entries for each key
        for key in allKeys.sorted() {
            var localizations: [String: Localization] = [:]
            var comment: String?

            // Check if this is a plural key (exists in stringsdict)
            let isPluralKey = stringsdictFiles.contains { $0.entries[key] != nil }

            if isPluralKey {
                // Handle plural entries
                for (language, file) in stringsdictByLang {
                    if let entry = file.entries[key] {
                        localizations[language] = convertStringsdictEntry(entry)
                    }
                }
            } else {
                // Handle simple string entries
                for (language, file) in stringsByLang {
                    if let entry = file.entries[key] {
                        localizations[language] = Localization(
                            value: entry.value,
                            state: .translated,
                        )
                        // Capture comment from source language
                        if language == sourceLanguage, comment == nil {
                            comment = entry.comment
                        }
                    }
                }
            }

            xcstrings.strings[key] = StringEntry(
                comment: comment,
                extractionState: "manual",
                shouldTranslate: true,
                localizations: localizations.isEmpty ? nil : localizations,
            )
        }

        return xcstrings
    }

    // MARK: - XCStrings to Legacy

    /// Migrate an XCStrings catalog to legacy .strings and .stringsdict files.
    ///
    /// - Parameters:
    ///   - xcstrings: The source XCStrings catalog.
    ///   - language: The target language to extract.
    /// - Returns: Tuple of (StringsFile, StringsdictFile?) for the language.
    public func migrateToLegacy(
        xcstrings: XCStrings,
        language: String,
    ) -> (strings: StringsFile, stringsdict: StringsdictFile?) {
        var stringsEntries: [String: StringsEntry] = [:]
        var stringsdictEntries: [String: StringsdictEntry] = [:]

        for (key, entry) in xcstrings.strings {
            guard let localization = entry.localizations?[language] else { continue }

            if let variations = localization.variations?.plural, !variations.isEmpty {
                // This is a plural entry → goes to stringsdict
                stringsdictEntries[key] = convertToStringsdictEntry(
                    key: key,
                    pluralVariations: variations,
                )
            } else if let stringUnit = localization.stringUnit {
                // Simple string → goes to .strings
                stringsEntries[key] = StringsEntry(
                    value: stringUnit.value,
                    comment: entry.comment,
                )
            }
        }

        let stringsFile = StringsFile(
            language: language,
            entries: stringsEntries,
        )

        let stringsdictFile: StringsdictFile? = if stringsdictEntries.isEmpty {
            nil
        } else {
            StringsdictFile(
                language: language,
                entries: stringsdictEntries,
            )
        }

        return (stringsFile, stringsdictFile)
    }

    // MARK: - Batch Migration

    /// Migrate all legacy files in a directory to xcstrings.
    ///
    /// Scans for .lproj directories and their .strings/.stringsdict files.
    ///
    /// - Parameters:
    ///   - directory: The directory containing .lproj folders.
    ///   - stringsFileName: The .strings file name (default: "Localizable.strings").
    ///   - stringsdictFileName: The .stringsdict file name (default: "Localizable.stringsdict").
    ///   - sourceLanguage: The source language code.
    /// - Returns: A complete XCStrings catalog.
    public func migrateDirectoryToXCStrings(
        directory: URL,
        stringsFileName: String = "Localizable.strings",
        stringsdictFileName: String = "Localizable.stringsdict",
        sourceLanguage: String = "en",
    ) async throws -> XCStrings {
        let fm = FileManager.default
        let stringsParser = StringsFileParser()
        let stringsdictParser = StringsdictFileParser()

        guard let contents = try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else {
            throw LegacyFormatError.fileNotFound(directory.path)
        }

        var stringsFiles: [StringsFile] = []
        var stringsdictFiles: [StringsdictFile] = []

        for item in contents where item.pathExtension == "lproj" {
            // Parse .strings file
            let stringsURL = item.appendingPathComponent(stringsFileName)
            if fm.fileExists(atPath: stringsURL.path) {
                let file = try await stringsParser.parse(at: stringsURL)
                stringsFiles.append(file)
            }

            // Parse .stringsdict file
            let stringsdictURL = item.appendingPathComponent(stringsdictFileName)
            if fm.fileExists(atPath: stringsdictURL.path) {
                let file = try await stringsdictParser.parse(at: stringsdictURL)
                stringsdictFiles.append(file)
            }
        }

        return migrateToXCStrings(
            stringsFiles: stringsFiles,
            stringsdictFiles: stringsdictFiles,
            sourceLanguage: sourceLanguage,
        )
    }

    /// Migrate an xcstrings file to legacy .strings/.stringsdict files.
    ///
    /// Creates .lproj directories with appropriate files for each language.
    ///
    /// - Parameters:
    ///   - xcstrings: The source XCStrings catalog.
    ///   - directory: The output directory.
    ///   - stringsFileName: The .strings file name (default: "Localizable.strings").
    ///   - stringsdictFileName: The .stringsdict file name (default: "Localizable.stringsdict").
    public func migrateXCStringsToDirectory(
        xcstrings: XCStrings,
        directory: URL,
        stringsFileName: String = "Localizable.strings",
        stringsdictFileName: String = "Localizable.stringsdict",
    ) async throws {
        let fm = FileManager.default
        let stringsParser = StringsFileParser()
        let stringsdictParser = StringsdictFileParser()

        // Get all languages in the catalog
        let languages = xcstrings.presentLanguages

        for language in languages {
            let lprojDir = directory.appendingPathComponent("\(language).lproj")

            // Create .lproj directory if needed
            if !fm.fileExists(atPath: lprojDir.path) {
                try fm.createDirectory(at: lprojDir, withIntermediateDirectories: true)
            }

            let (stringsFile, stringsdictFile) = migrateToLegacy(
                xcstrings: xcstrings,
                language: language,
            )

            // Write .strings file
            if !stringsFile.entries.isEmpty {
                let stringsURL = lprojDir.appendingPathComponent(stringsFileName)
                try await stringsParser.write(stringsFile, to: stringsURL)
            }

            // Write .stringsdict file if there are plural entries
            if let stringsdictFile, !stringsdictFile.entries.isEmpty {
                let stringsdictURL = lprojDir.appendingPathComponent(stringsdictFileName)
                try await stringsdictParser.write(stringsdictFile, to: stringsdictURL)
            }
        }
    }

    // MARK: Private

    /// Convert a stringsdict entry to an XCStrings localization.
    private func convertStringsdictEntry(_ entry: StringsdictEntry) -> Localization {
        // For single-variable plurals, convert to variations
        if entry.variables.count == 1,
           let (_, variable) = entry.variables.first {
            var pluralVariations: [String: Localization] = [:]

            for (category, form) in variable.pluralForms {
                pluralVariations[category.rawValue] = Localization(
                    value: form,
                    state: .translated,
                )
            }

            return Localization(
                stringUnit: nil,
                variations: Variations(plural: pluralVariations),
                substitutions: nil,
            )
        }

        // For complex entries with multiple variables, store the format key
        // The full stringsdict structure would need substitutions
        return Localization(
            stringUnit: StringUnit(state: .translated, value: entry.formatKey),
            variations: nil,
            substitutions: nil,
        )
    }

    /// Convert plural variations back to a stringsdict entry.
    private func convertToStringsdictEntry(
        key: String,
        pluralVariations: [String: Localization],
    ) -> StringsdictEntry {
        var pluralForms: [PluralCategory: String] = [:]

        for (categoryString, localization) in pluralVariations {
            guard let category = PluralCategory(rawValue: categoryString),
                  let value = localization.stringUnit?.value else { continue }
            pluralForms[category] = value
        }

        // Detect format specifier from the value
        let formatSpecifier = detectFormatSpecifier(in: pluralForms.values.first ?? "")

        let variable = PluralVariable(
            formatSpecifier: formatSpecifier,
            ruleType: "NSStringPluralRuleType",
            pluralForms: pluralForms,
        )

        return StringsdictEntry(
            formatKey: "%#@count@",
            variables: ["count": variable],
        )
    }

    /// Detect the format specifier from a string.
    private func detectFormatSpecifier(in string: String) -> String {
        // Look for common format specifiers
        if string.contains("%lld") { return "lld" }
        if string.contains("%ld") { return "ld" }
        if string.contains("%d") { return "d" }
        if string.contains("%lu") { return "lu" }
        if string.contains("%u") { return "u" }
        if string.contains("%@") { return "@" }
        if string.contains("%.") { return "f" }
        return "d"
    }
}

// MARK: - MigrationReport

/// Report from a migration operation.
public struct MigrationReport: Sendable {
    // MARK: Lifecycle

    public init(
        simpleStrings: Int,
        pluralEntries: Int,
        languages: [String],
        warnings: [String] = [],
    ) {
        self.simpleStrings = simpleStrings
        self.pluralEntries = pluralEntries
        self.languages = languages
        self.warnings = warnings
    }

    // MARK: Public

    /// Number of simple string entries migrated.
    public let simpleStrings: Int

    /// Number of plural entries migrated.
    public let pluralEntries: Int

    /// Languages processed.
    public let languages: [String]

    /// Warnings encountered during migration.
    public let warnings: [String]

    /// Whether the migration was successful.
    public var isSuccessful: Bool { warnings.isEmpty }
}
