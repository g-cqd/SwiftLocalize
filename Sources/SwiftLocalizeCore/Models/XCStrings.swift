//
//  XCStrings.swift
//  SwiftLocalize
//

import Foundation

// MARK: - XCStrings Root

/// Root structure for xcstrings (String Catalog) files.
/// Conforms to Codable for JSON serialization and Sendable for thread safety.
public struct XCStrings: Codable, Sendable, Equatable {
    /// The source language code (e.g., "en").
    public var sourceLanguage: String

    /// Dictionary of string keys to their entries.
    public var strings: [String: StringEntry]

    /// Format version (typically "1.0").
    public var version: String

    public init(
        sourceLanguage: String,
        strings: [String: StringEntry] = [:],
        version: String = "1.0"
    ) {
        self.sourceLanguage = sourceLanguage
        self.strings = strings
        self.version = version
    }
}

// MARK: - String Entry

/// A single string entry in the catalog.
public struct StringEntry: Codable, Sendable, Equatable {
    /// Developer comment providing context for translators.
    public var comment: String?

    /// How the string was added: "manual", "extracted_with_value", "stale".
    public var extractionState: String?

    /// Whether the string should be translated.
    public var shouldTranslate: Bool?

    /// Localizations keyed by language code.
    public var localizations: [String: Localization]?

    public init(
        comment: String? = nil,
        extractionState: String? = nil,
        shouldTranslate: Bool? = nil,
        localizations: [String: Localization]? = nil
    ) {
        self.comment = comment
        self.extractionState = extractionState
        self.shouldTranslate = shouldTranslate
        self.localizations = localizations
    }
}

// MARK: - Localization

/// A localization for a specific language.
public struct Localization: Codable, Sendable, Equatable {
    /// Simple string translation.
    public var stringUnit: StringUnit?

    /// Plural/device variations.
    public var variations: Variations?

    /// Dynamic substitutions.
    public var substitutions: [String: Substitution]?

    public init(
        stringUnit: StringUnit? = nil,
        variations: Variations? = nil,
        substitutions: [String: Substitution]? = nil
    ) {
        self.stringUnit = stringUnit
        self.variations = variations
        self.substitutions = substitutions
    }

    /// Convenience initializer for simple translations.
    public init(value: String, state: TranslationState = .translated) {
        self.stringUnit = StringUnit(state: state, value: value)
        self.variations = nil
        self.substitutions = nil
    }
}

// MARK: - String Unit

/// A simple translated string with state.
public struct StringUnit: Codable, Sendable, Equatable {
    /// Translation state.
    public var state: TranslationState

    /// The translated string value.
    public var value: String

    public init(state: TranslationState, value: String) {
        self.state = state
        self.value = value
    }
}

// MARK: - Translation State

/// State of a translation.
public enum TranslationState: String, Codable, Sendable, Equatable {
    case new
    case translated
    case needsReview = "needs_review"
    case stale
}

// MARK: - Variations

/// Variations for plurals, devices, etc.
public struct Variations: Codable, Sendable, Equatable {
    /// Plural variations keyed by category (zero, one, two, few, many, other).
    public var plural: [String: Localization]?

    /// Device variations keyed by device type (iphone, ipad, mac, watch, appletv).
    public var device: [String: Localization]?

    public init(
        plural: [String: Localization]? = nil,
        device: [String: Localization]? = nil
    ) {
        self.plural = plural
        self.device = device
    }
}

// MARK: - Substitution

/// A substitution placeholder in a localized string.
public struct Substitution: Codable, Sendable, Equatable {
    /// Argument number for the substitution.
    public var argNum: Int?

    /// Format specifier (e.g., "Int", "String").
    public var formatSpecifier: String?

    /// Variations for this substitution.
    public var variations: Variations?

    public init(
        argNum: Int? = nil,
        formatSpecifier: String? = nil,
        variations: Variations? = nil
    ) {
        self.argNum = argNum
        self.formatSpecifier = formatSpecifier
        self.variations = variations
    }
}

// MARK: - Parsing

extension XCStrings {
    /// Parse an xcstrings file from a URL.
    public static func parse(from url: URL) throws -> XCStrings {
        let data = try Data(contentsOf: url)
        return try parse(from: data)
    }

    /// Parse xcstrings from JSON data.
    public static func parse(from data: Data) throws -> XCStrings {
        let decoder = JSONDecoder()
        return try decoder.decode(XCStrings.self, from: data)
    }

    /// Encode to JSON data.
    public func encode(prettyPrint: Bool = true, sortKeys: Bool = true) throws -> Data {
        let encoder = JSONEncoder()
        var formatting: JSONEncoder.OutputFormatting = []
        if prettyPrint {
            formatting.insert(.prettyPrinted)
        }
        if sortKeys {
            formatting.insert(.sortedKeys)
        }
        formatting.insert(.withoutEscapingSlashes)
        encoder.outputFormatting = formatting
        return try encoder.encode(self)
    }

    /// Write to a file URL.
    public func write(to url: URL, prettyPrint: Bool = true, sortKeys: Bool = true) throws {
        let data = try encode(prettyPrint: prettyPrint, sortKeys: sortKeys)
        try data.write(to: url)
    }
}

// MARK: - Utility Extensions

extension XCStrings {
    /// Get all string keys that need translation for a given language.
    public func keysNeedingTranslation(for language: String) -> [String] {
        strings.compactMap { key, entry in
            guard entry.shouldTranslate != false else { return nil }
            guard entry.localizations?[language]?.stringUnit == nil else { return nil }
            return key
        }.sorted()
    }

    /// Get all languages present in the catalog.
    public var presentLanguages: Set<String> {
        var languages = Set<String>()
        for entry in strings.values {
            guard let localizations = entry.localizations else { continue }
            languages.formUnion(localizations.keys)
        }
        return languages
    }

    /// Count of translated strings for a language.
    public func translatedCount(for language: String) -> Int {
        strings.values.filter { entry in
            entry.localizations?[language]?.stringUnit != nil
        }.count
    }
}
