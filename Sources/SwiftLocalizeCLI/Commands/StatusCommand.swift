//
//  StatusCommand.swift
//  SwiftLocalize
//

import ArgumentParser
import Foundation
import SwiftLocalizeCore

// MARK: - StatusCommand

struct StatusCommand: AsyncParsableCommand {
    // MARK: Internal

    static let configuration = CommandConfiguration(
        commandName: "status",
        abstract: "Show translation status.",
    )

    @Option(name: [.short, .customLong("config")], help: "Configuration file path.")
    var configPath: String?

    @Argument(help: "File patterns to process.")
    var files: [String] = []

    @Flag(name: .customLong("json"), help: "Output as JSON.")
    var jsonOutput = false

    func run() async throws {
        let loader = ConfigurationLoader()
        let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)

        let config: Configuration = if let configPath = configPath {
            try loader.load(from: URL(fileURLWithPath: configPath))
        } else {
            (try? loader.load(searchingIn: cwd)) ?? loader.defaultConfiguration()
        }

        let xcstringsURLs = findXCStringsFiles(in: cwd)

        if xcstringsURLs.isEmpty {
            print("No xcstrings files found.")
            return
        }

        let allStatus = try collectStatus(urls: xcstringsURLs, config: config)

        if jsonOutput {
            try printJSONStatus(allStatus)
        } else {
            printTextStatus(allStatus)
        }
    }

    // MARK: Private

    private struct FileStatus {
        let file: String
        let totalStrings: Int
        let languages: [String: LanguageStatus]
    }

    private struct LanguageStatus {
        let translated: Int
        let missing: Int
        let percentage: Double
    }

    private func findXCStringsFiles(in directory: URL) -> [URL] {
        var xcstringsURLs: [URL] = []
        let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles],
        )
        while let url = enumerator?.nextObject() as? URL {
            if url.pathExtension == "xcstrings" {
                xcstringsURLs.append(url)
            }
        }
        return xcstringsURLs
    }

    private func collectStatus(urls: [URL], config: Configuration) throws -> [FileStatus] {
        var allStatus: [FileStatus] = []

        for url in urls {
            let xcstrings: XCStrings
            do {
                xcstrings = try XCStrings.parse(from: url)
            } catch {
                CLIOutput.printError("Failed to parse \(url.lastPathComponent): \(error.localizedDescription)")
                continue
            }

            let totalStrings = xcstrings.strings.count
            var languageStatus: [String: LanguageStatus] = [:]

            for targetLang in config.targetLanguages {
                let missing = xcstrings.keysNeedingTranslation(for: targetLang.code)
                let translated = totalStrings - missing.count
                let percentage = totalStrings > 0 ? Double(translated) / Double(totalStrings) * 100 : 100

                languageStatus[targetLang.code] = LanguageStatus(
                    translated: translated,
                    missing: missing.count,
                    percentage: percentage,
                )
            }

            allStatus.append(FileStatus(
                file: url.lastPathComponent,
                totalStrings: totalStrings,
                languages: languageStatus,
            ))
        }

        return allStatus
    }

    private func printJSONStatus(_ allStatus: [FileStatus]) throws {
        struct JSONStatus: Encodable {
            let files: [JSONFileStatus]
        }

        struct JSONFileStatus: Encodable {
            let file: String
            let totalStrings: Int
            let languages: [String: JSONLangStatus]
        }

        struct JSONLangStatus: Encodable {
            let translated: Int
            let missing: Int
            let percentage: Double
        }

        let jsonStatus = JSONStatus(
            files: allStatus.map { status in
                JSONFileStatus(
                    file: status.file,
                    totalStrings: status.totalStrings,
                    languages: status.languages.mapValues { lang in
                        JSONLangStatus(
                            translated: lang.translated,
                            missing: lang.missing,
                            percentage: lang.percentage,
                        )
                    },
                )
            },
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(jsonStatus)
        print(String(data: data, encoding: .utf8) ?? "{}")
    }

    private func printTextStatus(_ allStatus: [FileStatus]) {
        print("Translation Status")
        print("==================\n")

        for status in allStatus {
            print("\(status.file) (\(status.totalStrings) strings)")

            for (langCode, langStatus) in status.languages.sorted(by: { $0.key < $1.key }) {
                let bar = makeProgressBar(percentage: langStatus.percentage, width: 20)
                let percentStr = String(format: "%5.1f%%", langStatus.percentage)
                print("  \(langCode): \(bar) \(percentStr) (\(langStatus.translated)/\(status.totalStrings))")
            }
            print()
        }
    }

    private func makeProgressBar(percentage: Double, width: Int) -> String {
        let filled = Int(Double(width) * percentage / 100)
        let empty = width - filled
        return "[" + String(repeating: "=", count: filled) + String(repeating: " ", count: empty) + "]"
    }
}
