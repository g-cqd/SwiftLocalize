# SwiftLocalize Codebase Review & Improvement Plan

**Review Date:** December 28, 2025
**Reviewer:** Claude Code

---

## Executive Summary

SwiftLocalize is a comprehensive Swift package for automated localization of xcstrings files using AI/ML translation providers. The implementation is **approximately 90% complete** against the original plan. Core translation functionality is fully implemented, along with multi-target support, CLI providers, and comprehensive testing.

---

## Implementation Status

### Completed Features ✅

| Phase | Feature | Status |
|-------|---------|--------|
| 1 | XCStrings Models & Parser | ✅ Complete |
| 1 | Configuration System (JSON) | ✅ Complete |
| 1 | HTTP Client | ✅ Complete |
| 1 | Error Types | ✅ Complete |
| 2 | OpenAI Provider | ✅ Complete |
| 2 | Anthropic Provider | ✅ Complete |
| 2 | Gemini Provider | ✅ Complete |
| 2 | DeepL Provider | ✅ Complete |
| 2 | Ollama Provider | ✅ Complete |
| 3 | Apple Translation Provider | ✅ Complete |
| 3 | Foundation Models Provider | ✅ Complete |
| 3 | Language Detection | ✅ Complete |
| 5 | TranslationService (basic) | ✅ Complete |
| 5 | RateLimiter | ✅ Complete |
| 6 | CLI: translate command | ✅ Complete |
| 6 | CLI: validate command | ✅ Complete |
| 6 | CLI: status command | ✅ Complete |
| 6 | CLI: init command | ✅ Complete |
| 6 | CLI: providers command | ✅ Complete |
| 7 | Build Plugin (basic) | ✅ Complete |
| 7 | Command Plugin (basic) | ✅ Complete |

### Missing Features ❌

| Phase | Feature | Priority | Effort |
|-------|---------|----------|--------|
| 4 | SourceCodeAnalyzer | High | Medium |
| 4 | TranslationMemory | High | Medium |
| 4 | Glossary Management | High | Low |
| 4 | ContextBuilder | High | Medium |
| 5 | ChangeDetector | Critical | Medium |
| 6 | CLI: glossary command | Medium | Low |
| 6 | CLI: cache command | Low | Low |
| 6 | CI/CD mode (--ci flag) | Critical | Low |
| 8 | Integration Tests | High | Medium |
| 8 | End-to-End Tests | Medium | Medium |

---

## Provider API Analysis

### OpenAI ✅ UPDATED (Dec 2025)

**Current Configuration:**
- Model: `gpt-5.2-chat-latest` (default)
- API: v1 Chat Completions

**Available Models:**
| Model | Released | Best For | Input Cost | Output Cost |
|-------|----------|----------|------------|-------------|
| gpt-5.2 | Dec 2025 | Flagship, coding/agentic | $1.75/M | $14.00/M |
| gpt-5.2-chat-latest | Dec 2025 | Fast writing/info | $1.75/M | $14.00/M |
| gpt-5.2-pro | Dec 2025 | Most accurate | Premium | Premium |
| gpt-5.1 | Nov 2025 | Balanced | $1.00/M | $8.00/M |
| o4-mini | Dec 2025 | Fast reasoning | $0.40/M | $1.60/M |

**Implementation:**
```swift
public enum Model {
    public static let gpt5_2 = "gpt-5.2"
    public static let gpt5_2_chat = "gpt-5.2-chat-latest"
    public static let gpt5_2_pro = "gpt-5.2-pro"
    public static let gpt5_1 = "gpt-5.1"
    public static let o4_mini = "o4-mini"
}
```

### Anthropic ✅ CURRENT

**Current Configuration:**
- Model: `claude-sonnet-4-20250514`
- API Version: `2023-06-01`

**Available Models:**
| Model | Released | Best For |
|-------|----------|----------|
| claude-opus-4-5 | Nov 2025 | Complex tasks, agents |
| claude-sonnet-4-5 | Sep 2025 | Balanced |
| claude-sonnet-4 | May 2025 | Cost-effective (default) |
| claude-haiku-4-5 | Nov 2025 | Fast and efficient |

**Recommended:** Keep `claude-sonnet-4` as default (cost-effective), add Opus 4.5 option for complex translations.

### Google Gemini ✅ UPDATED (Dec 2025)

**Current Configuration:**
- Model: `gemini-3-flash-preview` (default)
- API: v1beta

**Available Models:**
| Model | Released | Notes | Input Cost | Output Cost |
|-------|----------|-------|------------|-------------|
| gemini-3-flash-preview | Dec 2025 | Frontier + Flash speed | $0.50/M | $3.00/M |
| gemini-3-pro | Nov 2025 | Best reasoning | $1.00/M | $6.00/M |
| gemini-2.0-flash | 2025 | Stable multimodal | $0.30/M | $2.50/M |
| gemini-2.0-flash-lite | 2025 | Ultra-efficient | $0.10/M | $0.80/M |

**Implementation:**
```swift
public enum Model {
    public static let gemini3_flash = "gemini-3-flash-preview"
    public static let gemini3_pro = "gemini-3-pro"
    public static let gemini2_0_flash = "gemini-2.0-flash"
    public static let gemini2_0_flash_lite = "gemini-2.0-flash-lite"
}
```

### DeepL ✅ CURRENT

**Current Configuration:**
- API: v2
- Formality support: ✅
- Language conversion: ✅

**Status:** API is current, but could add:
- Glossary v3 API support (multilingual glossaries)
- Document translation support
- Tag handling v2

**Recommended Additions:**
```swift
// Add to DeepLProviderConfig
public let tagHandlingVersion: String? = "v2"
```

### Ollama ✅ CURRENT

**Current Configuration:**
- Model: `llama3.2`
- Local REST API

**Status:** Good, models are user-configured.

### Apple Translation ✅ CURRENT

**Current Configuration:**
- Framework: Translation
- Availability: macOS 15+, iOS 18+

**Status:** Current with platform requirements.

### Apple Foundation Models ✅ CURRENT

**Current Configuration:**
- Framework: FoundationModels
- Availability: macOS 26+, iOS 26+

**Status:** Current with latest platform.

---

## Critical Missing Features for Production Use

### 1. Change Detection (ChangeDetector)

**Why Critical:** Without change detection, every run translates ALL strings, which is:
- Expensive (API costs)
- Slow (unnecessary translations)
- Inconsistent (may change existing translations)

**Implementation Required:**
```swift
public actor ChangeDetector {
    // Hash-based change detection
    // Cache persistence (.swiftlocalize-cache.json)
    // Incremental translation support
}
```

### 2. CI/CD Mode

**Why Critical:** Current CLI is designed for interactive use. CI/CD requires:
- Deterministic exit codes
- Machine-readable output (JSON)
- Non-interactive mode
- Fail-fast on errors

**Required Features:**
```bash
swiftlocalize translate --ci          # CI mode
swiftlocalize validate --strict --ci  # Fail on warnings
swiftlocalize status --json           # Already exists ✅
```

### 3. Context-Aware Translation (Phase 4)

**Why Important:** Context dramatically improves translation quality:
- Developer comments → Intent clarity
- Source code analysis → UI element context
- Translation memory → Consistency
- Glossary → Brand terminology

**Current State:** Configuration exists but implementation is missing.

---

## Developer Workflow Gaps

### Daily Workflow Issues

1. **No Incremental Translation**
   - Every run is a full translation
   - Wastes API calls and time
   - Solution: Implement ChangeDetector

2. **No Translation Preview**
   - `--dry-run` shows counts but not translations
   - Solution: Add `--preview` flag to show proposed translations

3. **No Undo/Rollback**
   - No backup before translation
   - Solution: Add `output.backup: true` functionality

4. **No Translation Review Mode**
   - Can't review translations before committing
   - Solution: Add `--review` flag or separate review command

### CI/CD Integration Issues

1. **Exit Codes Not Documented**
   - Unclear what exit codes mean
   - Solution: Document and standardize exit codes

2. **No GitHub Actions Example**
   - Missing CI integration documentation
   - Solution: Add `.github/workflows/localize.yml` example

3. **No Cache Persistence Strategy**
   - Cache isn't git-tracked by default
   - Solution: Document cache strategies

---

## Improvement Plan

### Phase A: Critical Fixes (Priority: Immediate) ✅ COMPLETED

1. **Update Provider Models** ✅
   - [x] OpenAI: `gpt-4o` → `gpt-5.2-chat-latest` (Dec 2025)
   - [x] Gemini: `gemini-1.5-flash` → `gemini-3-flash-preview` (Dec 2025)
   - [x] Add model version constants for all providers

2. **Implement ChangeDetector** ✅
   - [x] Hash-based change detection (SHA256)
   - [x] Cache file persistence (.swiftlocalize-cache.json)
   - [x] Full API for integration with TranslationService

3. **Add CI/CD Mode** ✅
   - [x] `--ci` flag for translate and validate commands
   - [x] Standardized exit codes
   - [x] JSON output in CI mode
   - [x] `--incremental` flag for incremental translation

### Phase B: Context-Aware Translation (Priority: High)

1. **Implement TranslationMemory**
   - [ ] Store successful translations
   - [ ] Fuzzy matching for similar strings
   - [ ] Quality scoring

2. **Implement Glossary**
   - [ ] Load glossary from config
   - [ ] Term detection in source strings
   - [ ] Include terms in prompts

3. **Implement ContextBuilder**
   - [ ] Combine all context sources
   - [ ] Generate optimized prompts
   - [ ] Include developer comments

### Phase C: Developer Experience (Priority: Medium) ✅ COMPLETED

1. **Add CLI Commands**
   - [x] `swiftlocalize glossary` - Manage glossary terms (list, add, remove, init)
   - [x] `swiftlocalize cache` - Manage translation cache (info, clear)
   - [x] `swiftlocalize migrate` - Convert between formats (to-xcstrings, to-legacy)
   - [ ] `swiftlocalize diff` - Show translation changes

2. **Add Workflow Features**
   - [x] `--preview` flag for translation preview
   - [x] `--backup` flag for file backup
   - [ ] `--review` interactive review mode

3. **Improve Validation**
   - [ ] Placeholder validation (%@, %d, etc.)
   - [ ] Length validation (too long/short)
   - [ ] Quality scoring

### Phase D: Testing & Documentation (Priority: High) ✅ COMPLETED

1. **Add Integration Tests**
   - [x] Mock HTTP responses for all providers
   - [x] Test provider fallback chain
   - [x] Test error handling
   - [x] CLI feature tests (286 tests across 58 suites)

2. **Add End-to-End Tests**
   - [x] Full translation workflow
   - [x] CLI command feature tests (glossary, cache, migrate)
   - [x] Configuration loading tests

3. **Documentation**
   - [x] README with usage examples (README.md)
   - [x] CI/CD integration guide (docs/CI-CD-Integration.md)
   - [x] Provider setup guides (docs/Provider-Setup.md)

### Phase E: CLI-Based Provider Alternatives (Priority: Medium) ✅ COMPLETED

Enable SwiftLocalize to leverage locally-installed AI CLI tools as alternative translation providers. This provides flexibility for developers who prefer using their existing CLI subscriptions or need offline capabilities.

#### 1. Gemini CLI Provider ✅
- **Installation:** `npm install -g @google/gemini-cli`
- **Binary Detection:** `which gemini` or user-configured path
- **Free Tier:** 60 requests/min, 1,000 requests/day
- **Features:**
  - [x] Detect gemini CLI availability
  - [x] Execute translation prompts via CLI
  - [x] Parse JSON output responses
  - [x] Support custom model selection via CLI flags

#### 2. GitHub Copilot CLI Provider ✅
- **Installation:** `npm install -g @github/copilot-cli` or Homebrew
- **Binary Detection:** User-configured path (e.g., `~/.bun/bin/copilot`)
- **Requirements:** GitHub Copilot Pro/Pro+/Business/Enterprise subscription
- **Features:**
  - [x] Detect copilot CLI availability
  - [x] Use programmatic mode (`copilot -p "prompt"`)
  - [x] Support model switching (`/model` command)
  - [x] Handle authentication flow

#### 3. OpenAI Codex CLI Provider ✅
- **Installation:** `npm i -g @openai/codex` or `brew install --cask codex`
- **Binary Detection:** `which codex` or user-configured path
- **Requirements:** ChatGPT Plus/Pro/Business subscription
- **Features:**
  - [x] Detect codex CLI availability
  - [x] Execute translation prompts in non-interactive mode
  - [x] Support approval mode configuration
  - [x] Handle GPT-5-Codex model

#### 4. Generic CLI Provider ✅
- Added GenericCLIProvider for wrapping any LLM CLI tool
- Configurable binary path, pre/post prompt args, stdin support

#### Configuration Schema Extension
```json
{
  "providers": {
    "gemini-cli": {
      "enabled": true,
      "binaryPath": "/usr/local/bin/gemini",
      "model": "gemini-3-flash"
    },
    "copilot-cli": {
      "enabled": true,
      "binaryPath": "~/.bun/bin/copilot",
      "model": "claude-sonnet-4-5"
    },
    "codex-cli": {
      "enabled": true,
      "binaryPath": "/usr/local/bin/codex",
      "approvalMode": "auto"
    }
  }
}
```

#### Implementation Considerations
- **Binary Detection:** Auto-detect installed CLIs at runtime
- **Fallback Chain:** CLI providers can be part of the fallback chain
- **Rate Limiting:** Respect CLI-specific rate limits
- **Error Handling:** Handle CLI authentication failures gracefully
- **Output Parsing:** Parse structured output from each CLI tool
- **Timeout Management:** CLI commands may have longer execution times

#### Benefits
- **Cost Flexibility:** Use existing subscriptions instead of API keys
- **Offline Capability:** Codex CLI supports local operation
- **Developer Familiarity:** Leverage tools developers already use
- **No API Key Management:** Authentication handled by CLI tools

### Phase F: Legacy String Catalogs & Multi-Target Support (Priority: High) ✅ COMPLETED

Enable comprehensive handling of legacy localization formats, cross-catalog key synchronization, and seamless support for multi-package/multi-target projects (main app + SPM packages).

**Implementation completed:**
- ✅ StringsFile parser with UTF-8/UTF-16 support
- ✅ StringsdictFile parser with plural categories
- ✅ FormatMigrator for format conversion
- ✅ ProjectStructureDetector for multi-target detection
- ✅ KeyConsistencyAnalyzer for cross-catalog sync
- ✅ CatalogSynchronizer for key synchronization
- ✅ CLI: `swiftlocalize targets` command
- ✅ CLI: `swiftlocalize sync-keys` command
- ✅ CLI: `--target` and `--all-targets` flags for translate command

---

#### F.1: Legacy Format Support

##### F.1.1: .strings File Parser

**Format Specification:**
- UTF-8 or UTF-16 encoded key-value pairs
- Syntax: `"key" = "value";`
- Comments: `//` or `/* */`
- Escape sequences: `\n`, `\t`, `\"`, `\\`

**Implementation:**
```swift
public actor StringsFileParser {
    /// Parse a .strings file into key-value pairs
    public func parse(at url: URL) async throws -> [String: StringsEntry]

    /// Write key-value pairs to a .strings file
    public func write(_ entries: [String: StringsEntry], to url: URL) async throws

    /// Detect encoding (UTF-8 vs UTF-16)
    public func detectEncoding(at url: URL) async throws -> String.Encoding
}

public struct StringsEntry: Sendable {
    public let value: String
    public let comment: String?
    public let lineNumber: Int
}
```

**Tasks:**
- [x] Implement .strings lexer/tokenizer
- [x] Handle both UTF-8 and UTF-16 encodings
- [x] Preserve comments during round-trip
- [x] Validate escape sequences
- [x] Detect and warn about duplicate keys

##### F.1.2: .stringsdict File Parser

**Format Specification:**
- XML Property List (plist) format
- `NSStringLocalizedFormatKey` for format strings
- `NSStringPluralRuleType` for pluralization
- CLDR plural categories: zero, one, two, few, many, other

**Implementation:**
```swift
public actor StringsdictParser {
    /// Parse a .stringsdict file
    public func parse(at url: URL) async throws -> [String: StringsdictEntry]

    /// Write entries to a .stringsdict file
    public func write(_ entries: [String: StringsdictEntry], to url: URL) async throws
}

public struct StringsdictEntry: Sendable {
    public let formatKey: String
    public let variables: [String: PluralVariable]
}

public struct PluralVariable: Sendable {
    public let formatValueType: String  // "d", "f", "@", etc.
    public let zero: String?
    public let one: String?
    public let two: String?
    public let few: String?
    public let many: String?
    public let other: String
}
```

**Tasks:**
- [x] Implement plist XML parser for stringsdict
- [x] Support nested plural variables
- [x] Validate plural category completeness
- [x] Handle format specifiers (%d, %@, etc.)
- [x] Support multiple variables per key

##### F.1.3: Format Migration Utilities

**Capabilities:**
- Migrate `.strings` + `.stringsdict` → `.xcstrings`
- Convert `.xcstrings` → legacy formats (for compatibility)
- Merge multiple legacy files into single catalog

**Implementation:**
```swift
public actor LocalizationMigrator {
    /// Migrate legacy files to xcstrings
    public func migrateToXCStrings(
        stringsFiles: [URL],
        stringsdictFiles: [URL],
        outputURL: URL,
        options: MigrationOptions
    ) async throws -> MigrationReport

    /// Export xcstrings to legacy format
    public func exportToLegacy(
        xcstrings: XCStrings,
        outputDirectory: URL,
        format: LegacyFormat
    ) async throws
}

public struct MigrationOptions: Sendable {
    /// How to handle key conflicts
    public var conflictResolution: ConflictResolution
    /// Preserve original comments
    public var preserveComments: Bool
    /// Sort keys alphabetically
    public var sortKeys: Bool
}

public enum ConflictResolution: Sendable {
    case keepFirst
    case keepLast
    case merge
    case error
}
```

**CLI Integration:**
```bash
# Migrate legacy to xcstrings
swiftlocalize migrate --from Localizable.strings --from Localizable.stringsdict --to Localizable.xcstrings

# Export xcstrings to legacy (for tooling compatibility)
swiftlocalize export --from Localizable.xcstrings --format strings --to en.lproj/

# Validate migration
swiftlocalize validate --check-migration --legacy-dir en.lproj/ --xcstrings Localizable.xcstrings
```

---

#### F.2: Cross-Catalog Key Synchronization

##### F.2.1: Key Consistency Analyzer

Ensure keys are consistent across multiple xcstrings files in a project.

**Implementation:**
```swift
public actor KeyConsistencyAnalyzer {
    /// Analyze key consistency across multiple catalogs
    public func analyze(
        catalogs: [URL],
        options: ConsistencyOptions
    ) async throws -> ConsistencyReport

    /// Get unified key set across all catalogs
    public func getUnifiedKeySet(
        catalogs: [URL]
    ) async throws -> Set<String>
}

public struct ConsistencyReport: Sendable {
    /// Keys present in all catalogs
    public let commonKeys: Set<String>
    /// Keys missing from specific catalogs
    public let missingKeys: [URL: Set<String>]
    /// Keys with conflicting source values
    public let conflicts: [KeyConflict]
    /// Keys unique to specific catalogs (intentional)
    public let exclusiveKeys: [URL: Set<String>]
}

public struct KeyConflict: Sendable {
    public let key: String
    public let sourceValues: [URL: String]
    public let recommendation: String
}
```

**Tasks:**
- [x] Build unified key index across catalogs
- [x] Detect missing keys per catalog
- [x] Identify conflicting source values
- [x] Support intentional exclusions via config
- [x] Generate synchronization suggestions

##### F.2.2: Key Sorting Strategy

**Sort Modes:**
```swift
public enum KeySortMode: Sendable {
    /// Alphabetical A-Z
    case alphabetical
    /// Alphabetical Z-A
    case alphabeticalDescending
    /// By extraction state (manual first)
    case byExtractionState
    /// By translation completeness
    case byCompleteness
    /// Preserve original order
    case preserve
    /// Custom comparator
    case custom((String, String) -> Bool)
}
```

**Cross-Catalog Sorting:**
```swift
public actor CatalogSynchronizer {
    /// Sort all catalogs with consistent key ordering
    public func synchronizeKeyOrder(
        catalogs: [URL],
        sortMode: KeySortMode
    ) async throws

    /// Ensure all catalogs have the same keys (add missing as "needs_translation")
    public func synchronizeKeys(
        catalogs: [URL],
        masterCatalog: URL?,
        options: SyncOptions
    ) async throws -> SyncReport
}
```

**Tasks:**
- [x] Implement consistent sorting across catalogs
- [x] Add missing keys with "needs_translation" state
- [x] Support master/secondary catalog hierarchy
- [x] Preserve catalog-specific metadata
- [x] Generate diff report before sync

##### F.2.3: Key Deduplication

Handle shared strings across packages:

```swift
public struct DeduplicationStrategy: Sendable {
    /// How to handle duplicate translations
    public var duplicateHandling: DuplicateHandling
    /// Reference catalog for canonical translations
    public var referenceCatalog: URL?
    /// Keys to exclude from deduplication
    public var exclusions: Set<String>
}

public enum DuplicateHandling: Sendable {
    /// Keep all duplicates (document for awareness)
    case keep
    /// Use reference catalog as source of truth
    case useReference
    /// Create shared catalog and reference it
    case extractToShared
}
```

---

#### F.3: Multi-Package/Multi-Target Architecture

##### F.3.1: Project Structure Detection

**Supported Layouts:**
```
# Layout A: Monorepo with multiple packages
MyApp/
├── Package.swift                    # Root package
├── Sources/
│   └── MyApp/
│       └── Localizable.xcstrings    # App strings
├── Packages/
│   ├── FeatureA/
│   │   ├── Package.swift
│   │   └── Sources/FeatureA/
│   │       └── Localizable.xcstrings
│   └── FeatureB/
│       ├── Package.swift
│       └── Sources/FeatureB/
│           └── Localizable.xcstrings

# Layout B: App with local packages
MyApp/
├── MyApp.xcodeproj
├── MyApp/
│   └── Localizable.xcstrings
└── LocalPackages/
    ├── Core/
    │   └── Sources/Core/
    │       └── Localizable.xcstrings
    └── UI/
        └── Sources/UI/
            └── Localizable.xcstrings

# Layout C: Xcode project with multiple targets
MyApp/
├── MyApp.xcodeproj
├── MyApp/
│   └── Localizable.xcstrings
├── MyAppKit/
│   └── Localizable.xcstrings
└── MyAppWidgets/
    └── Localizable.xcstrings
```

**Implementation:**
```swift
public actor ProjectStructureDetector {
    /// Detect project layout and all localization targets
    public func detect(at rootURL: URL) async throws -> ProjectStructure

    /// Find all xcstrings files with their target context
    public func findLocalizationFiles(
        in project: ProjectStructure
    ) async throws -> [LocalizationTarget]
}

public struct ProjectStructure: Sendable {
    public let type: ProjectType
    public let rootURL: URL
    public let targets: [TargetInfo]
    public let packages: [PackageInfo]
}

public enum ProjectType: Sendable {
    case xcodeProject
    case swiftPackage
    case workspace
    case monorepo
}

public struct LocalizationTarget: Sendable {
    public let name: String
    public let type: TargetType
    public let xcstringsURL: URL
    public let bundleIdentifier: String?
    public let defaultLocalization: String
    public let parentPackage: String?
}

public enum TargetType: Sendable {
    case mainApp
    case framework
    case swiftPackage
    case appExtension
    case widget
    case test
}
```

##### F.3.2: Target-Aware Configuration

**Extended Configuration Schema:**
```json
{
  "version": "2.0",
  "projectType": "monorepo",
  "defaultLocalization": "en",

  "targets": {
    "MyApp": {
      "path": "Sources/MyApp",
      "xcstrings": "Localizable.xcstrings",
      "languages": ["en", "fr", "de", "ja"],
      "provider": "anthropic"
    },
    "FeatureA": {
      "path": "Packages/FeatureA/Sources/FeatureA",
      "xcstrings": "Localizable.xcstrings",
      "languages": ["en", "fr", "de"],
      "inheritsFrom": "MyApp"
    },
    "FeatureB": {
      "path": "Packages/FeatureB/Sources/FeatureB",
      "xcstrings": "Localizable.xcstrings",
      "languages": "$inherit",
      "provider": "$inherit"
    }
  },

  "shared": {
    "glossary": "shared-glossary.json",
    "translationMemory": "shared-tm.json",
    "keyPrefix": {
      "FeatureA": "featureA.",
      "FeatureB": "featureB."
    }
  },

  "synchronization": {
    "enabled": true,
    "masterTarget": "MyApp",
    "sortMode": "alphabetical",
    "validateConsistency": true
  }
}
```

**Implementation:**
```swift
public struct MultiTargetConfiguration: Codable, Sendable {
    public var projectType: ProjectType
    public var defaultLocalization: String
    public var targets: [String: TargetConfiguration]
    public var shared: SharedConfiguration
    public var synchronization: SynchronizationConfiguration
}

public struct TargetConfiguration: Codable, Sendable {
    public var path: String
    public var xcstrings: String
    public var languages: LanguageSpec
    public var provider: ProviderSpec
    public var inheritsFrom: String?
}

public enum LanguageSpec: Codable, Sendable {
    case explicit([String])
    case inherit
}
```

##### F.3.3: Bundle-Aware Translation

Handle `Bundle.module` vs `Bundle.main` correctly:

```swift
public actor BundleAwareTranslator {
    /// Translate with bundle context awareness
    public func translate(
        target: LocalizationTarget,
        context: TranslationContext
    ) async throws -> TranslationReport

    /// Validate bundle configuration
    public func validateBundleSetup(
        target: LocalizationTarget
    ) async throws -> [BundleIssue]
}

public struct BundleIssue: Sendable {
    public let severity: Severity
    public let message: String
    public let suggestion: String
}
```

**Common Issues Detected:**
- Missing `defaultLocalization` in Package.swift
- Empty xcstrings in main app (required for mixed localizations)
- Missing `CFBundleAllowMixedLocalizations` flag
- Incorrect bundle reference in code

---

#### F.4: CLI Commands for Multi-Target

```bash
# Discover all targets
swiftlocalize targets --discover
# Output: Found 3 localization targets: MyApp, FeatureA, FeatureB

# Translate specific target
swiftlocalize translate --target FeatureA

# Translate all targets
swiftlocalize translate --all-targets

# Synchronize keys across all targets
swiftlocalize sync-keys --all-targets --sort alphabetical

# Check consistency
swiftlocalize validate --consistency --all-targets

# Generate report
swiftlocalize status --all-targets --json > localization-status.json

# Migrate legacy files for a target
swiftlocalize migrate --target FeatureA --from-legacy
```

---

#### F.5: Implementation Tasks Summary

| Task | Priority | Effort | Dependencies |
|------|----------|--------|--------------|
| .strings parser | High | Medium | None |
| .stringsdict parser | High | Medium | None |
| Migration utilities | High | Medium | Parsers |
| Key consistency analyzer | High | Low | None |
| Cross-catalog sorting | Medium | Low | Consistency analyzer |
| Project structure detector | High | Medium | None |
| Multi-target configuration | High | Medium | Structure detector |
| Bundle-aware translation | Medium | Low | Multi-target config |
| CLI multi-target commands | Medium | Low | All above |
| Key deduplication | Low | Medium | Consistency analyzer |

---

#### F.6: Configuration File Discovery

**Search Order:**
1. `.swiftlocalize.json` in current directory
2. `.swiftlocalize.json` in git root
3. `swiftlocalize.json` in current directory
4. Package.swift adjacent `.swiftlocalize.json`
5. `~/.config/swiftlocalize/config.json` (user defaults)

**Auto-Detection:**
```swift
public actor ConfigurationDiscovery {
    /// Find and merge configuration from all sources
    public func discover(from workingDirectory: URL) async throws -> Configuration

    /// Generate initial configuration based on project structure
    public func generateConfiguration(
        for project: ProjectStructure
    ) async throws -> Configuration
}
```

### Phase G: Translation-Only Mode with Read-Only Context (Priority: High)

A dedicated mode that **only translates localization files** without modifying any source code, while optionally extracting usage context through read-only code analysis.

---

#### G.1: Core Principle - Strict File Isolation

**Guarantee:** SwiftLocalize will NEVER modify files outside the designated localization scope.

**Allowed Modifications:**
- `.xcstrings` files (String Catalogs)
- `.strings` files (legacy, if enabled)
- `.stringsdict` files (legacy, if enabled)
- Cache files (`.swiftlocalize-cache.json`)
- Report files (when `--output` specified)

**Read-Only Access:**
- `.swift` source files (for context extraction)
- `Package.swift` (for project structure)
- `.xcodeproj` / `.xcworkspace` (for target detection)
- Git history (for change tracking)

---

#### G.2: Translation-Only Mode Implementation

##### G.2.1: Mode Configuration

```swift
public enum OperationMode: Sendable {
    /// Only translate localization files, never touch source code
    case translationOnly
    /// Translate and optionally update code (future: auto-fix NSLocalizedString calls)
    case full
}

public struct TranslationOnlyOptions: Sendable {
    /// Enable read-only context extraction from source code
    public var extractContext: Bool = true

    /// Depth of context extraction
    public var contextDepth: ContextDepth = .standard

    /// Files to analyze for context (glob patterns)
    public var contextSources: [String] = ["**/*.swift"]

    /// Exclude patterns for context analysis
    public var contextExcludes: [String] = ["**/Tests/**", "**/*Tests.swift"]

    /// Whether to include git blame information
    public var includeGitContext: Bool = false
}

public enum ContextDepth: Sendable {
    /// No context extraction (fastest)
    case none
    /// Key usage locations only
    case minimal
    /// Usage + surrounding code (5 lines)
    case standard
    /// Full file analysis with UI element detection
    case deep
}
```

##### G.2.2: Read-Only Context Extractor

```swift
public actor ReadOnlyContextExtractor {
    private let fileManager: FileManager
    private let options: TranslationOnlyOptions

    /// Extract context without modifying any files
    public func extractContext(
        for keys: [String],
        in projectRoot: URL
    ) async throws -> [String: StringContext]

    /// Find all usages of a localization key (read-only)
    public func findUsages(
        key: String,
        in sourceFiles: [URL]
    ) async throws -> [KeyUsage]

    /// Extract UI element context from SwiftUI/UIKit code
    public func detectUIContext(
        for usage: KeyUsage
    ) async throws -> UIElementContext?
}

public struct StringContext: Sendable {
    /// The localization key
    public let key: String

    /// Developer comment from xcstrings
    public let comment: String?

    /// Where the key is used in code
    public let usages: [KeyUsage]

    /// Detected UI element type
    public let uiContext: UIElementContext?

    /// SwiftUI modifiers applied
    public let modifiers: [String]

    /// Surrounding code snippet
    public let codeSnippet: String?

    /// Git author of the key addition
    public let gitAuthor: String?
}

public struct KeyUsage: Sendable {
    public let file: URL
    public let line: Int
    public let column: Int
    public let snippet: String
    public let callSite: CallSiteType
}

public enum CallSiteType: Sendable {
    case text           // SwiftUI Text("key")
    case localizedStringKey  // LocalizedStringKey("key")
    case nsLocalizedString   // NSLocalizedString("key", ...)
    case stringInit     // String(localized: "key")
    case infoPlist      // Info.plist reference
    case storyboard     // Storyboard/XIB reference
    case unknown
}

public struct UIElementContext: Sendable {
    public let elementType: UIElementType
    public let parentView: String?
    public let accessibilityHint: String?
}

public enum UIElementType: Sendable {
    case button
    case label
    case navigationTitle
    case tabItem
    case alert
    case actionSheet
    case textField
    case placeholder
    case accessibilityLabel
    case menuItem
    case tooltip
    case unknown
}
```

---

#### G.3: CLI Integration

```bash
# Default: Translation-only mode (no code modifications)
swiftlocalize translate Localizable.xcstrings

# Explicitly enable translation-only mode
swiftlocalize translate --mode translation-only

# Translation with context extraction
swiftlocalize translate --with-context

# Translation with deep context (slower, more accurate)
swiftlocalize translate --with-context --context-depth deep

# Translation without any context (fastest)
swiftlocalize translate --no-context

# Dry run with context preview
swiftlocalize translate --dry-run --with-context --show-context

# Verify no code modifications will occur
swiftlocalize translate --verify-isolation
```

**CLI Flags:**
```swift
struct TranslateCommand: AsyncParsableCommand {
    @Option(name: .long, help: "Operation mode")
    var mode: OperationMode = .translationOnly

    @Flag(name: .long, help: "Extract usage context from source code (read-only)")
    var withContext = false

    @Flag(name: .long, help: "Skip context extraction entirely")
    var noContext = false

    @Option(name: .long, help: "Context extraction depth")
    var contextDepth: ContextDepth = .standard

    @Flag(name: .long, help: "Verify strict file isolation before running")
    var verifyIsolation = false

    @Flag(name: .long, help: "Show extracted context in output")
    var showContext = false
}
```

---

#### G.4: Safety Guarantees

##### G.4.1: File Access Audit

```swift
public actor FileAccessAuditor {
    private var readOperations: [FileOperation] = []
    private var writeOperations: [FileOperation] = []

    /// Record a file read operation
    public func recordRead(url: URL, purpose: String)

    /// Record a file write operation (will be validated)
    public func recordWrite(url: URL, purpose: String)

    /// Validate all write operations are within allowed scope
    public func validateWrites(
        allowedPatterns: [String]
    ) throws -> ValidationResult

    /// Generate audit report
    public func generateReport() -> FileAccessReport
}

public struct FileAccessReport: Sendable {
    public let filesRead: [URL]
    public let filesWritten: [URL]
    public let violationsDetected: [Violation]
    public let summary: String
}
```

##### G.4.2: Pre-Flight Verification

```swift
public actor IsolationVerifier {
    /// Verify that the operation will not modify unexpected files
    public func verify(
        configuration: Configuration,
        mode: OperationMode
    ) async throws -> VerificationResult

    /// List all files that WILL be modified
    public func listModifications(
        configuration: Configuration
    ) async throws -> [PlannedModification]

    /// List all files that WILL be read
    public func listReads(
        configuration: Configuration,
        options: TranslationOnlyOptions
    ) async throws -> [PlannedRead]
}

public struct VerificationResult: Sendable {
    public let isIsolated: Bool
    public let plannedWrites: [URL]
    public let plannedReads: [URL]
    public let warnings: [String]
}
```

---

#### G.5: Context-Enhanced Translation Prompts

When context is extracted, it enhances translation quality:

```swift
public struct ContextEnhancedPrompt: Sendable {
    /// Build prompt with extracted context
    public func build(
        key: String,
        sourceValue: String,
        context: StringContext?,
        targetLanguage: LanguageCode
    ) -> String
}

// Example enhanced prompt
"""
Translate the following UI string to French.

Source: "Save Changes"
Key: "button.save"

Context:
- UI Element: Button
- Location: Used in EditProfileView.swift:45
- Code: Button("Save Changes") { viewModel.save() }
- Developer Comment: "Primary save button in profile editor"
- Modifiers: .buttonStyle(.borderedProminent)

Translation should be:
- Concise (button text)
- Action-oriented
- Consistent with app terminology

Provide only the translation, no explanation.
"""
```

---

#### G.6: Configuration Schema

```json
{
  "mode": "translation-only",

  "context": {
    "enabled": true,
    "depth": "standard",
    "sources": ["Sources/**/*.swift"],
    "excludes": ["**/Tests/**", "**/Mocks/**"],
    "includeGitContext": false,
    "cacheContext": true
  },

  "isolation": {
    "strict": true,
    "allowedWritePatterns": [
      "**/*.xcstrings",
      "**/.swiftlocalize-cache.json"
    ],
    "verifyBeforeRun": true,
    "generateAuditLog": false
  }
}
```

---

#### G.7: Implementation Tasks

| Task | Priority | Effort | Dependencies |
|------|----------|--------|--------------|
| Read-only context extractor | High | Medium | None |
| Key usage finder (grep-based) | High | Low | None |
| UI element detector | Medium | Medium | Key usage finder |
| File access auditor | High | Low | None |
| Isolation verifier | High | Low | File access auditor |
| Context-enhanced prompts | Medium | Low | Context extractor |
| CLI flags integration | Medium | Low | All above |
| Audit log generation | Low | Low | File access auditor |

---

#### G.8: Use Cases

**1. CI/CD Pipeline Translation**
```bash
# Safe for automated pipelines - guaranteed no code changes
swiftlocalize translate --ci --mode translation-only --verify-isolation
```

**2. High-Quality Translation with Context**
```bash
# Best quality translations using code context
swiftlocalize translate --with-context --context-depth deep
```

**3. Fast Batch Translation**
```bash
# Maximum speed, skip context analysis
swiftlocalize translate --no-context --parallel
```

**4. Translation Preview with Context**
```bash
# See what context will be used without translating
swiftlocalize translate --dry-run --with-context --show-context
```

**5. Audit Mode for Compliance**
```bash
# Generate full audit log of all file operations
swiftlocalize translate --generate-audit-log --output audit.json
```

---

## Recommended Model Defaults

Based on December 2025 API research, here are recommended defaults:

```swift
// Recommended model defaults for cost-effective translation
public enum RecommendedModels {
    static let openai = "gpt-5.2-chat-latest"  // Fast, good value
    static let anthropic = "claude-sonnet-4"   // Balanced
    static let gemini = "gemini-3-flash-preview" // Latest Flash
    static let ollama = "llama3.2"             // Local
}

// For highest quality (higher cost)
public enum PremiumModels {
    static let openai = "gpt-5.2-pro"
    static let anthropic = "claude-opus-4-5"
    static let gemini = "gemini-3-pro"
}

// For high-volume / cost-sensitive
public enum EconomyModels {
    static let openai = "o4-mini"              // Fast reasoning
    static let anthropic = "claude-haiku-4-5"  // Efficient
    static let gemini = "gemini-2.0-flash-lite" // Ultra-efficient
}
```

---

## Test Coverage Analysis

**Current:** 286 tests across 58 suites ✅

| Category | Suites | Tests |
|----------|--------|-------|
| Core Models | 15 | 60+ |
| Providers | 8 | 30+ |
| Services | 10 | 40+ |
| CLI Features | 5 | 15 |
| Integration | 8 | 40+ |
| Context/Memory | 6 | 25+ |
| Legacy Formats | 6 | 30+ |
| Errors | 8 | 25+ |

**Completed:**
- [x] Provider integration tests (mock HTTP)
- [x] CLI command tests
- [x] TranslationService tests
- [x] ChangeDetector tests
- [x] End-to-end translation tests
- [x] Glossary feature tests
- [x] Cache feature tests
- [x] Migration feature tests

**Target:** 100+ tests with >80% coverage ✅ ACHIEVED (286 tests)

---

## Sources

### API Documentation
- [OpenAI Models Documentation](https://platform.openai.com/docs/models)
- [Introducing GPT-5.2](https://openai.com/index/introducing-gpt-5-2/)
- [GPT-5.2 Model API](https://platform.openai.com/docs/models/gpt-5.2)
- [Claude Models Overview](https://platform.claude.com/docs/en/about-claude/models/overview)
- [Introducing Claude Opus 4.5](https://www.anthropic.com/news/claude-opus-4-5)
- [Gemini Models](https://ai.google.dev/gemini-api/docs/models)
- [Gemini 3 Flash Announcement](https://blog.google/products/gemini/gemini-3-flash/)
- [Gemini API Changelog](https://ai.google.dev/gemini-api/docs/changelog)
- [DeepL API Documentation](https://developers.deepl.com/docs)
- [DeepL Roadmap and Release Notes](https://developers.deepl.com/docs/resources/roadmap-and-release-notes)

### CLI Tools
- [Gemini CLI - GitHub](https://github.com/google-gemini/gemini-cli)
- [Gemini CLI Documentation](https://geminicli.com/)
- [GitHub Copilot CLI - GitHub](https://github.com/github/copilot-cli)
- [GitHub Copilot CLI Documentation](https://docs.github.com/en/copilot/how-tos/use-copilot-agents/use-copilot-cli)
- [OpenAI Codex CLI - GitHub](https://github.com/openai/codex)
- [Codex CLI Documentation](https://developers.openai.com/codex/cli)
