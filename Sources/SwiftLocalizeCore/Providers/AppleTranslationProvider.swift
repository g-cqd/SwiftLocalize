//
//  AppleTranslationProvider.swift
//  SwiftLocalize
//

import Foundation

#if canImport(Translation)
    import Translation

    // MARK: - Apple Translation Provider

    /// Translation provider using Apple's on-device Translation framework.
    ///
    /// **Important Limitations:**
    /// - The Translation framework requires a SwiftUI context to function.
    /// - This provider is designed for use within SwiftUI apps or views.
    /// - For CLI tools or non-SwiftUI contexts, use other providers (OpenAI, DeepL, etc.).
    ///
    /// The Translation framework uses on-device ML models:
    /// - No API key required
    /// - Works offline (after model download)
    /// - Privacy-preserving (translations never leave device)
    /// - Requires iOS 17.4+ / macOS 14.4+
    ///
    /// ## Usage in SwiftUI
    ///
    /// The recommended pattern is to use the `TranslationSessionProvider` to obtain
    /// a session within a SwiftUI view context, then pass it to this provider.
    ///
    /// ```swift
    /// struct ContentView: View {
    ///     @State private var translationSession: TranslationSession?
    ///
    ///     var body: some View {
    ///         Text("Hello")
    ///             .translationTask { session in
    ///                 let provider = AppleTranslationProvider(session: session)
    ///                 // Use provider for translations
    ///             }
    ///     }
    /// }
    /// ```
    @available(macOS 15, iOS 18, *)
    public final class AppleTranslationProvider: TranslationProvider, @unchecked Sendable {
        // MARK: Lifecycle

        /// Initialize with an existing TranslationSession.
        ///
        /// - Parameter session: A TranslationSession obtained from SwiftUI's translationTask.
        public init(session: TranslationSession) {
            self.session = session
        }

        // MARK: Public

        public let identifier = "apple"
        public let displayName = "Apple Translation"

        // MARK: - TranslationProvider

        public func isAvailable() async -> Bool {
            true
        }

        public func supportedLanguages() async throws -> [LanguagePair] {
            // Apple Translation supports many languages but the exact list
            // depends on downloaded models. Return empty to indicate "check at runtime".
            []
        }

        public func translate(
            _ strings: [String],
            from source: LanguageCode,
            to target: LanguageCode,
            context: TranslationContext?,
        ) async throws -> [TranslationResult] {
            guard !strings.isEmpty else { return [] }

            var results: [TranslationResult] = []

            for string in strings {
                do {
                    let response = try await session.translate(string)
                    results.append(TranslationResult(
                        original: string,
                        translated: response.targetText,
                        confidence: 1.0,
                        provider: identifier,
                    ))
                } catch {
                    throw TranslationError.providerError(
                        provider: identifier,
                        message: "Translation failed: \(error.localizedDescription)",
                    )
                }
            }

            return results
        }

        // MARK: Private

        private let session: TranslationSession
    }

    // MARK: - Translation Session Helper

    /// Configuration for creating a TranslationSession.
    @available(macOS 15, iOS 18, *)
    public struct AppleTranslationConfig: Sendable {
        // MARK: Lifecycle

        public init(
            sourceLanguage: LanguageCode? = nil,
            targetLanguage: LanguageCode,
        ) {
            self.sourceLanguage = sourceLanguage.flatMap { code in
                Locale.Language(identifier: code.code)
            }
            self.targetLanguage = Locale.Language(identifier: targetLanguage.code)
        }

        // MARK: Public

        /// Source language (nil for auto-detection).
        public let sourceLanguage: Locale.Language?

        /// Target language.
        public let targetLanguage: Locale.Language

        /// Create a TranslationSession.Configuration from this config.
        public func makeSessionConfiguration() -> TranslationSession.Configuration {
            TranslationSession.Configuration(
                source: sourceLanguage,
                target: targetLanguage,
            )
        }
    }

    // MARK: - Language Availability

    @available(macOS 15, iOS 18, *)
    public extension AppleTranslationProvider {
        /// Check if translation models are available for the given language pair.
        ///
        /// - Parameters:
        ///   - source: Source language code.
        ///   - target: Target language code.
        /// - Returns: True if models are available or can be downloaded.
        static func isLanguagePairAvailable(
            from source: LanguageCode,
            to target: LanguageCode,
        ) async -> Bool {
            let sourceLocale = Locale.Language(identifier: source.code)
            let targetLocale = Locale.Language(identifier: target.code)

            let availability = LanguageAvailability()
            let status = await availability.status(
                from: sourceLocale,
                to: targetLocale,
            )

            switch status {
            case .installed,
                 .supported:
                return true

            case .unsupported:
                return false

            @unknown default:
                return false
            }
        }

        /// Get the download status for a language pair.
        ///
        /// - Parameters:
        ///   - source: Source language code.
        ///   - target: Target language code.
        /// - Returns: Description of the availability status.
        static func languagePairStatus(
            from source: LanguageCode,
            to target: LanguageCode,
        ) async -> String {
            let sourceLocale = Locale.Language(identifier: source.code)
            let targetLocale = Locale.Language(identifier: target.code)

            let availability = LanguageAvailability()
            let status = await availability.status(
                from: sourceLocale,
                to: targetLocale,
            )

            switch status {
            case .installed:
                return "Models installed and ready"

            case .supported:
                return "Supported (download required)"

            case .unsupported:
                return "Language pair not supported"

            @unknown default:
                return "Unknown status"
            }
        }
    }

#else

    // MARK: - Stub for Unsupported Platforms

    /// Stub implementation when Translation framework is not available.
    ///
    /// The Translation framework requires macOS 14.4+ / iOS 17.4+.
    public final class AppleTranslationProvider: TranslationProvider, @unchecked Sendable {
        // MARK: Lifecycle

        public init() {}

        // MARK: Public

        public let identifier = "apple"
        public let displayName = "Apple Translation (Unavailable)"

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
                message: "Translation framework requires macOS 14.4+ / iOS 17.4+",
            )
        }
    }

#endif
