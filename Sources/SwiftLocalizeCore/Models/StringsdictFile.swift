//
//  StringsdictFile.swift
//  SwiftLocalize
//

import Foundation

// MARK: - Stringsdict File Model

/// Represents a legacy .stringsdict localization file.
///
/// .stringsdict files are XML property lists that define plural rules
/// using the CLDR plural categories: zero, one, two, few, many, other.
///
/// Example structure:
/// ```xml
/// <dict>
///   <key>%lld items</key>
///   <dict>
///     <key>NSStringLocalizedFormatKey</key>
///     <string>%#@items@</string>
///     <key>items</key>
///     <dict>
///       <key>NSStringFormatSpecTypeKey</key>
///       <string>NSStringPluralRuleType</string>
///       <key>NSStringFormatValueTypeKey</key>
///       <string>lld</string>
///       <key>one</key>
///       <string>%lld item</string>
///       <key>other</key>
///       <string>%lld items</string>
///     </dict>
///   </dict>
/// </dict>
/// ```
public struct StringsdictFile: Sendable, Equatable {
    /// The language code this file represents.
    public var language: String

    /// Dictionary of plural entries keyed by their identifier.
    public var entries: [String: StringsdictEntry]

    public init(language: String, entries: [String: StringsdictEntry] = [:]) {
        self.language = language
        self.entries = entries
    }

    /// Get all keys sorted alphabetically.
    public var sortedKeys: [String] {
        entries.keys.sorted()
    }
}

// MARK: - Stringsdict Entry

/// A single entry in a .stringsdict file.
public struct StringsdictEntry: Sendable, Equatable {
    /// The localized format key pattern (e.g., "%#@items@").
    public var formatKey: String

    /// Variables defined in this entry.
    public var variables: [String: PluralVariable]

    public init(formatKey: String, variables: [String: PluralVariable] = [:]) {
        self.formatKey = formatKey
        self.variables = variables
    }
}

// MARK: - Plural Variable

/// A plural variable within a stringsdict entry.
public struct PluralVariable: Sendable, Equatable {
    /// The format specifier type (e.g., "lld", "d", "@").
    public var formatSpecifier: String

    /// Plural rule type (usually "NSStringPluralRuleType").
    public var ruleType: String

    /// Plural forms keyed by CLDR category.
    public var pluralForms: [PluralCategory: String]

    public init(
        formatSpecifier: String,
        ruleType: String = "NSStringPluralRuleType",
        pluralForms: [PluralCategory: String] = [:]
    ) {
        self.formatSpecifier = formatSpecifier
        self.ruleType = ruleType
        self.pluralForms = pluralForms
    }
}

// MARK: - Plural Category

/// CLDR plural categories.
public enum PluralCategory: String, Sendable, Codable, CaseIterable, Equatable {
    case zero
    case one
    case two
    case few
    case many
    case other

    /// Categories required for a given language.
    ///
    /// Different languages use different subsets of plural categories.
    public static func required(for languageCode: String) -> Set<PluralCategory> {
        let baseCode = languageCode.components(separatedBy: "-").first ?? languageCode

        switch baseCode {
        // Languages with only "other"
        case "ja", "ko", "zh", "vi", "th", "id", "ms":
            return [.other]

        // Languages with "one" and "other"
        case "en", "de", "es", "it", "pt", "nl", "sv", "da", "no", "fi", "el", "he", "hi", "bn", "ta", "te", "ml":
            return [.one, .other]

        // Languages with "one", "few", "many", "other"
        case "ru", "uk", "pl", "cs", "sk", "hr", "sr", "bg", "sl":
            return [.one, .few, .many, .other]

        // Arabic has all categories
        case "ar":
            return [.zero, .one, .two, .few, .many, .other]

        // French uses "one" and "other" (with "many" for large numbers)
        case "fr":
            return [.one, .many, .other]

        // Welsh has several forms
        case "cy":
            return [.zero, .one, .two, .few, .many, .other]

        default:
            return [.one, .other]
        }
    }
}

// MARK: - Stringsdict Parser

/// Parses and writes legacy .stringsdict files.
public actor StringsdictFileParser {

    public init() {}

    // MARK: - Parsing

    /// Parse a .stringsdict file from a URL.
    ///
    /// - Parameters:
    ///   - url: The file URL to parse.
    ///   - language: The language code for this file.
    /// - Returns: A parsed StringsdictFile.
    /// - Throws: `LegacyFormatError` if parsing fails.
    public func parse(at url: URL, language: String? = nil) throws -> StringsdictFile {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw LegacyFormatError.fileNotFound(url.path)
        }

        let data = try Data(contentsOf: url)
        let lang = language ?? extractLanguage(from: url)

        return try parse(data: data, language: lang)
    }

    /// Parse .stringsdict from data.
    public func parse(data: Data, language: String) throws -> StringsdictFile {
        let plist: [String: Any]
        do {
            guard let dict = try PropertyListSerialization.propertyList(
                from: data,
                format: nil
            ) as? [String: Any] else {
                throw LegacyFormatError.stringsdictParseError("Root must be a dictionary")
            }
            plist = dict
        } catch let error as LegacyFormatError {
            throw error
        } catch {
            throw LegacyFormatError.stringsdictParseError("Invalid plist: \(error.localizedDescription)")
        }

        var entries: [String: StringsdictEntry] = [:]

        for (key, value) in plist {
            guard let entryDict = value as? [String: Any] else {
                throw LegacyFormatError.stringsdictParseError("Entry '\(key)' must be a dictionary")
            }

            entries[key] = try parseEntry(key: key, dict: entryDict)
        }

        return StringsdictFile(language: language, entries: entries)
    }

    // MARK: - Entry Parsing

    private func parseEntry(key: String, dict: [String: Any]) throws -> StringsdictEntry {
        guard let formatKey = dict["NSStringLocalizedFormatKey"] as? String else {
            throw LegacyFormatError.missingRequiredKey(key: key, field: "NSStringLocalizedFormatKey")
        }

        var variables: [String: PluralVariable] = [:]

        for (varName, varValue) in dict {
            // Skip the format key itself
            if varName == "NSStringLocalizedFormatKey" { continue }

            guard let varDict = varValue as? [String: Any] else { continue }

            // Check if this is a plural variable
            guard let specTypeKey = varDict["NSStringFormatSpecTypeKey"] as? String else { continue }

            if specTypeKey == "NSStringPluralRuleType" {
                variables[varName] = try parsePluralVariable(name: varName, dict: varDict, parentKey: key)
            }
        }

        return StringsdictEntry(formatKey: formatKey, variables: variables)
    }

    private func parsePluralVariable(
        name: String,
        dict: [String: Any],
        parentKey: String
    ) throws -> PluralVariable {
        guard let formatValueType = dict["NSStringFormatValueTypeKey"] as? String else {
            throw LegacyFormatError.missingRequiredKey(key: parentKey, field: "NSStringFormatValueTypeKey")
        }

        let ruleType = dict["NSStringFormatSpecTypeKey"] as? String ?? "NSStringPluralRuleType"

        var pluralForms: [PluralCategory: String] = [:]

        for category in PluralCategory.allCases {
            if let form = dict[category.rawValue] as? String {
                pluralForms[category] = form
            }
        }

        // Must have at least "other"
        if pluralForms[.other] == nil {
            throw LegacyFormatError.invalidPluralRule(
                key: parentKey,
                message: "Variable '\(name)' missing required 'other' plural form"
            )
        }

        return PluralVariable(
            formatSpecifier: formatValueType,
            ruleType: ruleType,
            pluralForms: pluralForms
        )
    }

    // MARK: - Writing

    /// Write a StringsdictFile to a URL.
    public func write(_ file: StringsdictFile, to url: URL, sortKeys: Bool = true) throws {
        let plist = serialize(file, sortKeys: sortKeys)

        let data: Data
        do {
            data = try PropertyListSerialization.data(
                fromPropertyList: plist,
                format: .xml,
                options: 0
            )
        } catch {
            throw LegacyFormatError.writeFailed("Failed to serialize plist: \(error.localizedDescription)")
        }

        try data.write(to: url, options: .atomic)
    }

    /// Serialize a StringsdictFile to a property list dictionary.
    public func serialize(_ file: StringsdictFile, sortKeys: Bool = true) -> [String: Any] {
        var plist: [String: Any] = [:]

        let keys = sortKeys ? file.sortedKeys : Array(file.entries.keys)

        for key in keys {
            guard let entry = file.entries[key] else { continue }
            plist[key] = serializeEntry(entry)
        }

        return plist
    }

    private func serializeEntry(_ entry: StringsdictEntry) -> [String: Any] {
        var dict: [String: Any] = [
            "NSStringLocalizedFormatKey": entry.formatKey
        ]

        for (varName, variable) in entry.variables {
            dict[varName] = serializeVariable(variable)
        }

        return dict
    }

    private func serializeVariable(_ variable: PluralVariable) -> [String: Any] {
        var dict: [String: Any] = [
            "NSStringFormatSpecTypeKey": variable.ruleType,
            "NSStringFormatValueTypeKey": variable.formatSpecifier
        ]

        for (category, form) in variable.pluralForms {
            dict[category.rawValue] = form
        }

        return dict
    }

    // MARK: - Language Extraction

    private func extractLanguage(from url: URL) -> String {
        let pathComponents = url.pathComponents
        for component in pathComponents.reversed() {
            if component.hasSuffix(".lproj") {
                return String(component.dropLast(6))
            }
        }
        return "en"
    }
}
