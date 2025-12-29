# Phase 2: Provider Infrastructure

**Status:** Complete
**Started:** 2025-12-28
**Completed:** 2025-12-28

## Completed Items

- [x] OpenAI provider implementation
- [x] Anthropic provider implementation
- [x] Google Gemini provider implementation
- [x] DeepL provider implementation
- [x] Ollama provider implementation
- [x] CLI tool provider wrapper

## Implementation Notes

All providers follow a consistent pattern:
- Use `HTTPClient` actor for HTTP requests
- Use `TranslationPromptBuilder` for LLM prompt generation (LLM providers)
- Map HTTP errors to `TranslationError` using private `mapHTTPError` function
- Support configuration from environment variables or explicit config
- Implement `TranslationProvider` protocol

### Swift 6 Typed Throws Workaround
Encountered a Swift compiler bug (crash) when using `catch let error as HTTPError` pattern with
typed throws. Worked around by adding a fallback `catch` clause after the typed catch.

## API Reference

### OpenAI Chat Completions
- Endpoint: `https://api.openai.com/v1/chat/completions`
- Model: gpt-4o (default)
- JSON mode supported via `response_format: { type: "json_object" }`

### Anthropic Messages
- Endpoint: `https://api.anthropic.com/v1/messages`
- Model: claude-sonnet-4-20250514 (default)
- Required headers: x-api-key, anthropic-version

### Google Gemini
- Endpoint: `https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent`
- Model: gemini-1.5-flash (default)
- API key via query parameter

### DeepL
- Free endpoint: `https://api-free.deepl.com/v2/translate`
- Pro endpoint: `https://api.deepl.com/v2/translate`
- Direct translation (not LLM-based)

### Ollama
- Local endpoint: `http://localhost:11434/api/generate`
- Model: llama3.2 (configurable)
- No API key required

## Files Created

### OpenAI Provider (`Sources/SwiftLocalizeCore/Providers/OpenAIProvider.swift`)
- `OpenAIProvider` - Translation provider using OpenAI Chat Completions API
- `OpenAIProviderConfig` - Configuration with API key, model, base URL, max tokens, temperature
- Supports: GPT-4o (default), Azure OpenAI endpoints
- Features: JSON mode for reliable structured output

### Anthropic Provider (`Sources/SwiftLocalizeCore/Providers/AnthropicProvider.swift`)
- `AnthropicProvider` - Translation provider using Anthropic Messages API
- `AnthropicProviderConfig` - Configuration with API key, model, base URL, max tokens
- Supports: Claude Sonnet 4 (default), requires anthropic-version header
- Error handling for 529 (API overloaded) status

### Gemini Provider (`Sources/SwiftLocalizeCore/Providers/GeminiProvider.swift`)
- `GeminiProvider` - Translation provider using Google Gemini generateContent API
- `GeminiProviderConfig` - Configuration with API key, model, base URL, temperature
- Supports: gemini-1.5-flash (default), JSON response MIME type
- API key passed via URL query parameter

### DeepL Provider (`Sources/SwiftLocalizeCore/Providers/DeepLProvider.swift`)
- `DeepLProvider` - Translation provider using DeepL Translation API (non-LLM)
- `DeepLProviderConfig` - Configuration with API key, tier (free/pro), formality
- Features: Formality support for select languages, preserve formatting
- Automatic tier detection from API key suffix (:fx = free)
- Language code conversion for DeepL format (uppercase, regional variants)

### Ollama Provider (`Sources/SwiftLocalizeCore/Providers/OllamaProvider.swift`)
- `OllamaProvider` - Translation provider using local Ollama server
- `OllamaProviderConfig` - Configuration with base URL, model, temperature, context size
- Features: No API key required, list models, pull models
- Supports: llama3.2 (default), any Ollama-compatible model
- Longer timeout (120s) for local model loading

### CLI Tool Provider (`Sources/SwiftLocalizeCore/Providers/CLIToolProvider.swift`)
- `CLIToolProvider` - Wrapper for external CLI tools (gemini, copilot, custom scripts)
- `CLIToolProviderConfig` - Configuration with tool path, arguments, environment, timeout
- Features: stdin/stdout communication, auto-confirm flag support
- Preset configurations for Gemini CLI and GitHub Copilot CLI
