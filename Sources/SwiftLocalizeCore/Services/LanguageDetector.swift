//
//  LanguageDetector.swift
//  SwiftLocalize
//

import Foundation
import NaturalLanguage

// MARK: - Language Detector

/// Detects the language of text using Apple's NaturalLanguage framework.
///
/// Uses `NLLanguageRecognizer` for on-device language detection without network calls.
/// Works best with complete sentences; short single words may produce unreliable results.
public struct LanguageDetector: Sendable {

    /// Result of language detection.
    public struct DetectionResult: Sendable, Equatable {
        /// The most likely language.
        public let language: LanguageCode

        /// Confidence score (0.0 to 1.0).
        public let confidence: Double

        public init(language: LanguageCode, confidence: Double) {
            self.language = language
            self.confidence = confidence
        }
    }

    /// Configuration for language detection.
    public struct Configuration: Sendable {
        /// Languages to constrain detection to (empty means all languages).
        public let languageConstraints: [LanguageCode]

        /// Languages to hint as likely candidates.
        public let languageHints: [String: Double]

        /// Minimum confidence threshold for detection.
        public let minimumConfidence: Double

        public init(
            languageConstraints: [LanguageCode] = [],
            languageHints: [String: Double] = [:],
            minimumConfidence: Double = 0.5
        ) {
            self.languageConstraints = languageConstraints
            self.languageHints = languageHints
            self.minimumConfidence = minimumConfidence
        }

        /// Default configuration with no constraints.
        public static let `default` = Configuration()
    }

    private let configuration: Configuration

    public init(configuration: Configuration = .default) {
        self.configuration = configuration
    }

    // MARK: - Detection Methods

    /// Detect the dominant language in the given text.
    ///
    /// - Parameter text: The text to analyze.
    /// - Returns: The detected language and confidence, or nil if detection failed.
    public func detectLanguage(in text: String) -> DetectionResult? {
        let recognizer = NLLanguageRecognizer()

        // Apply constraints if specified
        if !configuration.languageConstraints.isEmpty {
            let nlLanguages = configuration.languageConstraints.compactMap { code in
                NLLanguage(rawValue: code.code)
            }
            recognizer.languageConstraints = nlLanguages
        }

        // Apply hints if specified
        if !configuration.languageHints.isEmpty {
            var nlHints: [NLLanguage: Double] = [:]
            for (code, weight) in configuration.languageHints {
                nlHints[NLLanguage(rawValue: code)] = weight
            }
            recognizer.languageHints = nlHints
        }

        recognizer.processString(text)

        guard let dominantLanguage = recognizer.dominantLanguage else {
            return nil
        }

        // Get confidence for the dominant language
        let hypotheses = recognizer.languageHypotheses(withMaximum: 1)
        let confidence = hypotheses[dominantLanguage] ?? 0.0

        guard confidence >= configuration.minimumConfidence else {
            return nil
        }

        let languageCode = LanguageCode(dominantLanguage.rawValue)
        return DetectionResult(language: languageCode, confidence: confidence)
    }

    /// Detect multiple possible languages with their probabilities.
    ///
    /// - Parameters:
    ///   - text: The text to analyze.
    ///   - maxResults: Maximum number of language candidates to return.
    /// - Returns: Array of detection results sorted by confidence (highest first).
    public func detectLanguages(
        in text: String,
        maxResults: Int = 5
    ) -> [DetectionResult] {
        let recognizer = NLLanguageRecognizer()

        // Apply constraints if specified
        if !configuration.languageConstraints.isEmpty {
            let nlLanguages = configuration.languageConstraints.compactMap { code in
                NLLanguage(rawValue: code.code)
            }
            recognizer.languageConstraints = nlLanguages
        }

        // Apply hints if specified
        if !configuration.languageHints.isEmpty {
            var nlHints: [NLLanguage: Double] = [:]
            for (code, weight) in configuration.languageHints {
                nlHints[NLLanguage(rawValue: code)] = weight
            }
            recognizer.languageHints = nlHints
        }

        recognizer.processString(text)

        let hypotheses = recognizer.languageHypotheses(withMaximum: maxResults)

        return hypotheses
            .filter { $0.value >= configuration.minimumConfidence }
            .sorted { $0.value > $1.value }
            .map { language, confidence in
                DetectionResult(
                    language: LanguageCode(language.rawValue),
                    confidence: confidence
                )
            }
    }

    /// Check if the given text is likely in the specified language.
    ///
    /// - Parameters:
    ///   - text: The text to analyze.
    ///   - language: The expected language.
    ///   - threshold: Minimum confidence threshold (default: 0.7).
    /// - Returns: True if the text is likely in the specified language.
    public func isLanguage(
        _ text: String,
        expectedLanguage language: LanguageCode,
        threshold: Double = 0.7
    ) -> Bool {
        guard let result = detectLanguage(in: text) else {
            return false
        }

        return result.language.code == language.code && result.confidence >= threshold
    }

    /// Get the BCP 47 language tag for the detected language.
    ///
    /// - Parameter text: The text to analyze.
    /// - Returns: The BCP 47 language tag (e.g., "en", "fr-CA"), or nil if detection failed.
    public func detectLanguageTag(in text: String) -> String? {
        detectLanguage(in: text)?.language.code
    }
}

// MARK: - Batch Detection

extension LanguageDetector {
    /// Detect languages for multiple texts.
    ///
    /// - Parameter texts: Array of texts to analyze.
    /// - Returns: Array of detection results (nil for texts where detection failed).
    public func detectLanguages(in texts: [String]) -> [DetectionResult?] {
        texts.map { detectLanguage(in: $0) }
    }

    /// Group texts by their detected language.
    ///
    /// - Parameter texts: Array of texts to analyze.
    /// - Returns: Dictionary mapping language codes to texts in that language.
    public func groupByLanguage(_ texts: [String]) -> [LanguageCode: [String]] {
        var groups: [LanguageCode: [String]] = [:]

        for text in texts {
            if let result = detectLanguage(in: text) {
                groups[result.language, default: []].append(text)
            }
        }

        return groups
    }
}

// MARK: - Supported Languages

extension LanguageDetector {
    /// Get all languages supported by the language recognizer.
    ///
    /// - Returns: Set of supported language codes.
    public static var supportedLanguages: Set<LanguageCode> {
        // NLLanguageRecognizer supports these languages as of macOS 14/iOS 17
        let languages: [String] = [
            "ar", "bg", "ca", "cs", "da", "de", "el", "en", "es", "fa",
            "fi", "fr", "he", "hi", "hr", "hu", "id", "it", "ja", "ko",
            "ms", "nb", "nl", "pl", "pt", "ro", "ru", "sk", "sv", "th",
            "tr", "uk", "vi", "zh-Hans", "zh-Hant"
        ]
        return Set(languages.map { LanguageCode($0) })
    }
}
