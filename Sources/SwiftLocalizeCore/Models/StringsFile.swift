//
//  StringsFile.swift
//  SwiftLocalize
//

import Foundation

// MARK: - StringsFile

/// Represents a legacy .strings localization file.
///
/// .strings files are plain text key-value pairs in the format:
/// ```
/// /* Optional comment */
/// "key" = "value";
/// ```
///
/// They can be encoded as UTF-8 or UTF-16 (with BOM).
public struct StringsFile: Sendable, Equatable {
    // MARK: Lifecycle

    public init(
        language: String,
        entries: [String: StringsEntry] = [:],
        encoding: String.Encoding = .utf8,
    ) {
        self.language = language
        self.entries = entries
        self.encoding = encoding
    }

    // MARK: Public

    /// The language code this file represents.
    public var language: String

    /// Dictionary of string entries keyed by their identifier.
    public var entries: [String: StringsEntry]

    /// The file encoding detected or used for writing.
    public var encoding: String.Encoding

    /// Get all keys sorted alphabetically.
    public var sortedKeys: [String] {
        entries.keys.sorted()
    }
}

// MARK: - StringsEntry

/// A single entry in a .strings file.
public struct StringsEntry: Sendable, Equatable {
    // MARK: Lifecycle

    public init(value: String, comment: String? = nil) {
        self.value = value
        self.comment = comment
    }

    // MARK: Public

    /// The translated or source string value.
    public var value: String

    /// Optional developer comment.
    public var comment: String?
}

// MARK: - StringsFileParser

/// Parses and writes legacy .strings files.
///
/// Handles both UTF-8 and UTF-16 encoded files with proper BOM detection.
/// Preserves comments and maintains round-trip fidelity.
public actor StringsFileParser {
    // MARK: Lifecycle

    public init() {}

    // MARK: Public

    // MARK: - Parsing

    /// Parse a .strings file from a URL.
    ///
    /// - Parameters:
    ///   - url: The file URL to parse.
    ///   - language: The language code for this file (extracted from path if nil).
    /// - Returns: A parsed StringsFile.
    /// - Throws: `LegacyFormatError` if parsing fails.
    public func parse(at url: URL, language: String? = nil) throws -> StringsFile {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw LegacyFormatError.fileNotFound(url.path)
        }

        let data = try Data(contentsOf: url)
        let (content, encoding) = try decodeWithEncoding(data: data, path: url.path)

        let lang = language ?? extractLanguage(from: url)
        let entries = try parseContent(content, path: url.path)

        return StringsFile(
            language: lang,
            entries: entries,
            encoding: encoding,
        )
    }

    /// Parse .strings content from a string.
    ///
    /// - Parameters:
    ///   - content: The string content to parse.
    ///   - language: The language code.
    /// - Returns: A parsed StringsFile.
    public func parse(content: String, language: String) throws -> StringsFile {
        let entries = try parseContent(content, path: "<string>")
        return StringsFile(language: language, entries: entries, encoding: .utf8)
    }

    // MARK: - Writing

    /// Write a StringsFile to a URL.
    ///
    /// - Parameters:
    ///   - file: The StringsFile to write.
    ///   - url: The destination URL.
    ///   - sortKeys: Whether to sort keys alphabetically (default: true).
    public func write(_ file: StringsFile, to url: URL, sortKeys: Bool = true) throws {
        let content = serialize(file, sortKeys: sortKeys)

        guard let data = content.data(using: file.encoding) else {
            throw LegacyFormatError.writeFailed("Failed to encode content as \(file.encoding)")
        }

        // Add BOM for UTF-16
        var outputData = Data()
        if file.encoding == .utf16BigEndian {
            outputData.append(contentsOf: [0xFE, 0xFF])
            outputData.append(data)
        } else if file.encoding == .utf16LittleEndian || file.encoding == .utf16 {
            outputData.append(contentsOf: [0xFF, 0xFE])
            outputData.append(data)
        } else {
            outputData = data
        }

        try outputData.write(to: url, options: .atomic)
    }

    /// Serialize a StringsFile to a string.
    public func serialize(_ file: StringsFile, sortKeys: Bool = true) -> String {
        var lines: [String] = []

        let keys = sortKeys ? file.sortedKeys : Array(file.entries.keys)

        for key in keys {
            guard let entry = file.entries[key] else { continue }

            if let comment = entry.comment {
                lines.append("/* \(comment) */")
            }

            let escapedKey = escapeString(key)
            let escapedValue = escapeString(entry.value)
            lines.append("\"\(escapedKey)\" = \"\(escapedValue)\";")
            lines.append("")
        }

        return lines.joined(separator: "\n")
    }

    // MARK: Private

    // MARK: - Encoding Detection

    /// Detect file encoding from data.
    ///
    /// Checks for UTF-16 BOM markers, falls back to UTF-8.
    private func decodeWithEncoding(data: Data, path: String) throws -> (String, String.Encoding) {
        // Check for UTF-16 BOM
        if data.count >= 2 {
            let bytes = [UInt8](data.prefix(2))

            // UTF-16 BE BOM: FE FF
            if bytes[0] == 0xFE, bytes[1] == 0xFF {
                let textData = data.dropFirst(2)
                guard let string = String(data: Data(textData), encoding: .utf16BigEndian) else {
                    throw LegacyFormatError.encodingDetectionFailed(path)
                }
                return (string, .utf16BigEndian)
            }

            // UTF-16 LE BOM: FF FE
            if bytes[0] == 0xFF, bytes[1] == 0xFE {
                let textData = data.dropFirst(2)
                guard let string = String(data: Data(textData), encoding: .utf16LittleEndian) else {
                    throw LegacyFormatError.encodingDetectionFailed(path)
                }
                return (string, .utf16LittleEndian)
            }
        }

        // Check for UTF-8 BOM (EF BB BF)
        var textData = data
        if data.count >= 3 {
            let bytes = [UInt8](data.prefix(3))
            if bytes[0] == 0xEF, bytes[1] == 0xBB, bytes[2] == 0xBF {
                textData = data.dropFirst(3)
            }
        }

        // Try UTF-8
        guard let string = String(data: textData, encoding: .utf8) else {
            throw LegacyFormatError.encodingDetectionFailed(path)
        }
        return (string, .utf8)
    }

    // MARK: - Content Parsing

    private func parseContent(_ content: String, path: String) throws -> [String: StringsEntry] {
        var entries: [String: StringsEntry] = [:]
        var currentComment: String?
        var lineNumber = 0

        let lines = content.components(separatedBy: .newlines)
        var index = 0

        while index < lines.count {
            lineNumber = index + 1
            let line = lines[index].trimmingCharacters(in: .whitespaces)
            index += 1

            // Skip empty lines
            if line.isEmpty { continue }

            // Single-line comment /* ... */
            if line.hasPrefix("/*"), line.hasSuffix("*/") {
                let commentStart = line.index(line.startIndex, offsetBy: 2)
                let commentEnd = line.index(line.endIndex, offsetBy: -2)
                if commentStart < commentEnd {
                    currentComment = String(line[commentStart ..< commentEnd]).trimmingCharacters(in: .whitespaces)
                }
                continue
            }

            // Multi-line comment start
            if line.hasPrefix("/*") {
                var commentLines: [String] = []
                let firstPart = String(line.dropFirst(2)).trimmingCharacters(in: .whitespaces)
                if !firstPart.isEmpty {
                    commentLines.append(firstPart)
                }

                while index < lines.count {
                    let commentLine = lines[index]
                    index += 1

                    if commentLine.contains("*/") {
                        let endIdx = commentLine.range(of: "*/")!.lowerBound
                        let lastPart = String(commentLine[..<endIdx]).trimmingCharacters(in: .whitespaces)
                        if !lastPart.isEmpty {
                            commentLines.append(lastPart)
                        }
                        break
                    } else {
                        commentLines.append(commentLine.trimmingCharacters(in: .whitespaces))
                    }
                }

                currentComment = commentLines.joined(separator: " ")
                continue
            }

            // C++ style comment //
            if line.hasPrefix("//") {
                currentComment = String(line.dropFirst(2)).trimmingCharacters(in: .whitespaces)
                continue
            }

            // Key-value pair: "key" = "value";
            if line.hasPrefix("\"") {
                let (key, value) = try parseKeyValuePair(line, lineNumber: lineNumber)
                entries[key] = StringsEntry(value: value, comment: currentComment)
                currentComment = nil
            }
        }

        return entries
    }

    private func parseKeyValuePair(_ line: String, lineNumber: Int) throws -> (String, String) {
        var chars = Array(line)
        var idx = 0

        // Parse key
        guard chars[idx] == "\"" else {
            throw LegacyFormatError.stringsParseError(line: lineNumber, message: "Expected opening quote for key")
        }
        idx += 1

        let key = try parseQuotedString(chars: &chars, index: &idx, lineNumber: lineNumber)

        // Skip whitespace
        while idx < chars.count, chars[idx].isWhitespace {
            idx += 1
        }

        // Expect =
        guard idx < chars.count, chars[idx] == "=" else {
            throw LegacyFormatError.stringsParseError(line: lineNumber, message: "Expected '=' after key")
        }
        idx += 1

        // Skip whitespace
        while idx < chars.count, chars[idx].isWhitespace {
            idx += 1
        }

        // Parse value
        guard idx < chars.count, chars[idx] == "\"" else {
            throw LegacyFormatError.stringsParseError(line: lineNumber, message: "Expected opening quote for value")
        }
        idx += 1

        let value = try parseQuotedString(chars: &chars, index: &idx, lineNumber: lineNumber)

        return (key, value)
    }

    private func parseQuotedString(chars: inout [Character], index: inout Int, lineNumber: Int) throws -> String {
        var result: [Character] = []

        while index < chars.count {
            let char = chars[index]

            if char == "\"" {
                index += 1
                return String(result)
            }

            if char == "\\", index + 1 < chars.count {
                index += 1
                let escaped = chars[index]
                switch escaped {
                case "n": result.append("\n")
                case "r": result.append("\r")
                case "t": result.append("\t")
                case "\\": result.append("\\")
                case "\"": result.append("\"")
                case "u",
                     "U":
                    // Unicode escape: \U0000 or \u0000
                    index += 1
                    var hexChars: [Character] = []
                    while index < chars.count, hexChars.count < 4, chars[index].isHexDigit {
                        hexChars.append(chars[index])
                        index += 1
                    }
                    if hexChars.count == 4,
                       let codePoint = UInt32(String(hexChars), radix: 16),
                       let scalar = Unicode.Scalar(codePoint) {
                        result.append(Character(scalar))
                    }
                    continue

                default:
                    result.append(char)
                    result.append(escaped)
                }
                index += 1
            } else {
                result.append(char)
                index += 1
            }
        }

        throw LegacyFormatError.stringsParseError(line: lineNumber, message: "Unterminated string")
    }

    // MARK: - String Escaping

    private func escapeString(_ string: String) -> String {
        var result = ""
        for char in string {
            switch char {
            case "\"": result += "\\\""
            case "\\": result += "\\\\"
            case "\n": result += "\\n"
            case "\r": result += "\\r"
            case "\t": result += "\\t"
            default: result.append(char)
            }
        }
        return result
    }

    // MARK: - Language Extraction

    /// Extract language code from a .lproj directory path.
    private func extractLanguage(from url: URL) -> String {
        // Look for .lproj in path: Base.lproj, en.lproj, etc.
        let pathComponents = url.pathComponents
        for component in pathComponents.reversed() {
            if component.hasSuffix(".lproj") {
                return String(component.dropLast(6))
            }
        }
        return "en"
    }
}
