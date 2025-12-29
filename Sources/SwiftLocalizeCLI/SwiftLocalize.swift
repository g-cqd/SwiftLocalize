//
//  SwiftLocalize.swift
//  SwiftLocalize
//

import ArgumentParser
import Foundation
import SwiftLocalizeCore

// MARK: - OperationMode + ExpressibleByArgument

extension OperationMode: ExpressibleByArgument {}

// MARK: - ContextDepth + ExpressibleByArgument

extension ContextDepth: ExpressibleByArgument {}

// MARK: - SwiftLocalize

@main
struct SwiftLocalize: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "swiftlocalize",
        abstract: "Automated localization for Swift projects using AI/ML translation providers.",
        version: "0.3.0",
        subcommands: [
            TranslateCommand.self,
            ValidateCommand.self,
            StatusCommand.self,
            InitCommand.self,
            ProvidersCommand.self,
            MigrateCommand.self,
            GlossaryCommand.self,
            CacheCommand.self,
            TargetsCommand.self,
            SyncKeysCommand.self,
        ],
        defaultSubcommand: TranslateCommand.self,
    )
}
