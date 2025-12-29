//
//  Plugin.swift
//  SwiftLocalizeBuildPlugin
//

import Foundation
import PackagePlugin

// MARK: - SwiftLocalizeBuildPlugin

/// Build tool plugin that validates translations during the build process.
///
/// This plugin runs on every build to verify that xcstrings files are valid
/// and have complete translations. It does NOT perform translations automatically
/// (use the command plugin for that) as translation requires API calls.
///
/// The plugin will emit warnings for:
/// - Missing translations for configured target languages
/// - Invalid xcstrings file format
/// - Format specifier mismatches between source and translations
@main
struct SwiftLocalizeBuildPlugin: BuildToolPlugin {
    func createBuildCommands(context: PluginContext, target: Target) async throws -> [Command] {
        // Find xcstrings files in the target
        guard let sourceTarget = target as? SourceModuleTarget else {
            return []
        }

        let xcstringsFiles = sourceTarget.sourceFiles.filter { file in
            file.url.pathExtension == "xcstrings"
        }

        guard !xcstringsFiles.isEmpty else {
            return []
        }

        // Get the swiftlocalize tool for validation
        let tool: PluginContext.Tool
        do {
            tool = try context.tool(named: "swiftlocalize")
        } catch {
            // Tool not available, skip validation
            Diagnostics.warning("swiftlocalize tool not found, skipping translation validation")
            return []
        }

        // Create a validation command for each xcstrings file
        var commands: [Command] = []

        for file in xcstringsFiles {
            // Create output file path for the build system
            // We use a marker file to track validation status
            let outputPath = context.pluginWorkDirectoryURL.appending(
                path: "\(file.url.lastPathComponent).validated",
            )

            commands.append(.buildCommand(
                displayName: "Validate \(file.url.lastPathComponent)",
                executable: tool.url,
                arguments: [
                    "validate",
                    file.url.path,
                ],
                inputFiles: [file.url],
                outputFiles: [outputPath],
            ))
        }

        return commands
    }
}

#if canImport(XcodeProjectPlugin)
    import XcodeProjectPlugin

    extension SwiftLocalizeBuildPlugin: XcodeBuildToolPlugin {
        func createBuildCommands(
            context: XcodePluginContext,
            target: XcodeTarget,
        ) throws -> [Command] {
            // Find xcstrings files in the target's input files
            let xcstringsFiles = target.inputFiles.filter { file in
                file.url.pathExtension == "xcstrings"
            }

            guard !xcstringsFiles.isEmpty else {
                return []
            }

            // Get the swiftlocalize tool
            let tool: PluginContext.Tool
            do {
                tool = try context.tool(named: "swiftlocalize")
            } catch {
                Diagnostics.warning("swiftlocalize tool not found, skipping translation validation")
                return []
            }

            // Create validation commands
            var commands: [Command] = []

            for file in xcstringsFiles {
                let outputPath = context.pluginWorkDirectoryURL.appending(
                    path: "\(file.url.lastPathComponent).validated",
                )

                commands.append(.buildCommand(
                    displayName: "Validate \(file.url.lastPathComponent)",
                    executable: tool.url,
                    arguments: [
                        "validate",
                        file.url.path,
                    ],
                    inputFiles: [file.url],
                    outputFiles: [outputPath],
                ))
            }

            return commands
        }
    }
#endif
