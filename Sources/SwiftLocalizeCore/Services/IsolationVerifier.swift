//
//  IsolationVerifier.swift
//  SwiftLocalizeCore
//

import Foundation

// MARK: - File Access Auditing

public struct FileOperation: Sendable {
    public let url: URL
    public let type: OperationType
    public let purpose: String
    public let timestamp: Date
    
    public enum OperationType: String, Sendable {
        case read
        case write
    }
}

public struct Violation: Sendable {
    public let url: URL
    public let operation: FileOperation.OperationType
    public let reason: String
}

public struct FileAccessReport: Sendable {
    public let filesRead: [URL]
    public let filesWritten: [URL]
    public let violationsDetected: [Violation]
    public let summary: String
}

public actor FileAccessAuditor {
    private var readOperations: [FileOperation] = []
    private var writeOperations: [FileOperation] = []
    
    public init() {}
    
    /// Record a file read operation.
    public func recordRead(url: URL, purpose: String) {
        readOperations.append(FileOperation(
            url: url,
            type: .read,
            purpose: purpose,
            timestamp: Date()
        ))
    }
    
    /// Record a file write operation.
    public func recordWrite(url: URL, purpose: String) {
        writeOperations.append(FileOperation(
            url: url,
            type: .write,
            purpose: purpose,
            timestamp: Date()
        ))
    }
    
    /// Validate all write operations are within allowed scope.
    public func validateWrites(allowedPatterns: [String]) throws -> [Violation] {
        var violations: [Violation] = []

        for op in writeOperations {
            let path = op.url.path
            var allowed = false

            // Check if file matches any allowed pattern
            for pattern in allowedPatterns {
                if matchesGlobPattern(path: path, pattern: pattern) {
                    allowed = true
                    break
                }
            }

            if !allowed {
                violations.append(Violation(
                    url: op.url,
                    operation: .write,
                    reason: "Write not allowed for pattern(s): \(allowedPatterns)"
                ))
            }
        }

        return violations
    }

    /// Simple glob pattern matching.
    private func matchesGlobPattern(path: String, pattern: String) -> Bool {
        // Handle common glob patterns
        if pattern == "*" || pattern == "**/*" {
            return true
        }

        // Handle **/*.extension patterns
        if pattern.hasPrefix("**/") {
            let suffix = String(pattern.dropFirst(3))
            if suffix.hasPrefix("*.") {
                let ext = String(suffix.dropFirst(2))
                return path.hasSuffix(".\(ext)")
            }
            // Handle **/filename patterns
            return path.hasSuffix("/\(suffix)") || path.hasSuffix(suffix)
        }

        // Handle *.extension patterns
        if pattern.hasPrefix("*.") {
            let ext = String(pattern.dropFirst(2))
            return path.hasSuffix(".\(ext)")
        }

        // Handle exact path or contains
        return path.contains(pattern.replacingOccurrences(of: "*", with: ""))
    }
    
    /// Generate audit report.
    public func generateReport() -> FileAccessReport {
        let reads = readOperations.map(\.url)
        let writes = writeOperations.map(\.url)
        
        // This is a simplified check, real validation should use validateWrites
        // But for the report we just list what happened
        
        return FileAccessReport(
            filesRead: reads,
            filesWritten: writes,
            violationsDetected: [], // Populated by explicit validation call
            summary: "Read \(reads.count) files, wrote \(writes.count) files."
        )
    }
}

// MARK: - Isolation Verification

public struct PlannedModification: Sendable {
    public let url: URL
    public let reason: String
}

public struct PlannedRead: Sendable {
    public let url: URL
    public let reason: String
}

public struct VerificationResult: Sendable {
    public let isIsolated: Bool
    public let plannedWrites: [URL]
    public let plannedReads: [URL]
    public let warnings: [String]
}

public actor IsolationVerifier {

    private let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    /// Verify that the operation will not modify unexpected files.
    public func verify(
        configuration: Configuration,
        mode: OperationMode,
        files: [URL]
    ) async throws -> VerificationResult {

        let plannedWrites = try await listModifications(configuration: configuration, files: files)
        let plannedReads = try await listReads(configuration: configuration, mode: mode)

        var warnings: [String] = []

        // In translation-only mode, validate all writes are allowed
        if mode == .translationOnly {
            for modification in plannedWrites {
                let isAllowed = isWriteAllowed(
                    url: modification.url,
                    patterns: configuration.isolation.allowedWritePatterns
                )
                if !isAllowed {
                    warnings.append("Unexpected write target for translation-only mode: \(modification.url.lastPathComponent)")
                }
            }
        }

        let isIsolated = warnings.isEmpty

        return VerificationResult(
            isIsolated: isIsolated,
            plannedWrites: plannedWrites.map(\.url),
            plannedReads: plannedReads.map(\.url),
            warnings: warnings
        )
    }

    /// List all files that WILL be modified.
    public func listModifications(
        configuration: Configuration,
        files: [URL]
    ) async throws -> [PlannedModification] {
        var modifications: [PlannedModification] = []

        // XCStrings files that will be translated
        for file in files {
            if file.pathExtension == "xcstrings" {
                modifications.append(PlannedModification(
                    url: file,
                    reason: "Translation target"
                ))
            } else if file.pathExtension == "strings" || file.pathExtension == "stringsdict" {
                modifications.append(PlannedModification(
                    url: file,
                    reason: "Legacy format translation target"
                ))
            }
        }

        // Cache file
        let cacheFile = configuration.changeDetection.cacheFile
        let cacheURL = URL(fileURLWithPath: cacheFile)
        modifications.append(PlannedModification(
            url: cacheURL,
            reason: "Translation cache"
        ))

        // Translation memory file (if enabled)
        if let tmSettings = configuration.context.translationMemory,
           tmSettings.enabled {
            let tmURL = URL(fileURLWithPath: tmSettings.file)
            modifications.append(PlannedModification(
                url: tmURL,
                reason: "Translation memory storage"
            ))
        }

        return modifications
    }

    /// List all files that WILL be read.
    public func listReads(
        configuration: Configuration,
        mode: OperationMode
    ) async throws -> [PlannedRead] {
        var reads: [PlannedRead] = []

        // Configuration file
        reads.append(PlannedRead(
            url: URL(fileURLWithPath: ".swiftlocalize.json"),
            reason: "Configuration"
        ))

        // Source code files (if context extraction is enabled)
        if let sourceSettings = configuration.context.sourceCode,
           sourceSettings.enabled {
            let sourceFiles = try await findSourceFiles(
                patterns: sourceSettings.paths,
                excludes: sourceSettings.exclude
            )
            for file in sourceFiles {
                reads.append(PlannedRead(
                    url: file,
                    reason: "Context extraction (read-only)"
                ))
            }
        }

        // Glossary file (if enabled)
        if let glossarySettings = configuration.context.glossary,
           glossarySettings.enabled,
           let glossaryFile = glossarySettings.file {
            let glossaryURL = URL(fileURLWithPath: glossaryFile)
            reads.append(PlannedRead(
                url: glossaryURL,
                reason: "Glossary terms"
            ))
        }

        // Translation memory file (if enabled)
        if let tmSettings = configuration.context.translationMemory,
           tmSettings.enabled {
            let tmURL = URL(fileURLWithPath: tmSettings.file)
            reads.append(PlannedRead(
                url: tmURL,
                reason: "Translation memory lookup"
            ))
        }

        return reads
    }

    // MARK: - Private Helpers

    /// Check if a write is allowed by the configured patterns.
    private func isWriteAllowed(url: URL, patterns: [String]) -> Bool {
        let path = url.path

        for pattern in patterns {
            if matchesGlobPattern(path: path, pattern: pattern) {
                return true
            }
        }

        return false
    }

    /// Simple glob pattern matching.
    private func matchesGlobPattern(path: String, pattern: String) -> Bool {
        // Handle common glob patterns
        if pattern == "*" || pattern == "**/*" {
            return true
        }

        // Handle **/*.extension patterns
        if pattern.hasPrefix("**/") {
            let suffix = String(pattern.dropFirst(3))
            if suffix.hasPrefix("*.") {
                let ext = String(suffix.dropFirst(2))
                return path.hasSuffix(".\(ext)")
            }
            return path.contains(suffix)
        }

        // Handle *.extension patterns
        if pattern.hasPrefix("*.") {
            let ext = String(pattern.dropFirst(2))
            return path.hasSuffix(".\(ext)")
        }

        // Handle exact path or contains
        return path.contains(pattern.replacingOccurrences(of: "*", with: ""))
    }

    /// Find source files matching patterns.
    private func findSourceFiles(
        patterns: [String],
        excludes: [String]
    ) async throws -> [URL] {
        var sourceFiles: [URL] = []
        let currentDir = URL(fileURLWithPath: fileManager.currentDirectoryPath)

        // For each pattern, find matching files
        for pattern in patterns {
            let files = try findFiles(matching: pattern, in: currentDir)

            // Filter out excluded files
            let filtered = files.filter { url in
                let path = url.path
                for exclude in excludes {
                    if matchesGlobPattern(path: path, pattern: exclude) {
                        return false
                    }
                }
                return true
            }

            sourceFiles.append(contentsOf: filtered)
        }

        return Array(Set(sourceFiles)) // Remove duplicates
    }

    /// Find files matching a simple glob pattern.
    private func findFiles(matching pattern: String, in directory: URL) throws -> [URL] {
        var results: [URL] = []

        // Determine file extension from pattern
        var searchExtension: String?
        if pattern.contains("*.swift") {
            searchExtension = "swift"
        } else if pattern.contains("*.") {
            if let range = pattern.range(of: "*.", options: .backwards) {
                searchExtension = String(pattern[range.upperBound...])
            }
        }

        // Enumerate directory
        guard let enumerator = fileManager.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return results
        }

        for case let fileURL as URL in enumerator {
            if let ext = searchExtension {
                if fileURL.pathExtension == ext {
                    results.append(fileURL)
                }
            } else {
                results.append(fileURL)
            }
        }

        return results
    }
}