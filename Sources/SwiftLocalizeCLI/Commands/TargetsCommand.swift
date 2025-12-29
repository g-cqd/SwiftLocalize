//
//  TargetsCommand.swift
//  SwiftLocalize
//

import ArgumentParser
import Foundation
import SwiftLocalizeCore

// MARK: - TargetsCommand

struct TargetsCommand: AsyncParsableCommand {
    // MARK: Internal

    static let configuration = CommandConfiguration(
        commandName: "targets",
        abstract: "Discover and list localization targets in the project.",
    )

    @Option(name: [.short, .customLong("path")], help: "Project root path.")
    var projectPath: String?

    @Flag(name: .customLong("json"), help: "Output as JSON.")
    var jsonOutput = false

    @Flag(name: [.short, .customLong("verbose")], help: "Verbose output.")
    var verbose = false

    func run() async throws {
        let fm = FileManager.default
        let cwd = fm.currentDirectoryPath

        let rootURL = if let path = projectPath {
            URL(fileURLWithPath: path, relativeTo: URL(fileURLWithPath: cwd))
        } else {
            URL(fileURLWithPath: cwd)
        }

        let detector = ProjectStructureDetector()
        let structure = try await detector.detect(at: rootURL)

        if jsonOutput {
            try printJSONStructure(structure)
        } else {
            printTextStructure(structure, rootURL: rootURL)
        }
    }

    // MARK: Private

    private func printJSONStructure(_ structure: ProjectStructure) throws {
        struct JSONTarget: Encodable {
            let name: String
            let type: String
            let path: String
            let defaultLocalization: String
            let parentPackage: String?
        }

        struct JSONStructure: Encodable {
            let projectType: String
            let targets: [JSONTarget]
            let packages: [String]
        }

        let jsonStruct = JSONStructure(
            projectType: structure.type.rawValue,
            targets: structure.targets.map { target in
                JSONTarget(
                    name: target.name,
                    type: target.type.rawValue,
                    path: target.xcstringsURL.path,
                    defaultLocalization: target.defaultLocalization,
                    parentPackage: target.parentPackage,
                )
            },
            packages: structure.packages.map(\.name),
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(jsonStruct)
        print(String(data: data, encoding: .utf8) ?? "{}")
    }

    private func printTextStructure(_ structure: ProjectStructure, rootURL: URL) {
        print("Project Structure")
        print("=================")
        print("Type: \(structure.type.rawValue)")
        print("Root: \(rootURL.path)")

        if !structure.packages.isEmpty {
            print("\nPackages:")
            for pkg in structure.packages {
                print("  - \(pkg.name)")
            }
        }

        print("\nLocalization Targets (\(structure.targets.count)):")
        if structure.targets.isEmpty {
            print("  No localization targets found.")
            print("  Run 'swiftlocalize init' to set up localization.")
        } else {
            for target in structure.targets {
                print("\n  \(target.name)")
                print("    Type: \(target.type.rawValue)")
                print("    File: \(target.xcstringsURL.lastPathComponent)")
                if verbose {
                    print("    Path: \(target.xcstringsURL.path)")
                    print("    Language: \(target.defaultLocalization)")
                    if let parent = target.parentPackage {
                        print("    Package: \(parent)")
                    }
                }
            }
        }

        print("\nUse 'swiftlocalize translate --target <name>' to translate a specific target.")
        print("Use 'swiftlocalize translate --all-targets' to translate all targets.")
    }
}
