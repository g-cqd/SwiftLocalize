//
//  TranslateCommand.swift
//  SwiftLocalize
//

import ArgumentParser
import Foundation
import SwiftLocalizeCore

// MARK: - TranslateCommand

struct TranslateCommand: AsyncParsableCommand {
    // MARK: Internal

    static let configuration = CommandConfiguration(
        commandName: "translate",
        abstract: "Translate xcstrings files.",
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

    @Flag(
        name: .customLong("incremental"),
        inversion: .prefixedNo,
        help: "Use incremental translation (skip unchanged strings).",
    )
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

        let config = try loadConfiguration(effectiveQuiet: effectiveQuiet)
        let mutableConfig = applyConfigurationOverrides(to: config)

        // Validate configuration
        let loader = ConfigurationLoader()
        let issues = loader.validate(mutableConfig)
        let errors = issues.filter(\.isError)
        if !errors.isEmpty {
            for issue in errors {
                CLIOutput.printError("Error: \(issue.message)")
            }
            throw ExitCode.failure
        }

        if verbose {
            let warnings = issues.filter { !$0.isError }
            for warning in warnings {
                CLIOutput.printWarning("Warning: \(warning.message)")
            }
        }

        // Find xcstrings files
        let xcstringsURLs = try await findXCStringsFiles(config: mutableConfig, effectiveQuiet: effectiveQuiet)

        if xcstringsURLs.isEmpty {
            if !effectiveQuiet {
                CLIOutput.printWarning("No xcstrings files found.")
            }
            return
        }

        if verbose, !effectiveQuiet {
            print("Found \(xcstringsURLs.count) xcstrings file(s)")
            for url in xcstringsURLs {
                print("  - \(url.lastPathComponent)")
            }
        }

        // Verify isolation if configured
        try await verifyFileIsolation(config: mutableConfig, urls: xcstringsURLs, effectiveQuiet: effectiveQuiet)

        // Handle special modes
        if dryRun {
            try await performDryRun(urls: xcstringsURLs, config: mutableConfig)
            return
        }

        if preview {
            try await performPreview(urls: xcstringsURLs, config: mutableConfig)
            return
        }

        // Create backups if requested
        if backup {
            try createBackups(urls: xcstringsURLs, effectiveQuiet: effectiveQuiet)
        }

        // Perform translation
        let report = try await performTranslation(
            urls: xcstringsURLs,
            config: mutableConfig,
            effectiveQuiet: effectiveQuiet,
            effectiveJson: effectiveJson,
        )

        // Output results
        if effectiveJson {
            try TranslateReportOutput.printJSONReport(report)
        } else if !effectiveQuiet {
            TranslateReportOutput.printTextReport(report, verbose: verbose)
        }

        // Exit codes for CI
        if report.failedCount > 0 {
            throw ExitCode(1)
        }
    }

    // MARK: Private

    private func loadConfiguration(effectiveQuiet: Bool) throws -> Configuration {
        let loader = ConfigurationLoader()

        if let configPath = configPath {
            let configURL = URL(fileURLWithPath: configPath)
            do {
                return try loader.load(from: configURL)
            } catch {
                CLIOutput.printError("Failed to load config: \(error.localizedDescription)")
                throw ExitCode.failure
            }
        } else {
            let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            do {
                return try loader.load(searchingIn: cwd)
            } catch {
                if !effectiveQuiet {
                    CLIOutput.printError("No configuration file found. Run 'swiftlocalize init' to create one.")
                    CLIOutput.printError("Or specify target languages with --languages")
                }
                throw ExitCode.failure
            }
        }
    }

    private func applyConfigurationOverrides(to configuration: Configuration) -> Configuration {
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
            if contextDepth != .standard {
                config.context.depth = contextDepth
            }
        }

        // Isolation overrides
        if verifyIsolation {
            config.isolation.verifyBeforeRun = true
        }

        // Language overrides
        if let languagesArg = languages {
            let langs = languagesArg.split(separator: ",")
                .map { LanguageCode(String($0).trimmingCharacters(in: .whitespaces)) }
            config.targetLanguages = langs
        }

        return config
    }

    private func findXCStringsFiles(config: Configuration, effectiveQuiet: Bool) async throws -> [URL] {
        var xcstringsURLs: [URL] = []

        if allTargets || target != nil {
            let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            let detector = ProjectStructureDetector()
            let structure = try await detector.detect(at: cwd)

            if let targetName = target {
                guard let locTarget = structure.targets.first(where: { $0.name == targetName }) else {
                    CLIOutput.printError("Target '\(targetName)' not found. Available targets:")
                    for t in structure.targets {
                        CLIOutput.printError("  - \(t.name)")
                    }
                    throw ExitCode.failure
                }
                xcstringsURLs = [locTarget.xcstringsURL]
                if verbose, !effectiveQuiet {
                    print("Translating target: \(targetName)")
                }
            } else {
                xcstringsURLs = structure.targets.map(\.xcstringsURL)
                if verbose, !effectiveQuiet {
                    print("Discovered \(structure.targets.count) target(s)")
                    for t in structure.targets {
                        print("  - \(t.name): \(t.xcstringsURL.lastPathComponent)")
                    }
                }
            }
        } else {
            xcstringsURLs = try findXCStringsFilesFromPatterns(patterns: files.isEmpty ? config.files.include : files)
        }

        return xcstringsURLs
    }

    private func findXCStringsFilesFromPatterns(patterns: [String]) throws -> [URL] {
        let fm = FileManager.default
        let cwd = fm.currentDirectoryPath
        var results: [URL] = []

        for pattern in patterns {
            if pattern.contains("*") {
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
        let fm = FileManager.default
        var results: [URL] = []

        let baseURL = URL(fileURLWithPath: directory)
        let enumerator = fm.enumerator(
            at: baseURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles],
        )

        while let url = enumerator?.nextObject() as? URL {
            if url.pathExtension == "xcstrings" {
                if pattern.contains("**") || pattern == "*.xcstrings" || url.lastPathComponent.hasSuffix(".xcstrings") {
                    results.append(url)
                }
            }
        }

        return results
    }

    private func verifyFileIsolation(config: Configuration, urls: [URL], effectiveQuiet: Bool) async throws {
        guard config.isolation.verifyBeforeRun else { return }

        if verbose, !effectiveQuiet {
            print("Verifying file isolation...")
        }

        let verifier = IsolationVerifier()
        let result = try await verifier.verify(configuration: config, mode: config.mode, files: urls)

        if !result.isIsolated {
            CLIOutput.printError("Isolation verification failed!")
            for warning in result.warnings {
                CLIOutput.printError("  - \(warning)")
            }
            if config.isolation.strict {
                throw ExitCode.failure
            }
        } else if verbose, !effectiveQuiet {
            print("Isolation verification passed.")
        }
    }

    private func createBackups(urls: [URL], effectiveQuiet: Bool) throws {
        for url in urls {
            let backupURL = url.appendingPathExtension("bak")
            try? FileManager.default.removeItem(at: backupURL)
            try FileManager.default.copyItem(at: url, to: backupURL)
            if verbose, !effectiveQuiet {
                print("Backup created: \(backupURL.lastPathComponent)")
            }
        }
    }

    private func performTranslation(
        urls: [URL],
        config: Configuration,
        effectiveQuiet: Bool,
        effectiveJson: Bool,
    ) async throws -> TranslationReport {
        let service = TranslationService(configuration: config)
        await service.registerDefaultProviders()

        if !effectiveQuiet {
            print("Starting translation...")
        }

        let report = try await service.translateFiles(at: urls) { progress in
            if !effectiveQuiet, !effectiveJson {
                let percentage = Int(progress.percentage * 100)
                let langInfo = progress.currentLanguage.map { " [\($0.code)]" } ?? ""
                print("\rProgress: \(percentage)%\(langInfo) (\(progress.completed)/\(progress.total))", terminator: "")
                fflush(stdout)
            }
        }

        if !effectiveQuiet, !effectiveJson {
            print()
        }

        return report
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
                try await previewLanguage(
                    targetLanguage: targetLanguage,
                    xcstrings: xcstrings,
                    service: service,
                )
            }
        }

        print("NOTE: No changes were saved. Run without --preview to apply translations.")
    }

    private func previewLanguage(
        targetLanguage: LanguageCode,
        xcstrings: XCStrings,
        service: TranslationService,
    ) async throws {
        let keys = xcstrings.keysNeedingTranslation(for: targetLanguage.code)
        guard !keys.isEmpty else { return }

        print("  [\(targetLanguage.code)] \(keys.count) string(s) to translate:")

        let previewKeys = keys.prefix(5)
        var stringsToPreview: [String] = []

        for key in previewKeys {
            if let entry = xcstrings.strings[key],
               let sourceLocalization = entry.localizations?[xcstrings.sourceLanguage],
               let sourceValue = sourceLocalization.stringUnit?.value
            {
                stringsToPreview.append(sourceValue)
            } else {
                stringsToPreview.append(key)
            }
        }

        do {
            let results = try await service.translateBatch(
                stringsToPreview,
                from: LanguageCode(xcstrings.sourceLanguage),
                to: targetLanguage,
            )

            for (index, result) in results.enumerated() {
                let key = Array(previewKeys)[index]
                print("    \"\(key)\":")
                print("      Source: \(result.original)")
                print("      -> \(result.translated)")
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
