//
//  LocalizationCatalog.swift
//  SwiftLocalize
//

import Foundation

// MARK: - Localization Catalog Protocol

/// Protocol for unified access to localization catalogs.
///
/// This protocol abstracts over different localization formats:
/// - `.xcstrings` (String Catalogs - modern format)
/// - `.strings` (legacy plain text format)
/// - `.stringsdict` (legacy plural rules format)
public protocol LocalizationCatalog: Sendable {
    /// The source language for this catalog.
    var sourceLanguage: String { get }

    /// All string keys in the catalog.
    var allKeys: [String] { get }

    /// Languages present in the catalog.
    var presentLanguages: Set<String> { get }

    /// Get the source value for a key.
    func sourceValue(for key: String) -> String?

    /// Get a translation for a key and language.
    func translation(for key: String, language: String) -> String?

    /// Check if a key has a translation for a language.
    func hasTranslation(for key: String, language: String) -> Bool

    /// Get keys needing translation for a language.
    func keysNeedingTranslation(for language: String) -> [String]
}

// MARK: - Catalog Format

/// Supported localization file formats.
public enum LocalizationFormat: String, Sendable, CaseIterable {
    /// Modern String Catalog format (.xcstrings)
    case xcstrings

    /// Legacy strings file format (.strings)
    case strings

    /// Legacy stringsdict format (.stringsdict)
    case stringsdict

    /// Detect format from file extension.
    public static func detect(from url: URL) -> LocalizationFormat? {
        switch url.pathExtension.lowercased() {
        case "xcstrings": return .xcstrings
        case "strings": return .strings
        case "stringsdict": return .stringsdict
        default: return nil
        }
    }
}

// MARK: - XCStrings Catalog Conformance

extension XCStrings: LocalizationCatalog {
    public var allKeys: [String] {
        Array(strings.keys).sorted()
    }

    public func sourceValue(for key: String) -> String? {
        guard let entry = strings[key] else { return nil }
        return entry.localizations?[sourceLanguage]?.stringUnit?.value ?? key
    }

    public func translation(for key: String, language: String) -> String? {
        strings[key]?.localizations?[language]?.stringUnit?.value
    }

    public func hasTranslation(for key: String, language: String) -> Bool {
        guard let unit = strings[key]?.localizations?[language]?.stringUnit else {
            return false
        }
        return unit.state == .translated && !unit.value.isEmpty
    }
}

// MARK: - Unified Catalog Wrapper

/// A unified wrapper for different catalog formats.
///
/// Use this to work with any localization format through a common interface.
public struct UnifiedCatalog: LocalizationCatalog, Sendable {
    public let sourceLanguage: String
    public let format: LocalizationFormat

    private let source: any LocalizationCatalog

    public init(_ xcstrings: XCStrings) {
        self.sourceLanguage = xcstrings.sourceLanguage
        self.format = .xcstrings
        self.source = xcstrings
    }

    public init(_ stringsFile: StringsFile, sourceLanguage: String) {
        self.sourceLanguage = sourceLanguage
        self.format = .strings
        self.source = StringsCatalogAdapter(stringsFile, sourceLanguage: sourceLanguage)
    }

    public init(_ stringsdictFile: StringsdictFile, sourceLanguage: String) {
        self.sourceLanguage = sourceLanguage
        self.format = .stringsdict
        self.source = StringsdictCatalogAdapter(stringsdictFile, sourceLanguage: sourceLanguage)
    }

    public var allKeys: [String] { source.allKeys }
    public var presentLanguages: Set<String> { source.presentLanguages }

    public func sourceValue(for key: String) -> String? {
        source.sourceValue(for: key)
    }

    public func translation(for key: String, language: String) -> String? {
        source.translation(for: key, language: language)
    }

    public func hasTranslation(for key: String, language: String) -> Bool {
        source.hasTranslation(for: key, language: language)
    }

    public func keysNeedingTranslation(for language: String) -> [String] {
        source.keysNeedingTranslation(for: language)
    }
}

// MARK: - Strings Catalog Adapter

/// Adapter to make StringsFile conform to LocalizationCatalog.
private struct StringsCatalogAdapter: LocalizationCatalog, Sendable {
    let file: StringsFile
    let sourceLanguage: String

    init(_ file: StringsFile, sourceLanguage: String) {
        self.file = file
        self.sourceLanguage = sourceLanguage
    }

    var allKeys: [String] { file.sortedKeys }

    var presentLanguages: Set<String> { [file.language] }

    func sourceValue(for key: String) -> String? {
        file.entries[key]?.value
    }

    func translation(for key: String, language: String) -> String? {
        guard language == file.language else { return nil }
        return file.entries[key]?.value
    }

    func hasTranslation(for key: String, language: String) -> Bool {
        guard language == file.language else { return false }
        guard let entry = file.entries[key] else { return false }
        return !entry.value.isEmpty
    }

    func keysNeedingTranslation(for language: String) -> [String] {
        guard language != file.language else { return [] }
        return allKeys
    }
}

// MARK: - Stringsdict Catalog Adapter

/// Adapter to make StringsdictFile conform to LocalizationCatalog.
private struct StringsdictCatalogAdapter: LocalizationCatalog, Sendable {
    let file: StringsdictFile
    let sourceLanguage: String

    init(_ file: StringsdictFile, sourceLanguage: String) {
        self.file = file
        self.sourceLanguage = sourceLanguage
    }

    var allKeys: [String] { file.sortedKeys }

    var presentLanguages: Set<String> { [file.language] }

    func sourceValue(for key: String) -> String? {
        file.entries[key]?.formatKey
    }

    func translation(for key: String, language: String) -> String? {
        guard language == file.language else { return nil }
        return file.entries[key]?.formatKey
    }

    func hasTranslation(for key: String, language: String) -> Bool {
        guard language == file.language else { return false }
        return file.entries[key] != nil
    }

    func keysNeedingTranslation(for language: String) -> [String] {
        guard language != file.language else { return [] }
        return allKeys
    }
}

// MARK: - Multi-File Catalog

/// A catalog composed of multiple .strings files for different languages.
///
/// Use this when working with legacy projects that have separate
/// .lproj directories with .strings files for each language.
public struct MultiLanguageStringsCatalog: LocalizationCatalog, Sendable {
    public let sourceLanguage: String

    /// Files indexed by language code.
    private let files: [String: StringsFile]

    public init(sourceLanguage: String, files: [StringsFile]) {
        self.sourceLanguage = sourceLanguage
        self.files = Dictionary(uniqueKeysWithValues: files.map { ($0.language, $0) })
    }

    public var allKeys: [String] {
        var keys: Set<String> = []
        for file in files.values {
            keys.formUnion(file.entries.keys)
        }
        return keys.sorted()
    }

    public var presentLanguages: Set<String> {
        Set(files.keys)
    }

    public func sourceValue(for key: String) -> String? {
        files[sourceLanguage]?.entries[key]?.value
    }

    public func translation(for key: String, language: String) -> String? {
        files[language]?.entries[key]?.value
    }

    public func hasTranslation(for key: String, language: String) -> Bool {
        guard let file = files[language],
              let entry = file.entries[key] else { return false }
        return !entry.value.isEmpty
    }

    public func keysNeedingTranslation(for language: String) -> [String] {
        guard language != sourceLanguage else { return [] }

        let targetFile = files[language]
        return allKeys.filter { key in
            guard let entry = targetFile?.entries[key] else { return true }
            return entry.value.isEmpty
        }
    }
}

// MARK: - Catalog Loader

/// Loads localization catalogs from files.
public actor CatalogLoader {

    private let stringsParser = StringsFileParser()
    private let stringsdictParser = StringsdictFileParser()

    public init() {}

    /// Load a catalog from a file URL.
    ///
    /// Automatically detects the format from the file extension.
    public func load(from url: URL, sourceLanguage: String? = nil) async throws -> UnifiedCatalog {
        guard let format = LocalizationFormat.detect(from: url) else {
            throw LegacyFormatError.unsupportedEncoding("Unknown file extension: \(url.pathExtension)")
        }

        switch format {
        case .xcstrings:
            let xcstrings = try XCStrings.parse(from: url)
            return UnifiedCatalog(xcstrings)

        case .strings:
            let stringsFile = try await stringsParser.parse(at: url)
            return UnifiedCatalog(stringsFile, sourceLanguage: sourceLanguage ?? "en")

        case .stringsdict:
            let stringsdictFile = try await stringsdictParser.parse(at: url)
            return UnifiedCatalog(stringsdictFile, sourceLanguage: sourceLanguage ?? "en")
        }
    }

    /// Load all .strings files from .lproj directories.
    ///
    /// - Parameters:
    ///   - directory: The directory containing .lproj folders.
    ///   - fileName: The .strings file name (e.g., "Localizable.strings").
    ///   - sourceLanguage: The source language code.
    /// - Returns: A MultiLanguageStringsCatalog with all found translations.
    public func loadStringsFromLproj(
        directory: URL,
        fileName: String = "Localizable.strings",
        sourceLanguage: String = "en"
    ) async throws -> MultiLanguageStringsCatalog {
        let fm = FileManager.default

        guard let contents = try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else {
            throw LegacyFormatError.fileNotFound(directory.path)
        }

        var files: [StringsFile] = []

        for item in contents where item.pathExtension == "lproj" {
            let stringsURL = item.appendingPathComponent(fileName)
            if fm.fileExists(atPath: stringsURL.path) {
                let file = try await stringsParser.parse(at: stringsURL)
                files.append(file)
            }
        }

        return MultiLanguageStringsCatalog(sourceLanguage: sourceLanguage, files: files)
    }
}
