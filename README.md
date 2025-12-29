# SwiftLocalize

Automated localization for Swift projects using AI/ML translation providers.

SwiftLocalize translates your Xcode String Catalogs (`.xcstrings`) files using various translation providers including OpenAI, Anthropic Claude, Google Gemini, DeepL, Ollama, and Apple's on-device Translation framework.

## Features

- **Multiple Translation Providers**: OpenAI, Anthropic, Gemini, DeepL, Ollama, and Apple Translation
- **Context-Aware Translation**: Uses app context, glossary terms, and source code analysis for better translations
- **Incremental Translation**: Only translates new or modified strings to save costs
- **Legacy Format Support**: Migrate between `.strings`/`.stringsdict` and `.xcstrings` formats
- **Glossary Management**: Maintain consistent terminology across translations
- **CI/CD Integration**: JSON output and strict exit codes for automation
- **Swift Package Plugin**: Integrate directly into your Xcode build process

## Installation

### Swift Package Manager

Add to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/your-org/SwiftLocalize.git", from: "0.2.0")
]
```

### Homebrew (Coming Soon)

```bash
brew install swiftlocalize
```

## Quick Start

### 1. Initialize Configuration

```bash
swiftlocalize init
```

This creates `.swiftlocalize.json` in your project root.

### 2. Set Up API Keys

```bash
# For OpenAI
export OPENAI_API_KEY="sk-..."

# For Anthropic
export ANTHROPIC_API_KEY="sk-ant-..."

# For Google Gemini
export GEMINI_API_KEY="..."

# For DeepL
export DEEPL_API_KEY="..."
```

### 3. Translate Your Strings

```bash
# Translate all xcstrings files
swiftlocalize translate

# Translate specific languages
swiftlocalize translate --languages fr,de,es

# Preview translations before applying
swiftlocalize translate --preview

# Create backups before modifying
swiftlocalize translate --backup
```

## CLI Commands

### translate

Translate `.xcstrings` files.

```bash
# Basic translation
swiftlocalize translate

# With specific provider
swiftlocalize translate --provider openai

# Dry run (show what would be translated)
swiftlocalize translate --dry-run

# Force retranslation of all strings
swiftlocalize translate --force

# Preview mode (translate and show results without saving)
swiftlocalize translate --preview

# Create backup files before modifying
swiftlocalize translate --backup
```

### status

Show translation status for your project.

```bash
swiftlocalize status

# Output:
# Translation Status
# ==================
#
# Localizable.xcstrings (42 strings)
#   fr: [====================] 100.0% (42/42)
#   de: [================    ]  80.5% (34/42)
#   es: [============        ]  60.0% (25/42)
```

### validate

Validate translations for consistency and completeness.

```bash
swiftlocalize validate

# Strict mode (fail on warnings)
swiftlocalize validate --strict

# CI mode (strict + JSON output)
swiftlocalize validate --ci
```

### providers

List available translation providers and their status.

```bash
swiftlocalize providers

# Output:
# Available Translation Providers
# ================================
#
# [OK] OpenAI GPT (openai)
# [OK] Anthropic Claude (anthropic)
# [--] Google Gemini (gemini)
#       GEMINI_API_KEY not set
# [OK] Ollama (Local) (ollama)
```

### migrate

Convert between localization file formats.

```bash
# Migrate .strings/.stringsdict to .xcstrings
swiftlocalize migrate to-xcstrings --input ./Resources --output Localizable.xcstrings

# Export .xcstrings to .strings/.stringsdict
swiftlocalize migrate to-legacy Localizable.xcstrings --output ./Legacy
```

### glossary

Manage translation glossary for consistent terminology.

```bash
# Initialize glossary
swiftlocalize glossary init

# Add a brand name (do not translate)
swiftlocalize glossary add "MyAppName" --do-not-translate

# Add a term with translations
swiftlocalize glossary add "Settings" -t fr:Paramètres -t de:Einstellungen

# List all glossary terms
swiftlocalize glossary list

# Remove a term
swiftlocalize glossary remove "OldTerm"
```

### cache

Manage translation cache for incremental translation.

```bash
# Show cache information
swiftlocalize cache info

# Clear the cache (forces retranslation)
swiftlocalize cache clear
```

## Configuration

SwiftLocalize uses a JSON configuration file (`.swiftlocalize.json`):

```json
{
  "sourceLanguage": "en",
  "targetLanguages": ["fr", "de", "es", "ja", "zh-Hans"],
  "providers": {
    "preferred": ["openai", "anthropic"],
    "fallback": ["deepl", "ollama"],
    "openai": {
      "model": "gpt-4o",
      "maxTokens": 4096
    }
  },
  "translation": {
    "batchSize": 20,
    "retryAttempts": 3
  },
  "context": {
    "appName": "MyApp",
    "appDescription": "A productivity app for managing tasks",
    "domain": "productivity",
    "tone": "friendly",
    "formality": "neutral"
  },
  "files": {
    "include": ["**/*.xcstrings"],
    "exclude": ["**/Pods/**"]
  }
}
```

## Translation Providers

### OpenAI

Uses GPT-4 or GPT-3.5 for high-quality translations.

```bash
export OPENAI_API_KEY="sk-..."
```

### Anthropic Claude

Uses Claude for context-aware translations.

```bash
export ANTHROPIC_API_KEY="sk-ant-..."
```

### Google Gemini

Uses Gemini models for translation.

```bash
export GEMINI_API_KEY="..."
```

### DeepL

Professional translation API with high accuracy.

```bash
export DEEPL_API_KEY="..."
```

### Ollama (Local)

Run translations locally using open-source models.

```bash
# Start Ollama server
ollama serve

# Use a translation-capable model
ollama pull llama3.2
```

### Apple Translation (macOS 14.4+)

Uses Apple's on-device Translation framework. No API key required.

## Swift Package Plugin

Add SwiftLocalize as a build tool plugin:

```swift
// Package.swift
targets: [
    .target(
        name: "MyApp",
        plugins: [
            .plugin(name: "SwiftLocalizeBuildPlugin", package: "SwiftLocalize")
        ]
    )
]
```

Or use the command plugin:

```bash
swift package plugin swiftlocalize translate
```

## CI/CD Integration

### GitHub Actions

```yaml
name: Localization

on:
  push:
    paths:
      - '**/*.xcstrings'

jobs:
  translate:
    runs-on: macos-latest
    steps:
      - uses: actions/checkout@v4

      - name: Translate strings
        env:
          OPENAI_API_KEY: ${{ secrets.OPENAI_API_KEY }}
        run: |
          swift run swiftlocalize translate --ci

      - name: Commit translations
        run: |
          git add *.xcstrings
          git commit -m "Update translations" || exit 0
          git push
```

### Validation in CI

```bash
# Validate translations and fail on any issues
swiftlocalize validate --ci
```

Exit codes:
- `0`: Success
- `1`: Translation/validation errors
- `2`: Configuration errors

## Glossary

Maintain consistent terminology with a glossary file (`.swiftlocalize-glossary.json`):

```json
{
  "version": "1.0",
  "terms": [
    {
      "term": "MyApp",
      "doNotTranslate": true
    },
    {
      "term": "Dashboard",
      "translations": {
        "fr": "Tableau de bord",
        "de": "Dashboard",
        "es": "Panel"
      }
    }
  ]
}
```

## Migrating from Legacy Formats

### From .strings files

```bash
# Migrate all .lproj directories to a single .xcstrings
swiftlocalize migrate to-xcstrings \
  --input ./Resources \
  --output Localizable.xcstrings \
  --source-lang en
```

### To .strings files (for older Xcode versions)

```bash
# Export .xcstrings to .lproj directories
swiftlocalize migrate to-legacy Localizable.xcstrings \
  --output ./LegacyResources
```

## Best Practices

1. **Use incremental translation**: Only new/modified strings are translated by default
2. **Set up a glossary**: Ensures consistent translation of app-specific terms
3. **Add context**: Configure app description and domain for better translations
4. **Use preview mode**: Check translations before applying with `--preview`
5. **Backup files**: Use `--backup` flag when running in production
6. **Validate in CI**: Run `swiftlocalize validate --ci` in your CI pipeline

## Requirements

- macOS 14.0+
- Swift 6.0+
- Xcode 16.0+

## License

MIT License - see [LICENSE](LICENSE) for details.

## Contributing

Contributions are welcome! Please read our [Contributing Guide](CONTRIBUTING.md) for details.
