//
//  Plugin.swift
//  SwiftLocalizeCommandPlugin
//

import Foundation
import PackagePlugin

// MARK: - SwiftLocalizeCommandPlugin

@main
struct SwiftLocalizeCommandPlugin: CommandPlugin {
    // MARK: Internal

    func performCommand(
        context: PluginContext,
        arguments: [String],
    ) async throws {
        // Get the swiftlocalize tool
        let tool = try context.tool(named: "swiftlocalize")

        // Parse arguments for subcommand
        var processArguments = arguments

        // If no subcommand specified, default to translate
        if processArguments.isEmpty || processArguments.first?.starts(with: "-") == true {
            processArguments.insert("translate", at: 0)
        }

        // Find xcstrings files in the package if no files specified
        if !processArguments.contains(where: { $0.hasSuffix(".xcstrings") }) {
            let xcstringsFiles = findXCStringsFiles(in: context.package.directoryURL)
            if !xcstringsFiles.isEmpty, !processArguments.contains("--help") {
                processArguments.append(contentsOf: xcstringsFiles.map(\.path))
            }
        }

        // Create and run the process
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool.url.path)
        process.arguments = processArguments
        process.currentDirectoryURL = context.package.directoryURL

        // Set up pipes for output
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        try process.run()
        process.waitUntilExit()

        // Read output
        let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()

        if let output = String(data: outputData, encoding: .utf8), !output.isEmpty {
            print(output)
        }

        if let errorOutput = String(data: errorData, encoding: .utf8), !errorOutput.isEmpty {
            Diagnostics.error(errorOutput)
        }

        if process.terminationStatus != 0 {
            throw PluginError.translationFailed(exitCode: process.terminationStatus)
        }
    }

    // MARK: Private

    private func findXCStringsFiles(in directory: URL) -> [URL] {
        var results: [URL] = []
        let fm = FileManager.default

        guard let enumerator = fm.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants],
        ) else {
            return results
        }

        while let url = enumerator.nextObject() as? URL {
            if url.pathExtension == "xcstrings" {
                results.append(url)
            }
        }

        return results
    }
}

// MARK: - PluginError

enum PluginError: Error, CustomStringConvertible {
    case translationFailed(exitCode: Int32)

    // MARK: Internal

    var description: String {
        switch self {
        case let .translationFailed(exitCode):
            "Translation failed with exit code \(exitCode)"
        }
    }
}

#if canImport(XcodeProjectPlugin)
    import XcodeProjectPlugin

    extension SwiftLocalizeCommandPlugin: XcodeCommandPlugin {
        func performCommand(
            context: XcodePluginContext,
            arguments: [String],
        ) throws {
            // Get the swiftlocalize tool
            let tool = try context.tool(named: "swiftlocalize")

            // Parse arguments
            var processArguments = arguments
            if processArguments.isEmpty || processArguments.first?.starts(with: "-") == true {
                processArguments.insert("translate", at: 0)
            }

            // Find xcstrings files in the project
            let xcstringsFiles = findXCStringsFilesInXcodeProject(context.xcodeProject)
            if !xcstringsFiles.isEmpty, !processArguments.contains("--help") {
                processArguments.append(contentsOf: xcstringsFiles.map(\.path))
            }

            // Run the tool
            let process = Process()
            process.executableURL = URL(fileURLWithPath: tool.url.path)
            process.arguments = processArguments
            process.currentDirectoryURL = context.xcodeProject.directoryURL

            let outputPipe = Pipe()
            let errorPipe = Pipe()
            process.standardOutput = outputPipe
            process.standardError = errorPipe

            try process.run()
            process.waitUntilExit()

            let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()

            if let output = String(data: outputData, encoding: .utf8), !output.isEmpty {
                print(output)
            }

            if let errorOutput = String(data: errorData, encoding: .utf8), !errorOutput.isEmpty {
                Diagnostics.error(errorOutput)
            }

            if process.terminationStatus != 0 {
                throw PluginError.translationFailed(exitCode: process.terminationStatus)
            }
        }

        private func findXCStringsFilesInXcodeProject(_ project: XcodeProject) -> [URL] {
            var results: [URL] = []

            for target in project.targets {
                for file in target.inputFiles {
                    if file.url.pathExtension == "xcstrings" {
                        results.append(file.url)
                    }
                }
            }

            return results
        }
    }
#endif
