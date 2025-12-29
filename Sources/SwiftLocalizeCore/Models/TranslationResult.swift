//
//  TranslationResult.swift
//  SwiftLocalize
//

import Foundation

// MARK: - Translation Result

/// The result of translating a single string.
public struct TranslationResult: Sendable, Equatable {
    /// The original source string.
    public let original: String

    /// The translated string.
    public let translated: String

    /// Confidence score (0.0 to 1.0), if available.
    public let confidence: Double?

    /// The provider that performed the translation.
    public let provider: String

    /// Additional metadata from the provider.
    public let metadata: [String: String]?

    public init(
        original: String,
        translated: String,
        confidence: Double? = nil,
        provider: String,
        metadata: [String: String]? = nil
    ) {
        self.original = original
        self.translated = translated
        self.confidence = confidence
        self.provider = provider
        self.metadata = metadata
    }
}

// MARK: - Translation Context

/// Context provided to translation providers for better translation quality.
public struct TranslationContext: Sendable, Equatable {
    /// Application description for context.
    public let appDescription: String?

    /// Application domain (e.g., "automotive", "fitness").
    public let domain: String?

    /// Whether to preserve format specifiers (%@, %lld, etc.).
    public let preserveFormatters: Bool

    /// Whether to preserve Markdown syntax.
    public let preserveMarkdown: Bool

    /// Additional instructions for the translator.
    public let additionalInstructions: String?

    /// Glossary terms to use.
    public let glossaryTerms: [GlossaryTerm]?

    /// Similar translations from translation memory.
    public let translationMemoryMatches: [TranslationMemoryMatch]?

    /// UI element context for each string.
    public let stringContexts: [String: StringTranslationContext]?

    public init(
        appDescription: String? = nil,
        domain: String? = nil,
        preserveFormatters: Bool = true,
        preserveMarkdown: Bool = true,
        additionalInstructions: String? = nil,
        glossaryTerms: [GlossaryTerm]? = nil,
        translationMemoryMatches: [TranslationMemoryMatch]? = nil,
        stringContexts: [String: StringTranslationContext]? = nil
    ) {
        self.appDescription = appDescription
        self.domain = domain
        self.preserveFormatters = preserveFormatters
        self.preserveMarkdown = preserveMarkdown
        self.additionalInstructions = additionalInstructions
        self.glossaryTerms = glossaryTerms
        self.translationMemoryMatches = translationMemoryMatches
        self.stringContexts = stringContexts
    }
}

// MARK: - Translation Memory Match

/// A match from translation memory.
public struct TranslationMemoryMatch: Sendable, Equatable {
    /// The source string that was matched.
    public let source: String

    /// The translation of the matched string.
    public let translation: String

    /// Similarity score (0.0 to 1.0).
    public let similarity: Double

    public init(source: String, translation: String, similarity: Double) {
        self.source = source
        self.translation = translation
        self.similarity = similarity
    }
}

// MARK: - String Translation Context

/// Context for a specific string being translated.
public struct StringTranslationContext: Sendable, Equatable {
    /// The string key.
    public let key: String

    /// Developer comment from xcstrings.
    public let comment: String?

    /// UI element types where this string is used.
    public let uiElementTypes: Set<UIElementType>?

    /// Code snippets showing usage.
    public let codeSnippets: [String]?

    public init(
        key: String,
        comment: String? = nil,
        uiElementTypes: Set<UIElementType>? = nil,
        codeSnippets: [String]? = nil
    ) {
        self.key = key
        self.comment = comment
        self.uiElementTypes = uiElementTypes
        self.codeSnippets = codeSnippets
    }
}

// MARK: - UI Element Type

/// Types of UI elements where strings might be used.
public enum UIElementType: String, Sendable, Codable, Equatable, Hashable, CaseIterable {
    case button
    case text
    case label
    case alert
    case navigationTitle
    case confirmationDialog
    case textField
    case tabItem
    case sheet
    case menu
    case tooltip
    case placeholder
    case errorMessage
    case successMessage
    case accessibilityLabel
    case accessibilityHint
}

// MARK: - Translation Progress

/// Progress information for translation operations.
public struct TranslationProgress: Sendable {
    /// Total number of strings to translate.
    public let total: Int

    /// Number of strings completed.
    public let completed: Int

    /// Number of strings that failed.
    public let failed: Int

    /// Current language being translated.
    public let currentLanguage: LanguageCode?

    /// Current provider being used.
    public let currentProvider: String?

    /// Progress percentage (0.0 to 1.0).
    public var percentage: Double {
        guard total > 0 else { return 0 }
        return Double(completed) / Double(total)
    }

    public init(
        total: Int,
        completed: Int,
        failed: Int = 0,
        currentLanguage: LanguageCode? = nil,
        currentProvider: String? = nil
    ) {
        self.total = total
        self.completed = completed
        self.failed = failed
        self.currentLanguage = currentLanguage
        self.currentProvider = currentProvider
    }
}

// MARK: - Translation Report

/// Summary report of a translation operation.
public struct TranslationReport: Sendable {
    /// Total strings processed.
    public let totalStrings: Int

    /// Strings successfully translated.
    public let translatedCount: Int

    /// Strings that failed to translate.
    public let failedCount: Int

    /// Strings skipped (already translated or excluded).
    public let skippedCount: Int

    /// Breakdown by language.
    public let byLanguage: [LanguageCode: LanguageReport]

    /// Total duration.
    public let duration: Duration

    /// Errors encountered.
    public let errors: [TranslationReportError]

    public init(
        totalStrings: Int,
        translatedCount: Int,
        failedCount: Int,
        skippedCount: Int,
        byLanguage: [LanguageCode: LanguageReport],
        duration: Duration,
        errors: [TranslationReportError] = []
    ) {
        self.totalStrings = totalStrings
        self.translatedCount = translatedCount
        self.failedCount = failedCount
        self.skippedCount = skippedCount
        self.byLanguage = byLanguage
        self.duration = duration
        self.errors = errors
    }
}

/// Report for a single language.
public struct LanguageReport: Sendable {
    public let language: LanguageCode
    public let translatedCount: Int
    public let failedCount: Int
    public let provider: String

    public init(
        language: LanguageCode,
        translatedCount: Int,
        failedCount: Int,
        provider: String
    ) {
        self.language = language
        self.translatedCount = translatedCount
        self.failedCount = failedCount
        self.provider = provider
    }
}

/// An error in the translation report.
public struct TranslationReportError: Sendable {
    public let key: String
    public let language: LanguageCode
    public let message: String

    public init(key: String, language: LanguageCode, message: String) {
        self.key = key
        self.language = language
        self.message = message
    }
}
