# Translation Provider Setup Guide

This guide covers setting up each translation provider supported by SwiftLocalize.

## Overview

SwiftLocalize supports multiple translation providers. You can configure a preferred provider and fallback providers in your configuration:

```json
{
  "providers": {
    "preferred": ["openai"],
    "fallback": ["anthropic", "deepl", "ollama"]
  }
}
```

## OpenAI

OpenAI's GPT models provide high-quality translations with excellent context understanding.

### Setup

1. Create an account at [OpenAI](https://platform.openai.com/)
2. Generate an API key in the [API Keys section](https://platform.openai.com/api-keys)
3. Set the environment variable:

```bash
export OPENAI_API_KEY="sk-..."
```

### Configuration

```json
{
  "providers": {
    "openai": {
      "model": "gpt-4o",
      "maxTokens": 4096,
      "temperature": 0.3
    }
  }
}
```

### Available Models

| Model | Best For | Cost |
|-------|----------|------|
| `gpt-4o` | High-quality translations, complex context | Higher |
| `gpt-4o-mini` | Good balance of quality and cost | Medium |
| `gpt-3.5-turbo` | Basic translations, high volume | Lower |

### Pricing

Check [OpenAI Pricing](https://openai.com/pricing) for current rates.

---

## Anthropic Claude

Claude excels at understanding nuanced context and maintaining consistent tone.

### Setup

1. Create an account at [Anthropic Console](https://console.anthropic.com/)
2. Generate an API key
3. Set the environment variable:

```bash
export ANTHROPIC_API_KEY="sk-ant-..."
```

### Configuration

```json
{
  "providers": {
    "anthropic": {
      "model": "claude-3-5-sonnet-latest",
      "maxTokens": 4096
    }
  }
}
```

### Available Models

| Model | Best For | Cost |
|-------|----------|------|
| `claude-3-5-sonnet-latest` | Best quality, nuanced translations | Higher |
| `claude-3-5-haiku-latest` | Fast, cost-effective translations | Lower |

### Pricing

Check [Anthropic Pricing](https://www.anthropic.com/pricing) for current rates.

---

## Google Gemini

Gemini provides strong multilingual capabilities, especially for Asian languages.

### Setup

1. Go to [Google AI Studio](https://aistudio.google.com/)
2. Get an API key
3. Set the environment variable:

```bash
export GEMINI_API_KEY="..."
```

### Configuration

```json
{
  "providers": {
    "gemini": {
      "model": "gemini-1.5-flash",
      "maxTokens": 8192
    }
  }
}
```

### Available Models

| Model | Best For | Cost |
|-------|----------|------|
| `gemini-1.5-pro` | Complex translations, long context | Higher |
| `gemini-1.5-flash` | Fast translations, good quality | Lower |

### Pricing

Check [Google AI Pricing](https://ai.google.dev/pricing) for current rates.

---

## DeepL

DeepL is a dedicated translation service known for high-quality European language translations.

### Setup

1. Create an account at [DeepL](https://www.deepl.com/pro-api)
2. Get an API key (Free or Pro)
3. Set the environment variable:

```bash
export DEEPL_API_KEY="..."
```

### Configuration

```json
{
  "providers": {
    "deepl": {
      "formality": "default"
    }
  }
}
```

### Formality Options

- `default` - Standard formality
- `more` - More formal translations (where available)
- `less` - Less formal translations (where available)
- `prefer_more` - Prefer formal, fall back to default
- `prefer_less` - Prefer informal, fall back to default

### Supported Languages

DeepL excels at European languages:
- English, German, French, Spanish, Italian, Dutch, Polish, Portuguese, Russian, Japanese, Chinese

### Pricing

- **Free Plan**: 500,000 characters/month
- **Pro Plan**: Pay-per-use

Check [DeepL Pricing](https://www.deepl.com/pro#pricing) for current rates.

---

## Ollama (Local)

Run translations locally using open-source models. No API key required, completely private.

### Setup

1. Install Ollama:

```bash
# macOS
brew install ollama

# Linux
curl -fsSL https://ollama.com/install.sh | sh
```

2. Start the Ollama server:

```bash
ollama serve
```

3. Pull a translation-capable model:

```bash
# Recommended models for translation
ollama pull llama3.2
ollama pull qwen2.5
ollama pull mistral
```

### Configuration

```json
{
  "providers": {
    "ollama": {
      "model": "llama3.2",
      "host": "http://localhost:11434"
    }
  }
}
```

### Recommended Models

| Model | Size | Quality | Speed |
|-------|------|---------|-------|
| `llama3.2:3b` | 2GB | Good | Fast |
| `llama3.2:8b` | 4.7GB | Better | Medium |
| `qwen2.5:7b` | 4.4GB | Good for Asian languages | Medium |
| `mistral:7b` | 4.1GB | Good for European languages | Medium |

### GPU Acceleration

Ollama automatically uses GPU when available:

```bash
# Check GPU status
ollama ps

# Force CPU-only
OLLAMA_GPU_LAYERS=0 ollama serve
```

### Custom Host

For remote Ollama servers:

```json
{
  "providers": {
    "ollama": {
      "host": "http://192.168.1.100:11434"
    }
  }
}
```

---

## Apple Translation (macOS 14.4+)

Uses Apple's on-device Translation framework. Completely private, no API key required.

### Requirements

- macOS 14.4 (Sonoma) or later
- Xcode 15.3 or later

### Setup

No setup required. The provider is automatically available on compatible systems.

### Configuration

```json
{
  "providers": {
    "preferred": ["apple-translation"]
  }
}
```

### Supported Languages

Apple Translation supports major languages including:
- English, Spanish, French, German, Italian, Portuguese, Chinese, Japanese, Korean, Arabic, Russian

### Limitations

- Requires macOS 14.4+
- Not available on Linux or in CI environments without macOS runners
- Language pair availability depends on system configuration

---

## Apple Intelligence (macOS 26+)

Uses on-device Apple Intelligence models via the FoundationModels framework.

### Requirements

- macOS 26 or later
- Apple Silicon Mac
- Apple Intelligence enabled in System Settings

### Setup

1. Enable Apple Intelligence in System Settings > Apple Intelligence & Siri
2. No API key required

### Configuration

```json
{
  "providers": {
    "preferred": ["foundation-models"]
  }
}
```

---

## Provider Selection Strategy

### Recommended Configuration

```json
{
  "providers": {
    "preferred": ["openai"],
    "fallback": ["anthropic", "deepl", "ollama"],
    "openai": {
      "model": "gpt-4o-mini"
    },
    "anthropic": {
      "model": "claude-3-5-haiku-latest"
    }
  }
}
```

### Cost-Optimized Configuration

```json
{
  "providers": {
    "preferred": ["ollama", "deepl"],
    "fallback": ["openai"],
    "ollama": {
      "model": "llama3.2:3b"
    }
  }
}
```

### Quality-Optimized Configuration

```json
{
  "providers": {
    "preferred": ["openai"],
    "fallback": ["anthropic"],
    "openai": {
      "model": "gpt-4o"
    },
    "anthropic": {
      "model": "claude-3-5-sonnet-latest"
    }
  }
}
```

### Privacy-Focused Configuration

```json
{
  "providers": {
    "preferred": ["apple-translation", "ollama"],
    "ollama": {
      "model": "llama3.2:8b"
    }
  }
}
```

## Checking Provider Status

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
# [OK] DeepL (deepl)
# [OK] Ollama (Local) (ollama)
# [OK] Apple Translation (apple-translation)
```

## Troubleshooting

### API Key Not Found

```
Error: OPENAI_API_KEY not set
```

Ensure the environment variable is exported in your shell:

```bash
# Add to ~/.zshrc or ~/.bashrc
export OPENAI_API_KEY="sk-..."
```

### Rate Limiting

If you encounter rate limits:

1. Reduce batch size in configuration
2. Add delays between API calls
3. Use multiple providers with fallback

### Connection Issues

For Ollama connection issues:

```bash
# Check if Ollama is running
curl http://localhost:11434/api/tags

# Restart Ollama
killall ollama
ollama serve
```

### Model Not Found

```bash
# List available Ollama models
ollama list

# Pull missing model
ollama pull llama3.2
```
