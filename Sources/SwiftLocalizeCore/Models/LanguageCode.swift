//
//  LanguageCode.swift
//  SwiftLocalize
//

import Foundation

// MARK: - LanguageCode

/// Represents a BCP 47 language code.
public struct LanguageCode: Hashable, Sendable, Codable, ExpressibleByStringLiteral {
    // MARK: Lifecycle

    public init(_ code: String) {
        self.code = code
    }

    public init(stringLiteral value: String) {
        code = value
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        code = try container.decode(String.self)
    }

    // MARK: Public

    /// The raw language code string (e.g., "en", "zh-Hans", "pt-BR").
    public let code: String

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(code)
    }
}

// MARK: - Common Languages

public extension LanguageCode {
    static let english: LanguageCode = "en"
    static let spanish: LanguageCode = "es"
    static let french: LanguageCode = "fr"
    static let german: LanguageCode = "de"
    static let italian: LanguageCode = "it"
    static let portuguese: LanguageCode = "pt"
    static let portugueseBrazil: LanguageCode = "pt-BR"
    static let russian: LanguageCode = "ru"
    static let japanese: LanguageCode = "ja"
    static let korean: LanguageCode = "ko"
    static let chineseSimplified: LanguageCode = "zh-Hans"
    static let chineseTraditional: LanguageCode = "zh-Hant"
    static let arabic: LanguageCode = "ar"
    static let hindi: LanguageCode = "hi"
    static let dutch: LanguageCode = "nl"
    static let polish: LanguageCode = "pl"
    static let turkish: LanguageCode = "tr"
    static let ukrainian: LanguageCode = "uk"
    static let vietnamese: LanguageCode = "vi"
    static let thai: LanguageCode = "th"
    static let swedish: LanguageCode = "sv"
    static let danish: LanguageCode = "da"
    static let finnish: LanguageCode = "fi"
    static let norwegian: LanguageCode = "nb"
    static let czech: LanguageCode = "cs"
    static let greek: LanguageCode = "el"
    static let hebrew: LanguageCode = "he"
    static let indonesian: LanguageCode = "id"
    static let malay: LanguageCode = "ms"
    static let romanian: LanguageCode = "ro"
    static let hungarian: LanguageCode = "hu"
    static let catalan: LanguageCode = "ca"
}

// MARK: - LanguagePair

/// A source-target language pair for translation.
public struct LanguagePair: Hashable, Sendable, Codable {
    // MARK: Lifecycle

    public init(source: LanguageCode, target: LanguageCode) {
        self.source = source
        self.target = target
    }

    // MARK: Public

    public let source: LanguageCode
    public let target: LanguageCode
}

// MARK: - Display Name

public extension LanguageCode {
    /// Returns the display name for this language code in the specified locale.
    func displayName(in locale: Locale = .current) -> String {
        locale.localizedString(forIdentifier: code) ?? code
    }

    /// Returns the native display name for this language.
    var nativeDisplayName: String {
        let locale = Locale(identifier: code)
        return locale.localizedString(forIdentifier: code) ?? code
    }
}

// MARK: - LanguageCode + CustomStringConvertible

extension LanguageCode: CustomStringConvertible {
    public var description: String { code }
}

// MARK: - LanguagePair + CustomStringConvertible

extension LanguagePair: CustomStringConvertible {
    public var description: String { "\(source.code) → \(target.code)" }
}
