//
//  TranslationMemory.swift
//  SwiftLocalize
//

import Foundation

// MARK: - Translation Memory

/// Stores and retrieves previous translations for consistency.
///
/// Translation Memory (TM) is a key component of CAT (Computer-Assisted Translation)
/// systems. It stores source-target pairs and enables:
/// - Exact match reuse (100% matches)
/// - Fuzzy matching for similar strings
/// - Consistency across translations
///
/// ## Usage
/// ```swift
/// let tm = TranslationMemory(storageURL: cacheURL)
/// try await tm.load()
///
/// // Store a translation
/// await tm.store(
///     source: "Hello",
///     translation: "Bonjour",
///     language: "fr",
///     provider: "openai"
/// )
///
/// // Find similar translations
/// let matches = await tm.findSimilar(to: "Hello World", targetLanguage: "fr")
/// ```
public actor TranslationMemory {

    /// Storage location for the translation memory.
    private let storageURL: URL?

    /// In-memory entries indexed by source text.
    private var entries: [String: TMEntry] = [:]

    /// Minimum similarity threshold for fuzzy matches.
    private let minSimilarity: Double

    /// Maximum matches to return from fuzzy search.
    private let maxMatches: Int

    /// Whether the memory has unsaved changes.
    private var isDirty: Bool = false

    public init(
        storageURL: URL? = nil,
        minSimilarity: Double = 0.7,
        maxMatches: Int = 5
    ) {
        self.storageURL = storageURL
        self.minSimilarity = minSimilarity
        self.maxMatches = maxMatches
    }

    // MARK: - Storage

    /// Load translation memory from disk.
    public func load() throws {
        guard let url = storageURL else { return }

        guard FileManager.default.fileExists(atPath: url.path) else {
            return
        }

        let data = try Data(contentsOf: url)
        let storage = try JSONDecoder().decode(TMStorage.self, from: data)
        entries = storage.entries
        isDirty = false
    }

    /// Save translation memory to disk.
    public func save() throws {
        guard let url = storageURL else { return }
        guard isDirty else { return }

        let storage = TMStorage(version: "1.0", entries: entries)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(storage)
        try data.write(to: url, options: .atomic)
        isDirty = false
    }

    /// Force save regardless of dirty state.
    public func forceSave() throws {
        isDirty = true
        try save()
    }

    // MARK: - Query

    /// Find exact match for a source text.
    ///
    /// - Parameters:
    ///   - text: Source text to match.
    ///   - targetLanguage: Target language code.
    /// - Returns: The translation if found, nil otherwise.
    public func findExact(
        text: String,
        targetLanguage: String
    ) -> String? {
        guard let entry = entries[text],
              let translation = entry.translations[targetLanguage] else {
            return nil
        }
        return translation.value
    }

    /// Find similar translations using fuzzy matching.
    ///
    /// Uses Levenshtein distance normalized to similarity score.
    ///
    /// - Parameters:
    ///   - text: Source text to find matches for.
    ///   - targetLanguage: Target language code.
    ///   - limit: Maximum matches to return.
    /// - Returns: Array of matches sorted by similarity (highest first).
    public func findSimilar(
        to text: String,
        targetLanguage: String,
        limit: Int? = nil
    ) -> [TMMatch] {
        let effectiveLimit = limit ?? maxMatches

        // Check exact match first
        if let entry = entries[text],
           let translation = entry.translations[targetLanguage] {
            return [TMMatch(
                source: text,
                translation: translation.value,
                similarity: 1.0,
                provider: translation.provider,
                humanReviewed: translation.reviewedByHuman
            )]
        }

        // Fuzzy matching
        var matches: [TMMatch] = []

        for (source, entry) in entries {
            guard let translation = entry.translations[targetLanguage] else {
                continue
            }

            let similarity = calculateSimilarity(text, source)
            guard similarity >= minSimilarity else { continue }

            matches.append(TMMatch(
                source: source,
                translation: translation.value,
                similarity: similarity,
                provider: translation.provider,
                humanReviewed: translation.reviewedByHuman
            ))
        }

        // Sort by similarity descending
        matches.sort { $0.similarity > $1.similarity }

        return Array(matches.prefix(effectiveLimit))
    }

    /// Get all stored translations for a language.
    ///
    /// - Parameter language: Target language code.
    /// - Returns: Dictionary mapping source text to translation.
    public func allTranslations(for language: String) -> [String: String] {
        var result: [String: String] = [:]

        for (source, entry) in entries {
            if let translation = entry.translations[language] {
                result[source] = translation.value
            }
        }

        return result
    }

    /// Get statistics about the translation memory.
    public var statistics: TMStatistics {
        let totalEntries = entries.count
        var languageCounts: [String: Int] = [:]
        var humanReviewedCount = 0
        var providerCounts: [String: Int] = [:]

        for (_, entry) in entries {
            for (lang, translation) in entry.translations {
                languageCounts[lang, default: 0] += 1
                if translation.reviewedByHuman {
                    humanReviewedCount += 1
                }
                if let provider = translation.provider {
                    providerCounts[provider, default: 0] += 1
                }
            }
        }

        return TMStatistics(
            totalEntries: totalEntries,
            languageCounts: languageCounts,
            humanReviewedCount: humanReviewedCount,
            providerCounts: providerCounts
        )
    }

    // MARK: - Storage

    /// Store a new translation.
    ///
    /// - Parameters:
    ///   - source: Source text.
    ///   - translation: Translated text.
    ///   - language: Target language code.
    ///   - provider: Translation provider identifier.
    ///   - context: Optional context where the string is used.
    ///   - humanReviewed: Whether a human reviewed this translation.
    public func store(
        source: String,
        translation: String,
        language: String,
        provider: String,
        context: String? = nil,
        humanReviewed: Bool = false
    ) {
        var entry = entries[source] ?? TMEntry(
            sourceText: source,
            translations: [:],
            context: context,
            lastUsed: Date(),
            quality: .machineTranslated
        )

        entry.translations[language] = TranslatedText(
            value: translation,
            provider: provider,
            reviewedByHuman: humanReviewed,
            confidence: humanReviewed ? 1.0 : 0.9
        )
        entry.lastUsed = Date()

        if humanReviewed && entry.quality == .machineTranslated {
            entry.quality = .humanReviewed
        }

        entries[source] = entry
        isDirty = true
    }

    /// Store multiple translations in batch.
    public func storeBatch(
        _ translations: [(source: String, translation: String, language: String)],
        provider: String
    ) {
        for item in translations {
            store(
                source: item.source,
                translation: item.translation,
                language: item.language,
                provider: provider
            )
        }
    }

    /// Mark a translation as human-reviewed.
    public func markReviewed(source: String, language: String) {
        guard var entry = entries[source],
              var translation = entry.translations[language] else {
            return
        }

        translation.reviewedByHuman = true
        translation.confidence = 1.0
        entry.translations[language] = translation
        entry.quality = .humanReviewed
        entries[source] = entry
        isDirty = true
    }

    /// Remove an entry from the memory.
    public func remove(source: String) {
        entries.removeValue(forKey: source)
        isDirty = true
    }

    /// Clear all entries.
    public func clear() {
        entries.removeAll()
        isDirty = true
    }

    // MARK: - Similarity Calculation

    /// Calculate similarity between two strings using Levenshtein distance.
    ///
    /// Returns a value between 0.0 (completely different) and 1.0 (identical).
    private func calculateSimilarity(_ s1: String, _ s2: String) -> Double {
        guard !s1.isEmpty && !s2.isEmpty else {
            return s1 == s2 ? 1.0 : 0.0
        }

        let distance = levenshteinDistance(s1, s2)
        let maxLength = max(s1.count, s2.count)

        return 1.0 - (Double(distance) / Double(maxLength))
    }

    /// Calculate Levenshtein (edit) distance between two strings.
    private func levenshteinDistance(_ s1: String, _ s2: String) -> Int {
        let s1 = Array(s1)
        let s2 = Array(s2)

        let m = s1.count
        let n = s2.count

        // Edge cases
        if m == 0 { return n }
        if n == 0 { return m }

        // Use two rows instead of full matrix for memory efficiency
        var previousRow = Array(0...n)
        var currentRow = [Int](repeating: 0, count: n + 1)

        for i in 1...m {
            currentRow[0] = i

            for j in 1...n {
                let cost = s1[i - 1] == s2[j - 1] ? 0 : 1
                currentRow[j] = min(
                    previousRow[j] + 1,      // deletion
                    currentRow[j - 1] + 1,   // insertion
                    previousRow[j - 1] + cost // substitution
                )
            }

            swap(&previousRow, &currentRow)
        }

        return previousRow[n]
    }
}

// MARK: - Storage Models

/// Root storage structure for translation memory.
struct TMStorage: Codable {
    let version: String
    var entries: [String: TMEntry]
}

/// A single entry in the translation memory.
public struct TMEntry: Codable, Sendable {
    /// The source text.
    public var sourceText: String

    /// Translations indexed by language code.
    public var translations: [String: TranslatedText]

    /// Optional context where the string is used.
    public var context: String?

    /// Last time this entry was used.
    public var lastUsed: Date

    /// Quality level of the entry.
    public var quality: TranslationQuality

    public init(
        sourceText: String,
        translations: [String: TranslatedText],
        context: String?,
        lastUsed: Date,
        quality: TranslationQuality
    ) {
        self.sourceText = sourceText
        self.translations = translations
        self.context = context
        self.lastUsed = lastUsed
        self.quality = quality
    }
}

/// A translated text with metadata.
public struct TranslatedText: Codable, Sendable {
    /// The translated value.
    public var value: String

    /// Provider that generated this translation.
    public var provider: String?

    /// Whether a human has reviewed this translation.
    public var reviewedByHuman: Bool

    /// Confidence score (0.0 to 1.0).
    public var confidence: Double

    public init(
        value: String,
        provider: String?,
        reviewedByHuman: Bool,
        confidence: Double
    ) {
        self.value = value
        self.provider = provider
        self.reviewedByHuman = reviewedByHuman
        self.confidence = confidence
    }
}

// MARK: - Statistics

/// Statistics about the translation memory.
public struct TMStatistics: Sendable {
    /// Total number of source entries.
    public let totalEntries: Int

    /// Number of translations per language.
    public let languageCounts: [String: Int]

    /// Number of human-reviewed translations.
    public let humanReviewedCount: Int

    /// Number of translations per provider.
    public let providerCounts: [String: Int]
}
