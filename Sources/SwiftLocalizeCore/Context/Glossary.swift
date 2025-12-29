//
//  Glossary.swift
//  SwiftLocalize
//

import Foundation

// MARK: - Glossary

/// Manages app-specific terminology and their translations.
///
/// A glossary ensures consistent translation of domain-specific terms,
/// brand names, and technical vocabulary. Terms can be:
/// - Translated with specific per-language values
/// - Marked as "do not translate" (brand names, acronyms)
/// - Annotated with definitions for context
///
/// ## Usage
/// ```swift
/// let glossary = Glossary(storageURL: glossaryURL)
/// try await glossary.load()
///
/// // Add a term
/// await glossary.addTerm(GlossaryEntry(
///     term: "LotoFuel",
///     doNotTranslate: true
/// ))
///
/// // Add a translated term
/// await glossary.addTerm(GlossaryEntry(
///     term: "Fill-up",
///     translations: ["fr": "plein"]
/// ))
///
/// // Find terms in a string
/// let matches = await glossary.findTerms(in: "Record your LotoFuel fill-up today")
/// ```
public actor Glossary {
    // MARK: Lifecycle

    public init(storageURL: URL? = nil) {
        self.storageURL = storageURL
    }

    // MARK: Public

    /// Get all terms.
    public var allTerms: [GlossaryEntry] {
        terms.values.sorted { $0.term.lowercased() < $1.term.lowercased() }
    }

    /// Get the number of terms.
    public var count: Int {
        terms.count
    }

    // MARK: - Storage

    /// Load glossary from disk.
    public func load() throws {
        guard let url = storageURL else { return }

        guard FileManager.default.fileExists(atPath: url.path) else {
            return
        }

        let data = try Data(contentsOf: url)
        let storage = try JSONDecoder().decode(GlossaryStorage.self, from: data)
        terms = Dictionary(uniqueKeysWithValues: storage.terms.map { ($0.term.lowercased(), $0) })
        isDirty = false
    }

    /// Save glossary to disk.
    public func save() throws {
        guard let url = storageURL else { return }
        guard isDirty else { return }

        let sortedTerms = terms.values.sorted { $0.term.lowercased() < $1.term.lowercased() }
        let storage = GlossaryStorage(version: "1.0", terms: sortedTerms)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(storage)
        try data.write(to: url, options: .atomic)
        isDirty = false
    }

    /// Force save regardless of dirty state.
    public func forceSave() throws {
        isDirty = true
        try save()
    }

    // MARK: - Term Management

    /// Add or update a term.
    public func addTerm(_ term: GlossaryEntry) {
        terms[term.term.lowercased()] = term
        isDirty = true
    }

    /// Add multiple terms in batch.
    public func addTerms(_ newTerms: [GlossaryEntry]) {
        for term in newTerms {
            terms[term.term.lowercased()] = term
        }
        isDirty = true
    }

    /// Remove a term.
    public func removeTerm(_ term: String) {
        terms.removeValue(forKey: term.lowercased())
        isDirty = true
    }

    /// Get a specific term.
    public func getTerm(_ term: String) -> GlossaryEntry? {
        terms[term.lowercased()]
    }

    /// Clear all terms.
    public func clear() {
        terms.removeAll()
        isDirty = true
    }

    // MARK: - Term Finding

    /// Find glossary terms in a string.
    ///
    /// - Parameter text: The text to search in.
    /// - Returns: Array of matches found in the text.
    public func findTerms(in text: String) -> [GlossaryMatch] {
        let lowercasedText = text.lowercased()
        var matches: [GlossaryMatch] = []

        for (key, term) in terms {
            let searchKey = term.caseSensitive ? term.term : key

            // Check if term exists in text
            let searchText = term.caseSensitive ? text : lowercasedText

            if searchText.contains(searchKey) {
                matches.append(GlossaryMatch(
                    term: term.term,
                    doNotTranslate: term.doNotTranslate,
                    translations: term.translations,
                    definition: term.definition,
                ))
            }
        }

        return matches
    }

    /// Find terms that need translations for a language.
    ///
    /// - Parameter language: Target language code.
    /// - Returns: Terms that don't have a translation for the language.
    public func termsNeedingTranslation(for language: String) -> [GlossaryEntry] {
        allTerms.filter { term in
            !term.doNotTranslate && term.translations[language] == nil
        }
    }

    /// Generate prompt instructions for glossary terms.
    ///
    /// - Parameters:
    ///   - matches: Glossary matches found in strings.
    ///   - targetLanguage: Target language code.
    /// - Returns: Formatted instructions for LLM prompt.
    public func toPromptInstructions(
        matches: [GlossaryMatch],
        targetLanguage: String,
    ) -> String {
        guard !matches.isEmpty else { return "" }

        var instructions = ["Terminology to use:"]

        for match in matches {
            if match.doNotTranslate {
                instructions.append("- \"\(match.term)\" → Keep as \"\(match.term)\" (do not translate)")
            } else if let translation = match.translations[targetLanguage] {
                instructions.append("- \"\(match.term)\" → \"\(translation)\"")
            } else if let definition = match.definition {
                instructions.append("- \"\(match.term)\" - \(definition)")
            }
        }

        return instructions.joined(separator: "\n")
    }

    // MARK: - Import/Export

    /// Import terms from a dictionary.
    ///
    /// Useful for importing from configuration files.
    public func importTerms(from config: [[String: Any]]) {
        for termConfig in config {
            guard let term = termConfig["term"] as? String else { continue }

            let doNotTranslate = termConfig["doNotTranslate"] as? Bool ?? false
            let definition = termConfig["definition"] as? String
            let caseSensitive = termConfig["caseSensitive"] as? Bool ?? false
            let partOfSpeech: PartOfSpeech? = if let posString = termConfig["partOfSpeech"] as? String {
                PartOfSpeech(rawValue: posString)
            } else {
                nil
            }

            var translations: [String: String] = [:]
            if let transDict = termConfig["translations"] as? [String: String] {
                translations = transDict
            }

            addTerm(GlossaryEntry(
                term: term,
                definition: definition,
                translations: translations,
                caseSensitive: caseSensitive,
                doNotTranslate: doNotTranslate,
                partOfSpeech: partOfSpeech,
            ))
        }
    }

    /// Export terms to a configuration-friendly format.
    public func exportTerms() -> [[String: Any]] {
        allTerms.map { term in
            var dict: [String: Any] = ["term": term.term]

            if term.doNotTranslate {
                dict["doNotTranslate"] = true
            }

            if let definition = term.definition {
                dict["definition"] = definition
            }

            if term.caseSensitive {
                dict["caseSensitive"] = true
            }

            if let partOfSpeech = term.partOfSpeech {
                dict["partOfSpeech"] = partOfSpeech.rawValue
            }

            if !term.translations.isEmpty {
                dict["translations"] = term.translations
            }

            return dict
        }
    }

    // MARK: Private

    /// Storage location for the glossary.
    private let storageURL: URL?

    /// Terms indexed by their text (lowercased for matching).
    private var terms: [String: GlossaryEntry] = [:]

    /// Whether the glossary has unsaved changes.
    private var isDirty: Bool = false
}

// MARK: - GlossaryStorage

/// Root storage structure for glossary.
struct GlossaryStorage: Codable {
    let version: String
    var terms: [GlossaryEntry]
}

// MARK: - GlossaryEntry

/// A single term in the glossary.
///
/// This is separate from `GlossaryTerm` in Configuration to allow
/// for richer metadata and different serialization.
public struct GlossaryEntry: Codable, Sendable, Equatable {
    // MARK: Lifecycle

    public init(
        term: String,
        definition: String? = nil,
        translations: [String: String] = [:],
        caseSensitive: Bool = false,
        doNotTranslate: Bool = false,
        partOfSpeech: PartOfSpeech? = nil,
    ) {
        self.term = term
        self.definition = definition
        self.translations = translations
        self.caseSensitive = caseSensitive
        self.doNotTranslate = doNotTranslate
        self.partOfSpeech = partOfSpeech
    }

    // MARK: Public

    /// The term text.
    public let term: String

    /// Optional definition or context.
    public var definition: String?

    /// Translations indexed by language code.
    public var translations: [String: String]

    /// Whether matching should be case-sensitive.
    public var caseSensitive: Bool

    /// Whether this term should not be translated.
    public var doNotTranslate: Bool

    /// Part of speech for grammatical context.
    public var partOfSpeech: PartOfSpeech?
}

// MARK: - Convenience Extensions

public extension Glossary {
    /// Create a glossary with pre-defined terms.
    ///
    /// Useful for testing and quick setup.
    static func withTerms(_ terms: [GlossaryEntry]) -> Glossary {
        let glossary = Glossary()
        Task {
            await glossary.addTerms(terms)
        }
        return glossary
    }
}
