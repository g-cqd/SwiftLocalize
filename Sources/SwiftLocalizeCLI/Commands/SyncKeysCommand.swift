//
//  SyncKeysCommand.swift
//  SwiftLocalize
//

import ArgumentParser
import Foundation
import SwiftLocalizeCore

// MARK: - SyncKeysCommand

struct SyncKeysCommand: AsyncParsableCommand {
    // MARK: Internal

    static let configuration = CommandConfiguration(
        commandName: "sync-keys",
        abstract: "Synchronize localization keys across multiple catalogs.",
    )

    @Argument(help: "xcstrings files to synchronize (at least 2).")
    var files: [String] = []

    @Flag(name: .customLong("all-targets"), help: "Synchronize all discovered targets.")
    var allTargets = false

    @Option(
        name: .customLong("sort"),
        help: "Key sorting mode: alphabetical, alphabeticalDescending, byExtractionState, preserve.",
    )
    var sortMode: String = "alphabetical"

    @Flag(name: .customLong("dry-run"), help: "Show what would be synchronized without making changes.")
    var dryRun = false

    @Flag(name: .customLong("json"), help: "Output as JSON.")
    var jsonOutput = false

    @Flag(name: [.short, .customLong("verbose")], help: "Verbose output.")
    var verbose = false

    func run() async throws {
        let catalogURLs = try await resolveCatalogURLs()

        // Analyze consistency
        let report = try await analyzeConsistency(catalogURLs: catalogURLs)

        // Display conflicts if any
        displayConflicts(report: report)

        // Perform synchronization
        let syncReport = try await performSync(catalogURLs: catalogURLs)

        // Output results
        if jsonOutput {
            try printJSONReport(syncReport)
        } else {
            printTextReport(syncReport)
        }
    }

    // MARK: Private

    private func resolveCatalogURLs() async throws -> [URL] {
        let fm = FileManager.default
        let cwd = fm.currentDirectoryPath
        var catalogURLs: [URL] = []

        if allTargets {
            let cwdURL = URL(fileURLWithPath: cwd)
            let detector = ProjectStructureDetector()
            let structure = try await detector.detect(at: cwdURL)

            if structure.targets.count < 2 {
                CLIOutput.printError("Need at least 2 targets for synchronization. Found: \(structure.targets.count)")
                throw ExitCode.failure
            }

            catalogURLs = structure.targets.map(\.xcstringsURL)
            print("Synchronizing \(catalogURLs.count) targets:")
            for target in structure.targets {
                print("  - \(target.name)")
            }
        } else {
            if files.count < 2 {
                CLIOutput.printError("Need at least 2 files for synchronization.")
                CLIOutput.printError("Usage: swiftlocalize sync-keys file1.xcstrings file2.xcstrings")
                throw ExitCode.failure
            }

            catalogURLs = files.map { URL(fileURLWithPath: $0, relativeTo: URL(fileURLWithPath: cwd)) }

            for url in catalogURLs {
                if !fm.fileExists(atPath: url.path) {
                    CLIOutput.printError("File not found: \(url.path)")
                    throw ExitCode.failure
                }
            }
        }

        return catalogURLs
    }

    private func analyzeConsistency(catalogURLs: [URL]) async throws -> ConsistencyReport {
        let analyzer = KeyConsistencyAnalyzer()
        let report = try await analyzer.analyze(catalogs: catalogURLs)

        if !jsonOutput {
            print("\nKey Consistency Analysis")
            print("========================")
            print(report.summary)
        }

        return report
    }

    private func displayConflicts(report: ConsistencyReport) {
        guard !report.conflicts.isEmpty, !jsonOutput else { return }

        print("\nConflicts found (\(report.conflicts.count)):")
        let conflictsToShow = verbose ? report.conflicts.prefix(100) : report.conflicts.prefix(5)

        for conflict in conflictsToShow {
            print("  '\(conflict.key)':")
            for (url, value) in conflict.sourceValues {
                print("    \(url.lastPathComponent): \"\(value)\"")
            }
            print("    Recommendation: \(conflict.recommendation)")
        }

        if report.conflicts.count > 5, !verbose {
            print("  ... and \(report.conflicts.count - 5) more. Use -v for full list.")
        }
    }

    private func performSync(catalogURLs: [URL]) async throws -> SyncReport {
        let syncSortMode = parseSortMode(sortMode)

        let synchronizer = CatalogSynchronizer()
        let syncOptions = SyncOptions(
            sortAfterSync: syncSortMode != .preserve,
            dryRun: dryRun,
        )

        return try await synchronizer.synchronize(
            catalogs: catalogURLs,
            options: syncOptions,
        )
    }

    private func parseSortMode(_ mode: String) -> KeySortMode {
        switch mode.lowercased() {
        case "alphabetical",
             "asc":
            .alphabetical
        case "alphabeticaldescending",
             "desc":
            .alphabeticalDescending
        case "byextractionstate",
             "extraction":
            .byExtractionState

        case "none",
             "preserve":
            .preserve

        default:
            .alphabetical
        }
    }

    private func printJSONReport(_ syncReport: SyncReport) throws {
        struct JSONSyncReport: Encodable {
            let dryRun: Bool
            let totalKeysProcessed: Int
            let catalogsModified: Int
            let totalKeysAdded: Int
            let addedByFile: [String: [String]]
        }

        let jsonReport = JSONSyncReport(
            dryRun: syncReport.dryRun,
            totalKeysProcessed: syncReport.totalKeysProcessed,
            catalogsModified: syncReport.catalogsModified,
            totalKeysAdded: syncReport.totalKeysAdded,
            addedByFile: Dictionary(uniqueKeysWithValues: syncReport.addedKeys.map { url, keys in
                (url.lastPathComponent, keys)
            }),
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(jsonReport)
        print(String(data: data, encoding: .utf8) ?? "{}")
    }

    private func printTextReport(_ syncReport: SyncReport) {
        print("\nSynchronization \(dryRun ? "Preview" : "Complete")")
        print("=========================")
        print(syncReport.summary)

        if verbose, !syncReport.addedKeys.isEmpty {
            print("\nKeys added by file:")
            for (url, keys) in syncReport.addedKeys {
                print("  \(url.lastPathComponent): \(keys.count) keys")
                for key in keys.prefix(10) {
                    print("    + \(key)")
                }
                if keys.count > 10 {
                    print("    ... and \(keys.count - 10) more")
                }
            }
        }
    }
}
