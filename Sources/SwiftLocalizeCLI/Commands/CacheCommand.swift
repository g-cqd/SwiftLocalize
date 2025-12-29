//
//  CacheCommand.swift
//  SwiftLocalize
//

import ArgumentParser
import Foundation
import SwiftLocalizeCore

// MARK: - CacheCommand

struct CacheCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "cache",
        abstract: "Manage translation cache.",
        subcommands: [
            CacheInfo.self,
            CacheClear.self,
        ],
        defaultSubcommand: CacheInfo.self,
    )
}

// MARK: - CacheInfo

struct CacheInfo: AsyncParsableCommand {
    // MARK: Internal

    static let configuration = CommandConfiguration(
        commandName: "info",
        abstract: "Show translation cache information.",
    )

    @Option(name: [.short, .customLong("file")], help: "Cache file path.")
    var cachePath: String = ".swiftlocalize-cache.json"

    @Flag(name: .customLong("json"), help: "Output as JSON.")
    var jsonOutput = false

    func run() async throws {
        let cacheURL = URL(fileURLWithPath: cachePath)

        guard FileManager.default.fileExists(atPath: cacheURL.path) else {
            print("No cache file found at: \(cachePath)")
            print("Cache will be created after the first translation run.")
            return
        }

        let detector = ChangeDetector(cacheFile: cacheURL)
        try await detector.load()

        let stats = await detector.statistics

        if jsonOutput {
            try printJSONStats(stats, cachePath: cachePath)
        } else {
            printTextStats(stats, cachePath: cachePath)
        }
    }

    // MARK: Private

    private func printJSONStats(_ stats: CacheStatistics, cachePath: String) throws {
        struct CacheStats: Encodable {
            let cacheFile: String
            let version: String
            let totalEntries: Int
            let lastUpdated: String?
        }

        let dateFormatter = ISO8601DateFormatter()
        let jsonStats = CacheStats(
            cacheFile: cachePath,
            version: stats.cacheVersion,
            totalEntries: stats.totalEntries,
            lastUpdated: stats.lastUpdated.map { dateFormatter.string(from: $0) },
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(jsonStats)
        print(String(data: data, encoding: .utf8) ?? "{}")
    }

    private func printTextStats(_ stats: CacheStatistics, cachePath: String) {
        print("Translation Cache Info")
        print(String(repeating: "=", count: 40))
        print("File: \(cachePath)")
        print("Version: \(stats.cacheVersion)")
        print("Cached strings: \(stats.totalEntries)")
        if let lastUpdated = stats.lastUpdated {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .short
            print("Last updated: \(formatter.string(from: lastUpdated))")
        }
    }
}

// MARK: - CacheClear

struct CacheClear: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "clear",
        abstract: "Clear the translation cache.",
    )

    @Option(name: [.short, .customLong("file")], help: "Cache file path.")
    var cachePath: String = ".swiftlocalize-cache.json"

    @Flag(name: .customLong("confirm"), help: "Skip confirmation prompt.")
    var confirm = false

    func run() async throws {
        let cacheURL = URL(fileURLWithPath: cachePath)

        guard FileManager.default.fileExists(atPath: cacheURL.path) else {
            print("No cache file found at: \(cachePath)")
            return
        }

        if !confirm {
            print("This will delete the translation cache at: \(cachePath)")
            print("All strings will be re-translated on the next run.")
            print("Press Enter to confirm, or Ctrl+C to cancel...")
            _ = readLine()
        }

        try FileManager.default.removeItem(at: cacheURL)
        print("Cache cleared: \(cachePath)")
    }
}
