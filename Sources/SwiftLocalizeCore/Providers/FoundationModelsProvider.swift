//
//  FoundationModelsProvider.swift
//  SwiftLocalize
//

import Foundation

#if canImport(FoundationModels)
    import FoundationModels

    // MARK: - Foundation Models Provider

    /// Translation provider using Apple's on-device Foundation Models framework.
    ///
    /// Uses the ~3B parameter language model at the core of Apple Intelligence.
    /// Requires Apple Intelligence to be enabled on the device.
    ///
    /// **Platform Requirements:**
    /// - macOS 26+ / iOS 26+ / iPadOS 26+
    /// - Apple Intelligence-compatible device
    /// - Apple Intelligence enabled in System Settings
    ///
    /// **Capabilities:**
    /// - On-device translation (no network required)
    /// - Privacy-preserving (data never leaves device)
    /// - Fast inference using Apple Silicon
    /// - Structured output via guided generation
    @available(macOS 26, iOS 26, *)
    public final class FoundationModelsProvider: TranslationProvider, @unchecked Sendable {
        // MARK: Lifecycle

        public init(config: FoundationModelsProviderConfig = .default) {
            self.config = config
        }

        // MARK: Public

        /// Configuration for the Foundation Models provider.
        public struct FoundationModelsProviderConfig: Sendable {
            // MARK: Lifecycle

            public init(
                temperature: Double = 0.3,
                maxTokens: Int = 4096,
            ) {
                self.temperature = temperature
                self.maxTokens = maxTokens
            }

            // MARK: Public

            /// Default configuration.
            public static let `default` = FoundationModelsProviderConfig()

            /// Temperature for generation (0.0 to 2.0).
            public let temperature: Double

            /// Maximum tokens to generate.
            public let maxTokens: Int
        }

        public let identifier = "foundation-models"
        public let displayName = "Apple Intelligence"

        // MARK: - TranslationProvider

        public func isAvailable() async -> Bool {
            // Check if Apple Intelligence is available
            let model = SystemLanguageModel.default
            let availability = model.availability

            switch availability {
            case .available:
                return true

            case .unavailable:
                return false

            @unknown default:
                return false
            }
        }

        public func supportedLanguages() async throws -> [LanguagePair] {
            // Foundation Models support many languages via the LLM
            []
        }

        public func translate(
            _ strings: [String],
            from source: LanguageCode,
            to target: LanguageCode,
            context: TranslationContext?,
        ) async throws -> [TranslationResult] {
            guard !strings.isEmpty else { return [] }

            // Build the translation prompt
            let prompt = buildPrompt(
                strings: strings,
                source: source,
                target: target,
                context: context,
            )

            // Create a session with translation instructions
            let session = LanguageModelSession(
                model: SystemLanguageModel.default,
                instructions: buildSystemInstructions(target: target, context: context),
            )

            do {
                // Use guided generation for structured output
                let response = try await session.respond(
                    to: prompt,
                    generating: TranslationOutput.self,
                    options: GenerationOptions(
                        temperature: config.temperature,
                    ),
                )

                return mapToResults(
                    output: response.content,
                    originalStrings: strings,
                )
            } catch let error as LanguageModelSession.GenerationError {
                throw mapGenerationError(error)
            } catch {
                throw TranslationError.providerError(
                    provider: identifier,
                    message: error.localizedDescription,
                )
            }
        }

        // MARK: Private

        private let config: FoundationModelsProviderConfig

        // MARK: - Prompt Building

        private func buildSystemInstructions(
            target: LanguageCode,
            context: TranslationContext?,
        ) -> String {
            var parts: [String] = [
                "You are an expert translator for iOS/macOS applications.",
                "Translate UI strings accurately while preserving:",
                "- Format specifiers: %@, %lld, %.1f, %d",
                "- Markdown syntax: ^[], **, _, ~~",
                "- Placeholders: {name}, {{value}}",
                "- Original punctuation and formality level",
            ]

            if let appDesc = context?.appDescription {
                parts.append("Application context: \(appDesc)")
            }

            if let domain = context?.domain {
                parts.append("Domain: \(domain)")
            }

            if let terms = context?.glossaryTerms, !terms.isEmpty {
                parts.append("Use these exact translations for terms:")
                for term in terms {
                    if term.doNotTranslate == true {
                        parts.append("- \"\(term.term)\" → Keep unchanged")
                    } else if let translation = term.translations?[target.code] {
                        parts.append("- \"\(term.term)\" → \"\(translation)\"")
                    }
                }
            }

            return parts.joined(separator: "\n")
        }

        private func buildPrompt(
            strings: [String],
            source: LanguageCode,
            target: LanguageCode,
            context: TranslationContext?,
        ) -> String {
            let targetName = target.displayName()

            var prompt = "Translate these strings from \(source.displayName()) to \(targetName):\n\n"

            for (index, string) in strings.enumerated() {
                prompt += "\(index + 1). \"\(string)\"\n"

                if let stringContext = context?.stringContexts?[string] {
                    if let comment = stringContext.comment {
                        prompt += "   Context: \(comment)\n"
                    }
                }
            }

            return prompt
        }

        private func mapToResults(
            output: TranslationOutput,
            originalStrings: [String],
        ) -> [TranslationResult] {
            // Map translations back to original strings
            var results: [TranslationResult] = []

            for (index, original) in originalStrings.enumerated() {
                let translated: String = if index < output.translations.count {
                    output.translations[index].text
                } else {
                    original
                }

                results.append(TranslationResult(
                    original: original,
                    translated: translated,
                    confidence: 0.9,
                    provider: identifier,
                ))
            }

            return results
        }

        private func mapGenerationError(_ error: LanguageModelSession.GenerationError) -> TranslationError {
            switch error {
            case .guardrailViolation:
                return .providerError(
                    provider: identifier,
                    message: "Content blocked by safety guardrails",
                )

            case .exceededContextWindowSize:
                return .providerError(
                    provider: identifier,
                    message: "Input too long - exceeded context window",
                )

            @unknown default:
                return .providerError(
                    provider: identifier,
                    message: "Generation failed: \(error)",
                )
            }
        }
    }

    // MARK: - Generable Output Structures

    /// Structured output for translation using guided generation.
    @available(macOS 26, iOS 26, *)
    @Generable
    struct TranslationOutput: Sendable {
        /// Array of translated strings in order.
        let translations: [TranslatedString]
    }

    /// A single translated string.
    @available(macOS 26, iOS 26, *)
    @Generable
    struct TranslatedString: Sendable {
        /// The translated text.
        let text: String
    }

    // MARK: - Availability Checking

    @available(macOS 26, iOS 26, *)
    public extension FoundationModelsProvider {
        /// Check if Apple Intelligence is available and ready.
        static var isAppleIntelligenceAvailable: Bool {
            let model = SystemLanguageModel.default
            switch model.availability {
            case .available:
                return true

            case .unavailable:
                return false

            @unknown default:
                return false
            }
        }

        /// Get the reason why Apple Intelligence is unavailable.
        static var unavailabilityReason: String? {
            let model = SystemLanguageModel.default
            switch model.availability {
            case .available:
                return nil

            case let .unavailable(reason):
                switch reason {
                case .appleIntelligenceNotEnabled:
                    return "Apple Intelligence is not enabled in System Settings"

                case .deviceNotEligible:
                    return "This device does not support Apple Intelligence"

                case .modelNotReady:
                    return "Language model is still downloading or initializing"

                @unknown default:
                    return "Apple Intelligence is unavailable"
                }

            @unknown default:
                return "Unknown availability status"
            }
        }
    }

#else

    // MARK: - Stub for Unsupported Platforms

    /// Stub implementation when Foundation Models framework is not available.
    ///
    /// The Foundation Models framework requires macOS 26+ / iOS 26+.
    public final class FoundationModelsProvider: TranslationProvider, @unchecked Sendable {
        // MARK: Lifecycle

        public init(config: FoundationModelsProviderConfig = .default) {}

        // MARK: Public

        public struct FoundationModelsProviderConfig: Sendable {
            // MARK: Lifecycle

            public init(
                temperature: Double = 0.3,
                maxTokens: Int = 4096,
            ) {
                self.temperature = temperature
                self.maxTokens = maxTokens
            }

            // MARK: Public

            public static let `default` = FoundationModelsProviderConfig()

            public let temperature: Double
            public let maxTokens: Int
        }

        public let identifier = "foundation-models"
        public let displayName = "Apple Intelligence (Unavailable)"

        public func isAvailable() async -> Bool {
            false
        }

        public func supportedLanguages() async throws -> [LanguagePair] {
            []
        }

        public func translate(
            _ strings: [String],
            from source: LanguageCode,
            to target: LanguageCode,
            context: TranslationContext?,
        ) async throws -> [TranslationResult] {
            throw TranslationError.providerError(
                provider: identifier,
                message: "Foundation Models framework requires macOS 26+ / iOS 26+ with Apple Intelligence enabled",
            )
        }
    }

#endif
