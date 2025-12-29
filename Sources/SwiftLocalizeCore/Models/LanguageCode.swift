//
//  LanguageCode.swift
//  SwiftLocalize
//

import Foundation

// MARK: - Language Code

/// Represents a BCP 47 language code.
public struct LanguageCode: Hashable, Sendable, Codable, ExpressibleByStringLiteral {
    /// The raw language code string (e.g., "en", "zh-Hans", "pt-BR").
    public let code: String

    public init(_ code: String) {
        self.code = code
    }

    public init(stringLiteral value: String) {
        self.code = value
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.code = try container.decode(String.self)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(code)
    }
}

// MARK: - Common Languages

extension LanguageCode {
    public static let english: LanguageCode = "en"
    public static let spanish: LanguageCode = "es"
    public static let french: LanguageCode = "fr"
    public static let german: LanguageCode = "de"
    public static let italian: LanguageCode = "it"
    public static let portuguese: LanguageCode = "pt"
    public static let portugueseBrazil: LanguageCode = "pt-BR"
    public static let russian: LanguageCode = "ru"
    public static let japanese: LanguageCode = "ja"
    public static let korean: LanguageCode = "ko"
    public static let chineseSimplified: LanguageCode = "zh-Hans"
    public static let chineseTraditional: LanguageCode = "zh-Hant"
    public static let arabic: LanguageCode = "ar"
    public static let hindi: LanguageCode = "hi"
    public static let dutch: LanguageCode = "nl"
    public static let polish: LanguageCode = "pl"
    public static let turkish: LanguageCode = "tr"
    public static let ukrainian: LanguageCode = "uk"
    public static let vietnamese: LanguageCode = "vi"
    public static let thai: LanguageCode = "th"
    public static let swedish: LanguageCode = "sv"
    public static let danish: LanguageCode = "da"
    public static let finnish: LanguageCode = "fi"
    public static let norwegian: LanguageCode = "nb"
    public static let czech: LanguageCode = "cs"
    public static let greek: LanguageCode = "el"
    public static let hebrew: LanguageCode = "he"
    public static let indonesian: LanguageCode = "id"
    public static let malay: LanguageCode = "ms"
    public static let romanian: LanguageCode = "ro"
    public static let hungarian: LanguageCode = "hu"
    public static let catalan: LanguageCode = "ca"
}

// MARK: - Language Pair

/// A source-target language pair for translation.
public struct LanguagePair: Hashable, Sendable, Codable {
    public let source: LanguageCode
    public let target: LanguageCode

    public init(source: LanguageCode, target: LanguageCode) {
        self.source = source
        self.target = target
    }
}

// MARK: - Display Name

extension LanguageCode {
    /// Returns the display name for this language code in the specified locale.
    public func displayName(in locale: Locale = .current) -> String {
        locale.localizedString(forIdentifier: code) ?? code
    }

    /// Returns the native display name for this language.
    public var nativeDisplayName: String {
        let locale = Locale(identifier: code)
        return locale.localizedString(forIdentifier: code) ?? code
    }
}

// MARK: - CustomStringConvertible

extension LanguageCode: CustomStringConvertible {
    public var description: String { code }
}

extension LanguagePair: CustomStringConvertible {
    public var description: String { "\(source.code) → \(target.code)" }
}
