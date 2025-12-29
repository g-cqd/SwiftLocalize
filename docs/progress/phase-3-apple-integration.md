# Phase 3: Apple Integration

**Status:** Complete
**Started:** 2025-12-28
**Completed:** 2025-12-28

## Completed Items

- [x] Research macOS 26 Translation framework APIs
- [x] Apple Translation framework provider (macOS 15+/iOS 18+)
- [x] Foundation Models provider (macOS 26+/iOS 26+)
- [x] NaturalLanguage framework integration for language detection

## Implementation Notes

### Translation Framework (macOS 15+/iOS 18+)

The Translation framework is SwiftUI-only by design. Key findings:

- Requires `TranslationSession` obtained via SwiftUI's `.translationTask()` modifier
- On-device ML models (offline after download)
- No API key required
- Privacy-preserving (data never leaves device)
- `LanguageAvailability` API for checking model availability

**Limitation:** Cannot be used in pure CLI contexts without SwiftUI. The provider is designed
for use within SwiftUI apps where a session can be obtained.

### Foundation Models Framework (macOS 26+/iOS 26+)

Apple's new on-device LLM framework for Apple Intelligence:

- ~3B parameter language model
- Uses `SystemLanguageModel.default` for access
- `LanguageModelSession` for conversations
- `@Generable` macro for structured output (guided generation)
- Generation errors: `guardrailViolation`, `exceededContextWindowSize`, etc.

**Availability checking:**
- `SystemLanguageModel.default.availability` returns `.available` or `.unavailable(reason:)`
- Reasons: `appleIntelligenceNotEnabled`, `deviceNotEligible`, `modelNotReady`

### NaturalLanguage Framework (iOS 12+/macOS 10.14+)

Used for language detection:

- `NLLanguageRecognizer` for on-device language detection
- `dominantLanguage` for single language detection
- `languageHypotheses(withMaximum:)` for multiple candidates with confidence scores
- Supports language constraints and hints for improved accuracy
- Works best with full sentences (short texts may be unreliable)

## API Research Sources

- [WWDC 2025 Foundation Models](https://developer.apple.com/videos/play/wwdc2025/286/)
- [Foundation Models framework documentation](https://developer.apple.com/documentation/FoundationModels)
- [Translation framework documentation](https://developer.apple.com/documentation/translation/)
- [Create with Swift - Foundation Models](https://www.createwithswift.com/exploring-the-foundation-models-framework/)
- [Create with Swift - Translation framework](https://www.createwithswift.com/using-the-translation-framework-for-language-to-language-translation/)

## Files Created

### LanguageDetector (`Sources/SwiftLocalizeCore/Services/LanguageDetector.swift`)

- `LanguageDetector` - On-device language detection using NaturalLanguage framework
- `DetectionResult` - Language code with confidence score
- `Configuration` - Language constraints, hints, minimum confidence
- Methods: `detectLanguage(in:)`, `detectLanguages(in:maxResults:)`, `isLanguage(_:expectedLanguage:threshold:)`
- Batch methods: `detectLanguages(in texts:)`, `groupByLanguage(_:)`
- Static: `supportedLanguages` - set of supported language codes

### Apple Translation Provider (`Sources/SwiftLocalizeCore/Providers/AppleTranslationProvider.swift`)

- `AppleTranslationProvider` - Translation using Apple's on-device models
- Requires macOS 15+ / iOS 18+ (availability annotation)
- Takes `TranslationSession` from SwiftUI context
- `AppleTranslationConfig` - Source/target language configuration
- Static methods: `isLanguagePairAvailable(from:to:)`, `languagePairStatus(from:to:)`
- Fallback stub for unsupported platforms

### Foundation Models Provider (`Sources/SwiftLocalizeCore/Providers/FoundationModelsProvider.swift`)

- `FoundationModelsProvider` - Translation using Apple Intelligence on-device LLM
- Requires macOS 26+ / iOS 26+ (availability annotation)
- `FoundationModelsProviderConfig` - Temperature, max tokens configuration
- Uses `@Generable` structs for structured output:
  - `TranslationOutput` - Array of translations
  - `TranslatedString` - Individual translation
- Error mapping for `LanguageModelSession.GenerationError`
- Static: `isAppleIntelligenceAvailable`, `unavailabilityReason`
- Fallback stub for unsupported platforms

## Conditional Compilation

All Apple-specific providers use `#if canImport()` for conditional compilation:

```swift
#if canImport(Translation)
import Translation
// Full implementation
#else
// Stub that returns unavailable
#endif
```

This ensures the library compiles on all platforms while providing appropriate error messages
when frameworks are unavailable.
