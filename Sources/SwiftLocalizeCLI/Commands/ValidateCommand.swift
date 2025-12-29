//
//  ValidateCommand.swift
//  SwiftLocalize
//

import ArgumentParser
import Foundation
import SwiftLocalizeCore

// MARK: - ValidateCommand

struct ValidateCommand: AsyncParsableCommand {
    // MARK: Internal

    static let configuration = CommandConfiguration(
        commandName: "validate",
        abstract: "Validate translations in xcstrings files.",
    )

    @Option(name: [.short, .customLong("config")], help: "Configuration file path.")
    var configPath: String?

    @Argument(help: "File patterns to process.")
    var files: [String] = []

    @Flag(name: .customLong("strict"), help: "Fail on any validation warning.")
    var strict = false

    @Flag(name: .customLong("json"), help: "Output as JSON.")
    var jsonOutput = false

    @Flag(name: .customLong("ci"), help: "CI/CD mode (implies --strict and --json).")
    var ciMode = false

    func run() async throws {
        let effectiveStrict = strict || ciMode
        let effectiveJson = jsonOutput || ciMode
        let loader = ConfigurationLoader()
        let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)

        let config: Configuration = if let configPath = configPath {
            try loader.load(from: URL(fileURLWithPath: configPath))
        } else {
            (try? loader.load(searchingIn: cwd)) ?? loader.defaultConfiguration()
        }

        let xcstringsURLs = findXCStringsFiles(in: cwd)

        if xcstringsURLs.isEmpty {
            CLIOutput.printWarning("No xcstrings files found.")
            return
        }

        var hasErrors = false
        var hasWarnings = false

        for url in xcstringsURLs {
            let result = try validateFile(url: url, config: config)
            hasErrors = hasErrors || result.hasErrors
            hasWarnings = hasWarnings || result.hasWarnings
        }

        if hasErrors || (effectiveStrict && hasWarnings) {
            throw ExitCode.failure
        }

        if !hasErrors, !hasWarnings, !effectiveJson {
            print("\nValidation passed!")
        }
    }

    // MARK: Private

    private struct ValidationResult {
        let hasErrors: Bool
        let hasWarnings: Bool
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

    private func validateFile(url: URL, config: Configuration) throws -> ValidationResult {
        var hasErrors = false
        var hasWarnings = false

        let xcstrings: XCStrings
        do {
            xcstrings = try XCStrings.parse(from: url)
        } catch {
            CLIOutput.printError("Failed to parse \(url.lastPathComponent): \(error.localizedDescription)")
            return ValidationResult(hasErrors: true, hasWarnings: false)
        }

        print("Validating: \(url.lastPathComponent)")

        // Check for missing translations
        for targetLang in config.targetLanguages {
            let missing = xcstrings.keysNeedingTranslation(for: targetLang.code)
            if !missing.isEmpty {
                if config.validation.requireAllLanguages {
                    CLIOutput.printError("  [\(targetLang.code)] Missing \(missing.count) translation(s)")
                    hasErrors = true
                } else {
                    CLIOutput.printWarning("  [\(targetLang.code)] Missing \(missing.count) translation(s)")
                    hasWarnings = true
                }
            }
        }

        // Check for format specifier consistency
        if config.validation.validateFormatters {
            let formatResult = validateFormatSpecifiers(xcstrings: xcstrings)
            hasWarnings = hasWarnings || formatResult
        }

        // Check for missing comments
        if config.validation.warnMissingComments {
            let commentResult = validateComments(xcstrings: xcstrings)
            hasWarnings = hasWarnings || commentResult
        }

        return ValidationResult(hasErrors: hasErrors, hasWarnings: hasWarnings)
    }

    private func validateFormatSpecifiers(xcstrings: XCStrings) -> Bool {
        var hasWarnings = false

        for (key, entry) in xcstrings.strings {
            guard let sourceLocalization = entry.localizations?[xcstrings.sourceLanguage],
                  let sourceValue = sourceLocalization.stringUnit?.value
            else {
                continue
            }

            let sourceSpecifiers = extractFormatSpecifiers(from: sourceValue)

            for (langCode, localization) in entry.localizations ?? [:] {
                guard langCode != xcstrings.sourceLanguage,
                      let targetValue = localization.stringUnit?.value
                else {
                    continue
                }

                let targetSpecifiers = extractFormatSpecifiers(from: targetValue)

                if sourceSpecifiers.sorted() != targetSpecifiers.sorted() {
                    CLIOutput.printWarning("  [\(langCode)] Format specifier mismatch in '\(key)'")
                    hasWarnings = true
                }
            }
        }

        return hasWarnings
    }

    private func validateComments(xcstrings: XCStrings) -> Bool {
        var hasWarnings = false

        for (key, entry) in xcstrings.strings {
            if entry.comment == nil || entry.comment?.isEmpty == true {
                CLIOutput.printWarning("  Missing comment for '\(key)'")
                hasWarnings = true
            }
        }

        return hasWarnings
    }

    private func extractFormatSpecifiers(from string: String) -> [String] {
        let pattern = #"%[@dDuUxXoOfeEgGcCsSpaAFn]|%[0-9]*\.?[0-9]*[dDuUxXoOfeEgGcCsSpaAFnlh@]+"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(string.startIndex..., in: string)
        let matches = regex.matches(in: string, range: range)
        return matches.compactMap { match in
            guard let swiftRange = Range(match.range, in: string) else { return nil }
            return String(string[swiftRange])
        }
    }
}
