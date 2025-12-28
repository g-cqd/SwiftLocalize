# SwiftLocalize Implementation Plan

**Package Name:** `SwiftLocalize`
**Purpose:** Automated localization tool for Swift projects using AI/ML translation providers
**Target:** Swift 6.2+ with Strict Concurrency, macOS 15+/iOS 18+

---

## Executive Summary

SwiftLocalize is a comprehensive Swift package that automates the translation of String Catalogs (`.xcstrings`) files using multiple AI/ML backends. It provides both a command-line interface and a Swift Package Manager plugin for seamless integration into build workflows.

---

## Research Findings

### 1. Translation Provider Options

| Provider | Type | Pros | Cons |
|----------|------|------|------|
| **Apple Translation Framework** | On-device | Free, private, no API key | macOS 14.4+, limited languages, requires language pack downloads |
| **Apple Foundation Models** | On-device | Free, ~3B params, guided generation | macOS 26+ only, requires Apple Intelligence |
| **OpenAI API** | Cloud | High quality, GPT-4o, many languages | Requires API key, costs money |
| **Anthropic Claude API** | Cloud | High quality, large context | Requires API key, costs money |
| **Google Gemini API** | Cloud | Good quality, fast | Requires API key, API changes |
| **DeepL API** | Cloud | Best translation quality | Requires API key, costs money |
| **Ollama** | Local | Free, private, customizable | Requires local server, setup complexity |
| **CLI Tools** | External | Easy integration | Requires tools installed (gemini, copilot) |

### 2. xcstrings File Format

```json
{
  "sourceLanguage": "en",
  "version": "1.0",
  "strings": {
    "Hello": {
      "comment": "Greeting message",
      "extractionState": "manual",
      "localizations": {
        "fr": {
          "stringUnit": {
            "state": "translated",
            "value": "Bonjour"
          }
        }
      }
    }
  }
}
```

**Key Structures:**
- `stringUnit`: Simple translations
- `variations.plural`: Plural forms (zero, one, few, many, other)
- `variations.device`: Device-specific (iPhone, iPad, Mac, Watch)
- `substitutions`: Dynamic placeholders

### 3. Swift Package Plugin Architecture

- **BuildToolPlugin**: Runs on every build (prebuild/build commands)
- **CommandPlugin**: On-demand execution via `swift package <command>`
- Plugins run sandboxed with limited filesystem access
- Require explicit permissions for write operations

### 4. Apple Native Frameworks

**Translation Framework (macOS 14.4+):**
- `TranslationSession` for programmatic translation
- Requires SwiftUI context for session creation
- On-device, free, privacy-preserving
- Language packs must be downloaded

**Foundation Models (macOS 26+):**
- `@Generable` macro for structured outputs
- `Tool` protocol for custom capabilities
- ~3B parameter on-device model
- Guided generation for JSON output

**NaturalLanguage Framework:**
- `NLLanguageRecognizer` for language detection
- Confidence scores and hints
- Tokenization and lemmatization

### 5. Context-Aware Translation (RAG-Style)

Research shows that providing contextual information to LLMs dramatically improves translation quality:

**Key Findings:**
- Lokalise's RAG solution achieved 90-95% first-pass acceptance rates
- Context injection eliminates ambiguity in short UI strings
- Translation memories ensure consistency across the app
- Glossaries maintain brand-specific terminology

**Context Sources:**

| Source | Description | Impact |
|--------|-------------|--------|
| **Developer Comments** | `comment` field in xcstrings | High - explains intent |
| **Source Code Usage** | Where/how string is used in Swift/SwiftUI | High - UI element context |
| **Translation Memory** | Previous translations for consistency | High - maintains style |
| **Glossary/Terminology** | App-specific terms and their translations | Critical - brand consistency |
| **App Description** | Overall app purpose and domain | Medium - sets tone |
| **UI Element Type** | Button, label, alert, navigation | Medium - format hints |
| **Pluralization Context** | Grammatical number rules | High - correct forms |

---

## Context Extraction System

### Architecture

```
Sources/
└── SwiftLocalizeCore/
    └── Context/
        ├── ContextExtractor.swift       # Main orchestrator
        ├── SourceCodeAnalyzer.swift     # Swift/SwiftUI code analysis
        ├── CommentExtractor.swift       # xcstrings comment extraction
        ├── TranslationMemory.swift      # TM storage and retrieval
        ├── Glossary.swift               # Terminology management
        └── ContextBuilder.swift         # Prompt context assembly
```

### Source Code Context Extraction

```swift
/// Extracts usage context from Swift source files
public actor SourceCodeAnalyzer {

    /// Analyze how a string key is used in the codebase
    public func analyzeUsage(
        key: String,
        in projectPath: URL
    ) async throws -> StringUsageContext {
        // 1. Find all occurrences of the key in Swift files
        let occurrences = try await findOccurrences(key: key, in: projectPath)

        // 2. Determine UI element type (Button, Text, Label, Alert, etc.)
        let elementTypes = occurrences.compactMap { extractUIElement($0) }

        // 3. Extract surrounding code context
        let codeSnippets = occurrences.map { extractSnippet($0, lines: 5) }

        // 4. Detect SwiftUI modifiers that hint at usage
        let modifiers = occurrences.flatMap { extractModifiers($0) }

        return StringUsageContext(
            key: key,
            elementTypes: Set(elementTypes),
            codeSnippets: codeSnippets,
            modifiers: modifiers,
            fileLocations: occurrences.map(\.file)
        )
    }

    /// Extract UI element type from code
    private func extractUIElement(_ occurrence: CodeOccurrence) -> UIElementType? {
        let patterns: [(regex: String, type: UIElementType)] = [
            (#"Button\s*\(\s*["']?\#(key)"#, .button),
            (#"Text\s*\(\s*["']?\#(key)"#, .text),
            (#"Label\s*\(\s*["']?\#(key)"#, .label),
            (#"\.alert\s*\([^)]*["']?\#(key)"#, .alert),
            (#"\.navigationTitle\s*\(\s*["']?\#(key)"#, .navigationTitle),
            (#"\.confirmationDialog\s*\([^)]*["']?\#(key)"#, .confirmationDialog),
            (#"TextField\s*\(\s*["']?\#(key)"#, .textField),
            (#"\.tabItem\s*\{[^}]*["']?\#(key)"#, .tabItem),
            (#"\.sheet\s*\([^)]*["']?\#(key)"#, .sheet),
        ]
        // Match against patterns
        for (pattern, type) in patterns {
            if occurrence.context.matches(pattern) {
                return type
            }
        }
        return nil
    }
}

public enum UIElementType: String, Sendable {
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
}

public struct StringUsageContext: Sendable {
    public let key: String
    public let elementTypes: Set<UIElementType>
    public let codeSnippets: [String]
    public let modifiers: [String]
    public let fileLocations: [URL]

    /// Generate context description for LLM
    public func toContextDescription() -> String {
        var parts: [String] = []

        if !elementTypes.isEmpty {
            let types = elementTypes.map(\.rawValue).joined(separator: ", ")
            parts.append("UI Element: \(types)")
        }

        if !modifiers.isEmpty {
            parts.append("Modifiers: \(modifiers.joined(separator: ", "))")
        }

        if !codeSnippets.isEmpty {
            parts.append("Code Context:\n\(codeSnippets.first ?? "")")
        }

        return parts.joined(separator: "\n")
    }
}
```

### Translation Memory (TM)

```swift
/// Stores and retrieves previous translations for consistency
public actor TranslationMemory {
    private var entries: [String: TMEntry] = [:]
    private let storageURL: URL

    public struct TMEntry: Codable, Sendable {
        let sourceText: String
        let translations: [String: TranslatedText]  // langCode -> translation
        let context: String?
        let lastUsed: Date
        let quality: TranslationQuality
    }

    public struct TranslatedText: Codable, Sendable {
        let value: String
        let provider: String
        let reviewedByHuman: Bool
        let confidence: Double
    }

    public enum TranslationQuality: String, Codable, Sendable {
        case machineTranslated
        case humanReviewed
        case humanTranslated
    }

    /// Find similar translations for context
    public func findSimilar(
        to text: String,
        targetLanguage: String,
        limit: Int = 5
    ) async -> [TMMatch] {
        // 1. Exact match
        if let exact = entries[text] {
            if let translation = exact.translations[targetLanguage] {
                return [TMMatch(source: text, translation: translation.value, similarity: 1.0)]
            }
        }

        // 2. Fuzzy matching using Levenshtein distance or embeddings
        let matches = entries.compactMap { (key, entry) -> TMMatch? in
            guard let translation = entry.translations[targetLanguage] else { return nil }
            let similarity = calculateSimilarity(text, key)
            guard similarity > 0.7 else { return nil }
            return TMMatch(source: key, translation: translation.value, similarity: similarity)
        }

        return matches
            .sorted { $0.similarity > $1.similarity }
            .prefix(limit)
            .map { $0 }
    }

    /// Add new translation to memory
    public func store(
        source: String,
        translation: String,
        language: String,
        provider: String,
        context: String? = nil
    ) async {
        var entry = entries[source] ?? TMEntry(
            sourceText: source,
            translations: [:],
            context: context,
            lastUsed: Date(),
            quality: .machineTranslated
        )

        entry.translations[language] = TranslatedText(
            value: translation,
            provider: provider,
            reviewedByHuman: false,
            confidence: 0.9
        )

        entries[source] = entry
        await save()
    }
}

public struct TMMatch: Sendable {
    public let source: String
    public let translation: String
    public let similarity: Double
}
```

### Glossary Management

```swift
/// Manages app-specific terminology and their translations
public actor Glossary {
    private var terms: [String: GlossaryTerm] = [:]
    private let storageURL: URL

    public struct GlossaryTerm: Codable, Sendable {
        let term: String
        let definition: String?
        let translations: [String: String]  // langCode -> translation
        let caseSensitive: Bool
        let doNotTranslate: Bool
        let partOfSpeech: PartOfSpeech?
    }

    public enum PartOfSpeech: String, Codable, Sendable {
        case noun, verb, adjective, adverb, properNoun
    }

    /// Find glossary terms in a string
    public func findTerms(in text: String) -> [GlossaryMatch] {
        var matches: [GlossaryMatch] = []

        for (key, term) in terms {
            let searchText = term.caseSensitive ? text : text.lowercased()
            let searchKey = term.caseSensitive ? key : key.lowercased()

            if searchText.contains(searchKey) {
                matches.append(GlossaryMatch(
                    term: term.term,
                    range: text.range(of: key, options: term.caseSensitive ? [] : .caseInsensitive),
                    doNotTranslate: term.doNotTranslate,
                    translations: term.translations
                ))
            }
        }

        return matches
    }

    /// Generate glossary instructions for LLM
    public func toPromptInstructions(
        terms: [GlossaryMatch],
        targetLanguage: String
    ) -> String {
        guard !terms.isEmpty else { return "" }

        var instructions: [String] = ["Terminology to use:"]

        for match in terms {
            if match.doNotTranslate {
                instructions.append("- \"\(match.term)\" → Keep as \"\(match.term)\" (do not translate)")
            } else if let translation = match.translations[targetLanguage] {
                instructions.append("- \"\(match.term)\" → \"\(translation)\"")
            }
        }

        return instructions.joined(separator: "\n")
    }
}
```

### Context Builder for LLM Prompts

```swift
/// Assembles rich context for LLM translation prompts
public actor ContextBuilder {
    private let sourceCodeAnalyzer: SourceCodeAnalyzer
    private let translationMemory: TranslationMemory
    private let glossary: Glossary
    private let config: ContextConfiguration

    public struct ContextConfiguration: Sendable {
        let appName: String
        let appDescription: String
        let domain: String  // e.g., "fuel tracking", "fitness", "finance"
        let tone: Tone
        let formality: Formality
        let projectPath: URL?

        public enum Tone: String, Sendable {
            case friendly, professional, casual, formal, technical
        }

        public enum Formality: String, Sendable {
            case informal, neutral, formal
        }
    }

    /// Build comprehensive context for a translation batch
    public func buildContext(
        for entries: [(key: String, value: String, comment: String?)],
        targetLanguage: String
    ) async throws -> TranslationPromptContext {
        var stringContexts: [StringContext] = []
        var allGlossaryTerms: Set<GlossaryMatch> = []
        var relevantTMMatches: [TMMatch] = []

        for entry in entries {
            // 1. Extract developer comment
            let comment = entry.comment

            // 2. Analyze source code usage (if project path available)
            var usageContext: StringUsageContext?
            if let projectPath = config.projectPath {
                usageContext = try? await sourceCodeAnalyzer.analyzeUsage(
                    key: entry.key,
                    in: projectPath
                )
            }

            // 3. Find glossary terms
            let glossaryMatches = await glossary.findTerms(in: entry.value)
            allGlossaryTerms.formUnion(glossaryMatches)

            // 4. Find similar translations from TM
            let tmMatches = await translationMemory.findSimilar(
                to: entry.value,
                targetLanguage: targetLanguage,
                limit: 3
            )
            relevantTMMatches.append(contentsOf: tmMatches)

            stringContexts.append(StringContext(
                key: entry.key,
                value: entry.value,
                comment: comment,
                usageContext: usageContext,
                glossaryTerms: glossaryMatches
            ))
        }

        return TranslationPromptContext(
            appContext: buildAppContext(),
            stringContexts: stringContexts,
            glossaryTerms: Array(allGlossaryTerms),
            translationMemoryMatches: relevantTMMatches,
            targetLanguage: targetLanguage
        )
    }

    private func buildAppContext() -> String {
        """
        App: \(config.appName)
        Domain: \(config.domain)
        Description: \(config.appDescription)
        Tone: \(config.tone.rawValue)
        Formality: \(config.formality.rawValue)
        """
    }
}

public struct TranslationPromptContext: Sendable {
    let appContext: String
    let stringContexts: [StringContext]
    let glossaryTerms: [GlossaryMatch]
    let translationMemoryMatches: [TMMatch]
    let targetLanguage: String

    /// Generate the full system prompt for LLM
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
                parts.append("- \"\(match.source)\" → \"\(match.translation)\"")
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

    /// Generate the user prompt with strings to translate
    public func toUserPrompt() -> String {
        var prompt = "Translate the following strings to \(targetLanguage):\n\n"

        for ctx in stringContexts {
            prompt += "Key: \"\(ctx.key)\"\n"
            prompt += "Text: \"\(ctx.value)\"\n"

            if let comment = ctx.comment {
                prompt += "Developer Note: \(comment)\n"
            }

            if let usage = ctx.usageContext {
                prompt += "UI Context: \(usage.toContextDescription())\n"
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

public struct StringContext: Sendable {
    let key: String
    let value: String
    let comment: String?
    let usageContext: StringUsageContext?
    let glossaryTerms: [GlossaryMatch]
}

public struct GlossaryMatch: Hashable, Sendable {
    let term: String
    let range: Range<String.Index>?
    let doNotTranslate: Bool
    let translations: [String: String]
}
```

### Configuration Extension

```yaml
# .swiftlocalize.yml - Context Configuration Section

context:
  # App-level context
  app:
    name: "LotoFuel"
    description: "Fuel tracking and vehicle expense management app for iOS"
    domain: "automotive"
    tone: friendly
    formality: neutral

  # Source code analysis
  sourceCode:
    enabled: true
    paths:
      - "Sources/**/*.swift"
      - "LotoFuel/**/*.swift"
    exclude:
      - "**/*Tests*/**"

  # Translation memory
  translationMemory:
    enabled: true
    file: .swiftlocalize-tm.json
    minSimilarity: 0.7
    maxMatches: 5

  # Glossary
  glossary:
    enabled: true
    file: .swiftlocalize-glossary.json
    # Or inline terms:
    terms:
      - term: "LotoFuel"
        doNotTranslate: true
      - term: "Fill-up"
        translations:
          fr: "Plein"
          de: "Tanken"
          es: "Repostaje"
      - term: "MPG"
        definition: "Miles per gallon - fuel efficiency metric"
        translations:
          fr: "MPG"  # Keep as-is in French
          de: "MPG"
      - term: "odometer"
        translations:
          fr: "compteur kilométrique"
          de: "Kilometerzähler"
          es: "odómetro"

  # Developer comments extraction
  comments:
    # Include xcstrings comments in prompts
    includeInPrompt: true
    # Warn if strings lack comments
    warnMissing: true
```

---

## Package Architecture

### Module Structure

```
SwiftLocalize/
├── Package.swift
├── Sources/
│   ├── SwiftLocalizeCore/           # Core library
│   │   ├── Models/
│   │   │   ├── XCStrings.swift      # xcstrings file models
│   │   │   ├── Configuration.swift   # Config file models
│   │   │   ├── TranslationResult.swift
│   │   │   └── LanguageCode.swift
│   │   ├── Providers/
│   │   │   ├── TranslationProvider.swift      # Protocol
│   │   │   ├── AppleTranslationProvider.swift # Translation.framework
│   │   │   ├── FoundationModelProvider.swift  # FoundationModels.framework
│   │   │   ├── OpenAIProvider.swift           # REST API client
│   │   │   ├── AnthropicProvider.swift        # REST API client
│   │   │   ├── GeminiProvider.swift           # REST API client
│   │   │   ├── DeepLProvider.swift            # REST API client
│   │   │   ├── OllamaProvider.swift           # Local REST API client
│   │   │   └── CLIToolProvider.swift          # External CLI wrapper
│   │   ├── Services/
│   │   │   ├── TranslationService.swift       # Orchestration
│   │   │   ├── XCStringsParser.swift          # File I/O
│   │   │   ├── ConfigurationLoader.swift      # Config management
│   │   │   ├── ChangeDetector.swift           # Update detection
│   │   │   └── LanguageDetector.swift         # NaturalLanguage wrapper
│   │   ├── Context/
│   │   │   ├── ContextBuilder.swift           # Prompt context assembly
│   │   │   ├── SourceCodeAnalyzer.swift       # Swift/SwiftUI code analysis
│   │   │   ├── TranslationMemory.swift        # TM storage and retrieval
│   │   │   └── Glossary.swift                 # Terminology management
│   │   ├── HTTP/
│   │   │   ├── HTTPClient.swift               # URLSession wrapper
│   │   │   ├── HTTPRequest.swift
│   │   │   └── HTTPResponse.swift
│   │   └── Utilities/
│   │       ├── Logger.swift
│   │       ├── ProgressReporter.swift
│   │       └── RateLimiter.swift
│   │
│   ├── SwiftLocalizeCLI/            # Command-line tool
│   │   ├── SwiftLocalize.swift      # @main entry
│   │   ├── Commands/
│   │   │   ├── TranslateCommand.swift
│   │   │   ├── ValidateCommand.swift
│   │   │   ├── StatusCommand.swift
│   │   │   ├── InitCommand.swift
│   │   │   └── ProvidersCommand.swift
│   │   └── Formatters/
│   │       ├── ConsoleFormatter.swift
│   │       └── JSONFormatter.swift
│   │
│   └── SwiftLocalizePlugin/         # SPM Plugin
│       ├── SwiftLocalizeBuildPlugin.swift
│       └── SwiftLocalizeCommandPlugin.swift
│
├── Tests/
│   ├── SwiftLocalizeCoreTests/
│   │   ├── XCStringsParserTests.swift
│   │   ├── ConfigurationTests.swift
│   │   ├── ProviderTests/
│   │   └── ChangeDetectorTests.swift
│   └── IntegrationTests/
│
└── Plugins/
    ├── SwiftLocalizeBuildPlugin/
    │   └── Plugin.swift
    └── SwiftLocalizeCommandPlugin/
        └── Plugin.swift
```

---

## Configuration File Specification

**File:** `.swiftlocalize.yml` or `.swiftlocalize.json`

```yaml
# SwiftLocalize Configuration

# Source language for translations
sourceLanguage: en

# Target languages (ISO 639-1 codes)
targetLanguages:
  - fr
  - es
  - de
  - zh-Hans
  - ja
  - pt-BR

# Provider configuration (priority order)
providers:
  # Primary provider
  - name: apple-translation
    enabled: true
    priority: 1

  # Fallback providers
  - name: openai
    enabled: true
    priority: 2
    config:
      model: gpt-4o
      apiKeyEnv: OPENAI_API_KEY  # Environment variable name

  - name: anthropic
    enabled: false
    priority: 3
    config:
      model: claude-sonnet-4-20250514
      apiKeyEnv: ANTHROPIC_API_KEY

  - name: deepl
    enabled: false
    priority: 4
    config:
      apiKeyEnv: DEEPL_API_KEY
      formality: default  # default, more, less, prefer_more, prefer_less

  - name: ollama
    enabled: false
    priority: 5
    config:
      baseURL: http://localhost:11434
      model: llama3.2

  - name: cli-gemini
    enabled: false
    priority: 6
    config:
      path: /opt/homebrew/bin/gemini
      args: ["-y"]

# Translation settings
translation:
  # Batch size for API calls
  batchSize: 25

  # Concurrent requests per provider
  concurrency: 3

  # Rate limiting (requests per minute)
  rateLimit: 60

  # Retry configuration
  retries: 3
  retryDelay: 1.0  # seconds

  # Context for AI models
  context: "iOS fuel tracking app UI strings"

  # Preserve format specifiers
  preserveFormatters: true  # %@, %lld, %.1f, etc.

  # Preserve Markdown-like syntax
  preserveMarkdown: true  # ^[], **, _, etc.

# Change detection
changeDetection:
  enabled: true

  # How to detect changes
  strategy: hash  # hash, timestamp, git

  # Cache file location
  cacheFile: .swiftlocalize-cache.json

  # Only translate new/modified strings
  incrementalOnly: true

  # Force retranslation of strings with specific states
  retranslateStates:
    - needs_review
    - stale

# File patterns
files:
  # Include patterns (glob)
  include:
    - "**/*.xcstrings"

  # Exclude patterns
  exclude:
    - "**/Pods/**"
    - "**/.build/**"
    - "**/DerivedData/**"

# Output settings
output:
  # Write translations in-place or to separate files
  mode: in-place  # in-place, separate

  # Output directory (for separate mode)
  directory: Localizations/

  # Pretty print JSON
  prettyPrint: true

  # Sort keys alphabetically
  sortKeys: true

# Validation rules
validation:
  # Require all target languages
  requireAllLanguages: true

  # Check format specifier consistency
  validateFormatters: true

  # Maximum string length (0 = no limit)
  maxLength: 0

  # Warn on missing comments
  warnMissingComments: false

# Logging
logging:
  level: info  # debug, info, warn, error

  # Output format
  format: console  # console, json

  # Log file (optional)
  file: null
```

---

## API Design

### Core Protocol

```swift
/// Protocol for translation providers
public protocol TranslationProvider: Sendable {
    /// Provider identifier
    var identifier: String { get }

    /// Display name
    var displayName: String { get }

    /// Check if provider is available
    func isAvailable() async -> Bool

    /// Supported language pairs
    func supportedLanguages() async throws -> [LanguagePair]

    /// Translate a batch of strings
    func translate(
        _ strings: [String],
        from source: LanguageCode,
        to target: LanguageCode,
        context: TranslationContext?
    ) async throws -> [TranslationResult]
}

/// Translation context for AI providers
public struct TranslationContext: Sendable {
    public let appDescription: String?
    public let domain: String?
    public let preserveFormatters: Bool
    public let preserveMarkdown: Bool
    public let additionalInstructions: String?
}

/// Result of a translation
public struct TranslationResult: Sendable {
    public let original: String
    public let translated: String
    public let confidence: Double?
    public let provider: String
    public let metadata: [String: String]?
}
```

### Service Layer

```swift
/// Main translation service
public actor TranslationService {
    private let providers: [TranslationProvider]
    private let configuration: Configuration
    private let rateLimiter: RateLimiter

    public init(configuration: Configuration)

    /// Translate all pending strings in xcstrings files
    public func translateFiles(
        at paths: [URL],
        progress: @escaping @Sendable (TranslationProgress) -> Void
    ) async throws -> TranslationReport

    /// Translate specific strings
    public func translate(
        _ strings: [String],
        from source: LanguageCode,
        to targets: [LanguageCode]
    ) async throws -> [LanguageCode: [TranslationResult]]

    /// Validate translations
    public func validate(
        at paths: [URL]
    ) async throws -> ValidationReport
}
```

### XCStrings Models

```swift
/// Root xcstrings structure
public struct XCStrings: Codable, Sendable {
    public var sourceLanguage: String
    public var strings: [String: StringEntry]
    public var version: String
}

public struct StringEntry: Codable, Sendable {
    public var comment: String?
    public var extractionState: String?
    public var localizations: [String: Localization]?
}

public struct Localization: Codable, Sendable {
    public var stringUnit: StringUnit?
    public var variations: Variations?
    public var substitutions: [String: Substitution]?
}

public struct StringUnit: Codable, Sendable {
    public var state: TranslationState
    public var value: String
}

public enum TranslationState: String, Codable, Sendable {
    case new
    case translated
    case needsReview = "needs_review"
    case stale
}

public struct Variations: Codable, Sendable {
    public var plural: [String: Localization]?
    public var device: [String: Localization]?
}
```

---

## Provider Implementations

### 1. Apple Translation Provider

```swift
@available(macOS 14.4, iOS 17.4, *)
public final class AppleTranslationProvider: TranslationProvider, @unchecked Sendable {
    public let identifier = "apple-translation"
    public let displayName = "Apple Translation"

    private var session: TranslationSession?

    public func isAvailable() async -> Bool {
        // Check if Translation framework is available
        #if canImport(Translation)
        return true
        #else
        return false
        #endif
    }

    public func translate(
        _ strings: [String],
        from source: LanguageCode,
        to target: LanguageCode,
        context: TranslationContext?
    ) async throws -> [TranslationResult] {
        // Use TranslationSession for batch translation
        // Handle language pack downloads
        // Return results with confidence scores
    }
}
```

### 2. Foundation Models Provider

```swift
@available(macOS 26, iOS 26, *)
public final class FoundationModelProvider: TranslationProvider, @unchecked Sendable {
    public let identifier = "foundation-models"
    public let displayName = "Apple Intelligence"

    public func translate(
        _ strings: [String],
        from source: LanguageCode,
        to target: LanguageCode,
        context: TranslationContext?
    ) async throws -> [TranslationResult] {
        // Use @Generable for structured output
        // Leverage guided generation for JSON responses
    }
}

@Generable
struct TranslationOutput {
    let translations: [String: String]
}
```

### 3. OpenAI Provider

```swift
public final class OpenAIProvider: TranslationProvider, @unchecked Sendable {
    public let identifier = "openai"
    public let displayName = "OpenAI GPT"

    private let httpClient: HTTPClient
    private let config: OpenAIConfig

    public func translate(
        _ strings: [String],
        from source: LanguageCode,
        to target: LanguageCode,
        context: TranslationContext?
    ) async throws -> [TranslationResult] {
        let prompt = buildPrompt(strings: strings, source: source, target: target, context: context)

        let request = ChatCompletionRequest(
            model: config.model,
            messages: [
                .system(content: systemPrompt(context: context)),
                .user(content: prompt)
            ],
            responseFormat: .jsonObject
        )

        let response = try await httpClient.post(
            url: "https://api.openai.com/v1/chat/completions",
            body: request,
            headers: ["Authorization": "Bearer \(config.apiKey)"]
        )

        return parseResponse(response)
    }
}
```

### 4. HTTP Client (From Scratch)

```swift
/// Minimal HTTP client using URLSession
public actor HTTPClient {
    private let session: URLSession
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    public init(configuration: URLSessionConfiguration = .default) {
        self.session = URLSession(configuration: configuration)
        self.decoder = JSONDecoder()
        self.encoder = JSONEncoder()
    }

    public func post<Request: Encodable, Response: Decodable>(
        url: String,
        body: Request,
        headers: [String: String] = [:]
    ) async throws -> Response {
        guard let url = URL(string: url) else {
            throw HTTPError.invalidURL(url)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = try encoder.encode(body)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw HTTPError.invalidResponse
        }

        guard 200..<300 ~= httpResponse.statusCode else {
            throw HTTPError.statusCode(httpResponse.statusCode, data)
        }

        return try decoder.decode(Response.self, from: data)
    }
}
```

---

## CLI Design

```
USAGE: swiftlocalize <subcommand> [options]

SUBCOMMANDS:
  translate     Translate xcstrings files
  validate      Validate translations
  status        Show translation status
  init          Create configuration file
  providers     List available providers

TRANSLATE OPTIONS:
  -c, --config <path>       Configuration file path
  -f, --files <patterns>    File patterns to process
  -l, --languages <codes>   Target languages (comma-separated)
  -p, --provider <name>     Use specific provider
  --dry-run                 Show what would be translated
  --force                   Force retranslation of all strings
  -v, --verbose             Verbose output
  -q, --quiet               Minimal output
  --json                    Output as JSON

EXAMPLES:
  swiftlocalize translate
  swiftlocalize translate --files "**/*.xcstrings" --languages fr,de,es
  swiftlocalize translate --provider openai --dry-run
  swiftlocalize status --json
  swiftlocalize validate --strict
```

---

## Change Detection

```swift
/// Detects changes in source strings
public actor ChangeDetector {
    private let cacheURL: URL
    private var cache: TranslationCache

    public struct TranslationCache: Codable, Sendable {
        var version: String
        var entries: [String: CacheEntry]
    }

    public struct CacheEntry: Codable, Sendable {
        let sourceHash: String
        let translatedLanguages: Set<String>
        let lastModified: Date
    }

    /// Check which strings need translation
    public func detectChanges(
        in xcstrings: XCStrings,
        targetLanguages: [LanguageCode]
    ) async -> ChangeDetectionResult {
        var needsTranslation: [String: Set<LanguageCode>] = [:]

        for (key, entry) in xcstrings.strings {
            let sourceHash = computeHash(key)

            if let cached = cache.entries[key] {
                // Check if source changed
                if cached.sourceHash != sourceHash {
                    needsTranslation[key] = Set(targetLanguages)
                    continue
                }

                // Check which languages are missing
                let missing = Set(targetLanguages.map(\.code))
                    .subtracting(cached.translatedLanguages)

                if !missing.isEmpty {
                    needsTranslation[key] = Set(targetLanguages.filter { missing.contains($0.code) })
                }
            } else {
                // New string
                needsTranslation[key] = Set(targetLanguages)
            }
        }

        return ChangeDetectionResult(stringsToTranslate: needsTranslation)
    }

    /// Update cache after successful translation
    public func updateCache(
        key: String,
        sourceHash: String,
        translatedLanguages: Set<String>
    ) async {
        cache.entries[key] = CacheEntry(
            sourceHash: sourceHash,
            translatedLanguages: translatedLanguages,
            lastModified: Date()
        )
        await saveCache()
    }
}
```

---

## Testing Strategy

### Unit Tests

1. **XCStrings Parsing**
   - Parse valid xcstrings files
   - Handle malformed JSON
   - Preserve unknown fields
   - Round-trip encoding/decoding

2. **Configuration Loading**
   - YAML parsing
   - JSON parsing
   - Environment variable substitution
   - Default values
   - Validation errors

3. **Provider Tests**
   - Mock HTTP responses
   - Error handling
   - Rate limiting
   - Retry logic

4. **Change Detection**
   - New strings detection
   - Modified strings detection
   - Language gap detection
   - Cache persistence

### Integration Tests

1. **End-to-end translation flow**
2. **Multi-provider fallback**
3. **Concurrent translation**
4. **File I/O**

### Mocking Strategy

```swift
/// Mock provider for testing
public final class MockTranslationProvider: TranslationProvider, @unchecked Sendable {
    public let identifier = "mock"
    public let displayName = "Mock Provider"

    public var translations: [String: String] = [:]
    public var shouldFail = false
    public var delay: Duration = .zero

    public func translate(
        _ strings: [String],
        from source: LanguageCode,
        to target: LanguageCode,
        context: TranslationContext?
    ) async throws -> [TranslationResult] {
        if shouldFail {
            throw TranslationError.providerError("Mock failure")
        }

        try await Task.sleep(for: delay)

        return strings.map { string in
            TranslationResult(
                original: string,
                translated: translations[string] ?? "[\(target.code)] \(string)",
                confidence: 1.0,
                provider: identifier,
                metadata: nil
            )
        }
    }
}
```

---

## Implementation Phases

### Phase 1: Core Foundation
- [ ] Package structure and build configuration
- [ ] XCStrings models and parser
- [ ] Configuration file loader (YAML/JSON)
- [ ] HTTP client implementation
- [ ] Basic error types

### Phase 2: Provider Infrastructure
- [ ] TranslationProvider protocol
- [ ] OpenAI provider implementation
- [ ] Anthropic provider implementation
- [ ] Google Gemini provider implementation
- [ ] DeepL provider implementation
- [ ] Ollama provider implementation
- [ ] CLI tool provider wrapper

### Phase 3: Apple Integration
- [ ] Apple Translation framework provider
- [ ] Foundation Models provider (conditional compilation)
- [ ] NaturalLanguage framework integration
- [ ] Language detection utilities

### Phase 4: Context-Aware Translation
- [ ] SourceCodeAnalyzer for Swift/SwiftUI code analysis
- [ ] TranslationMemory for consistency
- [ ] Glossary management system
- [ ] ContextBuilder for prompt assembly
- [ ] Developer comment extraction
- [ ] UI element type detection

### Phase 5: Service Layer
- [ ] TranslationService actor
- [ ] Change detection system
- [ ] Rate limiting with token bucket
- [ ] Progress reporting
- [ ] Multi-provider fallback chain

### Phase 6: CLI Tool
- [ ] ArgumentParser integration
- [ ] translate command with context options
- [ ] validate command
- [ ] status command
- [ ] init command (config + glossary)
- [ ] glossary command (manage terms)
- [ ] Console formatting

### Phase 7: SPM Plugin
- [ ] Build tool plugin
- [ ] Command plugin
- [ ] Xcode integration testing

### Phase 8: Testing & Polish
- [ ] Comprehensive unit tests (>80% coverage)
- [ ] Integration tests with mock providers
- [ ] Context extraction tests
- [ ] Documentation (DocC)
- [ ] Example projects
- [ ] Performance optimization

---

## Dependencies

**Apple Frameworks Only:**
- Foundation
- Translation (macOS 14.4+, iOS 17.4+)
- FoundationModels (macOS 26+, iOS 26+)
- NaturalLanguage
- PackagePlugin

**Apple Open Source (SPM):**
- swift-argument-parser (Apple's official CLI framework)
- Yams (for YAML parsing) - *or implement minimal YAML parser*

---

## Platform Requirements

| Feature | macOS | iOS |
|---------|-------|-----|
| Core functionality | 14.0+ | 17.0+ |
| Apple Translation | 14.4+ | 17.4+ |
| Foundation Models | 26+ | 26+ |
| CLI tool | 14.0+ | N/A |
| SPM Plugin | 14.0+ | N/A |

---

## Security Considerations

1. **API Key Management**
   - Read from environment variables only
   - Never log or store API keys
   - Support keychain storage option

2. **Sandboxing**
   - SPM plugins run sandboxed
   - Request minimal permissions
   - Handle permission denials gracefully

3. **Network Security**
   - HTTPS only for all API calls
   - Certificate validation
   - No sensitive data in URLs

---

## Performance Targets

- Process 500+ strings in under 30 seconds (with API)
- Process 500+ strings in under 5 seconds (on-device)
- Memory usage under 100MB for typical projects
- Incremental translation with proper caching
- Parallel provider execution where possible

---

## Open Questions

1. Should we support `.strings` and `.stringsdict` files in addition to `.xcstrings`?
2. Should we implement a minimal YAML parser to avoid Yams dependency?
3. Should the build plugin run on every build or only when files change?
4. How to handle SwiftUI context requirement for Apple Translation?
5. Should context extraction be opt-in or default enabled?
6. Should we support embedding-based semantic similarity for TM matching?
7. How to handle conflicting glossary terms across different contexts?

---

## References

### Apple Frameworks
- [Apple Translation Framework](https://developer.apple.com/documentation/translation/)
- [Apple Foundation Models](https://developer.apple.com/documentation/FoundationModels)
- [WWDC24: Meet the Translation API](https://developer.apple.com/videos/play/wwdc2024/10117/)
- [WWDC25: Meet the Foundation Models framework](https://developer.apple.com/videos/play/wwdc2025/286/)
- [NaturalLanguage Framework](https://developer.apple.com/documentation/naturallanguage)

### Swift Package Manager
- [Swift Package Plugins](https://github.com/swiftlang/swift-package-manager/blob/main/Documentation/Plugins.md)
- [SE-0303: Extensible Build Tools](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0303-swiftpm-extensible-build-tools.md)
- [Swift Argument Parser](https://github.com/apple/swift-argument-parser)

### LLM Provider APIs
- [OpenAI API Reference](https://platform.openai.com/docs/api-reference)
- [Anthropic API Reference](https://docs.anthropic.com/en/api)
- [Google Gemini API](https://ai.google.dev/gemini-api/docs)
- [DeepL API Documentation](https://developers.deepl.com/docs)
- [Ollama API](https://github.com/ollama/ollama/blob/main/docs/api.md)

### Context-Aware Translation Research
- [LLMs Are Zero-Shot Context-Aware Simultaneous Translators](https://aclanthology.org/2024.emnlp-main.69/) - EMNLP 2024
- [K3Trans: Repository-Context Code Translation](https://arxiv.org/html/2503.18305v2)
- [RAG for Localization - Lokalise](https://lokalise.com/blog/rag-vs-the-buzz-how-retrieval-augmented-generation-is-quietly-disrupting-ai/)
- [Improving Glossary Support with RAG](https://inten.to/blog/improving-glossary-support-with-retrieval-augmented-generation/)
- [Crowdin Context Harvester](https://crowdin.com/blog/what-is-new-at-crowdin-october-2024)

### String Catalogs Format
- [WWDC23: Discover String Catalogs](https://developer.apple.com/videos/play/wwdc2023/10155/)
- [Lokalise XCStrings Documentation](https://docs.lokalise.com/en/articles/12710356-apple-xcstrings-xcstrings)
- [Xcode 26 AI-Powered Localization](https://dev.to/arshtechpro/wwdc-2025-explore-localization-with-xcode-26-n8n)
