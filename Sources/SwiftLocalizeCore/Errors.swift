//
//  Errors.swift
//  SwiftLocalize
//

import Foundation

// MARK: - TranslationError

/// Errors that can occur during translation operations.
public enum TranslationError: Error, Sendable, Equatable {
    /// No translation providers are available.
    case noProvidersAvailable

    /// The specified provider was not found.
    case providerNotFound(String)

    /// The provider does not support the requested language pair.
    case unsupportedLanguagePair(source: String, target: String)

    /// Translation failed with a provider-specific error.
    case providerError(provider: String, message: String)

    /// All providers failed to translate.
    case allProvidersFailed([String: String])

    /// Rate limit exceeded.
    case rateLimitExceeded(provider: String, retryAfter: TimeInterval?)

    /// The translation response was invalid or unparseable.
    case invalidResponse(String)

    /// Translation was cancelled.
    case cancelled
}

// MARK: - HTTPError

/// Errors that can occur during HTTP operations.
public enum HTTPError: Error, Sendable, Equatable {
    /// The URL string was invalid.
    case invalidURL(String)

    /// The response was not a valid HTTP response.
    case invalidResponse

    /// The server returned an error status code.
    case statusCode(Int, Data)

    /// Failed to encode the request body.
    case encodingFailed(String)

    /// Failed to decode the response body.
    case decodingFailed(String)

    /// The request timed out.
    case timeout

    /// Network connection failed.
    case connectionFailed(String)

    // MARK: Public

    public static func == (lhs: HTTPError, rhs: HTTPError) -> Bool {
        switch (lhs, rhs) {
        case let (.invalidURL(a), .invalidURL(b)):
            a == b

        case (.invalidResponse, .invalidResponse):
            true

        case let (.statusCode(codeA, dataA), .statusCode(codeB, dataB)):
            codeA == codeB && dataA == dataB

        case let (.encodingFailed(a), .encodingFailed(b)):
            a == b

        case let (.decodingFailed(a), .decodingFailed(b)):
            a == b

        case (.timeout, .timeout):
            true

        case let (.connectionFailed(a), .connectionFailed(b)):
            a == b

        default:
            false
        }
    }
}

// MARK: - ConfigurationError

/// Errors that can occur when loading or parsing configuration.
public enum ConfigurationError: Error, Sendable, Equatable {
    /// The configuration file was not found.
    case fileNotFound(String)

    /// The configuration file format is invalid.
    case invalidFormat(String)

    /// A required field is missing.
    case missingRequiredField(String)

    /// A field has an invalid value.
    case invalidValue(field: String, message: String)

    /// Environment variable not found.
    case environmentVariableNotFound(String)
}

// MARK: - XCStringsError

/// Errors that can occur when parsing or writing xcstrings files.
public enum XCStringsError: Error, Sendable, Equatable {
    /// The file was not found.
    case fileNotFound(String)

    /// The file is not valid JSON.
    case invalidJSON(String)

    /// The file structure doesn't match xcstrings format.
    case invalidStructure(String)

    /// Failed to write the file.
    case writeFailed(String)
}

// MARK: - ContextError

/// Errors that can occur during context extraction.
public enum ContextError: Error, Sendable, Equatable {
    /// Failed to analyze source code.
    case sourceAnalysisFailed(String)

    /// Failed to load translation memory.
    case translationMemoryLoadFailed(String)

    /// Failed to load glossary.
    case glossaryLoadFailed(String)
}

// MARK: - LegacyFormatError

/// Errors that can occur when parsing legacy localization formats.
public enum LegacyFormatError: Error, Sendable, Equatable {
    /// The file was not found.
    case fileNotFound(String)

    /// Failed to detect file encoding.
    case encodingDetectionFailed(String)

    /// The file encoding is not supported.
    case unsupportedEncoding(String)

    /// Failed to parse .strings file syntax.
    case stringsParseError(line: Int, message: String)

    /// Failed to parse .stringsdict plist structure.
    case stringsdictParseError(String)

    /// Invalid plural rule specification.
    case invalidPluralRule(key: String, message: String)

    /// Missing required key in stringsdict.
    case missingRequiredKey(key: String, field: String)

    /// Failed to write the file.
    case writeFailed(String)
}

// MARK: - TranslationError + LocalizedError

extension TranslationError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .noProvidersAvailable:
            return "No translation providers are available."

        case let .providerNotFound(name):
            return "Translation provider '\(name)' was not found."

        case let .unsupportedLanguagePair(source, target):
            return "Language pair \(source) → \(target) is not supported."

        case let .providerError(provider, message):
            return "Provider '\(provider)' error: \(message)"

        case let .allProvidersFailed(errors):
            let details = errors.map { "\($0.key): \($0.value)" }.joined(separator: ", ")
            return "All providers failed: \(details)"

        case let .rateLimitExceeded(provider, retryAfter):
            if let retry = retryAfter {
                return "Rate limit exceeded for '\(provider)'. Retry after \(retry)s."
            }
            return "Rate limit exceeded for '\(provider)'."

        case let .invalidResponse(message):
            return "Invalid response: \(message)"

        case .cancelled:
            return "Translation was cancelled."
        }
    }
}

// MARK: - HTTPError + LocalizedError

extension HTTPError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case let .invalidURL(url):
            "Invalid URL: \(url)"

        case .invalidResponse:
            "The server returned an invalid response."

        case let .statusCode(code, _):
            "HTTP error \(code)"

        case let .encodingFailed(message):
            "Failed to encode request: \(message)"

        case let .decodingFailed(message):
            "Failed to decode response: \(message)"

        case .timeout:
            "The request timed out."

        case let .connectionFailed(message):
            "Connection failed: \(message)"
        }
    }
}

// MARK: - ConfigurationError + LocalizedError

extension ConfigurationError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case let .fileNotFound(path):
            "Configuration file not found: \(path)"

        case let .invalidFormat(message):
            "Invalid configuration format: \(message)"

        case let .missingRequiredField(field):
            "Missing required field: \(field)"

        case let .invalidValue(field, message):
            "Invalid value for '\(field)': \(message)"

        case let .environmentVariableNotFound(name):
            "Environment variable not found: \(name)"
        }
    }
}

// MARK: - XCStringsError + LocalizedError

extension XCStringsError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case let .fileNotFound(path):
            "XCStrings file not found: \(path)"

        case let .invalidJSON(message):
            "Invalid JSON: \(message)"

        case let .invalidStructure(message):
            "Invalid xcstrings structure: \(message)"

        case let .writeFailed(message):
            "Failed to write file: \(message)"
        }
    }
}

// MARK: - ContextError + LocalizedError

extension ContextError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case let .sourceAnalysisFailed(message):
            "Source code analysis failed: \(message)"

        case let .translationMemoryLoadFailed(message):
            "Failed to load translation memory: \(message)"

        case let .glossaryLoadFailed(message):
            "Failed to load glossary: \(message)"
        }
    }
}

// MARK: - LegacyFormatError + LocalizedError

extension LegacyFormatError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case let .fileNotFound(path):
            "File not found: \(path)"

        case let .encodingDetectionFailed(path):
            "Failed to detect encoding for: \(path)"

        case let .unsupportedEncoding(encoding):
            "Unsupported file encoding: \(encoding)"

        case let .stringsParseError(line, message):
            "Parse error at line \(line): \(message)"

        case let .stringsdictParseError(message):
            "Stringsdict parse error: \(message)"

        case let .invalidPluralRule(key, message):
            "Invalid plural rule for '\(key)': \(message)"

        case let .missingRequiredKey(key, field):
            "Missing required field '\(field)' in key '\(key)'"

        case let .writeFailed(message):
            "Failed to write file: \(message)"
        }
    }
}
