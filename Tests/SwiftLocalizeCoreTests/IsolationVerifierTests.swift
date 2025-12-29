//
//  IsolationVerifierTests.swift
//  SwiftLocalizeCoreTests
//

import Foundation
import Testing

@testable import SwiftLocalizeCore

// MARK: - IsolationVerifierTests

struct IsolationVerifierTests {
    @Test
    func verifyTranslationOnlyMode_AllowedFiles() async throws {
        let verifier = IsolationVerifier()
        let config = Configuration(mode: .translationOnly)

        let files = [
            URL(fileURLWithPath: "/path/to/en.xcstrings"),
            URL(fileURLWithPath: "/path/to/fr.xcstrings"),
        ]

        let result = try await verifier.verify(configuration: config, mode: .translationOnly, files: files)

        #expect(result.isIsolated)
        #expect(result.warnings.isEmpty)
        // 2 input files + 1 cache file (default config)
        #expect(result.plannedWrites.count == 3)
    }

    @Test
    func verifyTranslationOnlyMode_OnlyProcessesLocalizationFiles() async throws {
        let verifier = IsolationVerifier()
        let config = Configuration(mode: .translationOnly)

        // Non-localization files are ignored (not added to modifications list)
        let files = [
            URL(fileURLWithPath: "/path/to/Source.swift"),
            URL(fileURLWithPath: "/path/to/en.xcstrings"),
        ]

        let result = try await verifier.verify(configuration: config, mode: .translationOnly, files: files)

        // Only xcstrings + cache should be in plannedWrites (swift file ignored)
        #expect(result.plannedWrites.count == 2)
        let extensions = result.plannedWrites.map(\.pathExtension)
        #expect(!extensions.contains("swift"))
    }

    @Test
    func verifyTranslationOnlyMode_WithContextExtraction() async throws {
        let verifier = IsolationVerifier()
        var config = Configuration(mode: .translationOnly)
        config.context.sourceCode = SourceCodeSettings(enabled: true)

        let files = [
            URL(fileURLWithPath: "/path/to/en.xcstrings"),
        ]

        let result = try await verifier.verify(configuration: config, mode: .translationOnly, files: files)

        #expect(result.isIsolated)
    }

    @Test
    func listModifications_IncludesAllTargetFiles() async throws {
        let verifier = IsolationVerifier()
        let config = Configuration(mode: .translationOnly)

        let files = [
            URL(fileURLWithPath: "/path/to/en.xcstrings"),
            URL(fileURLWithPath: "/path/to/fr.xcstrings"),
            URL(fileURLWithPath: "/path/to/Localizable.strings"),
        ]

        let modifications = try await verifier.listModifications(configuration: config, files: files)

        // Should include: 2 xcstrings + 1 strings + 1 cache file
        #expect(modifications.count == 4)

        let urls = modifications.map(\.url.lastPathComponent)
        #expect(urls.contains("en.xcstrings"))
        #expect(urls.contains("fr.xcstrings"))
        #expect(urls.contains("Localizable.strings"))
    }

    @Test
    func listModifications_IncludesTranslationMemory() async throws {
        let verifier = IsolationVerifier()
        var config = Configuration(mode: .translationOnly)
        config.context.translationMemory = TranslationMemorySettings(
            enabled: true,
            file: "/path/to/tm.json",
        )

        let files = [URL(fileURLWithPath: "/path/to/en.xcstrings")]

        let modifications = try await verifier.listModifications(configuration: config, files: files)

        // Should include: 1 xcstrings + 1 cache + 1 TM file
        #expect(modifications.count == 3)

        let hasTranslationMemory = modifications.contains { $0.reason.contains("Translation memory") }
        #expect(hasTranslationMemory)
    }

    @Test
    func listReads_IncludesConfigurationFile() async throws {
        let verifier = IsolationVerifier()
        let config = Configuration(mode: .translationOnly)

        let reads = try await verifier.listReads(configuration: config, mode: .translationOnly)

        let hasConfig = reads.contains { $0.reason == "Configuration" }
        #expect(hasConfig)
    }

    @Test
    func listReads_IncludesGlossaryWhenEnabled() async throws {
        let verifier = IsolationVerifier()
        var config = Configuration(mode: .translationOnly)
        config.context.glossary = GlossarySettings(
            enabled: true,
            file: "/path/to/glossary.json",
        )

        let reads = try await verifier.listReads(configuration: config, mode: .translationOnly)

        let hasGlossary = reads.contains { $0.reason == "Glossary terms" }
        #expect(hasGlossary)
    }
}

// MARK: - FileAccessAuditorTests

struct FileAccessAuditorTests {
    @Test
    func recordRead_TracksReadOperations() async {
        let auditor = FileAccessAuditor()
        let testURL = URL(fileURLWithPath: "/path/to/test.xcstrings")

        await auditor.recordRead(url: testURL, purpose: "Test read")

        let report = await auditor.generateReport()

        #expect(report.filesRead.count == 1)
        #expect(report.filesRead.first == testURL)
        #expect(report.filesWritten.isEmpty)
    }

    @Test
    func recordWrite_TracksWriteOperations() async {
        let auditor = FileAccessAuditor()
        let testURL = URL(fileURLWithPath: "/path/to/output.xcstrings")

        await auditor.recordWrite(url: testURL, purpose: "Test write")

        let report = await auditor.generateReport()

        #expect(report.filesWritten.count == 1)
        #expect(report.filesWritten.first == testURL)
        #expect(report.filesRead.isEmpty)
    }

    @Test
    func validateWrites_AllowsMatchingPatterns() async throws {
        let auditor = FileAccessAuditor()

        await auditor.recordWrite(
            url: URL(fileURLWithPath: "/path/to/file.xcstrings"),
            purpose: "Translation",
        )

        let violations = try await auditor.validateWrites(allowedPatterns: ["**/*.xcstrings"])

        #expect(violations.isEmpty)
    }

    @Test
    func validateWrites_RejectsNonMatchingPatterns() async throws {
        let auditor = FileAccessAuditor()

        await auditor.recordWrite(
            url: URL(fileURLWithPath: "/path/to/file.swift"),
            purpose: "Invalid write",
        )

        let violations = try await auditor.validateWrites(allowedPatterns: ["**/*.xcstrings"])

        #expect(violations.count == 1)
        #expect(violations.first?.url.pathExtension == "swift")
    }

    @Test
    func generateReport_ProvidesSummary() async {
        let auditor = FileAccessAuditor()

        await auditor.recordRead(url: URL(fileURLWithPath: "/a.txt"), purpose: "r1")
        await auditor.recordRead(url: URL(fileURLWithPath: "/b.txt"), purpose: "r2")
        await auditor.recordWrite(url: URL(fileURLWithPath: "/c.txt"), purpose: "w1")

        let report = await auditor.generateReport()

        #expect(report.filesRead.count == 2)
        #expect(report.filesWritten.count == 1)
        #expect(report.summary.contains("Read 2 files"))
        #expect(report.summary.contains("wrote 1 files"))
    }
}

// MARK: - OperationModeTests

struct OperationModeTests {
    @Test
    func translationOnlyMode_IsDefault() {
        let config = Configuration()
        #expect(config.mode == .translationOnly)
    }

    @Test
    func operationMode_IsCodable() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        let original = OperationMode.translationOnly
        let data = try encoder.encode(original)
        let decoded = try decoder.decode(OperationMode.self, from: data)

        #expect(decoded == original)
    }

    @Test
    func operationMode_FullModeExists() {
        let mode = OperationMode.full
        #expect(mode.rawValue == "full")
    }
}

// MARK: - ContextDepthTests

struct ContextDepthTests {
    @Test
    func contextDepth_HasAllExpectedCases() {
        let cases = ContextDepth.allCases
        #expect(cases.count == 4)
        #expect(cases.contains(.none))
        #expect(cases.contains(.minimal))
        #expect(cases.contains(.standard))
        #expect(cases.contains(.deep))
    }

    @Test
    func contextDepth_StandardIsDefault() {
        let settings = ContextSettings()
        #expect(settings.depth == .standard)
    }
}

// MARK: - IsolationSettingsTests

struct IsolationSettingsTests {
    @Test
    func defaultIsolationSettings_IsStrict() {
        let config = Configuration()
        #expect(config.isolation.strict == true)
    }

    @Test
    func defaultIsolationSettings_AllowsXcstringsAndCache() {
        let config = Configuration()
        let patterns = config.isolation.allowedWritePatterns

        #expect(patterns.contains("**/*.xcstrings"))
        #expect(patterns.contains("**/.swiftlocalize-cache.json"))
    }

    @Test
    func isolationSettings_VerifyBeforeRunDefaultsToTrue() {
        let config = Configuration()
        #expect(config.isolation.verifyBeforeRun == true)
    }
}
