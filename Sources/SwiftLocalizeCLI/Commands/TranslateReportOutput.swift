//
//  TranslateReportOutput.swift
//  SwiftLocalize
//

import Foundation
import SwiftLocalizeCore

// MARK: - TranslateReportOutput

/// Handles output formatting for translation reports.
enum TranslateReportOutput {
    // MARK: Internal

    // MARK: - Text Output

    static func printTextReport(_ report: TranslationReport, verbose: Bool) {
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
                let translated = langReport.translatedCount
                let failed = langReport.failedCount
                let provider = langReport.provider
                print("  \(lang.code): \(translated) translated, \(failed) failed [\(provider)]")
            }
        }

        if !report.errors.isEmpty, verbose {
            print("\nErrors:")
            for error in report.errors.prefix(10) {
                print("  [\(error.language.code)] \(error.key): \(error.message)")
            }
            if report.errors.count > 10 {
                print("  ... and \(report.errors.count - 10) more errors")
            }
        }
    }

    // MARK: - JSON Output

    static func printJSONReport(_ report: TranslationReport) throws {
        let seconds = Double(report.duration.components.seconds) +
            Double(report.duration.components.attoseconds) / 1_000_000_000_000_000_000

        let jsonReport = JSONReport(
            totalStrings: report.totalStrings,
            translatedCount: report.translatedCount,
            failedCount: report.failedCount,
            skippedCount: report.skippedCount,
            durationSeconds: seconds,
            byLanguage: Dictionary(uniqueKeysWithValues: report.byLanguage.map { lang, info in
                (lang.code, JSONReport.LanguageInfo(
                    translatedCount: info.translatedCount,
                    failedCount: info.failedCount,
                    provider: info.provider,
                ))
            }),
            errors: report.errors.map { error in
                JSONReport.ErrorInfo(
                    key: error.key,
                    language: error.language.code,
                    message: error.message,
                )
            },
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(jsonReport)
        print(String(data: data, encoding: .utf8) ?? "{}")
    }

    // MARK: Private

    // MARK: - JSON Report Types

    private struct JSONReport: Encodable {
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

        let totalStrings: Int
        let translatedCount: Int
        let failedCount: Int
        let skippedCount: Int
        let durationSeconds: Double
        let byLanguage: [String: LanguageInfo]
        let errors: [ErrorInfo]
    }
}
