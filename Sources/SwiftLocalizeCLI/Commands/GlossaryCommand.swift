//
//  GlossaryCommand.swift
//  SwiftLocalize
//

import ArgumentParser
import Foundation
import SwiftLocalizeCore

// MARK: - GlossaryCommand

struct GlossaryCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "glossary",
        abstract: "Manage translation glossary terms.",
        subcommands: [
            GlossaryList.self,
            GlossaryAdd.self,
            GlossaryRemove.self,
            GlossaryInit.self,
        ],
        defaultSubcommand: GlossaryList.self,
    )
}

// MARK: - GlossaryList

struct GlossaryList: AsyncParsableCommand {
    // MARK: Internal

    static let configuration = CommandConfiguration(
        commandName: "list",
        abstract: "List all glossary terms.",
    )

    @Option(name: [.short, .customLong("file")], help: "Glossary file path.")
    var glossaryPath: String = ".swiftlocalize-glossary.json"

    @Flag(name: .customLong("json"), help: "Output as JSON.")
    var jsonOutput = false

    func run() async throws {
        let glossaryURL = URL(fileURLWithPath: glossaryPath)
        let glossary = Glossary(storageURL: glossaryURL)

        do {
            try await glossary.load()
        } catch {
            print("No glossary file found. Run 'swiftlocalize glossary init' to create one.")
            return
        }

        let terms = await glossary.allTerms

        if terms.isEmpty {
            print("Glossary is empty. Use 'swiftlocalize glossary add' to add terms.")
            return
        }

        if jsonOutput {
            try printJSONTerms(terms)
        } else {
            printTextTerms(terms)
        }
    }

    // MARK: Private

    private func printJSONTerms(_ terms: [GlossaryEntry]) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(terms)
        print(String(data: data, encoding: .utf8) ?? "[]")
    }

    private func printTextTerms(_ terms: [GlossaryEntry]) {
        print("Glossary Terms (\(terms.count))")
        print(String(repeating: "=", count: 40))

        for term in terms {
            if term.doNotTranslate {
                print("\n\"\(term.term)\" [DO NOT TRANSLATE]")
            } else {
                print("\n\"\(term.term)\"")
            }

            if let definition = term.definition {
                print("  Definition: \(definition)")
            }

            if !term.translations.isEmpty {
                print("  Translations:")
                for (lang, translation) in term.translations.sorted(by: { $0.key < $1.key }) {
                    print("    \(lang): \(translation)")
                }
            }
        }
    }
}

// MARK: - GlossaryAdd

struct GlossaryAdd: AsyncParsableCommand {
    // MARK: Internal

    static let configuration = CommandConfiguration(
        commandName: "add",
        abstract: "Add a term to the glossary.",
    )

    @Argument(help: "The term to add.")
    var term: String

    @Option(name: [.short, .customLong("file")], help: "Glossary file path.")
    var glossaryPath: String = ".swiftlocalize-glossary.json"

    @Option(name: [.short, .customLong("definition")], help: "Definition or context for the term.")
    var definition: String?

    @Option(
        name: [.short, .customLong("translation")],
        parsing: .upToNextOption,
        help: "Translations as lang:value pairs (e.g., fr:Bonjour de:Hallo).",
    )
    var translations: [String] = []

    @Flag(name: .customLong("do-not-translate"), help: "Mark term as do-not-translate (brand names, etc.).")
    var doNotTranslate = false

    @Flag(name: .customLong("case-sensitive"), help: "Match term case-sensitively.")
    var caseSensitive = false

    func run() async throws {
        let glossaryURL = URL(fileURLWithPath: glossaryPath)
        let glossary = Glossary(storageURL: glossaryURL)

        try? await glossary.load()

        let translationDict = parseTranslations(translations)

        let entry = GlossaryEntry(
            term: term,
            definition: definition,
            translations: translationDict,
            caseSensitive: caseSensitive,
            doNotTranslate: doNotTranslate,
        )

        await glossary.addTerm(entry)
        try await glossary.forceSave()

        print("Added term: \"\(term)\"")
        if doNotTranslate {
            print("  [DO NOT TRANSLATE]")
        }
        if let definition {
            print("  Definition: \(definition)")
        }
        if !translationDict.isEmpty {
            print("  Translations: \(translationDict.map { "\($0.key):\($0.value)" }.joined(separator: ", "))")
        }
    }

    // MARK: Private

    private func parseTranslations(_ translations: [String]) -> [String: String] {
        var translationDict: [String: String] = [:]
        for translation in translations {
            let parts = translation.split(separator: ":", maxSplits: 1)
            if parts.count == 2 {
                translationDict[String(parts[0])] = String(parts[1])
            }
        }
        return translationDict
    }
}

// MARK: - GlossaryRemove

struct GlossaryRemove: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "remove",
        abstract: "Remove a term from the glossary.",
    )

    @Argument(help: "The term to remove.")
    var term: String

    @Option(name: [.short, .customLong("file")], help: "Glossary file path.")
    var glossaryPath: String = ".swiftlocalize-glossary.json"

    func run() async throws {
        let glossaryURL = URL(fileURLWithPath: glossaryPath)
        let glossary = Glossary(storageURL: glossaryURL)

        try await glossary.load()

        if await glossary.getTerm(term) == nil {
            CLIOutput.printError("Term not found: \"\(term)\"")
            throw ExitCode.failure
        }

        await glossary.removeTerm(term)
        try await glossary.forceSave()

        print("Removed term: \"\(term)\"")
    }
}

// MARK: - GlossaryInit

struct GlossaryInit: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "init",
        abstract: "Create a new glossary file.",
    )

    @Option(name: [.short, .customLong("file")], help: "Glossary file path.")
    var glossaryPath: String = ".swiftlocalize-glossary.json"

    @Flag(name: .customLong("force"), help: "Overwrite existing glossary.")
    var force = false

    func run() async throws {
        let glossaryURL = URL(fileURLWithPath: glossaryPath)

        if FileManager.default.fileExists(atPath: glossaryURL.path), !force {
            CLIOutput.printError("Glossary file already exists: \(glossaryPath)")
            CLIOutput.printError("Use --force to overwrite.")
            throw ExitCode.failure
        }

        let glossary = Glossary(storageURL: glossaryURL)

        await glossary.addTerm(GlossaryEntry(
            term: "AppName",
            definition: "Replace with your app name",
            doNotTranslate: true,
        ))

        try await glossary.forceSave()

        print("Created glossary file: \(glossaryPath)")
        print("\nNext steps:")
        print("  1. Add terms with 'swiftlocalize glossary add <term>'")
        print("  2. Configure translations with -t flag (e.g., -t fr:Bonjour)")
        print("  3. Mark brand names with --do-not-translate")
    }
}
