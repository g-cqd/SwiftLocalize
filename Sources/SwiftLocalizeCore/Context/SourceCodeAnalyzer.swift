//
//  SourceCodeAnalyzer.swift
//  SwiftLocalize
//

import Foundation

// MARK: - Source Code Analyzer

/// Analyzes Swift source code to extract context about how strings are used.
///
/// This actor scans Swift and SwiftUI files to determine:
/// - UI element types (Button, Text, Label, Alert, etc.)
/// - SwiftUI modifiers that affect presentation
/// - Surrounding code context
///
/// ## Usage
/// ```swift
/// let analyzer = SourceCodeAnalyzer()
/// let context = try await analyzer.analyzeUsage(
///     key: "welcome_message",
///     in: projectURL
/// )
/// print(context.elementTypes) // [.text, .navigationTitle]
/// ```
public actor SourceCodeAnalyzer {

    /// Patterns for detecting UI element types.
    private let elementPatterns: [(pattern: String, type: UIElementType)]

    /// Patterns for detecting SwiftUI modifiers.
    private let modifierPatterns: [String]

    /// File extensions to scan.
    private let fileExtensions: Set<String>

    /// Maximum lines of context to capture around a match.
    private let contextLines: Int

    public init(contextLines: Int = 5) {
        self.contextLines = contextLines
        self.fileExtensions = ["swift"]

        // Initialize element detection patterns
        // These use simple string matching for performance
        self.elementPatterns = [
            ("Button(", .button),
            ("Button {", .button),
            (".buttonStyle", .button),
            ("Text(", .text),
            ("Label(", .label),
            (".alert(", .alert),
            ("Alert(", .alert),
            (".navigationTitle(", .navigationTitle),
            (".navigationBarTitle(", .navigationTitle),
            (".confirmationDialog(", .confirmationDialog),
            ("TextField(", .textField),
            ("SecureField(", .textField),
            (".tabItem {", .tabItem),
            (".tabItem(", .tabItem),
            (".sheet(", .sheet),
            ("Menu(", .menu),
            (".contextMenu {", .menu),
            (".help(", .tooltip),
            (".placeholder", .placeholder),
            (".accessibilityLabel(", .accessibilityLabel),
            (".accessibilityHint(", .accessibilityHint),
        ]

        // Modifiers that provide context
        self.modifierPatterns = [
            ".font(",
            ".foregroundColor(",
            ".foregroundStyle(",
            ".bold(",
            ".italic(",
            ".lineLimit(",
            ".truncationMode(",
            ".multilineTextAlignment(",
            ".minimumScaleFactor(",
            ".frame(",
            ".padding(",
            ".disabled(",
            ".destructive",
            ".cancel",
            ".default",
        ]
    }

    // MARK: - Public API

    /// Analyze how a string key is used in the codebase.
    ///
    /// - Parameters:
    ///   - key: The string key to search for.
    ///   - projectPath: Root directory of the Swift project.
    /// - Returns: Context about how the string is used.
    public func analyzeUsage(
        key: String,
        in projectPath: URL
    ) throws -> StringUsageContext {
        let occurrences = try findOccurrences(key: key, in: projectPath)

        guard !occurrences.isEmpty else {
            return StringUsageContext(key: key)
        }

        // Detect UI element types
        var elementTypes: Set<UIElementType> = []
        for occurrence in occurrences {
            if let type = detectUIElement(in: occurrence.context) {
                elementTypes.insert(type)
            }
        }

        // Extract code snippets (limit to preserve context window)
        let codeSnippets = occurrences.prefix(3).map { $0.context }

        // Extract modifiers
        var modifiers: Set<String> = []
        for occurrence in occurrences {
            let foundModifiers = detectModifiers(in: occurrence.context)
            modifiers.formUnion(foundModifiers)
        }

        // File locations
        let fileLocations = Array(Set(occurrences.map(\.file))).sorted()

        return StringUsageContext(
            key: key,
            elementTypes: elementTypes,
            codeSnippets: codeSnippets,
            modifiers: Array(modifiers).sorted(),
            fileLocations: fileLocations
        )
    }

    /// Analyze multiple keys in batch for efficiency.
    ///
    /// - Parameters:
    ///   - keys: String keys to analyze.
    ///   - projectPath: Root directory of the Swift project.
    /// - Returns: Dictionary mapping keys to their usage context.
    public func analyzeUsage(
        keys: [String],
        in projectPath: URL
    ) throws -> [String: StringUsageContext] {
        // Build a file cache first
        let files = try collectSwiftFiles(in: projectPath)
        var fileContents: [URL: String] = [:]

        for file in files {
            if let content = try? String(contentsOf: file, encoding: .utf8) {
                fileContents[file] = content
            }
        }

        // Analyze each key
        var results: [String: StringUsageContext] = [:]

        for key in keys {
            let occurrences = findOccurrences(key: key, in: fileContents, basePath: projectPath)

            var elementTypes: Set<UIElementType> = []
            var modifiers: Set<String> = []
            var codeSnippets: [String] = []
            var fileLocations: Set<String> = []

            for occurrence in occurrences {
                if let type = detectUIElement(in: occurrence.context) {
                    elementTypes.insert(type)
                }
                modifiers.formUnion(detectModifiers(in: occurrence.context))
                if codeSnippets.count < 3 {
                    codeSnippets.append(occurrence.context)
                }
                fileLocations.insert(occurrence.file)
            }

            results[key] = StringUsageContext(
                key: key,
                elementTypes: elementTypes,
                codeSnippets: codeSnippets,
                modifiers: Array(modifiers).sorted(),
                fileLocations: fileLocations.sorted()
            )
        }

        return results
    }

    // MARK: - File Discovery

    /// Collect all Swift files in a directory.
    private func collectSwiftFiles(in directory: URL) throws -> [URL] {
        let fm = FileManager.default
        var files: [URL] = []

        guard let enumerator = fm.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return []
        }

        while let element = enumerator.nextObject() {
            guard let fileURL = element as? URL else { continue }

            // Skip common non-source directories
            let path = fileURL.path
            if path.contains(".build/") ||
               path.contains("DerivedData/") ||
               path.contains("Pods/") ||
               path.contains(".git/") ||
               path.contains("Carthage/") {
                continue
            }

            if fileExtensions.contains(fileURL.pathExtension.lowercased()) {
                files.append(fileURL)
            }
        }

        return files
    }

    // MARK: - Occurrence Finding

    /// Find all occurrences of a key in Swift files.
    private func findOccurrences(
        key: String,
        in projectPath: URL
    ) throws -> [CodeOccurrence] {
        let files = try collectSwiftFiles(in: projectPath)
        var occurrences: [CodeOccurrence] = []

        for file in files {
            guard let content = try? String(contentsOf: file, encoding: .utf8) else {
                continue
            }

            let fileOccurrences = findOccurrences(
                key: key,
                in: content,
                file: file.path,
                basePath: projectPath.path
            )
            occurrences.append(contentsOf: fileOccurrences)
        }

        return occurrences
    }

    /// Find occurrences using pre-loaded file contents.
    private func findOccurrences(
        key: String,
        in fileContents: [URL: String],
        basePath: URL
    ) -> [CodeOccurrence] {
        var occurrences: [CodeOccurrence] = []

        for (file, content) in fileContents {
            let fileOccurrences = findOccurrences(
                key: key,
                in: content,
                file: file.path,
                basePath: basePath.path
            )
            occurrences.append(contentsOf: fileOccurrences)
        }

        return occurrences
    }

    /// Find occurrences of a key in a single file's content.
    private func findOccurrences(
        key: String,
        in content: String,
        file: String,
        basePath: String
    ) -> [CodeOccurrence] {
        var occurrences: [CodeOccurrence] = []
        let lines = content.components(separatedBy: .newlines)

        // Search patterns for the key
        let searchPatterns = [
            "\"\(key)\"",           // Direct string literal
            "LocalizedStringKey(\"\(key)\")",
            "String(localized: \"\(key)\")",
            "NSLocalizedString(\"\(key)\"",
            "Text(\"\(key)\"",
            "Label(\"\(key)\"",
        ]

        for (lineIndex, line) in lines.enumerated() {
            for pattern in searchPatterns {
                if line.contains(pattern) {
                    // Extract surrounding context
                    let startLine = max(0, lineIndex - contextLines)
                    let endLine = min(lines.count - 1, lineIndex + contextLines)
                    let contextLines = lines[startLine...endLine].joined(separator: "\n")

                    // Calculate relative file path
                    var relativePath = file
                    if file.hasPrefix(basePath) {
                        relativePath = String(file.dropFirst(basePath.count))
                        if relativePath.hasPrefix("/") {
                            relativePath = String(relativePath.dropFirst())
                        }
                    }

                    // Find column
                    let column = (line.range(of: pattern)?.lowerBound.utf16Offset(in: line) ?? 0) + 1

                    occurrences.append(CodeOccurrence(
                        file: relativePath,
                        line: lineIndex + 1,
                        column: column,
                        context: contextLines,
                        matchedPattern: pattern
                    ))
                    break // Only one occurrence per line
                }
            }
        }

        return occurrences
    }

    // MARK: - Element Detection

    /// Detect UI element type from code context.
    private func detectUIElement(in context: String) -> UIElementType? {
        // Check patterns in order of specificity
        for (pattern, type) in elementPatterns {
            if context.contains(pattern) {
                return type
            }
        }

        // Additional heuristics
        if context.contains("error") || context.contains("Error") {
            if context.contains("message") || context.contains("Message") {
                return .errorMessage
            }
        }

        if context.contains("success") || context.contains("Success") {
            return .successMessage
        }

        return nil
    }

    /// Detect SwiftUI modifiers from code context.
    private func detectModifiers(in context: String) -> Set<String> {
        var found: Set<String> = []

        for pattern in modifierPatterns {
            if context.contains(pattern) {
                // Extract the modifier name without parameters
                let name = pattern.replacingOccurrences(of: "(", with: "")
                found.insert(name)
            }
        }

        return found
    }
}

// MARK: - Analyzer Errors

/// Errors that can occur during source code analysis.
public enum SourceCodeAnalyzerError: Error, Sendable {
    case directoryNotFound(String)
    case fileReadError(String, Error)
    case invalidPath(String)
}

extension SourceCodeAnalyzerError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .directoryNotFound(let path):
            return "Directory not found: \(path)"
        case .fileReadError(let path, let error):
            return "Failed to read file '\(path)': \(error.localizedDescription)"
        case .invalidPath(let path):
            return "Invalid path: \(path)"
        }
    }
}
