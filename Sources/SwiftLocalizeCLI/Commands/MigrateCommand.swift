//
//  MigrateCommand.swift
//  SwiftLocalize
//

import ArgumentParser
import Foundation
import SwiftLocalizeCore

// MARK: - MigrateCommand

struct MigrateCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "migrate",
        abstract: "Migrate between localization file formats.",
        subcommands: [
            MigrateToXCStrings.self,
            MigrateToLegacy.self,
        ],
        defaultSubcommand: MigrateToXCStrings.self,
    )
}

// MARK: - MigrateToXCStrings

struct MigrateToXCStrings: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "to-xcstrings",
        abstract: "Migrate .strings/.stringsdict files to .xcstrings format.",
    )

    @Option(name: [.short, .customLong("input")], help: "Input directory containing .lproj folders.")
    var inputDirectory: String?

    @Option(name: [.short, .customLong("output")], help: "Output .xcstrings file path.")
    var outputPath: String = "Localizable.xcstrings"

    @Option(name: .customLong("source-lang"), help: "Source language code.")
    var sourceLanguage: String = "en"

    @Option(name: .customLong("strings-file"), help: "Name of .strings file to migrate.")
    var stringsFileName: String = "Localizable.strings"

    @Option(name: .customLong("stringsdict-file"), help: "Name of .stringsdict file to migrate.")
    var stringsdictFileName: String = "Localizable.stringsdict"

    @Flag(name: [.short, .customLong("verbose")], help: "Verbose output.")
    var verbose = false

    func run() async throws {
        let fm = FileManager.default
        let cwd = fm.currentDirectoryPath

        let inputDir = if let input = inputDirectory {
            URL(fileURLWithPath: input, relativeTo: URL(fileURLWithPath: cwd))
        } else {
            URL(fileURLWithPath: cwd)
        }

        let outputURL = URL(fileURLWithPath: outputPath, relativeTo: URL(fileURLWithPath: cwd))

        if verbose {
            print("Migrating from: \(inputDir.path)")
            print("Output: \(outputURL.path)")
            print("Source language: \(sourceLanguage)")
        }

        let migrator = FormatMigrator()

        let xcstrings = try await migrator.migrateDirectoryToXCStrings(
            directory: inputDir,
            stringsFileName: stringsFileName,
            stringsdictFileName: stringsdictFileName,
            sourceLanguage: sourceLanguage,
        )

        try xcstrings.write(to: outputURL)

        let languages = xcstrings.presentLanguages
        print("Migration complete!")
        print("  Strings: \(xcstrings.strings.count)")
        print("  Languages: \(languages.joined(separator: ", "))")
        print("  Output: \(outputURL.lastPathComponent)")
    }
}

// MARK: - MigrateToLegacy

struct MigrateToLegacy: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "to-legacy",
        abstract: "Migrate .xcstrings file to .strings/.stringsdict format.",
    )

    @Argument(help: "Input .xcstrings file path.")
    var inputPath: String

    @Option(name: [.short, .customLong("output")], help: "Output directory for .lproj folders.")
    var outputDirectory: String?

    @Option(name: .customLong("strings-file"), help: "Name for output .strings files.")
    var stringsFileName: String = "Localizable.strings"

    @Option(name: .customLong("stringsdict-file"), help: "Name for output .stringsdict files.")
    var stringsdictFileName: String = "Localizable.stringsdict"

    @Flag(name: [.short, .customLong("verbose")], help: "Verbose output.")
    var verbose = false

    func run() async throws {
        let fm = FileManager.default
        let cwd = fm.currentDirectoryPath

        let inputURL = URL(fileURLWithPath: inputPath, relativeTo: URL(fileURLWithPath: cwd))

        let outputDir: URL = if let output = outputDirectory {
            URL(fileURLWithPath: output, relativeTo: URL(fileURLWithPath: cwd))
        } else {
            inputURL.deletingLastPathComponent()
        }

        guard fm.fileExists(atPath: inputURL.path) else {
            CLIOutput.printError("Input file not found: \(inputPath)")
            throw ExitCode.failure
        }

        if verbose {
            print("Migrating from: \(inputURL.path)")
            print("Output directory: \(outputDir.path)")
        }

        let xcstrings = try XCStrings.parse(from: inputURL)
        let migrator = FormatMigrator()

        try await migrator.migrateXCStringsToDirectory(
            xcstrings: xcstrings,
            directory: outputDir,
            stringsFileName: stringsFileName,
            stringsdictFileName: stringsdictFileName,
        )

        let languages = xcstrings.presentLanguages
        print("Migration complete!")
        print("  Strings: \(xcstrings.strings.count)")
        print("  Languages exported: \(languages.joined(separator: ", "))")
        print("  Output: \(outputDir.path)")
    }
}
