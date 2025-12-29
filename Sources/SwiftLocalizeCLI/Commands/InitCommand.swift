//
//  InitCommand.swift
//  SwiftLocalize
//

import ArgumentParser
import Foundation
import SwiftLocalizeCore

// MARK: - InitCommand

struct InitCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "init",
        abstract: "Create a configuration file.",
    )

    @Option(name: [.short, .customLong("output")], help: "Output file path.")
    var outputPath: String = ".swiftlocalize.json"

    @Flag(name: .customLong("force"), help: "Overwrite existing configuration.")
    var force = false

    func run() async throws {
        let outputURL = URL(fileURLWithPath: outputPath)

        if FileManager.default.fileExists(atPath: outputURL.path), !force {
            CLIOutput.printError("Configuration file already exists: \(outputPath)")
            CLIOutput.printError("Use --force to overwrite.")
            throw ExitCode.failure
        }

        let loader = ConfigurationLoader()
        let config = loader.defaultConfiguration()

        try loader.write(config, to: outputURL)

        print("Created configuration file: \(outputPath)")
        print("\nNext steps:")
        print("  1. Edit the configuration to add your target languages")
        print("  2. Configure your preferred translation providers")
        print("  3. Set up API keys as environment variables")
        print("  4. Run 'swiftlocalize translate' to translate your strings")
    }
}
