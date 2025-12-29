//
//  ContextModels.swift
//  SwiftLocalize
//

import Foundation

// MARK: - UIElementType Extension

extension UIElementType {
    /// Human-readable description for LLM context.
    public var contextDescription: String {
        switch self {
        case .button: return "Button label (keep short, action-oriented)"
        case .text: return "Body text (can be longer, informative)"
        case .label: return "Label text (concise, descriptive)"
        case .alert: return "Alert message (clear, possibly urgent)"
        case .navigationTitle: return "Navigation title (short, identifies screen)"
        case .confirmationDialog: return "Confirmation dialog (action-oriented options)"
        case .textField: return "Text field placeholder (brief hint)"
        case .tabItem: return "Tab bar item (very short, one or two words)"
        case .sheet: return "Sheet title or content"
        case .menu: return "Menu item (short, action-oriented)"
        case .tooltip: return "Tooltip (brief explanation)"
        case .placeholder: return "Placeholder text (hint for expected input)"
        case .errorMessage: return "Error message (clear explanation of problem)"
        case .successMessage: return "Success message (positive confirmation)"
        case .accessibilityLabel: return "Accessibility label (describes UI element)"
        case .accessibilityHint: return "Accessibility hint (describes action result)"
        }
    }
}

// MARK: - String Usage Context

/// Context about how a string key is used in the codebase.
public struct StringUsageContext: Sendable, Equatable {
    /// The string key being analyzed.
    public let key: String

    /// UI element types where this string is used.
    public let elementTypes: Set<UIElementType>

    /// Code snippets showing usage (limited to preserve context window).
    public let codeSnippets: [String]

    /// SwiftUI modifiers applied near the string usage.
    public let modifiers: [String]

    /// Files where the string is used.
    public let fileLocations: [String]

    public init(
        key: String,
        elementTypes: Set<UIElementType> = [],
        codeSnippets: [String] = [],
        modifiers: [String] = [],
        fileLocations: [String] = []
    ) {
        self.key = key
        self.elementTypes = elementTypes
        self.codeSnippets = codeSnippets
        self.modifiers = modifiers
        self.fileLocations = fileLocations
    }

    /// Generate context description for LLM prompts.
    public func toContextDescription() -> String {
        var parts: [String] = []

        if !elementTypes.isEmpty {
            let types = elementTypes.map(\.rawValue).sorted().joined(separator: ", ")
            parts.append("UI Element: \(types)")
        }

        if !modifiers.isEmpty {
            let mods = modifiers.prefix(5).joined(separator: ", ")
            parts.append("Modifiers: \(mods)")
        }

        if let snippet = codeSnippets.first {
            let truncated = snippet.count > 200 ? String(snippet.prefix(200)) + "..." : snippet
            parts.append("Code Context:\n\(truncated)")
        }

        return parts.joined(separator: "\n")
    }
}

// MARK: - Code Occurrence

/// A location where a string key appears in source code.
public struct CodeOccurrence: Sendable, Equatable {
    /// File path relative to project root.
    public let file: String

    /// Line number (1-indexed).
    public let line: Int

    /// Column number (1-indexed).
    public let column: Int

    /// Surrounding code context (a few lines).
    public let context: String

    /// The matched pattern that found this occurrence.
    public let matchedPattern: String?

    public init(
        file: String,
        line: Int,
        column: Int,
        context: String,
        matchedPattern: String? = nil
    ) {
        self.file = file
        self.line = line
        self.column = column
        self.context = context
        self.matchedPattern = matchedPattern
    }
}

// MARK: - Translation Memory Match

/// A match from the translation memory with extended metadata.
public struct TMMatch: Sendable, Equatable, Hashable {
    /// The source text that was matched.
    public let source: String

    /// The translation from the memory.
    public let translation: String

    /// Similarity score (0.0 to 1.0, 1.0 = exact match).
    public let similarity: Double

    /// The provider that generated this translation.
    public let provider: String?

    /// Whether a human reviewed this translation.
    public let humanReviewed: Bool

    public init(
        source: String,
        translation: String,
        similarity: Double,
        provider: String? = nil,
        humanReviewed: Bool = false
    ) {
        self.source = source
        self.translation = translation
        self.similarity = similarity
        self.provider = provider
        self.humanReviewed = humanReviewed
    }
}

// MARK: - Glossary Match

/// A glossary term found in a string.
public struct GlossaryMatch: Sendable, Equatable, Hashable {
    /// The matched term.
    public let term: String

    /// Whether this term should not be translated.
    public let doNotTranslate: Bool

    /// Available translations for this term.
    public let translations: [String: String]

    /// Definition or context for the term.
    public let definition: String?

    public init(
        term: String,
        doNotTranslate: Bool = false,
        translations: [String: String] = [:],
        definition: String? = nil
    ) {
        self.term = term
        self.doNotTranslate = doNotTranslate
        self.translations = translations
        self.definition = definition
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(term)
    }

    public static func == (lhs: GlossaryMatch, rhs: GlossaryMatch) -> Bool {
        lhs.term == rhs.term
    }
}

// MARK: - String Context

/// Combined context for a single string to translate.
public struct StringContext: Sendable {
    /// The string key.
    public let key: String

    /// The source text value.
    public let value: String

    /// Developer comment from xcstrings.
    public let comment: String?

    /// Code usage context.
    public let usageContext: StringUsageContext?

    /// Glossary terms found in the string.
    public let glossaryTerms: [GlossaryMatch]

    public init(
        key: String,
        value: String,
        comment: String? = nil,
        usageContext: StringUsageContext? = nil,
        glossaryTerms: [GlossaryMatch] = []
    ) {
        self.key = key
        self.value = value
        self.comment = comment
        self.usageContext = usageContext
        self.glossaryTerms = glossaryTerms
    }
}

// MARK: - Translation Prompt Context

/// Complete context for generating translation prompts.
public struct TranslationPromptContext: Sendable {
    /// App-level context description.
    public let appContext: String

    /// Individual string contexts.
    public let stringContexts: [StringContext]

    /// All glossary terms found.
    public let glossaryTerms: [GlossaryMatch]

    /// Relevant translation memory matches.
    public let translationMemoryMatches: [TMMatch]

    /// Target language code.
    public let targetLanguage: String

    public init(
        appContext: String,
        stringContexts: [StringContext],
        glossaryTerms: [GlossaryMatch] = [],
        translationMemoryMatches: [TMMatch] = [],
        targetLanguage: String
    ) {
        self.appContext = appContext
        self.stringContexts = stringContexts
        self.glossaryTerms = glossaryTerms
        self.translationMemoryMatches = translationMemoryMatches
        self.targetLanguage = targetLanguage
    }

    /// Generate the system prompt for LLM translation.
    public func toSystemPrompt() -> String {
        var parts: [String] = []

        parts.append("""
        You are an expert translator for iOS/macOS applications.

        \(appContext)
        """)

        if !glossaryTerms.isEmpty {
            parts.append("\nTerminology (use these exact translations):")
            for term in glossaryTerms {
                if term.doNotTranslate {
                    parts.append("- \"\(term.term)\" → Keep unchanged")
                } else if let trans = term.translations[targetLanguage] {
                    parts.append("- \"\(term.term)\" → \"\(trans)\"")
                }
            }
        }

        if !translationMemoryMatches.isEmpty {
            parts.append("\nPrevious translations for consistency:")
            for match in translationMemoryMatches.prefix(5) {
                let reviewed = match.humanReviewed ? " (reviewed)" : ""
                parts.append("- \"\(match.source)\" → \"\(match.translation)\"\(reviewed)")
            }
        }

        parts.append("""

        Translation Guidelines:
        - Preserve format specifiers: %@, %lld, %.1f, %d
        - Preserve Markdown syntax: ^[], **, _, ~~
        - Preserve placeholders: {name}, {{value}}
        - Maintain the same punctuation style
        - Keep the same formality level
        - Consider the UI element type for appropriate length/style
        """)

        return parts.joined(separator: "\n")
    }

    /// Generate the user prompt with strings to translate.
    public func toUserPrompt() -> String {
        var prompt = "Translate the following strings to \(targetLanguage):\n\n"

        for ctx in stringContexts {
            prompt += "Key: \"\(ctx.key)\"\n"
            prompt += "Text: \"\(ctx.value)\"\n"

            if let comment = ctx.comment, !comment.isEmpty {
                prompt += "Developer Note: \(comment)\n"
            }

            if let usage = ctx.usageContext, !usage.elementTypes.isEmpty {
                prompt += "UI Context: \(usage.toContextDescription())\n"
            }

            if !ctx.glossaryTerms.isEmpty {
                let terms = ctx.glossaryTerms.map(\.term).joined(separator: ", ")
                prompt += "Contains terms: \(terms)\n"
            }

            prompt += "\n"
        }

        prompt += """

        Return ONLY a JSON object mapping original text to translations:
        {"original1": "translation1", "original2": "translation2"}
        """

        return prompt
    }
}

// MARK: - Translation Quality

/// Quality level of a stored translation.
public enum TranslationQuality: String, Codable, Sendable {
    case machineTranslated
    case humanReviewed
    case humanTranslated
}

// MARK: - Part of Speech

/// Part of speech for glossary terms.
public enum PartOfSpeech: String, Codable, Sendable {
    case noun
    case verb
    case adjective
    case adverb
    case properNoun
}
