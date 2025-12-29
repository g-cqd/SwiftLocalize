//
//  ProvidersCommand.swift
//  SwiftLocalize
//

import ArgumentParser
import Foundation
import SwiftLocalizeCore

// MARK: - ProvidersCommand

struct ProvidersCommand: AsyncParsableCommand {
    // MARK: Internal

    static let configuration = CommandConfiguration(
        commandName: "providers",
        abstract: "List available translation providers.",
    )

    @Flag(name: .customLong("json"), help: "Output as JSON.")
    var jsonOutput = false

    func run() async throws {
        let providers = await collectProviderInfo()

        if jsonOutput {
            try printJSONProviders(providers)
        } else {
            printTextProviders(providers)
        }
    }

    // MARK: Private

    private struct ProviderInfo {
        let name: String
        let displayName: String
        let available: Bool
        let reason: String?
    }

    private func collectProviderInfo() async -> [ProviderInfo] {
        var providers: [ProviderInfo] = []
        providers.append(contentsOf: collectAPIProviders())
        await providers.append(contentsOf: collectLocalProviders())
        providers.append(contentsOf: collectAppleProviders())
        return providers
    }

    private func collectAPIProviders() -> [ProviderInfo] {
        var providers: [ProviderInfo] = []
        let env = ProcessInfo.processInfo.environment

        // Check OpenAI
        let openaiAvailable = env["OPENAI_API_KEY"] != nil
        providers.append(ProviderInfo(
            name: "openai",
            displayName: "OpenAI GPT",
            available: openaiAvailable,
            reason: openaiAvailable ? nil : "OPENAI_API_KEY not set",
        ))

        // Check Anthropic
        let anthropicAvailable = env["ANTHROPIC_API_KEY"] != nil
        providers.append(ProviderInfo(
            name: "anthropic",
            displayName: "Anthropic Claude",
            available: anthropicAvailable,
            reason: anthropicAvailable ? nil : "ANTHROPIC_API_KEY not set",
        ))

        // Check Gemini
        let geminiAvailable = env["GEMINI_API_KEY"] != nil
        providers.append(ProviderInfo(
            name: "gemini",
            displayName: "Google Gemini",
            available: geminiAvailable,
            reason: geminiAvailable ? nil : "GEMINI_API_KEY not set",
        ))

        // Check DeepL
        let deeplAvailable = env["DEEPL_API_KEY"] != nil
        providers.append(ProviderInfo(
            name: "deepl",
            displayName: "DeepL",
            available: deeplAvailable,
            reason: deeplAvailable ? nil : "DEEPL_API_KEY not set",
        ))

        return providers
    }

    private func collectLocalProviders() async -> [ProviderInfo] {
        var providers: [ProviderInfo] = []

        // Check Ollama
        let ollamaProvider = OllamaProvider()
        let ollamaAvailable = await ollamaProvider.isAvailable()
        providers.append(ProviderInfo(
            name: "ollama",
            displayName: "Ollama (Local)",
            available: ollamaAvailable,
            reason: ollamaAvailable ? nil : "Ollama server not running",
        ))

        return providers
    }

    private func collectAppleProviders() -> [ProviderInfo] {
        var providers: [ProviderInfo] = []

        // Apple Translation
        #if canImport(Translation)
            providers.append(ProviderInfo(
                name: "apple-translation",
                displayName: "Apple Translation",
                available: true,
                reason: nil,
            ))
        #else
            providers.append(ProviderInfo(
                name: "apple-translation",
                displayName: "Apple Translation",
                available: false,
                reason: "Requires macOS 14.4+ with Translation framework",
            ))
        #endif

        // Foundation Models
        #if canImport(FoundationModels)
            providers.append(ProviderInfo(
                name: "foundation-models",
                displayName: "Apple Intelligence",
                available: true,
                reason: nil,
            ))
        #else
            providers.append(ProviderInfo(
                name: "foundation-models",
                displayName: "Apple Intelligence",
                available: false,
                reason: "Requires macOS 26+ with Apple Intelligence enabled",
            ))
        #endif

        return providers
    }

    private func printJSONProviders(_ providers: [ProviderInfo]) throws {
        struct JSONProvider: Encodable {
            let name: String
            let displayName: String
            let available: Bool
            let reason: String?
        }

        let jsonProviders = providers.map { p in
            JSONProvider(name: p.name, displayName: p.displayName, available: p.available, reason: p.reason)
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(jsonProviders)
        print(String(data: data, encoding: .utf8) ?? "[]")
    }

    private func printTextProviders(_ providers: [ProviderInfo]) {
        print("Available Translation Providers")
        print("================================\n")

        for provider in providers {
            let status = provider.available ? "[OK]" : "[--]"
            print("\(status) \(provider.displayName) (\(provider.name))")
            if let reason = provider.reason {
                print("      \(reason)")
            }
        }

        print("\nSet up API keys as environment variables to enable cloud providers.")
        print("Run 'ollama serve' to enable local Ollama translations.")
    }
}
