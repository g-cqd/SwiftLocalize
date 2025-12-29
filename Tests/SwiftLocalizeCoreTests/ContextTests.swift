//
//  ContextTests.swift
//  SwiftLocalize
//

import Foundation
import Testing

@testable import SwiftLocalizeCore

// MARK: - UIElementTypeTests

@Suite("UIElementType Tests")
struct UIElementTypeTests {
    @Test("All UI element types have context descriptions")
    func allTypesHaveDescriptions() {
        for type in UIElementType.allCases {
            #expect(!type.contextDescription.isEmpty)
        }
    }

    @Test("Context descriptions are unique")
    func descriptionsAreUnique() {
        let descriptions = UIElementType.allCases.map(\.contextDescription)
        let uniqueDescriptions = Set(descriptions)
        #expect(descriptions.count == uniqueDescriptions.count)
    }
}

// MARK: - StringUsageContextTests

@Suite("StringUsageContext Tests")
struct StringUsageContextTests {
    @Test("Empty context produces empty description")
    func emptyContextDescription() {
        let context = StringUsageContext(key: "test_key")
        #expect(context.toContextDescription().isEmpty)
    }

    @Test("Context with element types includes them in description")
    func contextWithElementTypes() {
        let context = StringUsageContext(
            key: "test_key",
            elementTypes: [.button, .text],
        )
        let description = context.toContextDescription()
        #expect(description.contains("UI Element:"))
        #expect(description.contains("button"))
        #expect(description.contains("text"))
    }

    @Test("Context with modifiers includes them")
    func contextWithModifiers() {
        let context = StringUsageContext(
            key: "test_key",
            modifiers: [".font", ".bold"],
        )
        let description = context.toContextDescription()
        #expect(description.contains("Modifiers:"))
        #expect(description.contains(".font"))
    }

    @Test("Context with code snippet includes it")
    func contextWithCodeSnippet() {
        let snippet = "Button(\"Click me\") { action() }"
        let context = StringUsageContext(
            key: "test_key",
            codeSnippets: [snippet],
        )
        let description = context.toContextDescription()
        #expect(description.contains("Code Context:"))
        #expect(description.contains("Button"))
    }

    @Test("Long code snippets are truncated")
    func longSnippetsTruncated() {
        let longSnippet = String(repeating: "x", count: 500)
        let context = StringUsageContext(
            key: "test_key",
            codeSnippets: [longSnippet],
        )
        let description = context.toContextDescription()
        #expect(description.contains("..."))
        #expect(description.count < 500)
    }
}

// MARK: - TranslationMemoryTests

@Suite("TranslationMemory Tests")
struct TranslationMemoryTests {
    @Test("Store and retrieve exact match")
    func storeAndRetrieveExact() async {
        let tm = TranslationMemory()

        await tm.store(
            source: "Hello",
            translation: "Bonjour",
            language: "fr",
            provider: "test",
        )

        let result = await tm.findExact(text: "Hello", targetLanguage: "fr")
        #expect(result == "Bonjour")
    }

    @Test("Returns nil for missing translation")
    func missingTranslation() async {
        let tm = TranslationMemory()

        let result = await tm.findExact(text: "Hello", targetLanguage: "fr")
        #expect(result == nil)
    }

    @Test("Find similar translations with fuzzy matching")
    func findSimilar() async {
        let tm = TranslationMemory()

        await tm.store(
            source: "Hello World",
            translation: "Bonjour le Monde",
            language: "fr",
            provider: "test",
        )

        let matches = await tm.findSimilar(to: "Hello World!", targetLanguage: "fr")
        #expect(!matches.isEmpty)
        #expect(matches[0].translation == "Bonjour le Monde")
        #expect(matches[0].similarity > 0.8)
    }

    @Test("Exact match returns similarity 1.0")
    func exactMatchSimilarity() async {
        let tm = TranslationMemory()

        await tm.store(
            source: "Hello",
            translation: "Bonjour",
            language: "fr",
            provider: "test",
        )

        let matches = await tm.findSimilar(to: "Hello", targetLanguage: "fr")
        #expect(matches.count == 1)
        #expect(matches[0].similarity == 1.0)
    }

    @Test("Low similarity matches are filtered out")
    func lowSimilarityFiltered() async {
        let tm = TranslationMemory(minSimilarity: 0.7)

        await tm.store(
            source: "Hello",
            translation: "Bonjour",
            language: "fr",
            provider: "test",
        )

        let matches = await tm.findSimilar(to: "Completely different text", targetLanguage: "fr")
        #expect(matches.isEmpty)
    }

    @Test("Batch store multiple translations")
    func batchStore() async {
        let tm = TranslationMemory()

        await tm.storeBatch([
            ("Hello", "Bonjour", "fr"),
            ("Goodbye", "Au revoir", "fr"),
            ("Hello", "Hola", "es"),
        ], provider: "test")

        let frHello = await tm.findExact(text: "Hello", targetLanguage: "fr")
        let frGoodbye = await tm.findExact(text: "Goodbye", targetLanguage: "fr")
        let esHello = await tm.findExact(text: "Hello", targetLanguage: "es")

        #expect(frHello == "Bonjour")
        #expect(frGoodbye == "Au revoir")
        #expect(esHello == "Hola")
    }

    @Test("Mark translation as human reviewed")
    func markReviewed() async {
        let tm = TranslationMemory()

        await tm.store(
            source: "Hello",
            translation: "Bonjour",
            language: "fr",
            provider: "test",
        )

        await tm.markReviewed(source: "Hello", language: "fr")

        let matches = await tm.findSimilar(to: "Hello", targetLanguage: "fr")
        #expect(matches[0].humanReviewed == true)
    }

    @Test("Get all translations for a language")
    func allTranslationsForLanguage() async {
        let tm = TranslationMemory()

        await tm.storeBatch([
            ("Hello", "Bonjour", "fr"),
            ("Goodbye", "Au revoir", "fr"),
            ("World", "Mundo", "es"),
        ], provider: "test")

        let frTranslations = await tm.allTranslations(for: "fr")
        #expect(frTranslations.count == 2)
        #expect(frTranslations["Hello"] == "Bonjour")
        #expect(frTranslations["Goodbye"] == "Au revoir")
    }

    @Test("Statistics are accurate")
    func statistics() async {
        let tm = TranslationMemory()

        await tm.storeBatch([
            ("Hello", "Bonjour", "fr"),
            ("Hello", "Hola", "es"),
            ("Goodbye", "Au revoir", "fr"),
        ], provider: "openai")

        let stats = await tm.statistics
        #expect(stats.totalEntries == 2)
        #expect(stats.languageCounts["fr"] == 2)
        #expect(stats.languageCounts["es"] == 1)
        #expect(stats.providerCounts["openai"] == 3)
    }

    @Test("Remove entry")
    func removeEntry() async {
        let tm = TranslationMemory()

        await tm.store(
            source: "Hello",
            translation: "Bonjour",
            language: "fr",
            provider: "test",
        )

        await tm.remove(source: "Hello")

        let result = await tm.findExact(text: "Hello", targetLanguage: "fr")
        #expect(result == nil)
    }

    @Test("Clear all entries")
    func clearEntries() async {
        let tm = TranslationMemory()

        await tm.storeBatch([
            ("Hello", "Bonjour", "fr"),
            ("Goodbye", "Au revoir", "fr"),
        ], provider: "test")

        await tm.clear()

        let stats = await tm.statistics
        #expect(stats.totalEntries == 0)
    }
}

// MARK: - GlossaryTests

@Suite("Glossary Tests")
struct GlossaryTests {
    @Test("Add and retrieve term")
    func addAndRetrieveTerm() async {
        let glossary = Glossary()

        await glossary.addTerm(GlossaryEntry(
            term: "LotoFuel",
            doNotTranslate: true,
        ))

        let term = await glossary.getTerm("LotoFuel")
        #expect(term != nil)
        #expect(term?.doNotTranslate == true)
    }

    @Test("Case-insensitive term lookup")
    func caseInsensitiveLookup() async {
        let glossary = Glossary()

        await glossary.addTerm(GlossaryEntry(term: "LotoFuel"))

        let term = await glossary.getTerm("lotofuel")
        #expect(term != nil)
    }

    @Test("Find terms in text")
    func findTermsInText() async {
        let glossary = Glossary()

        await glossary.addTerms([
            GlossaryEntry(term: "LotoFuel", doNotTranslate: true),
            GlossaryEntry(term: "fill-up", translations: ["fr": "plein"]),
        ])

        let matches = await glossary.findTerms(in: "Record your LotoFuel fill-up today")
        #expect(matches.count == 2)
    }

    @Test("Case-sensitive matching when specified")
    func caseSensitiveMatching() async {
        let glossary = Glossary()

        await glossary.addTerm(GlossaryEntry(
            term: "API",
            caseSensitive: true,
            doNotTranslate: true,
        ))

        let matchesUppercase = await glossary.findTerms(in: "Use the API")
        let matchesLowercase = await glossary.findTerms(in: "Use the api")

        #expect(matchesUppercase.count == 1)
        #expect(matchesLowercase.isEmpty)
    }

    @Test("Terms needing translation for language")
    func termsNeedingTranslation() async {
        let glossary = Glossary()

        await glossary.addTerms([
            GlossaryEntry(term: "Hello", translations: ["fr": "Bonjour"]),
            GlossaryEntry(term: "Goodbye", translations: [:]),
            GlossaryEntry(term: "Brand", doNotTranslate: true),
        ])

        let needingFr = await glossary.termsNeedingTranslation(for: "fr")
        let needingDe = await glossary.termsNeedingTranslation(for: "de")

        #expect(needingFr.count == 1)
        #expect(needingFr[0].term == "Goodbye")
        #expect(needingDe.count == 2)
    }

    @Test("Generate prompt instructions")
    func promptInstructions() async {
        let glossary = Glossary()

        let matches = [
            GlossaryMatch(term: "Brand", doNotTranslate: true),
            GlossaryMatch(term: "Hello", translations: ["fr": "Bonjour"]),
        ]

        let instructions = await glossary.toPromptInstructions(
            matches: matches,
            targetLanguage: "fr",
        )

        #expect(instructions.contains("Terminology to use:"))
        #expect(instructions.contains("Brand"))
        #expect(instructions.contains("Keep as"))
        #expect(instructions.contains("Bonjour"))
    }

    @Test("Remove term")
    func removeTerm() async {
        let glossary = Glossary()

        await glossary.addTerm(GlossaryEntry(term: "Test"))
        await glossary.removeTerm("Test")

        let term = await glossary.getTerm("Test")
        #expect(term == nil)
    }

    @Test("All terms returns sorted list")
    func allTermsSorted() async {
        let glossary = Glossary()

        await glossary.addTerms([
            GlossaryEntry(term: "Zebra"),
            GlossaryEntry(term: "Apple"),
            GlossaryEntry(term: "Mango"),
        ])

        let allTerms = await glossary.allTerms
        #expect(allTerms.count == 3)
        #expect(allTerms[0].term == "Apple")
        #expect(allTerms[1].term == "Mango")
        #expect(allTerms[2].term == "Zebra")
    }

    @Test("Count returns correct number")
    func countTerms() async {
        let glossary = Glossary()

        await glossary.addTerms([
            GlossaryEntry(term: "A"),
            GlossaryEntry(term: "B"),
            GlossaryEntry(term: "C"),
        ])

        let count = await glossary.count
        #expect(count == 3)
    }
}

// MARK: - ContextConfigurationTests

@Suite("ContextConfiguration Tests")
struct ContextConfigurationTests {
    @Test("Build app context includes all fields")
    func buildAppContext() {
        let config = ContextConfiguration(
            appName: "TestApp",
            appDescription: "A test application",
            domain: "testing",
            tone: .professional,
            formality: .formal,
        )

        let context = config.buildAppContext()

        #expect(context.contains("TestApp"))
        #expect(context.contains("A test application"))
        #expect(context.contains("testing"))
        #expect(context.contains("Professional"))
        #expect(context.contains("Formal"))
    }

    @Test("Default configuration has sensible values")
    func defaultConfiguration() {
        let config = ContextConfiguration.default

        #expect(config.tone == .friendly)
        #expect(config.formality == .neutral)
        #expect(config.sourceCodeAnalysisEnabled == true)
    }

    @Test("Professional preset has correct values")
    func professionalPreset() {
        let config = ContextConfiguration.professional(appName: "BizApp")

        #expect(config.appName == "BizApp")
        #expect(config.tone == .professional)
        #expect(config.formality == .formal)
        #expect(config.domain == "business")
    }

    @Test("Casual preset has correct values")
    func casualPreset() {
        let config = ContextConfiguration.casual(appName: "FunApp")

        #expect(config.appName == "FunApp")
        #expect(config.tone == .casual)
        #expect(config.formality == .informal)
        #expect(config.domain == "consumer")
    }
}

// MARK: - TranslationPromptContextTests

@Suite("TranslationPromptContext Tests")
struct TranslationPromptContextTests {
    @Test("System prompt includes app context")
    func systemPromptIncludesAppContext() {
        let context = TranslationPromptContext(
            appContext: "App: TestApp\nDomain: testing",
            stringContexts: [],
            targetLanguage: "fr",
        )

        let prompt = context.toSystemPrompt()
        #expect(prompt.contains("TestApp"))
        #expect(prompt.contains("testing"))
    }

    @Test("System prompt includes glossary terms")
    func systemPromptIncludesGlossary() {
        let context = TranslationPromptContext(
            appContext: "App: Test",
            stringContexts: [],
            glossaryTerms: [
                GlossaryMatch(term: "Brand", doNotTranslate: true),
                GlossaryMatch(term: "Hello", translations: ["fr": "Bonjour"]),
            ],
            targetLanguage: "fr",
        )

        let prompt = context.toSystemPrompt()
        #expect(prompt.contains("Terminology"))
        #expect(prompt.contains("Brand"))
        #expect(prompt.contains("unchanged"))
        #expect(prompt.contains("Bonjour"))
    }

    @Test("System prompt includes TM matches")
    func systemPromptIncludesTMMatches() {
        let context = TranslationPromptContext(
            appContext: "App: Test",
            stringContexts: [],
            translationMemoryMatches: [
                TMMatch(source: "Hello", translation: "Bonjour", similarity: 1.0, humanReviewed: true),
            ],
            targetLanguage: "fr",
        )

        let prompt = context.toSystemPrompt()
        #expect(prompt.contains("Previous translations"))
        #expect(prompt.contains("Hello"))
        #expect(prompt.contains("Bonjour"))
        #expect(prompt.contains("reviewed"))
    }

    @Test("User prompt includes strings to translate")
    func userPromptIncludesStrings() {
        let context = TranslationPromptContext(
            appContext: "App: Test",
            stringContexts: [
                StringContext(key: "greeting", value: "Hello", comment: "Welcome message"),
            ],
            targetLanguage: "fr",
        )

        let prompt = context.toUserPrompt()
        #expect(prompt.contains("greeting"))
        #expect(prompt.contains("Hello"))
        #expect(prompt.contains("Welcome message"))
        #expect(prompt.contains("fr"))
    }

    @Test("User prompt includes UI context")
    func userPromptIncludesUIContext() {
        let context = TranslationPromptContext(
            appContext: "App: Test",
            stringContexts: [
                StringContext(
                    key: "action",
                    value: "Submit",
                    usageContext: StringUsageContext(
                        key: "action",
                        elementTypes: [.button],
                    ),
                ),
            ],
            targetLanguage: "fr",
        )

        let prompt = context.toUserPrompt()
        #expect(prompt.contains("UI Context"))
        #expect(prompt.contains("button"))
    }

    @Test("Compact system prompt is shorter")
    func compactPromptIsShorter() {
        let context = TranslationPromptContext(
            appContext: "App: TestApp\nDomain: testing\nDescription: A long description",
            stringContexts: [],
            glossaryTerms: [
                GlossaryMatch(term: "Term1", translations: ["fr": "Terme1"]),
                GlossaryMatch(term: "Term2", doNotTranslate: true),
            ],
            targetLanguage: "fr",
        )

        let full = context.toSystemPrompt()
        let compact = context.toCompactSystemPrompt()

        #expect(compact.count < full.count)
        #expect(compact.contains("fr"))
    }

    @Test("JSON request has correct structure")
    func jsonRequestStructure() {
        let context = TranslationPromptContext(
            appContext: "App: Test",
            stringContexts: [
                StringContext(key: "key1", value: "Value 1", comment: "Comment"),
            ],
            glossaryTerms: [
                GlossaryMatch(term: "Brand", doNotTranslate: true),
            ],
            targetLanguage: "fr",
        )

        let json = context.toJSONRequest()

        #expect(json["targetLanguage"] as? String == "fr")
        #expect(json["appContext"] as? String == "App: Test")

        let strings = json["strings"] as? [[String: Any]]
        #expect(strings?.count == 1)
        #expect(strings?[0]["key"] as? String == "key1")

        let glossary = json["glossary"] as? [[String: Any]]
        #expect(glossary?.count == 1)
        #expect(glossary?[0]["term"] as? String == "Brand")
    }
}

// MARK: - ContextBuilderTests

@Suite("ContextBuilder Tests")
struct ContextBuilderTests {
    @Test("Build simple context without analysis")
    func buildSimpleContext() async {
        let config = ContextConfiguration(
            appName: "TestApp",
            sourceCodeAnalysisEnabled: false,
        )

        let builder = ContextBuilder(config: config)

        let context = await builder.buildSimpleContext(
            for: [("key", "value", "comment")],
            targetLanguage: "fr",
        )

        #expect(context.stringContexts.count == 1)
        #expect(context.targetLanguage == "fr")
        #expect(context.appContext.contains("TestApp"))
    }

    @Test("Build context with glossary")
    func buildContextWithGlossary() async throws {
        let glossary = Glossary()
        await glossary.addTerm(GlossaryEntry(term: "LotoFuel", doNotTranslate: true))

        let config = ContextConfiguration(
            appName: "TestApp",
            sourceCodeAnalysisEnabled: false,
            translationMemoryEnabled: false,
            glossaryEnabled: true,
        )

        let builder = ContextBuilder(
            config: config,
            glossary: glossary,
        )

        let context = try await builder.buildContext(
            for: [("key", "Welcome to LotoFuel", nil)],
            targetLanguage: "fr",
        )

        #expect(!context.glossaryTerms.isEmpty)
        #expect(context.glossaryTerms[0].term == "LotoFuel")
    }

    @Test("Build context for single string")
    func buildContextSingleString() async throws {
        let config = ContextConfiguration(
            appName: "TestApp",
            sourceCodeAnalysisEnabled: false,
        )

        let builder = ContextBuilder(config: config)

        let context = try await builder.buildContext(
            key: "greeting",
            value: "Hello",
            comment: "Welcome message",
            targetLanguage: "de",
        )

        #expect(context.stringContexts.count == 1)
        #expect(context.stringContexts[0].key == "greeting")
        #expect(context.stringContexts[0].value == "Hello")
        #expect(context.stringContexts[0].comment == "Welcome message")
    }
}

// MARK: - TMMatchTests

@Suite("TMMatch Tests")
struct TMMatchTests {
    @Test("TMMatch equality")
    func tmMatchEquality() {
        let match1 = TMMatch(source: "Hello", translation: "Bonjour", similarity: 1.0)
        let match2 = TMMatch(source: "Hello", translation: "Bonjour", similarity: 1.0)
        let match3 = TMMatch(source: "Hello", translation: "Salut", similarity: 0.8)

        #expect(match1 == match2)
        #expect(match1 != match3)
    }

    @Test("TMMatch hashable")
    func tmMatchHashable() {
        let match1 = TMMatch(source: "Hello", translation: "Bonjour", similarity: 1.0)
        let match2 = TMMatch(source: "Hello", translation: "Bonjour", similarity: 1.0)

        var set = Set<TMMatch>()
        set.insert(match1)
        set.insert(match2)

        #expect(set.count == 1)
    }
}

// MARK: - GlossaryMatchTests

@Suite("GlossaryMatch Tests")
struct GlossaryMatchTests {
    @Test("GlossaryMatch equality based on term")
    func glossaryMatchEquality() {
        let match1 = GlossaryMatch(term: "Brand", doNotTranslate: true)
        let match2 = GlossaryMatch(term: "Brand", translations: ["fr": "Marque"])
        let match3 = GlossaryMatch(term: "Other")

        // Equality is based on term only
        #expect(match1 == match2)
        #expect(match1 != match3)
    }

    @Test("GlossaryMatch hashable")
    func glossaryMatchHashable() {
        let match1 = GlossaryMatch(term: "Brand", doNotTranslate: true)
        let match2 = GlossaryMatch(term: "Brand", translations: ["fr": "Marque"])

        var set = Set<GlossaryMatch>()
        set.insert(match1)
        set.insert(match2)

        #expect(set.count == 1)
    }
}

// MARK: - CodeOccurrenceTests

@Suite("CodeOccurrence Tests")
struct CodeOccurrenceTests {
    @Test("CodeOccurrence stores all properties")
    func codeOccurrenceProperties() {
        let occurrence = CodeOccurrence(
            file: "Sources/View.swift",
            line: 42,
            column: 10,
            context: "Button(\"Click me\")",
            matchedPattern: "Button(",
        )

        #expect(occurrence.file == "Sources/View.swift")
        #expect(occurrence.line == 42)
        #expect(occurrence.column == 10)
        #expect(occurrence.context == "Button(\"Click me\")")
        #expect(occurrence.matchedPattern == "Button(")
    }
}
