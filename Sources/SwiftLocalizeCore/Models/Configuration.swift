//
//  Configuration.swift
//  SwiftLocalize
//

import Foundation

// MARK: - Configuration

/// Root configuration for SwiftLocalize.
public struct Configuration: Codable, Sendable, Equatable {
    // MARK: Lifecycle

    public init(
        sourceLanguage: LanguageCode = .english,
        targetLanguages: [LanguageCode] = [],
        providers: [ProviderConfiguration] = [],
        translation: TranslationSettings = .init(),
        changeDetection: ChangeDetectionSettings = .init(),
        files: FileSettings = .init(),
        output: OutputSettings = .init(),
        validation: ValidationSettings = .init(),
        context: ContextSettings = .init(),
        logging: LoggingSettings = .init(),
        mode: OperationMode = .translationOnly,
        isolation: IsolationSettings = .init(),
    ) {
        self.sourceLanguage = sourceLanguage
        self.targetLanguages = targetLanguages
        self.providers = providers
        self.translation = translation
        self.changeDetection = changeDetection
        self.files = files
        self.output = output
        self.validation = validation
        self.context = context
        self.logging = logging
        self.mode = mode
        self.isolation = isolation
    }

    // MARK: Public

    /// Source language for translations.
    public var sourceLanguage: LanguageCode

    /// Target languages to translate to.
    public var targetLanguages: [LanguageCode]

    /// Provider configurations in priority order.
    public var providers: [ProviderConfiguration]

    /// Translation settings.
    public var translation: TranslationSettings

    /// Change detection settings.
    public var changeDetection: ChangeDetectionSettings

    /// File pattern settings.
    public var files: FileSettings

    /// Output settings.
    public var output: OutputSettings

    /// Validation rules.
    public var validation: ValidationSettings

    /// Context settings for AI-powered translation.
    public var context: ContextSettings

    /// Logging settings.
    public var logging: LoggingSettings

    /// Operation mode.
    public var mode: OperationMode

    /// Isolation settings.
    public var isolation: IsolationSettings
}

// MARK: - OperationMode

/// Operation mode for the tool.
public enum OperationMode: String, Codable, Sendable, Equatable, CaseIterable {
    /// Only translate localization files, never touch source code.
    case translationOnly = "translation-only"
    /// Translate and optionally update code.
    case full
}

// MARK: - IsolationSettings

/// Settings for file isolation and safety.
public struct IsolationSettings: Codable, Sendable, Equatable {
    // MARK: Lifecycle

    public init(
        strict: Bool = true,
        allowedWritePatterns: [String] = ["**/*.xcstrings", "**/.swiftlocalize-cache.json"],
        verifyBeforeRun: Bool = true,
        generateAuditLog: Bool = false,
    ) {
        self.strict = strict
        self.allowedWritePatterns = allowedWritePatterns
        self.verifyBeforeRun = verifyBeforeRun
        self.generateAuditLog = generateAuditLog
    }

    // MARK: Public

    /// Whether strict isolation is enabled.
    public var strict: Bool

    /// Allowed write patterns (glob).
    public var allowedWritePatterns: [String]

    /// Verify isolation before running.
    public var verifyBeforeRun: Bool

    /// Generate audit log.
    public var generateAuditLog: Bool
}

// MARK: - ProviderConfiguration

/// Configuration for a translation provider.
public struct ProviderConfiguration: Codable, Sendable, Equatable {
    // MARK: Lifecycle

    public init(
        name: ProviderName,
        enabled: Bool = true,
        priority: Int = 1,
        config: ProviderConfig? = nil,
    ) {
        self.name = name
        self.enabled = enabled
        self.priority = priority
        self.config = config
    }

    // MARK: Public

    /// Provider identifier.
    public var name: ProviderName

    /// Whether the provider is enabled.
    public var enabled: Bool

    /// Priority (lower = higher priority).
    public var priority: Int

    /// Provider-specific configuration.
    public var config: ProviderConfig?
}

// MARK: - ProviderName

/// Supported provider names.
public enum ProviderName: String, Codable, Sendable, Equatable, CaseIterable {
    case appleTranslation = "apple-translation"
    case foundationModels = "foundation-models"
    case openai
    case anthropic
    case gemini
    case deepl
    case ollama
    case cliGemini = "gemini-cli"
    case cliCopilot = "copilot-cli"
    case cliCodex = "codex-cli"
    case cliGeneric = "generic-cli"
}

// MARK: - ProviderConfig

/// Provider-specific configuration options.
public struct ProviderConfig: Codable, Sendable, Equatable {
    // MARK: Lifecycle

    public init(
        model: String? = nil,
        apiKeyEnv: String? = nil,
        baseURL: String? = nil,
        path: String? = nil,
        args: [String]? = nil,
        formality: Formality? = nil,
        approvalMode: String? = nil,
    ) {
        self.model = model
        self.apiKeyEnv = apiKeyEnv
        self.baseURL = baseURL
        self.path = path
        self.args = args
        self.formality = formality
        self.approvalMode = approvalMode
    }

    // MARK: Public

    /// Model name (for LLM providers).
    public var model: String?

    /// Environment variable name for API key.
    public var apiKeyEnv: String?

    /// Base URL (for self-hosted providers like Ollama).
    public var baseURL: String?

    /// Path to CLI tool.
    public var path: String?

    /// Additional arguments for CLI tools.
    public var args: [String]?

    /// Formality level (for DeepL).
    public var formality: Formality?

    /// Approval mode for Codex CLI.
    public var approvalMode: String?

    /// Alias for CLI provider path (convenience accessor).
    public var cliPath: String? { path }
}

// MARK: - Formality

/// Formality level for translation.
public enum Formality: String, Codable, Sendable, Equatable {
    case `default`
    case more
    case less
    case preferMore = "prefer_more"
    case preferLess = "prefer_less"
}

// MARK: - TranslationSettings

/// Settings for translation behavior.
public struct TranslationSettings: Codable, Sendable, Equatable {
    // MARK: Lifecycle

    public init(
        batchSize: Int = 25,
        concurrency: Int = 3,
        rateLimit: Int = 60,
        retries: Int = 3,
        retryDelay: Double = 1.0,
        context: String? = nil,
        preserveFormatters: Bool = true,
        preserveMarkdown: Bool = true,
    ) {
        self.batchSize = batchSize
        self.concurrency = concurrency
        self.rateLimit = rateLimit
        self.retries = retries
        self.retryDelay = retryDelay
        self.context = context
        self.preserveFormatters = preserveFormatters
        self.preserveMarkdown = preserveMarkdown
    }

    // MARK: Public

    /// Number of strings to translate in a single batch.
    public var batchSize: Int

    /// Maximum concurrent requests per provider.
    public var concurrency: Int

    /// Rate limit (requests per minute).
    public var rateLimit: Int

    /// Number of retry attempts.
    public var retries: Int

    /// Delay between retries in seconds.
    public var retryDelay: Double

    /// Context description for AI models.
    public var context: String?

    /// Preserve format specifiers (%@, %lld, etc.).
    public var preserveFormatters: Bool

    /// Preserve Markdown syntax.
    public var preserveMarkdown: Bool
}

// MARK: - ChangeDetectionSettings

/// Settings for detecting changed strings.
public struct ChangeDetectionSettings: Codable, Sendable, Equatable {
    // MARK: Lifecycle

    public init(
        enabled: Bool = true,
        strategy: ChangeDetectionStrategy = .hash,
        cacheFile: String = ".swiftlocalize-cache.json",
        incrementalOnly: Bool = true,
        retranslateStates: [TranslationState] = [.needsReview, .stale],
    ) {
        self.enabled = enabled
        self.strategy = strategy
        self.cacheFile = cacheFile
        self.incrementalOnly = incrementalOnly
        self.retranslateStates = retranslateStates
    }

    // MARK: Public

    /// Whether change detection is enabled.
    public var enabled: Bool

    /// Detection strategy.
    public var strategy: ChangeDetectionStrategy

    /// Cache file location.
    public var cacheFile: String

    /// Only translate new/modified strings.
    public var incrementalOnly: Bool

    /// States that should trigger retranslation.
    public var retranslateStates: [TranslationState]
}

// MARK: - ChangeDetectionStrategy

/// Strategy for detecting changes.
public enum ChangeDetectionStrategy: String, Codable, Sendable, Equatable {
    case hash
    case timestamp
    case git
}

// MARK: - FileSettings

/// Settings for file discovery.
public struct FileSettings: Codable, Sendable, Equatable {
    // MARK: Lifecycle

    public init(
        include: [String] = ["**/*.xcstrings"],
        exclude: [String] = ["**/Pods/**", "**/.build/**", "**/DerivedData/**"],
    ) {
        self.include = include
        self.exclude = exclude
    }

    // MARK: Public

    /// Glob patterns to include.
    public var include: [String]

    /// Glob patterns to exclude.
    public var exclude: [String]
}

// MARK: - OutputSettings

/// Settings for output generation.
public struct OutputSettings: Codable, Sendable, Equatable {
    // MARK: Lifecycle

    public init(
        mode: OutputMode = .inPlace,
        directory: String? = nil,
        prettyPrint: Bool = true,
        sortKeys: Bool = true,
    ) {
        self.mode = mode
        self.directory = directory
        self.prettyPrint = prettyPrint
        self.sortKeys = sortKeys
    }

    // MARK: Public

    /// Output mode.
    public var mode: OutputMode

    /// Output directory (for separate mode).
    public var directory: String?

    /// Whether to pretty-print JSON.
    public var prettyPrint: Bool

    /// Whether to sort keys alphabetically.
    public var sortKeys: Bool
}

// MARK: - OutputMode

/// Output mode for translations.
public enum OutputMode: String, Codable, Sendable, Equatable {
    case inPlace = "in-place"
    case separate
}

// MARK: - ValidationSettings

/// Settings for translation validation.
public struct ValidationSettings: Codable, Sendable, Equatable {
    // MARK: Lifecycle

    public init(
        requireAllLanguages: Bool = true,
        validateFormatters: Bool = true,
        maxLength: Int = 0,
        warnMissingComments: Bool = false,
    ) {
        self.requireAllLanguages = requireAllLanguages
        self.validateFormatters = validateFormatters
        self.maxLength = maxLength
        self.warnMissingComments = warnMissingComments
    }

    // MARK: Public

    /// Require all target languages to have translations.
    public var requireAllLanguages: Bool

    /// Validate format specifier consistency.
    public var validateFormatters: Bool

    /// Maximum string length (0 = no limit).
    public var maxLength: Int

    /// Warn on missing comments.
    public var warnMissingComments: Bool
}

// MARK: - ContextSettings

/// Settings for context-aware translation.
public struct ContextSettings: Codable, Sendable, Equatable {
    // MARK: Lifecycle

    public init(
        app: AppContext? = nil,
        depth: ContextDepth = .standard,
        projectRoot: String? = nil,
        sourceCode: SourceCodeSettings? = nil,
        translationMemory: TranslationMemorySettings? = nil,
        glossary: GlossarySettings? = nil,
        comments: CommentsSettings? = nil,
        includeGitContext: Bool = false,
    ) {
        self.app = app
        self.depth = depth
        self.projectRoot = projectRoot
        self.sourceCode = sourceCode
        self.translationMemory = translationMemory
        self.glossary = glossary
        self.comments = comments
        self.includeGitContext = includeGitContext
    }

    // MARK: Public

    /// Application context.
    public var app: AppContext?

    /// Context extraction depth.
    public var depth: ContextDepth

    /// Project root path (absolute). Used for source code analysis.
    public var projectRoot: String?

    /// Source code analysis settings.
    public var sourceCode: SourceCodeSettings?

    /// Translation memory settings.
    public var translationMemory: TranslationMemorySettings?

    /// Glossary settings.
    public var glossary: GlossarySettings?

    /// Developer comments settings.
    public var comments: CommentsSettings?

    /// Include git blame context.
    public var includeGitContext: Bool
}

// MARK: - ContextDepth

/// Depth of context extraction.
public enum ContextDepth: String, Codable, Sendable, Equatable, CaseIterable {
    /// No context extraction (fastest).
    case none
    /// Key usage locations only.
    case minimal
    /// Usage + surrounding code.
    case standard
    /// Full file analysis with UI element detection.
    case deep
}

// MARK: - AppContext

/// Application context for translation.
public struct AppContext: Codable, Sendable, Equatable {
    // MARK: Lifecycle

    public init(
        name: String,
        description: String? = nil,
        domain: String? = nil,
        tone: Tone? = nil,
        formality: FormalityLevel? = nil,
    ) {
        self.name = name
        self.description = description
        self.domain = domain
        self.tone = tone
        self.formality = formality
    }

    // MARK: Public

    /// Application name.
    public var name: String

    /// Application description.
    public var description: String?

    /// Application domain (e.g., "automotive", "fitness").
    public var domain: String?

    /// Desired tone.
    public var tone: Tone?

    /// Desired formality level.
    public var formality: FormalityLevel?
}

// MARK: - Tone

/// Tone for translations.
public enum Tone: String, Codable, Sendable, Equatable {
    case friendly
    case professional
    case casual
    case formal
    case technical
}

// MARK: - FormalityLevel

/// Formality level for translations.
public enum FormalityLevel: String, Codable, Sendable, Equatable {
    case informal
    case neutral
    case formal
}

// MARK: - SourceCodeSettings

/// Source code analysis settings.
public struct SourceCodeSettings: Codable, Sendable, Equatable {
    // MARK: Lifecycle

    public init(
        enabled: Bool = true,
        paths: [String] = ["Sources/**/*.swift"],
        exclude: [String] = ["**/*Tests*/**"],
    ) {
        self.enabled = enabled
        self.paths = paths
        self.exclude = exclude
    }

    // MARK: Public

    /// Whether source code analysis is enabled.
    public var enabled: Bool

    /// Paths to analyze.
    public var paths: [String]

    /// Paths to exclude.
    public var exclude: [String]
}

// MARK: - TranslationMemorySettings

/// Translation memory settings.
public struct TranslationMemorySettings: Codable, Sendable, Equatable {
    // MARK: Lifecycle

    public init(
        enabled: Bool = true,
        file: String = ".swiftlocalize-tm.json",
        minSimilarity: Double = 0.7,
        maxMatches: Int = 5,
    ) {
        self.enabled = enabled
        self.file = file
        self.minSimilarity = minSimilarity
        self.maxMatches = maxMatches
    }

    // MARK: Public

    /// Whether translation memory is enabled.
    public var enabled: Bool

    /// Storage file path.
    public var file: String

    /// Minimum similarity for matches.
    public var minSimilarity: Double

    /// Maximum number of matches to return.
    public var maxMatches: Int
}

// MARK: - GlossarySettings

/// Glossary settings.
public struct GlossarySettings: Codable, Sendable, Equatable {
    // MARK: Lifecycle

    public init(
        enabled: Bool = true,
        file: String? = nil,
        terms: [GlossaryTerm]? = nil,
    ) {
        self.enabled = enabled
        self.file = file
        self.terms = terms
    }

    // MARK: Public

    /// Whether glossary is enabled.
    public var enabled: Bool

    /// Glossary file path.
    public var file: String?

    /// Inline glossary terms.
    public var terms: [GlossaryTerm]?
}

// MARK: - GlossaryTerm

/// A glossary term definition.
public struct GlossaryTerm: Codable, Sendable, Equatable {
    // MARK: Lifecycle

    public init(
        term: String,
        definition: String? = nil,
        doNotTranslate: Bool? = nil,
        translations: [String: String]? = nil,
        caseSensitive: Bool? = nil,
    ) {
        self.term = term
        self.definition = definition
        self.doNotTranslate = doNotTranslate
        self.translations = translations
        self.caseSensitive = caseSensitive
    }

    // MARK: Public

    /// The term.
    public var term: String

    /// Definition or context.
    public var definition: String?

    /// Whether to keep the term untranslated.
    public var doNotTranslate: Bool?

    /// Translations by language code.
    public var translations: [String: String]?

    /// Case sensitivity.
    public var caseSensitive: Bool?
}

// MARK: - CommentsSettings

/// Developer comments settings.
public struct CommentsSettings: Codable, Sendable, Equatable {
    // MARK: Lifecycle

    public init(
        includeInPrompt: Bool = true,
        warnMissing: Bool = false,
    ) {
        self.includeInPrompt = includeInPrompt
        self.warnMissing = warnMissing
    }

    // MARK: Public

    /// Include xcstrings comments in translation prompts.
    public var includeInPrompt: Bool

    /// Warn if strings lack comments.
    public var warnMissing: Bool
}

// MARK: - LoggingSettings

/// Settings for logging.
public struct LoggingSettings: Codable, Sendable, Equatable {
    // MARK: Lifecycle

    public init(
        level: LogLevel = .info,
        format: LogFormat = .console,
        file: String? = nil,
    ) {
        self.level = level
        self.format = format
        self.file = file
    }

    // MARK: Public

    /// Log level.
    public var level: LogLevel

    /// Output format.
    public var format: LogFormat

    /// Log file path (optional).
    public var file: String?
}

// MARK: - LogLevel

/// Log levels.
public enum LogLevel: String, Codable, Sendable, Equatable, Comparable {
    case debug
    case info
    case warn
    case error

    // MARK: Public

    public static func < (lhs: LogLevel, rhs: LogLevel) -> Bool {
        let order: [LogLevel] = [.debug, .info, .warn, .error]
        guard let lhsIndex = order.firstIndex(of: lhs),
              let rhsIndex = order.firstIndex(of: rhs)
        else {
            return false
        }
        return lhsIndex < rhsIndex
    }
}

// MARK: - LogFormat

/// Log output formats.
public enum LogFormat: String, Codable, Sendable, Equatable {
    case console
    case json
}
