//
//  SwiftLocalize.swift
//  SwiftLocalize
//

import ArgumentParser
import Foundation
import SwiftLocalizeCore

extension OperationMode: ExpressibleByArgument {}
extension ContextDepth: ExpressibleByArgument {}

@main
struct SwiftLocalize: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "swiftlocalize",
        abstract: "Automated localization for Swift projects using AI/ML translation providers.",
        version: "0.3.0",
        subcommands: [
            TranslateCommand.self,
            ValidateCommand.self,
            StatusCommand.self,
            InitCommand.self,
            ProvidersCommand.self,
            MigrateCommand.self,
            GlossaryCommand.self,
            CacheCommand.self,
            TargetsCommand.self,
            SyncKeysCommand.self,
        ],
        defaultSubcommand: TranslateCommand.self
    )
}

// MARK: - Translate Command

struct TranslateCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "translate",
        abstract: "Translate xcstrings files."
    )

    @Option(name: [.short, .customLong("config")], help: "Configuration file path.")
    var configPath: String?

    @Argument(help: "File patterns to process (glob patterns like **/*.xcstrings).")
    var files: [String] = []

    @Option(name: [.short, .customLong("languages")], help: "Target languages (comma-separated).")
    var languages: String?

    @Option(name: [.short, .customLong("provider")], help: "Use a specific provider.")
    var provider: String?

    @Flag(name: .customLong("dry-run"), help: "Show what would be translated without making changes.")
    var dryRun = false

    @Flag(name: .customLong("force"), help: "Force retranslation of all strings.")
    var force = false

    @Flag(name: [.short, .customLong("verbose")], help: "Verbose output.")
    var verbose = false

    @Flag(name: [.short, .customLong("quiet")], help: "Minimal output.")
    var quiet = false

    @Flag(name: .customLong("json"), help: "Output as JSON.")
    var jsonOutput = false

    @Flag(name: .customLong("ci"), help: "CI/CD mode with strict exit codes and minimal output.")
    var ciMode = false

    @Flag(name: .customLong("incremental"), inversion: .prefixedNo, help: "Use incremental translation (skip unchanged strings).")
    var incremental = true

    @Flag(name: .customLong("preview"), help: "Show proposed translations without applying them.")
    var preview = false

    @Flag(name: .customLong("backup"), help: "Create backup files before modifying (.xcstrings.bak).")
    var backup = false

    @Option(name: .customLong("target"), help: "Translate a specific target only.")
    var target: String?

    @Flag(name: .customLong("all-targets"), help: "Translate all discovered targets in the project.")
    var allTargets = false

    @Option(name: .customLong("mode"), help: "Operation mode (translation-only, full).")
    var mode: OperationMode = .translationOnly

    @Flag(name: .customLong("with-context"), help: "Extract usage context from source code (read-only).")
    var withContext = false

    @Flag(name: .customLong("no-context"), help: "Skip context extraction entirely.")
    var noContext = false

    @Option(name: .customLong("context-depth"), help: "Context extraction depth (none, minimal, standard, deep).")
    var contextDepth: ContextDepth = .standard

    @Flag(name: .customLong("verify-isolation"), help: "Verify strict file isolation before running.")
    var verifyIsolation = false

    @Flag(name: .customLong("show-context"), help: "Show extracted context in output.")
    var showContext = false

    func run() async throws {
        // CI mode implies quiet and JSON output
        let effectiveQuiet = quiet || ciMode
        let effectiveJson = jsonOutput || ciMode

        let loader = ConfigurationLoader()

        // Load configuration
        let configuration: Configuration
        if let configPath = configPath {
            let configURL = URL(fileURLWithPath: configPath)
            do {
                configuration = try loader.load(from: configURL)
            } catch {
                printError("Failed to load config: \(error.localizedDescription)")
                throw ExitCode.failure
            }
        } else {
            let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            do {
                configuration = try loader.load(searchingIn: cwd)
            } catch {
                if !effectiveQuiet {
                    printError("No configuration file found. Run 'swiftlocalize init' to create one.")
                    printError("Or specify target languages with --languages")
                }
                throw ExitCode.failure
            }
        }

        // Apply CLI overrides to configuration
        var config = configuration

        // Mode override
        config.mode = mode

        // Context overrides
        if noContext {
            config.context.depth = .none
            config.context.sourceCode?.enabled = false
        } else if withContext {
            config.context.depth = contextDepth
            if config.context.sourceCode == nil {
                config.context.sourceCode = SourceCodeSettings(enabled: true)
            } else {
                config.context.sourceCode?.enabled = true
            }
        } else {
             // Respect flag if set explicitly, otherwise keep config
             if contextDepth != .standard {
                 config.context.depth = contextDepth
             }
        }

        // Isolation overrides
        if verifyIsolation {
            config.isolation.verifyBeforeRun = true
        }

        if let languagesArg = languages {
            let langs = languagesArg.split(separator: ",").map { LanguageCode(String($0).trimmingCharacters(in: .whitespaces)) }
            config.targetLanguages = langs
        }

        // Validate configuration
        let issues = loader.validate(config)
        let errors = issues.filter(\.isError)
        if !errors.isEmpty {
            for issue in errors {
                printError("Error: \(issue.message)")
            }
            throw ExitCode.failure
        }

        if verbose {
            let warnings = issues.filter { !$0.isError }
            for warning in warnings {
                printWarning("Warning: \(warning.message)")
            }
        }

        // Handle multi-target mode
        var xcstringsURLs: [URL] = []

        if allTargets || target != nil {
            let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            let detector = ProjectStructureDetector()
            let structure = try await detector.detect(at: cwd)

            if let targetName = target {
                // Find specific target
                guard let locTarget = structure.targets.first(where: { $0.name == targetName }) else {
                    printError("Target '\(targetName)' not found. Available targets:")
                    for t in structure.targets {
                        printError("  - \(t.name)")
                    }
                    throw ExitCode.failure
                }
                xcstringsURLs = [locTarget.xcstringsURL]
                if verbose && !effectiveQuiet {
                    print("Translating target: \(targetName)")
                }
            } else {
                // All targets
                xcstringsURLs = structure.targets.map(\.xcstringsURL)
                if verbose && !effectiveQuiet {
                    print("Discovered \(structure.targets.count) target(s)")
                    for t in structure.targets {
                        print("  - \(t.name): \(t.xcstringsURL.lastPathComponent)")
                    }
                }
            }
        } else {
            // Find xcstrings files using patterns
            xcstringsURLs = try findXCStringsFiles(patterns: files.isEmpty ? config.files.include : files)
        }

        if xcstringsURLs.isEmpty {
            if !effectiveQuiet {
                printWarning("No xcstrings files found.")
            }
            // In CI mode, no files is a success (nothing to translate)
            return
        }

        if verbose && !effectiveQuiet {
            print("Found \(xcstringsURLs.count) xcstrings file(s)")
            for url in xcstringsURLs {
                print("  - \(url.lastPathComponent)")
            }
        }

        // Isolation Verification
        if config.isolation.verifyBeforeRun {
            if verbose && !effectiveQuiet {
                print("Verifying file isolation...")
            }
            let verifier = IsolationVerifier()
            let result = try await verifier.verify(configuration: config, mode: config.mode, files: xcstringsURLs)

            if !result.isIsolated {
                printError("Isolation verification failed!")
                for warning in result.warnings {
                    printError("  - \(warning)")
                }
                if config.isolation.strict {
                    throw ExitCode.failure
                }
            } else if verbose && !effectiveQuiet {
                print("Isolation verification passed.")
            }
        }

        // Dry run - just show what would be translated
        if dryRun {
            try await performDryRun(urls: xcstringsURLs, config: config)
            return
        }

        // Preview mode - show proposed translations without applying
        if preview {
            try await performPreview(urls: xcstringsURLs, config: config)
            return
        }

        // Create backups if requested
        if backup {
            for url in xcstringsURLs {
                let backupURL = url.appendingPathExtension("bak")
                try? FileManager.default.removeItem(at: backupURL)
                try FileManager.default.copyItem(at: url, to: backupURL)
                if verbose && !effectiveQuiet {
                    print("Backup created: \(backupURL.lastPathComponent)")
                }
            }
        }

        // Create translation service
        let service = TranslationService(configuration: config)
        await service.registerDefaultProviders()

        // Perform translation
        if !effectiveQuiet {
            print("Starting translation...")
        }

        let report = try await service.translateFiles(at: xcstringsURLs) { progress in
            if !effectiveQuiet && !effectiveJson {
                let percentage = Int(progress.percentage * 100)
                let langInfo = progress.currentLanguage.map { " [\($0.code)]" } ?? ""
                print("\rProgress: \(percentage)%\(langInfo) (\(progress.completed)/\(progress.total))", terminator: "")
                fflush(stdout)
            }
        }

        if !effectiveQuiet && !effectiveJson {
            print() // New line after progress
        }

        // Output results
        if effectiveJson {
            try printJSONReport(report, ciMode: ciMode)
        } else if !effectiveQuiet {
            printReport(report)
        }

        // Exit codes for CI
        if report.failedCount > 0 {
            throw ExitCode(1) // Translation errors
        }
        if ciMode && report.translatedCount == 0 && report.totalStrings > 0 {
            // In CI mode, if nothing was translated but there were strings, it's informational
            // This is not an error - could mean all strings were already translated
        }
    }

    private func findXCStringsFiles(patterns: [String]) throws -> [URL] {
        let fm = FileManager.default
        let cwd = fm.currentDirectoryPath
        var results: [URL] = []

        for pattern in patterns {
            if pattern.contains("*") {
                // Simple glob expansion for common patterns
                let expanded = expandGlob(pattern: pattern, in: cwd)
                results.append(contentsOf: expanded)
            } else {
                let url = URL(fileURLWithPath: pattern, relativeTo: URL(fileURLWithPath: cwd))
                if fm.fileExists(atPath: url.path) {
                    results.append(url)
                }
            }
        }

        return results.filter { $0.pathExtension == "xcstrings" }
    }

    private func expandGlob(pattern: String, in directory: String) -> [URL] {
        // Simple recursive file search
        let fm = FileManager.default
        var results: [URL] = []

        let baseURL = URL(fileURLWithPath: directory)
        let enumerator = fm.enumerator(
            at: baseURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )

        while let url = enumerator?.nextObject() as? URL {
            if url.pathExtension == "xcstrings" {
                // Check if matches pattern (simple check for **/*.xcstrings)
                if pattern.contains("**") || pattern == "*.xcstrings" || url.lastPathComponent.hasSuffix(".xcstrings") {
                    results.append(url)
                }
            }
        }

        return results
    }

    private func performDryRun(urls: [URL], config: Configuration) async throws {
        print("Dry run - showing what would be translated:\n")

        for url in urls {
            let xcstrings = try XCStrings.parse(from: url)
            print("File: \(url.lastPathComponent)")

            for targetLanguage in config.targetLanguages {
                let keys = xcstrings.keysNeedingTranslation(for: targetLanguage.code)
                if !keys.isEmpty {
                    print("  \(targetLanguage.code): \(keys.count) string(s) need translation")
                    if verbose {
                        for key in keys.prefix(10) {
                            print("    - \"\(key)\"")
                        }
                        if keys.count > 10 {
                            print("    ... and \(keys.count - 10) more")
                        }
                    }
                } else {
                    print("  \(targetLanguage.code): All translated")
                }
            }
            print()
        }
    }

    private func performPreview(urls: [URL], config: Configuration) async throws {
        print("Translation Preview")
        print("===================\n")

        let service = TranslationService(configuration: config)
        await service.registerDefaultProviders()

        for url in urls {
            let xcstrings = try XCStrings.parse(from: url)
            print("File: \(url.lastPathComponent)\n")

            for targetLanguage in config.targetLanguages {
                let keys = xcstrings.keysNeedingTranslation(for: targetLanguage.code)
                guard !keys.isEmpty else { continue }

                print("  [\(targetLanguage.code)] \(keys.count) string(s) to translate:")

                // Get source strings to translate (limit to first 5 for preview)
                let previewKeys = keys.prefix(5)
                var stringsToPreview: [String] = []

                for key in previewKeys {
                    if let entry = xcstrings.strings[key],
                       let sourceLocalization = entry.localizations?[xcstrings.sourceLanguage],
                       let sourceValue = sourceLocalization.stringUnit?.value {
                        stringsToPreview.append(sourceValue)
                    } else {
                        stringsToPreview.append(key)
                    }
                }

                // Translate preview batch
                do {
                    let results = try await service.translateBatch(
                        stringsToPreview,
                        from: LanguageCode(xcstrings.sourceLanguage),
                        to: targetLanguage
                    )

                    for (index, result) in results.enumerated() {
                        let key = Array(previewKeys)[index]
                        print("    \"\(key)\":")
                        print("      Source: \(result.original)")
                        print("      → \(result.translated)")
                    }

                    if keys.count > 5 {
                        print("    ... and \(keys.count - 5) more strings")
                    }
                } catch {
                    print("    Error: \(error.localizedDescription)")
                }

                print()
            }
        }

        print("NOTE: No changes were saved. Run without --preview to apply translations.")
    }

    private func printReport(_ report: TranslationReport) {
        let seconds = report.duration.components.seconds
        let milliseconds = report.duration.components.attoseconds / 1_000_000_000_000_000

        print("\nTranslation Complete")
        print("====================")
        print("Total strings:  \(report.totalStrings)")
        print("Translated:     \(report.translatedCount)")
        print("Failed:         \(report.failedCount)")
        print("Skipped:        \(report.skippedCount)")
        print("Duration:       \(seconds).\(String(format: "%03d", milliseconds))s")

        if !report.byLanguage.isEmpty {
            print("\nBy Language:")
            for (lang, langReport) in report.byLanguage.sorted(by: { $0.key.code < $1.key.code }) {
                print("  \(lang.code): \(langReport.translatedCount) translated, \(langReport.failedCount) failed [\(langReport.provider)]")
            }
        }

        if !report.errors.isEmpty && verbose {
            print("\nErrors:")
            for error in report.errors.prefix(10) {
                print("  [\(error.language.code)] \(error.key): \(error.message)")
            }
            if report.errors.count > 10 {
                print("  ... and \(report.errors.count - 10) more errors")
            }
        }
    }

    private func printJSONReport(_ report: TranslationReport, ciMode: Bool = false) throws {
        struct JSONReport: Encodable {
            let totalStrings: Int
            let translatedCount: Int
            let failedCount: Int
            let skippedCount: Int
            let durationSeconds: Double
            let byLanguage: [String: LanguageInfo]
            let errors: [ErrorInfo]

            struct LanguageInfo: Encodable {
                let translatedCount: Int
                let failedCount: Int
                let provider: String
            }

            struct ErrorInfo: Encodable {
                let key: String
                let language: String
                let message: String
            }
        }

        let seconds = Double(report.duration.components.seconds) +
            Double(report.duration.components.attoseconds) / 1_000_000_000_000_000_000

        let jsonReport = JSONReport(
            totalStrings: report.totalStrings,
            translatedCount: report.translatedCount,
            failedCount: report.failedCount,
            skippedCount: report.skippedCount,
            durationSeconds: seconds,
            byLanguage: Dictionary(uniqueKeysWithValues: report.byLanguage.map { (lang, info) in
                (lang.code, JSONReport.LanguageInfo(
                    translatedCount: info.translatedCount,
                    failedCount: info.failedCount,
                    provider: info.provider
                ))
            }),
            errors: report.errors.map { error in
                JSONReport.ErrorInfo(
                    key: error.key,
                    language: error.language.code,
                    message: error.message
                )
            }
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(jsonReport)
        print(String(data: data, encoding: .utf8) ?? "{}")
    }
}

// MARK: - Validate Command

struct ValidateCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "validate",
        abstract: "Validate translations in xcstrings files."
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
        // CI mode implies strict and JSON output
        let effectiveStrict = strict || ciMode
        let effectiveJson = jsonOutput || ciMode
        let loader = ConfigurationLoader()
        let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)

        // Load configuration
        let config: Configuration
        if let configPath = configPath {
            config = try loader.load(from: URL(fileURLWithPath: configPath))
        } else {
            config = (try? loader.load(searchingIn: cwd)) ?? loader.defaultConfiguration()
        }

        // Find files
        let _ = files.isEmpty ? config.files.include : files
        var xcstringsURLs: [URL] = []

        let enumerator = FileManager.default.enumerator(
            at: cwd,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
        while let url = enumerator?.nextObject() as? URL {
            if url.pathExtension == "xcstrings" {
                xcstringsURLs.append(url)
            }
        }

        if xcstringsURLs.isEmpty {
            printWarning("No xcstrings files found.")
            return
        }

        var hasErrors = false
        var hasWarnings = false

        for url in xcstringsURLs {
            let xcstrings: XCStrings
            do {
                xcstrings = try XCStrings.parse(from: url)
            } catch {
                printError("Failed to parse \(url.lastPathComponent): \(error.localizedDescription)")
                hasErrors = true
                continue
            }

            print("Validating: \(url.lastPathComponent)")

            // Check for missing translations
            for targetLang in config.targetLanguages {
                let missing = xcstrings.keysNeedingTranslation(for: targetLang.code)
                if !missing.isEmpty {
                    if config.validation.requireAllLanguages {
                        printError("  [\(targetLang.code)] Missing \(missing.count) translation(s)")
                        hasErrors = true
                    } else {
                        printWarning("  [\(targetLang.code)] Missing \(missing.count) translation(s)")
                        hasWarnings = true
                    }
                }
            }

            // Check for format specifier consistency
            if config.validation.validateFormatters {
                for (key, entry) in xcstrings.strings {
                    guard let sourceLocalization = entry.localizations?[xcstrings.sourceLanguage],
                          let sourceValue = sourceLocalization.stringUnit?.value else {
                        continue
                    }

                    let sourceSpecifiers = extractFormatSpecifiers(from: sourceValue)

                    for (langCode, localization) in entry.localizations ?? [:] {
                        guard langCode != xcstrings.sourceLanguage,
                              let targetValue = localization.stringUnit?.value else {
                            continue
                        }

                        let targetSpecifiers = extractFormatSpecifiers(from: targetValue)

                        if sourceSpecifiers.sorted() != targetSpecifiers.sorted() {
                            printWarning("  [\(langCode)] Format specifier mismatch in '\(key)'")
                            hasWarnings = true
                        }
                    }
                }
            }

            // Check for missing comments
            if config.validation.warnMissingComments {
                for (key, entry) in xcstrings.strings {
                    if entry.comment == nil || entry.comment?.isEmpty == true {
                        printWarning("  Missing comment for '\(key)'")
                        hasWarnings = true
                    }
                }
            }
        }

        if hasErrors || (effectiveStrict && hasWarnings) {
            throw ExitCode.failure
        }

        if !hasErrors && !hasWarnings && !effectiveJson {
            print("\nValidation passed!")
        }
    }

    private func extractFormatSpecifiers(from string: String) -> [String] {
        let pattern = #"%[@dDuUxXoOfeEgGcCsSpaAFn]|%[0-9]*\.?[0-9]*[dDuUxXoOfeEgGcCsSpaAFnlh@]+"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(string.startIndex..., in: string)
        let matches = regex.matches(in: string, range: range)
        return matches.map { match in
            String(string[Range(match.range, in: string)!])
        }
    }
}

// MARK: - Status Command

struct StatusCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "status",
        abstract: "Show translation status."
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

        // Load configuration
        let config: Configuration
        if let configPath = configPath {
            config = try loader.load(from: URL(fileURLWithPath: configPath))
        } else {
            config = (try? loader.load(searchingIn: cwd)) ?? loader.defaultConfiguration()
        }

        // Find files
        var xcstringsURLs: [URL] = []
        let enumerator = FileManager.default.enumerator(
            at: cwd,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
        while let url = enumerator?.nextObject() as? URL {
            if url.pathExtension == "xcstrings" {
                xcstringsURLs.append(url)
            }
        }

        if xcstringsURLs.isEmpty {
            print("No xcstrings files found.")
            return
        }

        struct FileStatus {
            let file: String
            let totalStrings: Int
            let languages: [String: LanguageStatus]
        }

        struct LanguageStatus {
            let translated: Int
            let missing: Int
            let percentage: Double
        }

        var allStatus: [FileStatus] = []

        for url in xcstringsURLs {
            let xcstrings: XCStrings
            do {
                xcstrings = try XCStrings.parse(from: url)
            } catch {
                printError("Failed to parse \(url.lastPathComponent): \(error.localizedDescription)")
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
                    percentage: percentage
                )
            }

            allStatus.append(FileStatus(
                file: url.lastPathComponent,
                totalStrings: totalStrings,
                languages: languageStatus
            ))
        }

        if jsonOutput {
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
                                percentage: lang.percentage
                            )
                        }
                    )
                }
            )

            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(jsonStatus)
            print(String(data: data, encoding: .utf8) ?? "{}")
        } else {
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
    }

    private func makeProgressBar(percentage: Double, width: Int) -> String {
        let filled = Int(Double(width) * percentage / 100)
        let empty = width - filled
        return "[" + String(repeating: "=", count: filled) + String(repeating: " ", count: empty) + "]"
    }
}

// MARK: - Init Command

struct InitCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "init",
        abstract: "Create a configuration file."
    )

    @Option(name: [.short, .customLong("output")], help: "Output file path.")
    var outputPath: String = ".swiftlocalize.json"

    @Flag(name: .customLong("force"), help: "Overwrite existing configuration.")
    var force = false

    func run() async throws {
        let outputURL = URL(fileURLWithPath: outputPath)

        if FileManager.default.fileExists(atPath: outputURL.path) && !force {
            printError("Configuration file already exists: \(outputPath)")
            printError("Use --force to overwrite.")
            throw ExitCode.failure
        }

        let loader = ConfigurationLoader()
        let config = loader.defaultConfiguration()

        try loader.write(config, to: outputURL)

        print("Created configuration file: \(outputPath)")
        print("\nNext steps:")
        print("  1. Edit the configuration to add your target languages")
        print("  2. Configure your preferred translation providers")
        print("  3. Set up API keys as environment variables")
        print("  4. Run 'swiftlocalize translate' to translate your strings")
    }
}

// MARK: - Providers Command

struct ProvidersCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "providers",
        abstract: "List available translation providers."
    )

    @Flag(name: .customLong("json"), help: "Output as JSON.")
    var jsonOutput = false

    func run() async throws {
        struct ProviderInfo {
            let name: String
            let displayName: String
            let available: Bool
            let reason: String?
        }

        var providers: [ProviderInfo] = []

        // Check OpenAI
        let openaiAvailable = ProcessInfo.processInfo.environment["OPENAI_API_KEY"] != nil
        providers.append(ProviderInfo(
            name: "openai",
            displayName: "OpenAI GPT",
            available: openaiAvailable,
            reason: openaiAvailable ? nil : "OPENAI_API_KEY not set"
        ))

        // Check Anthropic
        let anthropicAvailable = ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"] != nil
        providers.append(ProviderInfo(
            name: "anthropic",
            displayName: "Anthropic Claude",
            available: anthropicAvailable,
            reason: anthropicAvailable ? nil : "ANTHROPIC_API_KEY not set"
        ))

        // Check Gemini
        let geminiAvailable = ProcessInfo.processInfo.environment["GEMINI_API_KEY"] != nil
        providers.append(ProviderInfo(
            name: "gemini",
            displayName: "Google Gemini",
            available: geminiAvailable,
            reason: geminiAvailable ? nil : "GEMINI_API_KEY not set"
        ))

        // Check DeepL
        let deeplAvailable = ProcessInfo.processInfo.environment["DEEPL_API_KEY"] != nil
        providers.append(ProviderInfo(
            name: "deepl",
            displayName: "DeepL",
            available: deeplAvailable,
            reason: deeplAvailable ? nil : "DEEPL_API_KEY not set"
        ))

        // Check Ollama
        let ollamaProvider = OllamaProvider()
        let ollamaAvailable = await ollamaProvider.isAvailable()
        providers.append(ProviderInfo(
            name: "ollama",
            displayName: "Ollama (Local)",
            available: ollamaAvailable,
            reason: ollamaAvailable ? nil : "Ollama server not running"
        ))

        // Apple Translation
        #if canImport(Translation)
        providers.append(ProviderInfo(
            name: "apple-translation",
            displayName: "Apple Translation",
            available: true,
            reason: nil
        ))
        #else
        providers.append(ProviderInfo(
            name: "apple-translation",
            displayName: "Apple Translation",
            available: false,
            reason: "Requires macOS 14.4+ with Translation framework"
        ))
        #endif

        // Foundation Models
        #if canImport(FoundationModels)
        providers.append(ProviderInfo(
            name: "foundation-models",
            displayName: "Apple Intelligence",
            available: true,
            reason: nil
        ))
        #else
        providers.append(ProviderInfo(
            name: "foundation-models",
            displayName: "Apple Intelligence",
            available: false,
            reason: "Requires macOS 26+ with Apple Intelligence enabled"
        ))
        #endif

        if jsonOutput {
            struct JSONProvider: Encodable {
                let name: String
                let displayName: String
                let available: Bool
                let reason: String?
            }

            let jsonProviders = providers.map { p in
                JSONProvider(name: p.name, displayName: p.displayName, available: p.available, reason: p.reason)
            }

            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(jsonProviders)
            print(String(data: data, encoding: .utf8) ?? "[]")
        } else {
            print("Available Translation Providers")
            print("================================\n")

            for provider in providers {
                let status = provider.available ? "[OK]" : "[--]"
                print("\(status) \(provider.displayName) (\(provider.name))")
                if let reason = provider.reason {
                    print("      \(reason)")
                }
            }

            print("\nSet up API keys as environment variables to enable cloud providers.")
            print("Run 'ollama serve' to enable local Ollama translations.")
        }
    }
}

// MARK: - Migrate Command

struct MigrateCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "migrate",
        abstract: "Migrate between localization file formats.",
        subcommands: [
            MigrateToXCStrings.self,
            MigrateToLegacy.self,
        ],
        defaultSubcommand: MigrateToXCStrings.self
    )
}

struct MigrateToXCStrings: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "to-xcstrings",
        abstract: "Migrate .strings/.stringsdict files to .xcstrings format."
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

        let inputDir: URL
        if let input = inputDirectory {
            inputDir = URL(fileURLWithPath: input, relativeTo: URL(fileURLWithPath: cwd))
        } else {
            inputDir = URL(fileURLWithPath: cwd)
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
            sourceLanguage: sourceLanguage
        )

        try xcstrings.write(to: outputURL)

        let languages = xcstrings.presentLanguages
        print("Migration complete!")
        print("  Strings: \(xcstrings.strings.count)")
        print("  Languages: \(languages.joined(separator: ", "))")
        print("  Output: \(outputURL.lastPathComponent)")
    }
}

struct MigrateToLegacy: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "to-legacy",
        abstract: "Migrate .xcstrings file to .strings/.stringsdict format."
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

        let outputDir: URL
        if let output = outputDirectory {
            outputDir = URL(fileURLWithPath: output, relativeTo: URL(fileURLWithPath: cwd))
        } else {
            outputDir = inputURL.deletingLastPathComponent()
        }

        guard fm.fileExists(atPath: inputURL.path) else {
            printError("Input file not found: \(inputPath)")
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
            stringsdictFileName: stringsdictFileName
        )

        let languages = xcstrings.presentLanguages
        print("Migration complete!")
        print("  Strings: \(xcstrings.strings.count)")
        print("  Languages exported: \(languages.joined(separator: ", "))")
        print("  Output: \(outputDir.path)")
    }
}

// MARK: - Glossary Command

struct GlossaryCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "glossary",
        abstract: "Manage translation glossary terms.",
        subcommands: [
            GlossaryList.self,
            GlossaryAdd.self,
            GlossaryRemove.self,
            GlossaryInit.self,
        ],
        defaultSubcommand: GlossaryList.self
    )
}

struct GlossaryList: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "list",
        abstract: "List all glossary terms."
    )

    @Option(name: [.short, .customLong("file")], help: "Glossary file path.")
    var glossaryPath: String = ".swiftlocalize-glossary.json"

    @Flag(name: .customLong("json"), help: "Output as JSON.")
    var jsonOutput = false

    func run() async throws {
        let glossaryURL = URL(fileURLWithPath: glossaryPath)
        let glossary = Glossary(storageURL: glossaryURL)

        do {
            try await glossary.load()
        } catch {
            print("No glossary file found. Run 'swiftlocalize glossary init' to create one.")
            return
        }

        let terms = await glossary.allTerms

        if terms.isEmpty {
            print("Glossary is empty. Use 'swiftlocalize glossary add' to add terms.")
            return
        }

        if jsonOutput {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(terms)
            print(String(data: data, encoding: .utf8) ?? "[]")
        } else {
            print("Glossary Terms (\(terms.count))")
            print(String(repeating: "=", count: 40))

            for term in terms {
                if term.doNotTranslate {
                    print("\n\"\(term.term)\" [DO NOT TRANSLATE]")
                } else {
                    print("\n\"\(term.term)\"")
                }

                if let definition = term.definition {
                    print("  Definition: \(definition)")
                }

                if !term.translations.isEmpty {
                    print("  Translations:")
                    for (lang, translation) in term.translations.sorted(by: { $0.key < $1.key }) {
                        print("    \(lang): \(translation)")
                    }
                }
            }
        }
    }
}

struct GlossaryAdd: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "add",
        abstract: "Add a term to the glossary."
    )

    @Argument(help: "The term to add.")
    var term: String

    @Option(name: [.short, .customLong("file")], help: "Glossary file path.")
    var glossaryPath: String = ".swiftlocalize-glossary.json"

    @Option(name: [.short, .customLong("definition")], help: "Definition or context for the term.")
    var definition: String?

    @Option(name: [.short, .customLong("translation")], parsing: .upToNextOption, help: "Translations as lang:value pairs (e.g., fr:Bonjour de:Hallo).")
    var translations: [String] = []

    @Flag(name: .customLong("do-not-translate"), help: "Mark term as do-not-translate (brand names, etc.).")
    var doNotTranslate = false

    @Flag(name: .customLong("case-sensitive"), help: "Match term case-sensitively.")
    var caseSensitive = false

    func run() async throws {
        let glossaryURL = URL(fileURLWithPath: glossaryPath)
        let glossary = Glossary(storageURL: glossaryURL)

        try? await glossary.load()

        // Parse translations
        var translationDict: [String: String] = [:]
        for translation in translations {
            let parts = translation.split(separator: ":", maxSplits: 1)
            if parts.count == 2 {
                translationDict[String(parts[0])] = String(parts[1])
            }
        }

        let entry = GlossaryEntry(
            term: term,
            definition: definition,
            translations: translationDict,
            caseSensitive: caseSensitive,
            doNotTranslate: doNotTranslate
        )

        await glossary.addTerm(entry)
        try await glossary.forceSave()

        print("Added term: \"\(term)\"")
        if doNotTranslate {
            print("  [DO NOT TRANSLATE]")
        }
        if let definition {
            print("  Definition: \(definition)")
        }
        if !translationDict.isEmpty {
            print("  Translations: \(translationDict.map { "\($0.key):\($0.value)" }.joined(separator: ", "))")
        }
    }
}

struct GlossaryRemove: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "remove",
        abstract: "Remove a term from the glossary."
    )

    @Argument(help: "The term to remove.")
    var term: String

    @Option(name: [.short, .customLong("file")], help: "Glossary file path.")
    var glossaryPath: String = ".swiftlocalize-glossary.json"

    func run() async throws {
        let glossaryURL = URL(fileURLWithPath: glossaryPath)
        let glossary = Glossary(storageURL: glossaryURL)

        try await glossary.load()

        if await glossary.getTerm(term) == nil {
            printError("Term not found: \"\(term)\"")
            throw ExitCode.failure
        }

        await glossary.removeTerm(term)
        try await glossary.forceSave()

        print("Removed term: \"\(term)\"")
    }
}

struct GlossaryInit: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "init",
        abstract: "Create a new glossary file."
    )

    @Option(name: [.short, .customLong("file")], help: "Glossary file path.")
    var glossaryPath: String = ".swiftlocalize-glossary.json"

    @Flag(name: .customLong("force"), help: "Overwrite existing glossary.")
    var force = false

    func run() async throws {
        let glossaryURL = URL(fileURLWithPath: glossaryPath)

        if FileManager.default.fileExists(atPath: glossaryURL.path) && !force {
            printError("Glossary file already exists: \(glossaryPath)")
            printError("Use --force to overwrite.")
            throw ExitCode.failure
        }

        let glossary = Glossary(storageURL: glossaryURL)

        // Add example terms
        await glossary.addTerm(GlossaryEntry(
            term: "AppName",
            definition: "Replace with your app name",
            doNotTranslate: true
        ))

        try await glossary.forceSave()

        print("Created glossary file: \(glossaryPath)")
        print("\nNext steps:")
        print("  1. Add terms with 'swiftlocalize glossary add <term>'")
        print("  2. Configure translations with -t flag (e.g., -t fr:Bonjour)")
        print("  3. Mark brand names with --do-not-translate")
    }
}

// MARK: - Cache Command

struct CacheCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "cache",
        abstract: "Manage translation cache.",
        subcommands: [
            CacheInfo.self,
            CacheClear.self,
        ],
        defaultSubcommand: CacheInfo.self
    )
}

struct CacheInfo: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "info",
        abstract: "Show translation cache information."
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
                lastUpdated: stats.lastUpdated.map { dateFormatter.string(from: $0) }
            )

            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(jsonStats)
            print(String(data: data, encoding: .utf8) ?? "{}")
        } else {
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
}

struct CacheClear: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "clear",
        abstract: "Clear the translation cache."
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

// MARK: - Targets Command

struct TargetsCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "targets",
        abstract: "Discover and list localization targets in the project."
    )

    @Option(name: [.short, .customLong("path")], help: "Project root path.")
    var projectPath: String?

    @Flag(name: .customLong("json"), help: "Output as JSON.")
    var jsonOutput = false

    @Flag(name: [.short, .customLong("verbose")], help: "Verbose output.")
    var verbose = false

    func run() async throws {
        let fm = FileManager.default
        let cwd = fm.currentDirectoryPath

        let rootURL: URL
        if let path = projectPath {
            rootURL = URL(fileURLWithPath: path, relativeTo: URL(fileURLWithPath: cwd))
        } else {
            rootURL = URL(fileURLWithPath: cwd)
        }

        let detector = ProjectStructureDetector()
        let structure = try await detector.detect(at: rootURL)

        if jsonOutput {
            struct JSONTarget: Encodable {
                let name: String
                let type: String
                let path: String
                let defaultLocalization: String
                let parentPackage: String?
            }

            struct JSONStructure: Encodable {
                let projectType: String
                let targets: [JSONTarget]
                let packages: [String]
            }

            let jsonStruct = JSONStructure(
                projectType: structure.type.rawValue,
                targets: structure.targets.map { target in
                    JSONTarget(
                        name: target.name,
                        type: target.type.rawValue,
                        path: target.xcstringsURL.path,
                        defaultLocalization: target.defaultLocalization,
                        parentPackage: target.parentPackage
                    )
                },
                packages: structure.packages.map(\.name)
            )

            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(jsonStruct)
            print(String(data: data, encoding: .utf8) ?? "{}")
        } else {
            print("Project Structure")
            print("=================")
            print("Type: \(structure.type.rawValue)")
            print("Root: \(rootURL.path)")

            if !structure.packages.isEmpty {
                print("\nPackages:")
                for pkg in structure.packages {
                    print("  - \(pkg.name)")
                }
            }

            print("\nLocalization Targets (\(structure.targets.count)):")
            if structure.targets.isEmpty {
                print("  No localization targets found.")
                print("  Run 'swiftlocalize init' to set up localization.")
            } else {
                for target in structure.targets {
                    print("\n  \(target.name)")
                    print("    Type: \(target.type.rawValue)")
                    print("    File: \(target.xcstringsURL.lastPathComponent)")
                    if verbose {
                        print("    Path: \(target.xcstringsURL.path)")
                        print("    Language: \(target.defaultLocalization)")
                        if let parent = target.parentPackage {
                            print("    Package: \(parent)")
                        }
                    }
                }
            }

            print("\nUse 'swiftlocalize translate --target <name>' to translate a specific target.")
            print("Use 'swiftlocalize translate --all-targets' to translate all targets.")
        }
    }
}

// MARK: - Sync Keys Command

struct SyncKeysCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "sync-keys",
        abstract: "Synchronize localization keys across multiple catalogs."
    )

    @Argument(help: "xcstrings files to synchronize (at least 2).")
    var files: [String] = []

    @Flag(name: .customLong("all-targets"), help: "Synchronize all discovered targets.")
    var allTargets = false

    @Option(name: .customLong("sort"), help: "Key sorting mode: alphabetical, alphabeticalDescending, byExtractionState, preserve.")
    var sortMode: String = "alphabetical"

    @Flag(name: .customLong("dry-run"), help: "Show what would be synchronized without making changes.")
    var dryRun = false

    @Flag(name: .customLong("json"), help: "Output as JSON.")
    var jsonOutput = false

    @Flag(name: [.short, .customLong("verbose")], help: "Verbose output.")
    var verbose = false

    func run() async throws {
        let fm = FileManager.default
        let cwd = fm.currentDirectoryPath
        var catalogURLs: [URL] = []

        if allTargets {
            let cwdURL = URL(fileURLWithPath: cwd)
            let detector = ProjectStructureDetector()
            let structure = try await detector.detect(at: cwdURL)

            if structure.targets.count < 2 {
                printError("Need at least 2 targets for synchronization. Found: \(structure.targets.count)")
                throw ExitCode.failure
            }

            catalogURLs = structure.targets.map(\.xcstringsURL)
            print("Synchronizing \(catalogURLs.count) targets:")
            for target in structure.targets {
                print("  - \(target.name)")
            }
        } else {
            if files.count < 2 {
                printError("Need at least 2 files for synchronization.")
                printError("Usage: swiftlocalize sync-keys file1.xcstrings file2.xcstrings")
                throw ExitCode.failure
            }

            catalogURLs = files.map { URL(fileURLWithPath: $0, relativeTo: URL(fileURLWithPath: cwd)) }

            for url in catalogURLs {
                if !fm.fileExists(atPath: url.path) {
                    printError("File not found: \(url.path)")
                    throw ExitCode.failure
                }
            }
        }

        // Analyze consistency first
        let analyzer = KeyConsistencyAnalyzer()
        let report = try await analyzer.analyze(catalogs: catalogURLs)

        if !jsonOutput {
            print("\nKey Consistency Analysis")
            print("========================")
            print(report.summary)
        }

        // Check for conflicts
        if !report.conflicts.isEmpty {
            if !jsonOutput {
                print("\nConflicts found (\(report.conflicts.count)):")
                for conflict in report.conflicts.prefix(verbose ? 100 : 5) {
                    print("  '\(conflict.key)':")
                    for (url, value) in conflict.sourceValues {
                        print("    \(url.lastPathComponent): \"\(value)\"")
                    }
                    print("    Recommendation: \(conflict.recommendation)")
                }
                if report.conflicts.count > 5 && !verbose {
                    print("  ... and \(report.conflicts.count - 5) more. Use -v for full list.")
                }
            }
        }

        // Synchronize
        let syncSortMode: KeySortMode
        switch sortMode.lowercased() {
        case "alphabetical", "asc":
            syncSortMode = .alphabetical
        case "alphabeticaldescending", "desc":
            syncSortMode = .alphabeticalDescending
        case "byextractionstate", "extraction":
            syncSortMode = .byExtractionState
        case "preserve", "none":
            syncSortMode = .preserve
        default:
            syncSortMode = .alphabetical
        }

        let synchronizer = CatalogSynchronizer()
        let syncOptions = SyncOptions(
            sortAfterSync: syncSortMode != .preserve,
            dryRun: dryRun
        )

        let syncReport = try await synchronizer.synchronize(
            catalogs: catalogURLs,
            options: syncOptions
        )

        if jsonOutput {
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
                addedByFile: Dictionary(uniqueKeysWithValues: syncReport.addedKeys.map { (url, keys) in
                    (url.lastPathComponent, keys)
                })
            )

            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(jsonReport)
            print(String(data: data, encoding: .utf8) ?? "{}")
        } else {
            print("\nSynchronization \(dryRun ? "Preview" : "Complete")")
            print("=========================")
            print(syncReport.summary)

            if verbose && !syncReport.addedKeys.isEmpty {
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
}

// MARK: - Helpers

private func printError(_ message: String) {
    fputs("Error: \(message)\n", stderr)
}

private func printWarning(_ message: String) {
    fputs("Warning: \(message)\n", stderr)
}
