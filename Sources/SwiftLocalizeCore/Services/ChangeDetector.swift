//
//  ChangeDetector.swift
//  SwiftLocalize
//

import CryptoKit
import Foundation

// MARK: - ChangeDetector

/// Detects changes in source strings to enable incremental translation.
///
/// The change detector maintains a cache of translated strings, allowing
/// subsequent translation runs to only process new or modified strings.
/// This dramatically reduces API costs and translation time for large projects.
///
/// ## Usage
/// ```swift
/// let detector = ChangeDetector(cacheFile: cacheURL)
/// try await detector.load()
///
/// // Check which strings need translation
/// let changes = await detector.detectChanges(in: xcstrings, targetLanguages: languages)
///
/// // After translation, update the cache
/// await detector.markTranslated(key: "hello", sourceHash: hash, languages: ["fr", "de"])
/// try await detector.save()
/// ```
public actor ChangeDetector {
    // MARK: Lifecycle

    // MARK: - Initialization

    public init(cacheFile: URL) {
        cacheURL = cacheFile
        cache = TranslationCache()
    }

    /// Initialize with a cache file path relative to a base directory.
    public init(cacheFileName: String, baseDirectory: URL) {
        cacheURL = baseDirectory.appendingPathComponent(cacheFileName)
        cache = TranslationCache()
    }

    // MARK: Public

    /// Get cache statistics.
    public var statistics: CacheStatistics {
        CacheStatistics(
            totalEntries: cache.entries.count,
            cacheVersion: cache.version,
            lastUpdated: cache.entries.values.map(\.lastModified).max(),
        )
    }

    // MARK: - Cache Persistence

    /// Load the cache from disk.
    public func load() throws {
        guard FileManager.default.fileExists(atPath: cacheURL.path) else {
            cache = TranslationCache()
            return
        }

        let data = try Data(contentsOf: cacheURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        cache = try decoder.decode(TranslationCache.self, from: data)
    }

    /// Save the cache to disk.
    public func save() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        let data = try encoder.encode(cache)
        try data.write(to: cacheURL, options: .atomic)
    }

    /// Clear all cached data.
    public func clear() {
        cache = TranslationCache()
    }

    // MARK: - Change Detection

    /// Detect which strings need translation.
    ///
    /// - Parameters:
    ///   - xcstrings: The xcstrings file to analyze.
    ///   - targetLanguages: Languages to check for translations.
    ///   - forceRetranslate: If true, mark all strings as needing translation.
    /// - Returns: Detection result with strings grouped by need.
    public func detectChanges(
        in xcstrings: XCStrings,
        targetLanguages: [LanguageCode],
        forceRetranslate: Bool = false,
    ) -> ChangeDetectionResult {
        if forceRetranslate {
            return forceRetranslateAll(xcstrings: xcstrings, targetLanguages: targetLanguages)
        }

        var state = DetectionState()

        for (key, entry) in xcstrings.strings {
            processEntry(
                key: key,
                entry: entry,
                xcstrings: xcstrings,
                targetLanguages: targetLanguages,
                state: &state,
            )
        }

        return ChangeDetectionResult(
            stringsToTranslate: state.needsTranslation,
            unchanged: state.unchanged,
            newStrings: state.newStrings,
            modifiedStrings: state.modifiedStrings,
        )
    }

    private struct DetectionState {
        var needsTranslation: [String: Set<LanguageCode>] = [:]
        var unchanged: [String] = []
        var newStrings: [String] = []
        var modifiedStrings: [String] = []
    }

    private func processEntry(
        key: String,
        entry: StringEntry,
        xcstrings: XCStrings,
        targetLanguages: [LanguageCode],
        state: inout DetectionState,
    ) {
        // Get the source value
        guard let sourceLocalization = entry.localizations?[xcstrings.sourceLanguage],
              let sourceValue = sourceLocalization.stringUnit?.value
        else {
            processKeyWithoutSource(
                key: key,
                entry: entry,
                xcstrings: xcstrings,
                targetLanguages: targetLanguages,
                state: &state
            )
            return
        }

        let sourceHash = computeHash(sourceValue)

        // Check if this is a new or modified string
        if let cached = cache.entries[key] {
            processCachedEntry(
                key: key,
                entry: entry,
                xcstrings: xcstrings,
                targetLanguages: targetLanguages,
                sourceHash: sourceHash,
                cached: cached,
                state: &state
            )
        } else {
            processNewEntry(
                key: key,
                entry: entry,
                xcstrings: xcstrings,
                targetLanguages: targetLanguages,
                sourceHash: sourceHash,
                state: &state
            )
        }
    }

    private func processKeyWithoutSource(
        key: String,
        entry: StringEntry,
        xcstrings: XCStrings,
        targetLanguages: [LanguageCode],
        state: inout DetectionState,
    ) {
        let sourceHash = computeHash(key)
        let missing = findMissingLanguages(
            key: key,
            sourceHash: sourceHash,
            entry: entry,
            targetLanguages: targetLanguages,
            xcstrings: xcstrings
        )
        if !missing.isEmpty {
            state.needsTranslation[key] = missing
            if cache.entries[key] == nil {
                state.newStrings.append(key)
            }
        }
    }

    private func processCachedEntry(
        key: String,
        entry: StringEntry,
        xcstrings: XCStrings,
        targetLanguages: [LanguageCode],
        sourceHash: String,
        cached: CacheEntry,
        state: inout DetectionState,
    ) {
        if cached.sourceHash != sourceHash {
            state.needsTranslation[key] = Set(targetLanguages)
            state.modifiedStrings.append(key)
        } else {
            let missing = findMissingLanguages(
                key: key,
                sourceHash: sourceHash,
                entry: entry,
                targetLanguages: targetLanguages,
                xcstrings: xcstrings
            )
            if missing.isEmpty {
                state.unchanged.append(key)
            } else {
                state.needsTranslation[key] = missing
            }
        }
    }

    private func processNewEntry(
        key: String,
        entry: StringEntry,
        xcstrings: XCStrings,
        targetLanguages: [LanguageCode],
        sourceHash: String,
        state: inout DetectionState,
    ) {
        let missing = findMissingLanguages(
            key: key,
            sourceHash: sourceHash,
            entry: entry,
            targetLanguages: targetLanguages,
            xcstrings: xcstrings
        )
        if !missing.isEmpty {
            state.needsTranslation[key] = missing
            state.newStrings.append(key)
        } else {
            state.unchanged.append(key)
        }
    }

    // MARK: - Cache Updates

    /// Mark a string as translated for the given languages.
    ///
    /// - Parameters:
    ///   - key: The string key.
    ///   - sourceValue: The source string value.
    ///   - languages: Languages that were translated.
    ///   - provider: The provider that performed the translation.
    public func markTranslated(
        key: String,
        sourceValue: String,
        languages: Set<String>,
        provider: String,
    ) {
        let sourceHash = computeHash(sourceValue)

        if var existing = cache.entries[key] {
            // Update existing entry
            existing.translatedLanguages.formUnion(languages)
            existing.lastModified = Date()
            existing.provider = provider

            // If source changed, update hash and reset languages to only new ones
            if existing.sourceHash != sourceHash {
                existing.sourceHash = sourceHash
                existing.translatedLanguages = languages
            }

            cache.entries[key] = existing
        } else {
            // Create new entry
            cache.entries[key] = CacheEntry(
                sourceHash: sourceHash,
                translatedLanguages: languages,
                lastModified: Date(),
                provider: provider,
            )
        }
    }

    /// Remove a string from the cache.
    public func remove(key: String) {
        cache.entries.removeValue(forKey: key)
    }

    // MARK: Private

    private let cacheURL: URL
    private var cache: TranslationCache

    private func findMissingLanguages(
        key: String,
        sourceHash: String,
        entry: StringEntry,
        targetLanguages: [LanguageCode],
        xcstrings: XCStrings,
    ) -> Set<LanguageCode> {
        var missing: Set<LanguageCode> = []

        for language in targetLanguages {
            // Skip source language
            guard language.code != xcstrings.sourceLanguage else { continue }

            // Check if translation exists in xcstrings
            let hasTranslation = if let localization = entry.localizations?[language.code],
                                    let unit = localization.stringUnit,
                                    unit.state == .translated,
                                    !unit.value.isEmpty {
                true
            } else {
                false
            }

            // Check if in cache
            let inCache = if let cached = cache.entries[key],
                             cached.sourceHash == sourceHash,
                             cached.translatedLanguages.contains(language.code) {
                true
            } else {
                false
            }

            if !hasTranslation, !inCache {
                missing.insert(language)
            }
        }

        return missing
    }

    private func forceRetranslateAll(
        xcstrings: XCStrings,
        targetLanguages: [LanguageCode],
    ) -> ChangeDetectionResult {
        var needsTranslation: [String: Set<LanguageCode>] = [:]

        for key in xcstrings.strings.keys {
            let languages = Set(targetLanguages.filter { $0.code != xcstrings.sourceLanguage })
            if !languages.isEmpty {
                needsTranslation[key] = languages
            }
        }

        return ChangeDetectionResult(
            stringsToTranslate: needsTranslation,
            unchanged: [],
            newStrings: Array(xcstrings.strings.keys),
            modifiedStrings: [],
        )
    }

    // MARK: - Hash Computation

    private func computeHash(_ string: String) -> String {
        let data = Data(string.utf8)
        let hash = SHA256.hash(data: data)
        return hash.prefix(16).map { String(format: "%02x", $0) }.joined()
    }
}

// MARK: - TranslationCache

/// Persistent cache for translation state.
public struct TranslationCache: Codable, Sendable {
    // MARK: Lifecycle

    public init(version: String = "1.0", entries: [String: CacheEntry] = [:]) {
        self.version = version
        self.entries = entries
    }

    // MARK: Public

    /// Cache format version.
    public var version: String

    /// Cached entries by string key.
    public var entries: [String: CacheEntry]
}

// MARK: - CacheEntry

/// A cached entry for a single string.
public struct CacheEntry: Codable, Sendable {
    // MARK: Lifecycle

    public init(
        sourceHash: String,
        translatedLanguages: Set<String>,
        lastModified: Date,
        provider: String,
    ) {
        self.sourceHash = sourceHash
        self.translatedLanguages = translatedLanguages
        self.lastModified = lastModified
        self.provider = provider
    }

    // MARK: Public

    /// Hash of the source string value.
    public var sourceHash: String

    /// Set of language codes that have been translated.
    public var translatedLanguages: Set<String>

    /// When the entry was last modified.
    public var lastModified: Date

    /// Provider that last translated this string.
    public var provider: String
}

// MARK: - ChangeDetectionResult

/// Result of change detection.
public struct ChangeDetectionResult: Sendable {
    /// Strings that need translation, with the languages that need translating.
    public let stringsToTranslate: [String: Set<LanguageCode>]

    /// Strings that are unchanged and don't need translation.
    public let unchanged: [String]

    /// New strings (not in cache).
    public let newStrings: [String]

    /// Modified strings (source changed since last translation).
    public let modifiedStrings: [String]

    /// Total number of strings that need translation.
    public var totalStringsToTranslate: Int {
        stringsToTranslate.count
    }

    /// Total number of translation operations (string × language pairs).
    public var totalTranslationOperations: Int {
        stringsToTranslate.values.reduce(0) { $0 + $1.count }
    }

    /// Check if any translations are needed.
    public var hasChanges: Bool {
        !stringsToTranslate.isEmpty
    }
}

// MARK: - CacheStatistics

/// Statistics about the cache.
public struct CacheStatistics: Sendable {
    /// Total number of cached entries.
    public let totalEntries: Int

    /// Cache format version.
    public let cacheVersion: String

    /// When the cache was last updated.
    public let lastUpdated: Date?
}
