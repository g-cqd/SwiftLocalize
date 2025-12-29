//
//  Errors.swift
//  SwiftLocalize
//

import Foundation

// MARK: - Translation Errors

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

// MARK: - HTTP Errors

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

    public static func == (lhs: HTTPError, rhs: HTTPError) -> Bool {
        switch (lhs, rhs) {
        case let (.invalidURL(a), .invalidURL(b)):
            return a == b
        case (.invalidResponse, .invalidResponse):
            return true
        case let (.statusCode(codeA, dataA), .statusCode(codeB, dataB)):
            return codeA == codeB && dataA == dataB
        case let (.encodingFailed(a), .encodingFailed(b)):
            return a == b
        case let (.decodingFailed(a), .decodingFailed(b)):
            return a == b
        case (.timeout, .timeout):
            return true
        case let (.connectionFailed(a), .connectionFailed(b)):
            return a == b
        default:
            return false
        }
    }
}

// MARK: - Configuration Errors

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

// MARK: - XCStrings Errors

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

// MARK: - Context Errors

/// Errors that can occur during context extraction.
public enum ContextError: Error, Sendable, Equatable {
    /// Failed to analyze source code.
    case sourceAnalysisFailed(String)

    /// Failed to load translation memory.
    case translationMemoryLoadFailed(String)

    /// Failed to load glossary.
    case glossaryLoadFailed(String)
}

// MARK: - Legacy Format Errors

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

// MARK: - LocalizedError Conformance

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

extension HTTPError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case let .invalidURL(url):
            return "Invalid URL: \(url)"
        case .invalidResponse:
            return "The server returned an invalid response."
        case let .statusCode(code, _):
            return "HTTP error \(code)"
        case let .encodingFailed(message):
            return "Failed to encode request: \(message)"
        case let .decodingFailed(message):
            return "Failed to decode response: \(message)"
        case .timeout:
            return "The request timed out."
        case let .connectionFailed(message):
            return "Connection failed: \(message)"
        }
    }
}

extension ConfigurationError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case let .fileNotFound(path):
            return "Configuration file not found: \(path)"
        case let .invalidFormat(message):
            return "Invalid configuration format: \(message)"
        case let .missingRequiredField(field):
            return "Missing required field: \(field)"
        case let .invalidValue(field, message):
            return "Invalid value for '\(field)': \(message)"
        case let .environmentVariableNotFound(name):
            return "Environment variable not found: \(name)"
        }
    }
}

extension XCStringsError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case let .fileNotFound(path):
            return "XCStrings file not found: \(path)"
        case let .invalidJSON(message):
            return "Invalid JSON: \(message)"
        case let .invalidStructure(message):
            return "Invalid xcstrings structure: \(message)"
        case let .writeFailed(message):
            return "Failed to write file: \(message)"
        }
    }
}

extension ContextError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case let .sourceAnalysisFailed(message):
            return "Source code analysis failed: \(message)"
        case let .translationMemoryLoadFailed(message):
            return "Failed to load translation memory: \(message)"
        case let .glossaryLoadFailed(message):
            return "Failed to load glossary: \(message)"
        }
    }
}

extension LegacyFormatError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case let .fileNotFound(path):
            return "File not found: \(path)"
        case let .encodingDetectionFailed(path):
            return "Failed to detect encoding for: \(path)"
        case let .unsupportedEncoding(encoding):
            return "Unsupported file encoding: \(encoding)"
        case let .stringsParseError(line, message):
            return "Parse error at line \(line): \(message)"
        case let .stringsdictParseError(message):
            return "Stringsdict parse error: \(message)"
        case let .invalidPluralRule(key, message):
            return "Invalid plural rule for '\(key)': \(message)"
        case let .missingRequiredKey(key, field):
            return "Missing required field '\(field)' in key '\(key)'"
        case let .writeFailed(message):
            return "Failed to write file: \(message)"
        }
    }
}
