//
//  XCStringsTests.swift
//  SwiftLocalize
//

import Foundation
import Testing
@testable import SwiftLocalizeCore

@Suite("XCStrings Parsing Tests")
struct XCStringsTests {

    // MARK: - Parsing from Data

    @Test("Parse valid xcstrings JSON")
    func parseValidJSON() throws {
        let json = """
        {
          "sourceLanguage": "en",
          "version": "1.0",
          "strings": {
            "Hello": {
              "comment": "Greeting",
              "localizations": {
                "en": {
                  "stringUnit": {
                    "state": "translated",
                    "value": "Hello"
                  }
                }
              }
            }
          }
        }
        """

        let data = json.data(using: .utf8)!
        let xcstrings = try XCStrings.parse(from: data)

        #expect(xcstrings.sourceLanguage == "en")
        #expect(xcstrings.version == "1.0")
        #expect(xcstrings.strings.count == 1)
        #expect(xcstrings.strings["Hello"]?.comment == "Greeting")
    }

    @Test("Parse xcstrings with all field types")
    func parseCompleteXCStrings() throws {
        let json = """
        {
          "sourceLanguage": "en",
          "version": "1.0",
          "strings": {
            "test_key": {
              "comment": "Test comment",
              "extractionState": "manual",
              "shouldTranslate": true,
              "localizations": {
                "en": {
                  "stringUnit": {
                    "state": "translated",
                    "value": "Test value"
                  }
                },
                "fr": {
                  "stringUnit": {
                    "state": "needs_review",
                    "value": "Valeur de test"
                  }
                }
              }
            }
          }
        }
        """

        let data = json.data(using: .utf8)!
        let xcstrings = try XCStrings.parse(from: data)

        let entry = try #require(xcstrings.strings["test_key"])
        #expect(entry.comment == "Test comment")
        #expect(entry.extractionState == "manual")
        #expect(entry.shouldTranslate == true)

        let enLocalization = try #require(entry.localizations?["en"])
        #expect(enLocalization.stringUnit?.state == .translated)
        #expect(enLocalization.stringUnit?.value == "Test value")

        let frLocalization = try #require(entry.localizations?["fr"])
        #expect(frLocalization.stringUnit?.state == .needsReview)
        #expect(frLocalization.stringUnit?.value == "Valeur de test")
    }

    @Test("Parse xcstrings with plural variations")
    func parsePluralVariations() throws {
        let json = """
        {
          "sourceLanguage": "en",
          "version": "1.0",
          "strings": {
            "%lld items": {
              "localizations": {
                "en": {
                  "variations": {
                    "plural": {
                      "one": {
                        "stringUnit": {
                          "state": "translated",
                          "value": "%lld item"
                        }
                      },
                      "other": {
                        "stringUnit": {
                          "state": "translated",
                          "value": "%lld items"
                        }
                      }
                    }
                  }
                }
              }
            }
          }
        }
        """

        let data = json.data(using: .utf8)!
        let xcstrings = try XCStrings.parse(from: data)

        let entry = try #require(xcstrings.strings["%lld items"])
        let enLocalization = try #require(entry.localizations?["en"])
        let plural = try #require(enLocalization.variations?.plural)

        #expect(plural["one"]?.stringUnit?.value == "%lld item")
        #expect(plural["other"]?.stringUnit?.value == "%lld items")
    }

    @Test("Parse xcstrings with device variations")
    func parseDeviceVariations() throws {
        let json = """
        {
          "sourceLanguage": "en",
          "version": "1.0",
          "strings": {
            "Settings": {
              "localizations": {
                "en": {
                  "variations": {
                    "device": {
                      "iphone": {
                        "stringUnit": {
                          "state": "translated",
                          "value": "Settings"
                        }
                      },
                      "mac": {
                        "stringUnit": {
                          "state": "translated",
                          "value": "Preferences"
                        }
                      }
                    }
                  }
                }
              }
            }
          }
        }
        """

        let data = json.data(using: .utf8)!
        let xcstrings = try XCStrings.parse(from: data)

        let entry = try #require(xcstrings.strings["Settings"])
        let enLocalization = try #require(entry.localizations?["en"])
        let device = try #require(enLocalization.variations?.device)

        #expect(device["iphone"]?.stringUnit?.value == "Settings")
        #expect(device["mac"]?.stringUnit?.value == "Preferences")
    }

    @Test("Parse xcstrings with substitutions")
    func parseSubstitutions() throws {
        let json = """
        {
          "sourceLanguage": "en",
          "version": "1.0",
          "strings": {
            "%@ has %lld messages": {
              "localizations": {
                "en": {
                  "stringUnit": {
                    "state": "translated",
                    "value": "%@ has %lld messages"
                  },
                  "substitutions": {
                    "count": {
                      "argNum": 2,
                      "formatSpecifier": "lld"
                    }
                  }
                }
              }
            }
          }
        }
        """

        let data = json.data(using: .utf8)!
        let xcstrings = try XCStrings.parse(from: data)

        let entry = try #require(xcstrings.strings["%@ has %lld messages"])
        let enLocalization = try #require(entry.localizations?["en"])
        let substitution = try #require(enLocalization.substitutions?["count"])

        #expect(substitution.argNum == 2)
        #expect(substitution.formatSpecifier == "lld")
    }

    // MARK: - Encoding

    @Test("Round-trip encoding/decoding")
    func roundTripEncoding() throws {
        let original = XCStrings(
            sourceLanguage: "en",
            strings: [
                "Hello": StringEntry(
                    comment: "Greeting",
                    localizations: [
                        "en": Localization(value: "Hello"),
                        "fr": Localization(value: "Bonjour"),
                    ]
                ),
                "Goodbye": StringEntry(
                    localizations: [
                        "en": Localization(value: "Goodbye"),
                    ]
                ),
            ],
            version: "1.0"
        )

        let encoded = try original.encode()
        let decoded = try XCStrings.parse(from: encoded)

        #expect(decoded.sourceLanguage == original.sourceLanguage)
        #expect(decoded.version == original.version)
        #expect(decoded.strings.count == original.strings.count)
        #expect(decoded.strings["Hello"]?.comment == "Greeting")
        #expect(decoded.strings["Hello"]?.localizations?["fr"]?.stringUnit?.value == "Bonjour")
    }

    @Test("Encode with pretty printing and sorted keys")
    func encodePrettyPrinted() throws {
        let xcstrings = XCStrings(
            sourceLanguage: "en",
            strings: [
                "B": StringEntry(localizations: ["en": Localization(value: "B")]),
                "A": StringEntry(localizations: ["en": Localization(value: "A")]),
            ]
        )

        let data = try xcstrings.encode(prettyPrint: true, sortKeys: true)
        let jsonString = String(data: data, encoding: .utf8)!

        // Sorted keys means "A" should come before "B"
        let aIndex = jsonString.range(of: "\"A\"")!.lowerBound
        let bIndex = jsonString.range(of: "\"B\"")!.lowerBound
        #expect(aIndex < bIndex)

        // Pretty printed should have newlines
        #expect(jsonString.contains("\n"))
    }

    // MARK: - Utility Methods

    @Test("Get keys needing translation")
    func keysNeedingTranslation() throws {
        let xcstrings = XCStrings(
            sourceLanguage: "en",
            strings: [
                "Translated": StringEntry(
                    localizations: [
                        "en": Localization(value: "Translated"),
                        "fr": Localization(value: "Traduit"),
                    ]
                ),
                "NotTranslated": StringEntry(
                    localizations: [
                        "en": Localization(value: "Not Translated"),
                    ]
                ),
                "DoNotTranslate": StringEntry(
                    shouldTranslate: false,
                    localizations: [
                        "en": Localization(value: "Do Not Translate"),
                    ]
                ),
            ]
        )

        let needingFr = xcstrings.keysNeedingTranslation(for: "fr")
        #expect(needingFr == ["NotTranslated"])

        let needingDe = xcstrings.keysNeedingTranslation(for: "de")
        #expect(needingDe.count == 2)
        #expect(needingDe.contains("Translated"))
        #expect(needingDe.contains("NotTranslated"))
        #expect(!needingDe.contains("DoNotTranslate"))
    }

    @Test("Get present languages")
    func presentLanguages() throws {
        let xcstrings = XCStrings(
            sourceLanguage: "en",
            strings: [
                "Hello": StringEntry(
                    localizations: [
                        "en": Localization(value: "Hello"),
                        "fr": Localization(value: "Bonjour"),
                        "es": Localization(value: "Hola"),
                    ]
                ),
                "Goodbye": StringEntry(
                    localizations: [
                        "en": Localization(value: "Goodbye"),
                        "de": Localization(value: "Auf Wiedersehen"),
                    ]
                ),
            ]
        )

        let languages = xcstrings.presentLanguages
        #expect(languages.count == 4)
        #expect(languages.contains("en"))
        #expect(languages.contains("fr"))
        #expect(languages.contains("es"))
        #expect(languages.contains("de"))
    }

    @Test("Get translated count for language")
    func translatedCount() throws {
        let xcstrings = XCStrings(
            sourceLanguage: "en",
            strings: [
                "A": StringEntry(
                    localizations: [
                        "en": Localization(value: "A"),
                        "fr": Localization(value: "A-fr"),
                    ]
                ),
                "B": StringEntry(
                    localizations: [
                        "en": Localization(value: "B"),
                        "fr": Localization(value: "B-fr"),
                    ]
                ),
                "C": StringEntry(
                    localizations: [
                        "en": Localization(value: "C"),
                    ]
                ),
            ]
        )

        #expect(xcstrings.translatedCount(for: "en") == 3)
        #expect(xcstrings.translatedCount(for: "fr") == 2)
        #expect(xcstrings.translatedCount(for: "de") == 0)
    }

    // MARK: - Error Cases

    @Test("Parse invalid JSON throws error")
    func parseInvalidJSON() throws {
        let invalidJSON = "{ not valid json }"
        let data = invalidJSON.data(using: .utf8)!

        #expect(throws: (any Error).self) {
            try XCStrings.parse(from: data)
        }
    }

    @Test("Parse JSON missing required fields")
    func parseMissingRequiredFields() throws {
        let json = """
        {
          "version": "1.0"
        }
        """

        let data = json.data(using: .utf8)!

        #expect(throws: (any Error).self) {
            try XCStrings.parse(from: data)
        }
    }

    // MARK: - Translation State

    @Test("Translation state raw values")
    func translationStateRawValues() {
        #expect(TranslationState.new.rawValue == "new")
        #expect(TranslationState.translated.rawValue == "translated")
        #expect(TranslationState.needsReview.rawValue == "needs_review")
        #expect(TranslationState.stale.rawValue == "stale")
    }

    // MARK: - Resource File Parsing

    @Test("Parse sample xcstrings resource file")
    func parseSampleResourceFile() throws {
        let bundle = Bundle.module
        guard let url = bundle.url(forResource: "Sample", withExtension: "xcstrings") else {
            Issue.record("Sample.xcstrings not found in test resources")
            return
        }

        let xcstrings = try XCStrings.parse(from: url)

        #expect(xcstrings.sourceLanguage == "en")
        #expect(xcstrings.version == "1.0")
        #expect(xcstrings.strings.count == 5)

        // Check Hello entry
        let hello = try #require(xcstrings.strings["Hello"])
        #expect(hello.comment == "Greeting message")
        #expect(hello.localizations?.count == 3)

        // Check shouldTranslate flag
        let doNotTranslate = try #require(xcstrings.strings["DoNotTranslate"])
        #expect(doNotTranslate.shouldTranslate == false)

        // Check plural variations exist
        let items = try #require(xcstrings.strings["%lld items"])
        let enItems = try #require(items.localizations?["en"])
        #expect(enItems.variations?.plural != nil)
    }
}
