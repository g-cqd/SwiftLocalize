//
//  ContextBuilder.swift
//  SwiftLocalize
//

import Foundation

// MARK: - Context Configuration

/// Configuration for context-aware translation.
public struct ContextConfiguration: Sendable, Equatable, Codable {
    /// App name for context.
    public let appName: String

    /// Brief description of the app.
    public let appDescription: String

    /// Domain/industry of the app (e.g., "automotive", "fitness", "finance").
    public let domain: String

    /// Desired tone for translations.
    public let tone: Tone

    /// Formality level for translations.
    public let formality: FormalityLevel

    /// Path to project source code (for code analysis).
    public let projectPath: URL?

    /// Whether source code analysis is enabled.
    public let sourceCodeAnalysisEnabled: Bool

    /// Whether translation memory is enabled.
    public let translationMemoryEnabled: Bool

    /// Whether glossary is enabled.
    public let glossaryEnabled: Bool

    public init(
        appName: String,
        appDescription: String = "",
        domain: String = "",
        tone: Tone = .friendly,
        formality: FormalityLevel = .neutral,
        projectPath: URL? = nil,
        sourceCodeAnalysisEnabled: Bool = true,
        translationMemoryEnabled: Bool = true,
        glossaryEnabled: Bool = true
    ) {
        self.appName = appName
        self.appDescription = appDescription
        self.domain = domain
        self.tone = tone
        self.formality = formality
        self.projectPath = projectPath
        self.sourceCodeAnalysisEnabled = sourceCodeAnalysisEnabled
        self.translationMemoryEnabled = translationMemoryEnabled
        self.glossaryEnabled = glossaryEnabled
    }

    /// Build app context string for LLM prompts.
    public func buildAppContext() -> String {
        var parts: [String] = []

        parts.append("App: \(appName)")

        if !domain.isEmpty {
            parts.append("Domain: \(domain)")
        }

        if !appDescription.isEmpty {
            parts.append("Description: \(appDescription)")
        }

        parts.append("Tone: \(tone.description)")
        parts.append("Formality: \(formality.description)")

        return parts.joined(separator: "\n")
    }
}

// MARK: - Tone Extension

extension Tone {
    /// Human-readable description for prompts.
    public var description: String {
        switch self {
        case .friendly: return "Friendly and approachable"
        case .professional: return "Professional and businesslike"
        case .casual: return "Casual and conversational"
        case .formal: return "Formal and polished"
        case .technical: return "Technical and precise"
        }
    }
}

// MARK: - FormalityLevel Extension

extension FormalityLevel {
    /// Human-readable description for prompts.
    public var description: String {
        switch self {
        case .informal: return "Informal (use casual pronouns like 'tu' in French)"
        case .neutral: return "Neutral (context-appropriate formality)"
        case .formal: return "Formal (use polite pronouns like 'vous' in French)"
        }
    }
}

// MARK: - Context Builder

/// Assembles rich context for LLM translation prompts.
///
/// The ContextBuilder orchestrates multiple context sources:
/// - Source code analysis (how strings are used in UI)
/// - Translation memory (previous translations for consistency)
/// - Glossary (domain-specific terminology)
/// - Developer comments from xcstrings
///
/// ## Usage
/// ```swift
/// let builder = ContextBuilder(
///     config: config,
///     sourceCodeAnalyzer: analyzer,
///     translationMemory: memory,
///     glossary: glossary
/// )
///
/// let context = try await builder.buildContext(
///     for: [("key", "Hello", "Greeting")],
///     targetLanguage: "fr"
/// )
///
/// print(context.toSystemPrompt())
/// print(context.toUserPrompt())
/// ```
public actor ContextBuilder {

    /// Configuration for context building.
    private let config: ContextConfiguration

    /// Source code analyzer for usage context.
    private let sourceCodeAnalyzer: SourceCodeAnalyzer?

    /// Translation memory for consistency.
    private let translationMemory: TranslationMemory?

    /// Glossary for terminology.
    private let glossary: Glossary?

    public init(
        config: ContextConfiguration,
        sourceCodeAnalyzer: SourceCodeAnalyzer? = nil,
        translationMemory: TranslationMemory? = nil,
        glossary: Glossary? = nil
    ) {
        self.config = config
        self.sourceCodeAnalyzer = sourceCodeAnalyzer
        self.translationMemory = translationMemory
        self.glossary = glossary
    }

    /// Convenience initializer with default components.
    public init(config: ContextConfiguration) {
        self.config = config
        self.sourceCodeAnalyzer = config.sourceCodeAnalysisEnabled ? SourceCodeAnalyzer() : nil
        self.translationMemory = nil
        self.glossary = nil
    }

    // MARK: - Context Building

    /// Build comprehensive context for a batch of strings.
    ///
    /// - Parameters:
    ///   - entries: Array of (key, value, comment) tuples.
    ///   - targetLanguage: Target language code.
    /// - Returns: Complete context for translation prompts.
    public func buildContext(
        for entries: [(key: String, value: String, comment: String?)],
        targetLanguage: String
    ) async throws -> TranslationPromptContext {
        var stringContexts: [StringContext] = []
        var allGlossaryTerms: Set<GlossaryMatch> = []
        var relevantTMMatches: [TMMatch] = []

        // Pre-fetch source code analysis if enabled and project path exists
        var usageContexts: [String: StringUsageContext] = [:]
        if config.sourceCodeAnalysisEnabled,
           let projectPath = config.projectPath,
           let analyzer = sourceCodeAnalyzer {
            let keys = entries.map(\.key)
            usageContexts = try await analyzer.analyzeUsage(keys: keys, in: projectPath)
        }
        // Note: analyzeUsage is synchronous but we're in an actor context

        for entry in entries {
            let comment = entry.comment

            // Get pre-computed usage context
            let usageContext = usageContexts[entry.key]

            // Find glossary terms
            var glossaryMatches: [GlossaryMatch] = []
            if config.glossaryEnabled, let glossary {
                glossaryMatches = await glossary.findTerms(in: entry.value)
                allGlossaryTerms.formUnion(glossaryMatches)
            }

            // Find similar translations from TM
            if config.translationMemoryEnabled, let tm = translationMemory {
                let tmMatches = await tm.findSimilar(
                    to: entry.value,
                    targetLanguage: targetLanguage,
                    limit: 3
                )
                relevantTMMatches.append(contentsOf: tmMatches)
            }

            stringContexts.append(StringContext(
                key: entry.key,
                value: entry.value,
                comment: comment,
                usageContext: usageContext,
                glossaryTerms: glossaryMatches
            ))
        }

        // Deduplicate TM matches
        let uniqueTMMatches = Array(Set(relevantTMMatches))
            .sorted { $0.similarity > $1.similarity }
            .prefix(5)

        return TranslationPromptContext(
            appContext: config.buildAppContext(),
            stringContexts: stringContexts,
            glossaryTerms: Array(allGlossaryTerms),
            translationMemoryMatches: Array(uniqueTMMatches),
            targetLanguage: targetLanguage
        )
    }

    /// Build context for a single string.
    public func buildContext(
        key: String,
        value: String,
        comment: String?,
        targetLanguage: String
    ) async throws -> TranslationPromptContext {
        try await buildContext(
            for: [(key, value, comment)],
            targetLanguage: targetLanguage
        )
    }

    // MARK: - Simple Context

    /// Build a simple context without source code analysis.
    ///
    /// Faster but provides less context.
    public func buildSimpleContext(
        for entries: [(key: String, value: String, comment: String?)],
        targetLanguage: String
    ) async -> TranslationPromptContext {
        var stringContexts: [StringContext] = []
        var allGlossaryTerms: Set<GlossaryMatch> = []

        for entry in entries {
            // Find glossary terms only
            var glossaryMatches: [GlossaryMatch] = []
            if config.glossaryEnabled, let glossary {
                glossaryMatches = await glossary.findTerms(in: entry.value)
                allGlossaryTerms.formUnion(glossaryMatches)
            }

            stringContexts.append(StringContext(
                key: entry.key,
                value: entry.value,
                comment: entry.comment,
                usageContext: nil,
                glossaryTerms: glossaryMatches
            ))
        }

        return TranslationPromptContext(
            appContext: config.buildAppContext(),
            stringContexts: stringContexts,
            glossaryTerms: Array(allGlossaryTerms),
            translationMemoryMatches: [],
            targetLanguage: targetLanguage
        )
    }

    // MARK: - Update Components

    /// Update the translation memory reference.
    public func setTranslationMemory(_ memory: TranslationMemory) -> ContextBuilder {
        ContextBuilder(
            config: config,
            sourceCodeAnalyzer: sourceCodeAnalyzer,
            translationMemory: memory,
            glossary: glossary
        )
    }

    /// Update the glossary reference.
    public func setGlossary(_ glossary: Glossary) -> ContextBuilder {
        ContextBuilder(
            config: config,
            sourceCodeAnalyzer: sourceCodeAnalyzer,
            translationMemory: translationMemory,
            glossary: glossary
        )
    }
}

// MARK: - Prompt Generation Helpers

extension TranslationPromptContext {
    /// Generate a compact system prompt (for models with smaller context windows).
    public func toCompactSystemPrompt() -> String {
        var parts: [String] = []

        parts.append("You are a translator for iOS apps. Target: \(targetLanguage)")

        if !glossaryTerms.isEmpty {
            let termsList = glossaryTerms.prefix(10).map { term in
                if term.doNotTranslate {
                    return "\(term.term) (keep)"
                } else if let trans = term.translations[targetLanguage] {
                    return "\(term.term)=\(trans)"
                }
                return nil
            }.compactMap { $0 }.joined(separator: ", ")
            if !termsList.isEmpty {
                parts.append("Terms: \(termsList)")
            }
        }

        parts.append("Preserve: %@, %d, %lld, %.1f, {placeholders}")

        return parts.joined(separator: "\n")
    }

    /// Generate a structured JSON request format.
    public func toJSONRequest() -> [String: Any] {
        var request: [String: Any] = [
            "targetLanguage": targetLanguage,
            "appContext": appContext
        ]

        var stringsToTranslate: [[String: Any]] = []
        for ctx in stringContexts {
            var item: [String: Any] = [
                "key": ctx.key,
                "value": ctx.value
            ]
            if let comment = ctx.comment {
                item["comment"] = comment
            }
            if let usage = ctx.usageContext, !usage.elementTypes.isEmpty {
                item["uiElement"] = usage.elementTypes.first?.rawValue
            }
            stringsToTranslate.append(item)
        }
        request["strings"] = stringsToTranslate

        if !glossaryTerms.isEmpty {
            var terms: [[String: Any]] = []
            for term in glossaryTerms {
                var t: [String: Any] = ["term": term.term]
                if term.doNotTranslate {
                    t["doNotTranslate"] = true
                } else if let trans = term.translations[targetLanguage] {
                    t["translation"] = trans
                }
                terms.append(t)
            }
            request["glossary"] = terms
        }

        return request
    }
}

// MARK: - Default Configuration

extension ContextConfiguration {
    /// Default configuration for a generic app.
    public static var `default`: ContextConfiguration {
        ContextConfiguration(
            appName: "App",
            appDescription: "",
            domain: "",
            tone: .friendly,
            formality: .neutral
        )
    }

    /// Configuration for a professional/business app.
    public static func professional(appName: String, description: String = "") -> ContextConfiguration {
        ContextConfiguration(
            appName: appName,
            appDescription: description,
            domain: "business",
            tone: .professional,
            formality: .formal
        )
    }

    /// Configuration for a casual/consumer app.
    public static func casual(appName: String, description: String = "") -> ContextConfiguration {
        ContextConfiguration(
            appName: appName,
            appDescription: description,
            domain: "consumer",
            tone: .casual,
            formality: .informal
        )
    }
}
