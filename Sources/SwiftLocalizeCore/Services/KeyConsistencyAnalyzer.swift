//
//  KeyConsistencyAnalyzer.swift
//  SwiftLocalize
//
//  Analyzes key consistency across multiple xcstrings catalogs.

import Foundation

// MARK: - Key Consistency Analyzer

/// Analyzes key consistency across multiple xcstrings catalogs.
///
/// Use this to:
/// - Find missing keys across catalogs
/// - Detect conflicting source values
/// - Identify keys unique to specific catalogs
/// - Synchronize keys across multi-target projects
///
/// ## Usage
/// ```swift
/// let analyzer = KeyConsistencyAnalyzer()
/// let report = try await analyzer.analyze(catalogs: [url1, url2, url3])
///
/// for (catalog, missing) in report.missingKeys {
///     print("\(catalog): missing \(missing.count) keys")
/// }
/// ```
public actor KeyConsistencyAnalyzer {

    public init() {}

    // MARK: - Analysis

    /// Analyze key consistency across multiple catalogs.
    ///
    /// - Parameters:
    ///   - catalogs: URLs to xcstrings files to analyze.
    ///   - options: Analysis options.
    /// - Returns: A consistency report.
    public func analyze(
        catalogs: [URL],
        options: ConsistencyOptions = .init()
    ) async throws -> ConsistencyReport {
        guard catalogs.count >= 2 else {
            return ConsistencyReport(
                commonKeys: [],
                missingKeys: [:],
                conflicts: [],
                exclusiveKeys: [:]
            )
        }

        // Load all catalogs
        var loadedCatalogs: [(URL, XCStrings)] = []
        for url in catalogs {
            let xcstrings = try XCStrings.parse(from: url)
            loadedCatalogs.append((url, xcstrings))
        }

        // Build key sets for each catalog
        var keySets: [URL: Set<String>] = [:]
        for (url, xcstrings) in loadedCatalogs {
            keySets[url] = Set(xcstrings.strings.keys)
        }

        // Find common keys (intersection of all)
        let allKeySets = Array(keySets.values)
        let commonKeys = allKeySets.dropFirst().reduce(allKeySets.first ?? []) { $0.intersection($1) }

        // Find unified key set (union of all)
        let unifiedKeys = allKeySets.reduce(into: Set<String>()) { $0.formUnion($1) }

        // Find missing keys per catalog
        var missingKeys: [URL: Set<String>] = [:]
        for (url, keySet) in keySets {
            let missing = unifiedKeys.subtracting(keySet)
            if !missing.isEmpty {
                missingKeys[url] = missing
            }
        }

        // Find exclusive keys per catalog (keys only in one catalog)
        var exclusiveKeys: [URL: Set<String>] = [:]
        for (url, keySet) in keySets {
            let otherKeys = keySets
                .filter { $0.key != url }
                .values
                .reduce(into: Set<String>()) { $0.formUnion($1) }
            let exclusive = keySet.subtracting(otherKeys)
            if !exclusive.isEmpty {
                exclusiveKeys[url] = exclusive
            }
        }

        // Find conflicts (same key with different source values)
        var conflicts: [KeyConflict] = []
        if options.checkSourceConflicts {
            conflicts = findConflicts(in: loadedCatalogs, commonKeys: commonKeys)
        }

        return ConsistencyReport(
            commonKeys: commonKeys.sorted(),
            missingKeys: missingKeys,
            conflicts: conflicts,
            exclusiveKeys: exclusiveKeys
        )
    }

    /// Get unified key set across all catalogs.
    ///
    /// - Parameter catalogs: URLs to xcstrings files.
    /// - Returns: Set of all unique keys across all catalogs.
    public func getUnifiedKeySet(catalogs: [URL]) async throws -> Set<String> {
        var allKeys: Set<String> = []

        for url in catalogs {
            let xcstrings = try XCStrings.parse(from: url)
            allKeys.formUnion(xcstrings.strings.keys)
        }

        return allKeys
    }

    // MARK: - Conflict Detection

    private func findConflicts(
        in catalogs: [(URL, XCStrings)],
        commonKeys: Set<String>
    ) -> [KeyConflict] {
        var conflicts: [KeyConflict] = []

        for key in commonKeys {
            var sourceValues: [URL: String] = [:]

            for (url, xcstrings) in catalogs {
                guard let entry = xcstrings.strings[key],
                      let localization = entry.localizations?[xcstrings.sourceLanguage],
                      let value = localization.stringUnit?.value else { continue }
                sourceValues[url] = value
            }

            // Check if all values are the same
            let uniqueValues = Set(sourceValues.values)
            if uniqueValues.count > 1 {
                let conflict = KeyConflict(
                    key: key,
                    sourceValues: sourceValues,
                    recommendation: generateConflictRecommendation(key: key, values: sourceValues)
                )
                conflicts.append(conflict)
            }
        }

        return conflicts
    }

    private func generateConflictRecommendation(
        key: String,
        values: [URL: String]
    ) -> String {
        // Find the most common value
        var valueCounts: [String: Int] = [:]
        for value in values.values {
            valueCounts[value, default: 0] += 1
        }

        guard let (mostCommon, count) = valueCounts.max(by: { $0.value < $1.value }) else {
            return "Review manually to determine the correct value for '\(key)'."
        }

        if count > values.count / 2 {
            return "Use '\(mostCommon)' as it appears in \(count) of \(values.count) catalogs."
        }

        return "Review manually - no clear consensus for '\(key)'."
    }
}

// MARK: - Consistency Options

/// Options for consistency analysis.
public struct ConsistencyOptions: Sendable {
    /// Whether to check for conflicting source values.
    public var checkSourceConflicts: Bool

    /// Keys to exclude from analysis.
    public var excludedKeys: Set<String>

    /// Whether to include test targets.
    public var includeTestTargets: Bool

    public init(
        checkSourceConflicts: Bool = true,
        excludedKeys: Set<String> = [],
        includeTestTargets: Bool = false
    ) {
        self.checkSourceConflicts = checkSourceConflicts
        self.excludedKeys = excludedKeys
        self.includeTestTargets = includeTestTargets
    }
}

// MARK: - Consistency Report

/// Report from key consistency analysis.
public struct ConsistencyReport: Sendable {
    /// Keys present in all catalogs.
    public let commonKeys: [String]

    /// Keys missing from specific catalogs.
    public let missingKeys: [URL: Set<String>]

    /// Keys with conflicting source values.
    public let conflicts: [KeyConflict]

    /// Keys unique to specific catalogs.
    public let exclusiveKeys: [URL: Set<String>]

    /// Total number of unique keys across all catalogs.
    public var totalUniqueKeys: Int {
        let allMissing = missingKeys.values.reduce(into: Set<String>()) { $0.formUnion($1) }
        return commonKeys.count + allMissing.count
    }

    /// Whether all catalogs are consistent.
    public var isConsistent: Bool {
        missingKeys.isEmpty && conflicts.isEmpty
    }

    /// Summary of the analysis.
    public var summary: String {
        var lines: [String] = []
        lines.append("Common keys: \(commonKeys.count)")
        lines.append("Total unique keys: \(totalUniqueKeys)")

        if !missingKeys.isEmpty {
            let totalMissing = missingKeys.values.reduce(0) { $0 + $1.count }
            lines.append("Missing keys: \(totalMissing) across \(missingKeys.count) catalogs")
        }

        if !conflicts.isEmpty {
            lines.append("Conflicts: \(conflicts.count)")
        }

        if !exclusiveKeys.isEmpty {
            let totalExclusive = exclusiveKeys.values.reduce(0) { $0 + $1.count }
            lines.append("Exclusive keys: \(totalExclusive)")
        }

        return lines.joined(separator: "\n")
    }

    public init(
        commonKeys: [String],
        missingKeys: [URL: Set<String>],
        conflicts: [KeyConflict],
        exclusiveKeys: [URL: Set<String>]
    ) {
        self.commonKeys = commonKeys
        self.missingKeys = missingKeys
        self.conflicts = conflicts
        self.exclusiveKeys = exclusiveKeys
    }
}

// MARK: - Key Conflict

/// A conflict where the same key has different source values.
public struct KeyConflict: Sendable {
    /// The conflicting key.
    public let key: String

    /// Source values by catalog URL.
    public let sourceValues: [URL: String]

    /// Recommendation for resolving the conflict.
    public let recommendation: String

    public init(key: String, sourceValues: [URL: String], recommendation: String) {
        self.key = key
        self.sourceValues = sourceValues
        self.recommendation = recommendation
    }
}

// MARK: - Catalog Synchronizer

/// Synchronizes keys across multiple xcstrings catalogs.
public actor CatalogSynchronizer {

    public init() {}

    // MARK: - Synchronization

    /// Synchronize key order across all catalogs.
    ///
    /// - Parameters:
    ///   - catalogs: URLs to xcstrings files.
    ///   - sortMode: How to sort keys.
    public func synchronizeKeyOrder(
        catalogs: [URL],
        sortMode: KeySortMode
    ) async throws {
        for url in catalogs {
            var xcstrings = try XCStrings.parse(from: url)

            // Reorder keys
            let sortedEntries = sortEntries(xcstrings.strings, mode: sortMode)
            xcstrings.strings = sortedEntries

            // Write back
            try xcstrings.write(to: url, prettyPrint: true, sortKeys: false)
        }
    }

    /// Synchronize keys across catalogs.
    ///
    /// Adds missing keys with "needs translation" state.
    ///
    /// - Parameters:
    ///   - catalogs: URLs to xcstrings files.
    ///   - masterCatalog: Optional master catalog to use as source of truth.
    ///   - options: Synchronization options.
    /// - Returns: A synchronization report.
    public func synchronize(
        catalogs: [URL],
        options: SyncOptions
    ) async throws -> SyncReport {
        let analyzer = KeyConsistencyAnalyzer()
        _ = try await analyzer.analyze(catalogs: catalogs)

        var addedKeys: [URL: [String]] = [:]
        var skippedKeys: [String] = []

        // Get the unified key set
        let unifiedKeys = try await analyzer.getUnifiedKeySet(catalogs: catalogs)

        // For each catalog, add missing keys
        for url in catalogs {
            var xcstrings = try XCStrings.parse(from: url)
            var added: [String] = []

            for key in unifiedKeys {
                // Skip excluded keys
                if options.excludedKeys.contains(key) {
                    if !skippedKeys.contains(key) {
                        skippedKeys.append(key)
                    }
                    continue
                }

                // Add missing key
                if xcstrings.strings[key] == nil {
                    xcstrings.strings[key] = StringEntry(
                        extractionState: "manual",
                        shouldTranslate: true,
                        localizations: nil
                    )
                    added.append(key)
                }
            }

            if !added.isEmpty {
                addedKeys[url] = added

                // Write updated catalog
                if !options.dryRun {
                    try xcstrings.write(
                        to: url,
                        prettyPrint: true,
                        sortKeys: options.sortAfterSync
                    )
                }
            }
        }

        return SyncReport(
            addedKeys: addedKeys,
            skippedKeys: skippedKeys,
            totalKeysProcessed: unifiedKeys.count,
            dryRun: options.dryRun
        )
    }

    // MARK: - Sorting

    private func sortEntries(
        _ entries: [String: StringEntry],
        mode: KeySortMode
    ) -> [String: StringEntry] {
        let sortedKeys: [String]

        switch mode {
        case .alphabetical:
            sortedKeys = entries.keys.sorted()
        case .alphabeticalDescending:
            sortedKeys = entries.keys.sorted(by: >)
        case .byExtractionState:
            sortedKeys = entries.keys.sorted { k1, k2 in
                let state1 = entries[k1]?.extractionState ?? ""
                let state2 = entries[k2]?.extractionState ?? ""
                if state1 == state2 {
                    return k1 < k2
                }
                // "manual" first, then "stale", then others
                if state1 == "manual" { return true }
                if state2 == "manual" { return false }
                return state1 < state2
            }
        case .preserve:
            return entries
        }

        var result: [String: StringEntry] = [:]
        for key in sortedKeys {
            result[key] = entries[key]
        }
        return result
    }
}

// MARK: - Key Sort Mode

/// Mode for sorting keys in catalogs.
public enum KeySortMode: String, Sendable, Codable, CaseIterable {
    /// Alphabetical A-Z.
    case alphabetical
    /// Alphabetical Z-A.
    case alphabeticalDescending
    /// By extraction state (manual first).
    case byExtractionState
    /// Preserve original order.
    case preserve
}

// MARK: - Sync Options

/// Options for key synchronization.
public struct SyncOptions: Sendable {
    /// Keys to exclude from synchronization.
    public var excludedKeys: Set<String>

    /// Whether to sort keys after sync.
    public var sortAfterSync: Bool

    /// Whether this is a dry run (no changes written).
    public var dryRun: Bool

    /// How to handle conflicts.
    public var conflictResolution: ConflictResolution

    public init(
        excludedKeys: Set<String> = [],
        sortAfterSync: Bool = true,
        dryRun: Bool = false,
        conflictResolution: ConflictResolution = .keepFirst
    ) {
        self.excludedKeys = excludedKeys
        self.sortAfterSync = sortAfterSync
        self.dryRun = dryRun
        self.conflictResolution = conflictResolution
    }
}

// MARK: - Conflict Resolution

/// How to handle key conflicts during synchronization.
public enum ConflictResolution: String, Sendable, Codable {
    /// Keep the first encountered value.
    case keepFirst
    /// Keep the last encountered value.
    case keepLast
    /// Merge values (combine localizations).
    case merge
    /// Fail on conflict.
    case error
}

// MARK: - Sync Report

/// Report from key synchronization.
public struct SyncReport: Sendable {
    /// Keys added to each catalog.
    public let addedKeys: [URL: [String]]

    /// Keys that were skipped.
    public let skippedKeys: [String]

    /// Total keys processed.
    public let totalKeysProcessed: Int

    /// Whether this was a dry run.
    public let dryRun: Bool

    /// Number of catalogs modified.
    public var catalogsModified: Int {
        addedKeys.filter { !$0.value.isEmpty }.count
    }

    /// Total keys added across all catalogs.
    public var totalKeysAdded: Int {
        addedKeys.values.reduce(0) { $0 + $1.count }
    }

    /// Summary of the synchronization.
    public var summary: String {
        var lines: [String] = []

        if dryRun {
            lines.append("[DRY RUN] No changes written.")
        }

        lines.append("Processed \(totalKeysProcessed) keys")
        lines.append("Modified \(catalogsModified) catalogs")
        lines.append("Added \(totalKeysAdded) keys total")

        if !skippedKeys.isEmpty {
            lines.append("Skipped \(skippedKeys.count) excluded keys")
        }

        return lines.joined(separator: "\n")
    }

    public init(
        addedKeys: [URL: [String]],
        skippedKeys: [String],
        totalKeysProcessed: Int,
        dryRun: Bool
    ) {
        self.addedKeys = addedKeys
        self.skippedKeys = skippedKeys
        self.totalKeysProcessed = totalKeysProcessed
        self.dryRun = dryRun
    }
}
