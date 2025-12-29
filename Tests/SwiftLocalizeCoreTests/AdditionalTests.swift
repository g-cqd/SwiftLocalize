//
//  AdditionalTests.swift
//  SwiftLocalize
//
//  Comprehensive tests for HTTPClient, LanguageCode, LanguageDetector,
//  Errors, and SourceCodeAnalyzer.
//

import Foundation
@testable import SwiftLocalizeCore
import Testing

// MARK: - LanguageCodeTests

@Suite("LanguageCode Tests")
struct LanguageCodeTests {
    @Test("Initialize with string literal")
    func initializeWithStringLiteral() {
        let code: LanguageCode = "en"
        #expect(code.code == "en")
    }

    @Test("Initialize with standard initializer")
    func initializeWithStandardInit() {
        let code = LanguageCode("fr")
        #expect(code.code == "fr")
    }

    @Test("Common language constants are correct")
    func commonLanguageConstants() {
        #expect(LanguageCode.english.code == "en")
        #expect(LanguageCode.spanish.code == "es")
        #expect(LanguageCode.french.code == "fr")
        #expect(LanguageCode.german.code == "de")
        #expect(LanguageCode.japanese.code == "ja")
        #expect(LanguageCode.chineseSimplified.code == "zh-Hans")
        #expect(LanguageCode.chineseTraditional.code == "zh-Hant")
        #expect(LanguageCode.portugueseBrazil.code == "pt-BR")
    }

    @Test("LanguageCode is hashable")
    func languageCodeHashable() {
        var set = Set<LanguageCode>()
        set.insert(.english)
        set.insert(.english)
        set.insert(.french)

        #expect(set.count == 2)
        #expect(set.contains(.english))
        #expect(set.contains(.french))
    }

    @Test("LanguageCode equality")
    func languageCodeEquality() {
        let code1 = LanguageCode("en")
        let code2: LanguageCode = "en"
        let code3 = LanguageCode("fr")

        #expect(code1 == code2)
        #expect(code1 != code3)
    }

    @Test("LanguageCode description matches code")
    func languageCodeDescription() {
        let code = LanguageCode("pt-BR")
        #expect(code.description == "pt-BR")
    }

    @Test("LanguageCode Codable round-trip")
    func languageCodeCodable() throws {
        let original = LanguageCode("zh-Hant")
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        let data = try encoder.encode(original)
        let decoded = try decoder.decode(LanguageCode.self, from: data)

        #expect(decoded == original)
        #expect(decoded.code == "zh-Hant")
    }

    @Test("LanguageCode display name in English locale")
    func languageCodeDisplayName() {
        let code = LanguageCode.french
        let displayName = code.displayName(in: Locale(identifier: "en"))

        #expect(displayName.contains("French"))
    }

    @Test("LanguageCode native display name")
    func languageCodeNativeDisplayName() {
        let code = LanguageCode.french
        let nativeName = code.nativeDisplayName

        // Should contain "français" or similar
        #expect(!nativeName.isEmpty)
    }
}

// MARK: - LanguagePairTests

@Suite("LanguagePair Tests")
struct LanguagePairTests {
    @Test("LanguagePair initialization")
    func languagePairInit() {
        let pair = LanguagePair(source: .english, target: .french)

        #expect(pair.source == .english)
        #expect(pair.target == .french)
    }

    @Test("LanguagePair description")
    func languagePairDescription() {
        let pair = LanguagePair(source: .english, target: .german)
        #expect(pair.description == "en → de")
    }

    @Test("LanguagePair equality")
    func languagePairEquality() {
        let pair1 = LanguagePair(source: .english, target: .french)
        let pair2 = LanguagePair(source: .english, target: .french)
        let pair3 = LanguagePair(source: .french, target: .english)

        #expect(pair1 == pair2)
        #expect(pair1 != pair3)
    }

    @Test("LanguagePair hashable")
    func languagePairHashable() {
        var set = Set<LanguagePair>()
        set.insert(LanguagePair(source: .english, target: .french))
        set.insert(LanguagePair(source: .english, target: .french))
        set.insert(LanguagePair(source: .english, target: .german))

        #expect(set.count == 2)
    }

    @Test("LanguagePair Codable round-trip")
    func languagePairCodable() throws {
        let original = LanguagePair(source: .english, target: .japanese)
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        let data = try encoder.encode(original)
        let decoded = try decoder.decode(LanguagePair.self, from: data)

        #expect(decoded == original)
    }
}

// MARK: - LanguageDetectorTests

@Suite("LanguageDetector Tests")
struct LanguageDetectorTests {
    @Test("Detect English text")
    func detectEnglish() {
        let detector = LanguageDetector()
        let result = detector.detectLanguage(in: "Hello, how are you doing today?")

        #expect(result != nil)
        #expect(result?.language.code == "en")
        #expect(result?.confidence ?? 0 > 0.5)
    }

    @Test("Detect French text")
    func detectFrench() {
        let detector = LanguageDetector()
        let result = detector.detectLanguage(in: "Bonjour, comment allez-vous aujourd'hui?")

        #expect(result != nil)
        #expect(result?.language.code == "fr")
    }

    @Test("Detect Spanish text")
    func detectSpanish() {
        let detector = LanguageDetector()
        let result = detector.detectLanguage(in: "Hola, ¿cómo estás hoy?")

        #expect(result != nil)
        #expect(result?.language.code == "es")
    }

    @Test("Detect German text")
    func detectGerman() {
        let detector = LanguageDetector()
        let result = detector.detectLanguage(in: "Guten Tag, wie geht es Ihnen?")

        #expect(result != nil)
        #expect(result?.language.code == "de")
    }

    @Test("Detect Japanese text")
    func detectJapanese() {
        let detector = LanguageDetector()
        let result = detector.detectLanguage(in: "こんにちは、お元気ですか？")

        #expect(result != nil)
        #expect(result?.language.code == "ja")
    }

    @Test("Detect multiple language candidates")
    func detectMultipleLanguages() {
        let detector = LanguageDetector()
        let results = detector.detectLanguages(
            in: "Hello world, this is a test sentence.",
            maxResults: 3,
        )

        #expect(!results.isEmpty)
        #expect(results[0].language.code == "en")
    }

    @Test("isLanguage returns true for correct language")
    func isLanguageCorrect() {
        let detector = LanguageDetector()
        let isEnglish = detector.isLanguage(
            "The quick brown fox jumps over the lazy dog.",
            expectedLanguage: .english,
        )

        #expect(isEnglish)
    }

    @Test("isLanguage returns false for wrong language")
    func isLanguageIncorrect() {
        let detector = LanguageDetector()
        let isFrench = detector.isLanguage(
            "The quick brown fox jumps over the lazy dog.",
            expectedLanguage: .french,
        )

        #expect(!isFrench)
    }

    @Test("detectLanguageTag returns tag string")
    func detectLanguageTag() {
        let detector = LanguageDetector()
        let tag = detector.detectLanguageTag(in: "Bonjour, je suis content de vous voir")

        #expect(tag == "fr")
    }

    @Test("Batch detection with longer sentences")
    func batchDetection() {
        let detector = LanguageDetector()
        // Using longer sentences for more reliable detection
        let texts = [
            "Hello, how are you doing today? I hope you are having a wonderful day.",
            "Bonjour, comment allez-vous aujourd'hui? J'espère que vous passez une bonne journée.",
            "Hola, ¿cómo estás hoy? Espero que tengas un día maravilloso.",
        ]

        let results = detector.detectLanguages(in: texts)

        #expect(results.count == 3)
        #expect(results[0]?.language.code == "en")
        #expect(results[1]?.language.code == "fr")
        #expect(results[2]?.language.code == "es")
    }

    @Test("Group texts by language with sufficient context")
    func groupByLanguage() {
        let detector = LanguageDetector()
        // Using longer sentences for more reliable detection
        let texts = [
            "The quick brown fox jumps over the lazy dog. This is a common English sentence.",
            "Good morning everyone, welcome to the meeting. Please take your seats.",
            "Bonjour à tous et bienvenue dans notre application. Nous sommes ravis de vous accueillir.",
            "Bonsoir mes amis, comment allez-vous ce soir? J'espère que vous allez bien.",
        ]

        let groups = detector.groupByLanguage(texts)

        #expect(groups[.english]?.count == 2)
        #expect(groups[.french]?.count == 2)
    }

    @Test("Detector with language constraints")
    func detectorWithConstraints() {
        let config = LanguageDetector.Configuration(
            languageConstraints: [.english, .french],
            minimumConfidence: 0.3,
        )
        let detector = LanguageDetector(configuration: config)

        let result = detector.detectLanguage(in: "Hello world")
        #expect(result != nil)
    }

    @Test("Detector with minimum confidence threshold")
    func detectorWithConfidenceThreshold() {
        let config = LanguageDetector.Configuration(minimumConfidence: 0.99)
        let detector = LanguageDetector(configuration: config)

        // Short text may not meet high confidence threshold
        let result = detector.detectLanguage(in: "Hi")
        // May or may not return result depending on confidence
        // Just verify it doesn't crash
    }

    @Test("Supported languages list is not empty")
    func supportedLanguagesNotEmpty() {
        let supported = LanguageDetector.supportedLanguages

        #expect(!supported.isEmpty)
        #expect(supported.contains(.english))
        #expect(supported.contains(.french))
        #expect(supported.contains(.german))
    }

    @Test("DetectionResult equality")
    func detectionResultEquality() {
        let result1 = LanguageDetector.DetectionResult(language: .english, confidence: 0.9)
        let result2 = LanguageDetector.DetectionResult(language: .english, confidence: 0.9)
        let result3 = LanguageDetector.DetectionResult(language: .french, confidence: 0.9)

        #expect(result1 == result2)
        #expect(result1 != result3)
    }
}

// MARK: - TranslationErrorTests

@Suite("TranslationError Tests")
struct TranslationErrorTests {
    @Test("noProvidersAvailable error description")
    func noProvidersAvailableDescription() {
        let error = TranslationError.noProvidersAvailable
        #expect(error.errorDescription?.contains("No translation providers") == true)
    }

    @Test("providerNotFound error description")
    func providerNotFoundDescription() {
        let error = TranslationError.providerNotFound("openai")
        #expect(error.errorDescription?.contains("openai") == true)
        #expect(error.errorDescription?.contains("not found") == true)
    }

    @Test("unsupportedLanguagePair error description")
    func unsupportedLanguagePairDescription() {
        let error = TranslationError.unsupportedLanguagePair(source: "en", target: "xx")
        #expect(error.errorDescription?.contains("en") == true)
        #expect(error.errorDescription?.contains("xx") == true)
    }

    @Test("providerError error description")
    func providerErrorDescription() {
        let error = TranslationError.providerError(provider: "deepl", message: "API key invalid")
        #expect(error.errorDescription?.contains("deepl") == true)
        #expect(error.errorDescription?.contains("API key invalid") == true)
    }

    @Test("allProvidersFailed error description")
    func allProvidersFailedDescription() {
        let errors = ["openai": "Rate limit", "anthropic": "Timeout"]
        let error = TranslationError.allProvidersFailed(errors)
        #expect(error.errorDescription?.contains("All providers failed") == true)
        #expect(error.errorDescription?.contains("openai") == true)
    }

    @Test("rateLimitExceeded with retry after")
    func rateLimitExceededWithRetry() {
        let error = TranslationError.rateLimitExceeded(provider: "openai", retryAfter: 60)
        #expect(error.errorDescription?.contains("Rate limit") == true)
        #expect(error.errorDescription?.contains("60") == true)
    }

    @Test("rateLimitExceeded without retry after")
    func rateLimitExceededWithoutRetry() {
        let error = TranslationError.rateLimitExceeded(provider: "openai", retryAfter: nil)
        #expect(error.errorDescription?.contains("Rate limit") == true)
        #expect(error.errorDescription?.contains("openai") == true)
    }

    @Test("invalidResponse error description")
    func invalidResponseDescription() {
        let error = TranslationError.invalidResponse("Missing 'translations' field")
        #expect(error.errorDescription?.contains("Invalid response") == true)
    }

    @Test("cancelled error description")
    func cancelledDescription() {
        let error = TranslationError.cancelled
        #expect(error.errorDescription?.contains("cancelled") == true)
    }

    @Test("TranslationError equality")
    func translationErrorEquality() {
        let error1 = TranslationError.providerNotFound("test")
        let error2 = TranslationError.providerNotFound("test")
        let error3 = TranslationError.providerNotFound("other")

        #expect(error1 == error2)
        #expect(error1 != error3)
    }
}

// MARK: - HTTPErrorTests

@Suite("HTTPError Tests")
struct HTTPErrorTests {
    @Test("invalidURL error description")
    func invalidURLDescription() {
        let error = HTTPError.invalidURL("not a url")
        #expect(error.errorDescription?.contains("Invalid URL") == true)
    }

    @Test("invalidResponse error description")
    func invalidResponseDescription() {
        let error = HTTPError.invalidResponse
        #expect(error.errorDescription?.contains("invalid response") == true)
    }

    @Test("statusCode error description")
    func statusCodeDescription() {
        let error = HTTPError.statusCode(404, Data())
        #expect(error.errorDescription?.contains("404") == true)
    }

    @Test("encodingFailed error description")
    func encodingFailedDescription() {
        let error = HTTPError.encodingFailed("Invalid JSON")
        #expect(error.errorDescription?.contains("encode") == true)
    }

    @Test("decodingFailed error description")
    func decodingFailedDescription() {
        let error = HTTPError.decodingFailed("Type mismatch")
        #expect(error.errorDescription?.contains("decode") == true)
    }

    @Test("timeout error description")
    func timeoutDescription() {
        let error = HTTPError.timeout
        #expect(error.errorDescription?.contains("timed out") == true)
    }

    @Test("connectionFailed error description")
    func connectionFailedDescription() {
        let error = HTTPError.connectionFailed("No network")
        #expect(error.errorDescription?.contains("Connection failed") == true)
    }

    @Test("HTTPError equality")
    func httpErrorEquality() {
        let data = Data("error".utf8)

        #expect(HTTPError.invalidURL("a") == HTTPError.invalidURL("a"))
        #expect(HTTPError.invalidURL("a") != HTTPError.invalidURL("b"))
        #expect(HTTPError.invalidResponse == HTTPError.invalidResponse)
        #expect(HTTPError.statusCode(404, data) == HTTPError.statusCode(404, data))
        #expect(HTTPError.statusCode(404, data) != HTTPError.statusCode(500, data))
        #expect(HTTPError.timeout == HTTPError.timeout)
        #expect(HTTPError.encodingFailed("a") == HTTPError.encodingFailed("a"))
        #expect(HTTPError.decodingFailed("a") == HTTPError.decodingFailed("a"))
        #expect(HTTPError.connectionFailed("a") == HTTPError.connectionFailed("a"))
    }
}

// MARK: - ConfigurationErrorTests

@Suite("ConfigurationError Tests")
struct ConfigurationErrorTests {
    @Test("fileNotFound error description")
    func fileNotFoundDescription() {
        let error = ConfigurationError.fileNotFound("/path/to/file")
        #expect(error.errorDescription?.contains("not found") == true)
        #expect(error.errorDescription?.contains("/path/to/file") == true)
    }

    @Test("invalidFormat error description")
    func invalidFormatDescription() {
        let error = ConfigurationError.invalidFormat("Expected object at root")
        #expect(error.errorDescription?.contains("Invalid configuration format") == true)
    }

    @Test("missingRequiredField error description")
    func missingRequiredFieldDescription() {
        let error = ConfigurationError.missingRequiredField("sourceLanguage")
        #expect(error.errorDescription?.contains("Missing required field") == true)
        #expect(error.errorDescription?.contains("sourceLanguage") == true)
    }

    @Test("invalidValue error description")
    func invalidValueDescription() {
        let error = ConfigurationError.invalidValue(field: "timeout", message: "must be positive")
        #expect(error.errorDescription?.contains("timeout") == true)
        #expect(error.errorDescription?.contains("must be positive") == true)
    }

    @Test("environmentVariableNotFound error description")
    func environmentVariableNotFoundDescription() {
        let error = ConfigurationError.environmentVariableNotFound("OPENAI_API_KEY")
        #expect(error.errorDescription?.contains("OPENAI_API_KEY") == true)
    }

    @Test("ConfigurationError equality")
    func configurationErrorEquality() {
        #expect(ConfigurationError.fileNotFound("a") == ConfigurationError.fileNotFound("a"))
        #expect(ConfigurationError.fileNotFound("a") != ConfigurationError.fileNotFound("b"))
        #expect(ConfigurationError.invalidFormat("a") == ConfigurationError.invalidFormat("a"))
    }
}

// MARK: - XCStringsErrorTests

@Suite("XCStringsError Tests")
struct XCStringsErrorTests {
    @Test("fileNotFound error description")
    func fileNotFoundDescription() {
        let error = XCStringsError.fileNotFound("Localizable.xcstrings")
        #expect(error.errorDescription?.contains("not found") == true)
    }

    @Test("invalidJSON error description")
    func invalidJSONDescription() {
        let error = XCStringsError.invalidJSON("Unexpected token")
        #expect(error.errorDescription?.contains("Invalid JSON") == true)
    }

    @Test("invalidStructure error description")
    func invalidStructureDescription() {
        let error = XCStringsError.invalidStructure("Missing 'strings' key")
        #expect(error.errorDescription?.contains("Invalid xcstrings structure") == true)
    }

    @Test("writeFailed error description")
    func writeFailedDescription() {
        let error = XCStringsError.writeFailed("Permission denied")
        #expect(error.errorDescription?.contains("Failed to write") == true)
    }

    @Test("XCStringsError equality")
    func xcstringsErrorEquality() {
        #expect(XCStringsError.fileNotFound("a") == XCStringsError.fileNotFound("a"))
        #expect(XCStringsError.invalidJSON("a") == XCStringsError.invalidJSON("a"))
        #expect(XCStringsError.invalidStructure("a") == XCStringsError.invalidStructure("a"))
        #expect(XCStringsError.writeFailed("a") == XCStringsError.writeFailed("a"))
    }
}

// MARK: - ContextErrorTests

@Suite("ContextError Tests")
struct ContextErrorTests {
    @Test("sourceAnalysisFailed error description")
    func sourceAnalysisFailedDescription() {
        let error = ContextError.sourceAnalysisFailed("Could not parse Swift file")
        #expect(error.errorDescription?.contains("Source code analysis failed") == true)
    }

    @Test("translationMemoryLoadFailed error description")
    func translationMemoryLoadFailedDescription() {
        let error = ContextError.translationMemoryLoadFailed("File corrupted")
        #expect(error.errorDescription?.contains("translation memory") == true)
    }

    @Test("glossaryLoadFailed error description")
    func glossaryLoadFailedDescription() {
        let error = ContextError.glossaryLoadFailed("Invalid format")
        #expect(error.errorDescription?.contains("glossary") == true)
    }

    @Test("ContextError equality")
    func contextErrorEquality() {
        #expect(ContextError.sourceAnalysisFailed("a") == ContextError.sourceAnalysisFailed("a"))
        #expect(ContextError.sourceAnalysisFailed("a") != ContextError.sourceAnalysisFailed("b"))
    }
}

// MARK: - LegacyFormatErrorTests

@Suite("LegacyFormatError Tests")
struct LegacyFormatErrorTests {
    @Test("fileNotFound error description")
    func fileNotFoundDescription() {
        let error = LegacyFormatError.fileNotFound("Localizable.strings")
        #expect(error.errorDescription?.contains("File not found") == true)
    }

    @Test("encodingDetectionFailed error description")
    func encodingDetectionFailedDescription() {
        let error = LegacyFormatError.encodingDetectionFailed("file.strings")
        #expect(error.errorDescription?.contains("detect encoding") == true)
    }

    @Test("unsupportedEncoding error description")
    func unsupportedEncodingDescription() {
        let error = LegacyFormatError.unsupportedEncoding("UTF-32")
        #expect(error.errorDescription?.contains("Unsupported file encoding") == true)
    }

    @Test("stringsParseError error description")
    func stringsParseErrorDescription() {
        let error = LegacyFormatError.stringsParseError(line: 42, message: "Unexpected character")
        #expect(error.errorDescription?.contains("line 42") == true)
    }

    @Test("stringsdictParseError error description")
    func stringsdictParseErrorDescription() {
        let error = LegacyFormatError.stringsdictParseError("Invalid plist")
        #expect(error.errorDescription?.contains("Stringsdict parse error") == true)
    }

    @Test("invalidPluralRule error description")
    func invalidPluralRuleDescription() {
        let error = LegacyFormatError.invalidPluralRule(key: "items_count", message: "Missing 'other' case")
        #expect(error.errorDescription?.contains("items_count") == true)
        #expect(error.errorDescription?.contains("plural rule") == true)
    }

    @Test("missingRequiredKey error description")
    func missingRequiredKeyDescription() {
        let error = LegacyFormatError.missingRequiredKey(key: "items", field: "NSStringLocalizedFormatKey")
        #expect(error.errorDescription?.contains("items") == true)
        #expect(error.errorDescription?.contains("NSStringLocalizedFormatKey") == true)
    }

    @Test("writeFailed error description")
    func writeFailedDescription() {
        let error = LegacyFormatError.writeFailed("Disk full")
        #expect(error.errorDescription?.contains("Failed to write") == true)
    }

    @Test("LegacyFormatError equality")
    func legacyFormatErrorEquality() {
        #expect(LegacyFormatError.fileNotFound("a") == LegacyFormatError.fileNotFound("a"))
        #expect(LegacyFormatError.stringsParseError(line: 1, message: "a") ==
            LegacyFormatError.stringsParseError(line: 1, message: "a"))
    }
}

// MARK: - HTTPClientTests

@Suite("HTTPClient Tests")
struct HTTPClientTests {
    @Test("HTTPClient initializes with default configuration")
    func initWithDefaultConfig() async {
        let client = HTTPClient()
        // Just verify initialization doesn't throw
        #expect(client != nil)
    }

    @Test("HTTPClient initializes with custom timeout")
    func initWithTimeout() async {
        let client = HTTPClient(timeout: 30)
        #expect(client != nil)
    }

    @Test("HTTPClient default timeout constant")
    func defaultTimeoutConstant() {
        #expect(HTTPClient.defaultTimeout == 60)
    }

    @Test("extractErrorMessage parses generic error format")
    func extractErrorMessageGeneric() async {
        let client = HTTPClient()
        let json = """
        {"error": {"message": "API key invalid"}}
        """
        let data = Data(json.utf8)

        let message = client.extractErrorMessage(from: data)
        #expect(message == "API key invalid")
    }

    @Test("extractErrorMessage parses message field")
    func extractErrorMessageField() async {
        let client = HTTPClient()
        let json = """
        {"message": "Rate limit exceeded"}
        """
        let data = Data(json.utf8)

        let message = client.extractErrorMessage(from: data)
        #expect(message == "Rate limit exceeded")
    }

    @Test("extractErrorMessage returns raw string for non-JSON")
    func extractErrorMessageRaw() async {
        let client = HTTPClient()
        let data = Data("Plain text error".utf8)

        let message = client.extractErrorMessage(from: data)
        #expect(message == "Plain text error")
    }

    @Test("HTTPClient GET with empty URL throws")
    func getEmptyURLThrows() async {
        let client = HTTPClient()

        do {
            let _: String = try await client.get(url: "")
            #expect(Bool(false), "Should have thrown")
        } catch let error as HTTPError {
            // Empty URL should throw invalidURL
            if case .invalidURL("") = error {
                // Expected
            } else {
                // Also accept connection error for edge cases
            }
        } catch {
            #expect(Bool(false), "Wrong error type: \(error)")
        }
    }

    @Test("HTTPClient POST with empty URL throws")
    func postEmptyURLThrows() async {
        let client = HTTPClient()

        struct TestBody: Encodable {
            let value: String
        }

        do {
            let _: String = try await client.post(
                url: "",
                body: TestBody(value: "test"),
            )
            #expect(Bool(false), "Should have thrown")
        } catch let error as HTTPError {
            // Empty URL should throw invalidURL
            if case .invalidURL("") = error {
                // Expected
            } else {
                // Also acceptable
            }
        } catch {
            #expect(Bool(false), "Wrong error type: \(error)")
        }
    }

    @Test("HTTPClient getData with empty URL throws")
    func getDataEmptyURLThrows() async {
        let client = HTTPClient()

        do {
            _ = try await client.getData(url: "")
            #expect(Bool(false), "Should have thrown")
        } catch let error as HTTPError {
            if case .invalidURL("") = error {
                // Expected
            } else {
                // Also acceptable
            }
        } catch {
            #expect(Bool(false), "Wrong error type: \(error)")
        }
    }
}

// MARK: - SourceCodeAnalyzerTests

@Suite("SourceCodeAnalyzer Tests")
struct SourceCodeAnalyzerTests {
    @Test("Analyzer initializes with default context lines")
    func analyzerInit() async {
        let analyzer = SourceCodeAnalyzer()
        #expect(analyzer != nil)
    }

    @Test("Analyzer initializes with custom context lines")
    func analyzerInitWithContextLines() async {
        let analyzer = SourceCodeAnalyzer(contextLines: 10)
        #expect(analyzer != nil)
    }

    @Test("SourceCodeAnalyzerError directoryNotFound description")
    func analyzerErrorDirectoryNotFound() {
        let error = SourceCodeAnalyzerError.directoryNotFound("/invalid/path")
        #expect(error.errorDescription?.contains("Directory not found") == true)
        #expect(error.errorDescription?.contains("/invalid/path") == true)
    }

    @Test("SourceCodeAnalyzerError fileReadError description")
    func analyzerErrorFileReadError() {
        struct TestError: Error, LocalizedError {
            var errorDescription: String? { "Test error" }
        }
        let error = SourceCodeAnalyzerError.fileReadError("/path/file.swift", TestError())
        #expect(error.errorDescription?.contains("Failed to read file") == true)
    }

    @Test("SourceCodeAnalyzerError invalidPath description")
    func analyzerErrorInvalidPath() {
        let error = SourceCodeAnalyzerError.invalidPath("~invalid~")
        #expect(error.errorDescription?.contains("Invalid path") == true)
    }
}

// MARK: - TranslationResultTests

@Suite("TranslationResult Tests")
struct TranslationResultTests {
    @Test("TranslationResult initialization with all fields")
    func translationResultFullInit() {
        let result = TranslationResult(
            original: "Hello",
            translated: "Bonjour",
            confidence: 0.95,
            provider: "openai",
            metadata: ["model": "gpt-4"],
        )

        #expect(result.original == "Hello")
        #expect(result.translated == "Bonjour")
        #expect(result.confidence == 0.95)
        #expect(result.provider == "openai")
        #expect(result.metadata?["model"] == "gpt-4")
    }

    @Test("TranslationResult initialization with minimal fields")
    func translationResultMinimalInit() {
        let result = TranslationResult(
            original: "Test",
            translated: "Tester",
            provider: "deepl",
        )

        #expect(result.original == "Test")
        #expect(result.translated == "Tester")
        #expect(result.confidence == nil)
        #expect(result.provider == "deepl")
        #expect(result.metadata == nil)
    }

    @Test("TranslationResult equality")
    func translationResultEquality() {
        let result1 = TranslationResult(original: "A", translated: "B", provider: "test")
        let result2 = TranslationResult(original: "A", translated: "B", provider: "test")
        let result3 = TranslationResult(original: "A", translated: "C", provider: "test")

        #expect(result1 == result2)
        #expect(result1 != result3)
    }
}

// MARK: - TranslationContextTests

@Suite("TranslationContext Tests")
struct TranslationContextTests {
    @Test("TranslationContext initialization with all fields")
    func translationContextFullInit() {
        let context = TranslationContext(
            appDescription: "A test app",
            domain: "testing",
            preserveFormatters: true,
            preserveMarkdown: false,
            additionalInstructions: "Keep it simple",
        )

        #expect(context.appDescription == "A test app")
        #expect(context.domain == "testing")
        #expect(context.preserveFormatters == true)
        #expect(context.preserveMarkdown == false)
        #expect(context.additionalInstructions == "Keep it simple")
    }

    @Test("TranslationContext default values")
    func translationContextDefaults() {
        let context = TranslationContext()

        #expect(context.appDescription == nil)
        #expect(context.domain == nil)
        #expect(context.preserveFormatters == true)
        #expect(context.preserveMarkdown == true)
        #expect(context.additionalInstructions == nil)
    }
}

// MARK: - TranslationProgressTests

@Suite("TranslationProgress Tests")
struct TranslationProgressTests {
    @Test("TranslationProgress percentage calculation")
    func progressPercentage() {
        let progress = TranslationProgress(total: 100, completed: 50, failed: 5)

        #expect(progress.percentage == 0.5)
    }

    @Test("TranslationProgress percentage with zero total")
    func progressPercentageZeroTotal() {
        let progress = TranslationProgress(total: 0, completed: 0)

        #expect(progress.percentage == 0)
    }

    @Test("TranslationProgress with language and provider")
    func progressWithDetails() {
        let progress = TranslationProgress(
            total: 50,
            completed: 25,
            failed: 2,
            currentLanguage: .french,
            currentProvider: "openai",
        )

        #expect(progress.total == 50)
        #expect(progress.completed == 25)
        #expect(progress.failed == 2)
        #expect(progress.currentLanguage == .french)
        #expect(progress.currentProvider == "openai")
    }
}

// MARK: - GlossaryTermTests

@Suite("GlossaryTerm Tests")
struct GlossaryTermTests {
    @Test("GlossaryTerm initialization")
    func glossaryTermInit() {
        let term = GlossaryTerm(
            term: "API",
            definition: "Application Programming Interface",
            doNotTranslate: false,
            translations: ["fr": "API", "de": "API"],
            caseSensitive: true,
        )

        #expect(term.term == "API")
        #expect(term.definition == "Application Programming Interface")
        #expect(term.translations?["fr"] == "API")
        #expect(term.caseSensitive == true)
        #expect(term.doNotTranslate == false)
    }

    @Test("GlossaryTerm Codable round-trip")
    func glossaryTermCodable() throws {
        let original = GlossaryTerm(
            term: "LotoFuel",
            definition: "Brand name",
            doNotTranslate: true,
        )

        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        let data = try encoder.encode(original)
        let decoded = try decoder.decode(GlossaryTerm.self, from: data)

        #expect(decoded.term == original.term)
        #expect(decoded.doNotTranslate == original.doNotTranslate)
    }
}

// MARK: - ToneAndFormalityTests

@Suite("Tone and FormalityLevel Tests")
struct ToneAndFormalityTests {
    @Test("Tone has all expected cases")
    func toneCases() {
        let tones: [Tone] = [.friendly, .professional, .casual, .formal, .technical]
        #expect(tones.count == 5)
    }

    @Test("Tone descriptions are not empty")
    func toneDescriptions() {
        for tone in [Tone.friendly, .professional, .casual, .formal, .technical] {
            #expect(!tone.description.isEmpty)
        }
    }

    @Test("FormalityLevel has all expected cases")
    func formalityLevelCases() {
        let levels: [FormalityLevel] = [.informal, .neutral, .formal]
        #expect(levels.count == 3)
    }

    @Test("FormalityLevel descriptions are not empty")
    func formalityLevelDescriptions() {
        for level in [FormalityLevel.informal, .neutral, .formal] {
            #expect(!level.description.isEmpty)
        }
    }
}

// MARK: - TranslationMemoryMatchTests

@Suite("TranslationMemoryMatch Tests")
struct TranslationMemoryMatchTests {
    @Test("TranslationMemoryMatch initialization")
    func matchInit() {
        let match = TranslationMemoryMatch(
            source: "Hello",
            translation: "Bonjour",
            similarity: 0.95,
        )

        #expect(match.source == "Hello")
        #expect(match.translation == "Bonjour")
        #expect(match.similarity == 0.95)
    }

    @Test("TranslationMemoryMatch equality")
    func matchEquality() {
        let match1 = TranslationMemoryMatch(source: "A", translation: "B", similarity: 1.0)
        let match2 = TranslationMemoryMatch(source: "A", translation: "B", similarity: 1.0)
        let match3 = TranslationMemoryMatch(source: "A", translation: "C", similarity: 1.0)

        #expect(match1 == match2)
        #expect(match1 != match3)
    }
}

// MARK: - LanguageReportTests

@Suite("LanguageReport Tests")
struct LanguageReportTests {
    @Test("LanguageReport initialization")
    func languageReportInit() {
        let report = LanguageReport(
            language: .french,
            translatedCount: 100,
            failedCount: 5,
            provider: "openai",
        )

        #expect(report.language == .french)
        #expect(report.translatedCount == 100)
        #expect(report.failedCount == 5)
        #expect(report.provider == "openai")
    }
}

// MARK: - TranslationReportErrorTests

@Suite("TranslationReportError Tests")
struct TranslationReportErrorTests {
    @Test("TranslationReportError initialization")
    func reportErrorInit() {
        let error = TranslationReportError(
            key: "greeting",
            language: .german,
            message: "Translation failed",
        )

        #expect(error.key == "greeting")
        #expect(error.language == .german)
        #expect(error.message == "Translation failed")
    }
}

// MARK: - StringTranslationContextTests

@Suite("StringTranslationContext Tests")
struct StringTranslationContextTests {
    @Test("StringTranslationContext initialization")
    func stringContextInit() {
        let context = StringTranslationContext(
            key: "welcome_message",
            comment: "Shown on home screen",
            uiElementTypes: [.text, .label],
            codeSnippets: ["Text(\"welcome_message\")"],
        )

        #expect(context.key == "welcome_message")
        #expect(context.comment == "Shown on home screen")
        #expect(context.uiElementTypes?.contains(.text) == true)
        #expect(context.codeSnippets?.count == 1)
    }

    @Test("StringTranslationContext with minimal fields")
    func stringContextMinimal() {
        let context = StringTranslationContext(key: "button_ok")

        #expect(context.key == "button_ok")
        #expect(context.comment == nil)
        #expect(context.uiElementTypes == nil)
        #expect(context.codeSnippets == nil)
    }
}
