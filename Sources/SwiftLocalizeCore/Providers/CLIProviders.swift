//
//  CLIProviders.swift
//  SwiftLocalize
//
//  CLI-based translation providers that use locally installed AI CLI tools.

import Foundation

// MARK: - CLIProviderBase

/// Base class for CLI-based translation providers.
///
/// CLI providers execute translation prompts through locally installed command-line tools
/// like Gemini CLI, GitHub Copilot CLI, or OpenAI Codex CLI.
public class CLIProviderBase: @unchecked Sendable {
    // MARK: Lifecycle

    init(timeout: TimeInterval = 120) {
        promptBuilder = TranslationPromptBuilder()
        self.timeout = timeout
    }

    // MARK: Internal

    let promptBuilder: TranslationPromptBuilder
    let timeout: TimeInterval

    /// Execute a CLI command and return the output.
    func executeCommand(
        _ command: String,
        arguments: [String],
        input: String? = nil,
    ) async throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: command)
        process.arguments = arguments

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        let inputPipe = Pipe()

        process.standardOutput = outputPipe
        process.standardError = errorPipe
        process.standardInput = inputPipe

        do {
            try process.run()

            // Write input if provided
            if let input, let data = input.data(using: .utf8) {
                try inputPipe.fileHandleForWriting.write(contentsOf: data)
                try inputPipe.fileHandleForWriting.close()
            }

            // Wait for completion with timeout
            let deadline = Date().addingTimeInterval(timeout)
            while process.isRunning, Date() < deadline {
                try await Task.sleep(nanoseconds: 100_000_000) // 100ms
            }

            if process.isRunning {
                process.terminate()
                throw TranslationError.providerError(
                    provider: "cli",
                    message: "CLI command timed out after \(Int(timeout)) seconds",
                )
            }

            let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()

            if process.terminationStatus != 0 {
                let errorMessage = String(data: errorData, encoding: .utf8) ?? "Unknown error"
                throw TranslationError.providerError(
                    provider: "cli",
                    message: "CLI command failed: \(errorMessage)",
                )
            }

            guard let output = String(data: outputData, encoding: .utf8) else {
                throw TranslationError.invalidResponse("CLI output is not valid UTF-8")
            }

            return output
        } catch let error as TranslationError {
            throw error
        } catch {
            throw TranslationError.providerError(
                provider: "cli",
                message: "Failed to execute CLI: \(error.localizedDescription)",
            )
        }
    }

    /// Find a CLI binary in common installation paths.
    func findBinary(name: String, customPath: String?) -> String? {
        if let customPath, FileManager.default.isExecutableFile(atPath: customPath) {
            return customPath
        }

        let searchPaths = [
            "/usr/local/bin/\(name)",
            "/opt/homebrew/bin/\(name)",
            "\(NSHomeDirectory())/.local/bin/\(name)",
            "\(NSHomeDirectory())/.bun/bin/\(name)",
            "\(NSHomeDirectory())/go/bin/\(name)",
            "/usr/bin/\(name)",
        ]

        if let foundPath = searchPaths.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) {
            return foundPath
        }

        // Try which command
        let whichProcess = Process()
        whichProcess.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        whichProcess.arguments = [name]

        let pipe = Pipe()
        whichProcess.standardOutput = pipe

        do {
            try whichProcess.run()
            whichProcess.waitUntilExit()

            if whichProcess.terminationStatus == 0 {
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                if let path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !path.isEmpty {
                    return path
                }
            }
        } catch {
            // Ignore and return nil
        }

        return nil
    }
}

// MARK: - GeminiCLIProvider

/// Translation provider using Google Gemini CLI.
///
/// Requires the Gemini CLI to be installed: `npm install -g @google/gemini-cli`
///
/// ## Configuration
/// ```json
/// {
///   "providers": {
///     "gemini-cli": {
///       "enabled": true,
///       "binaryPath": "/usr/local/bin/gemini",
///       "model": "gemini-2.0-flash"
///     }
///   }
/// }
/// ```
public final class GeminiCLIProvider: CLIProviderBase, TranslationProvider, @unchecked Sendable {
    // MARK: Lifecycle

    public init(config: GeminiCLIConfig = .init()) {
        self.config = config
        super.init()
        binaryPath = findBinary(name: "gemini", customPath: config.binaryPath)
    }

    // MARK: Public

    /// Configuration for the Gemini CLI provider.
    public struct GeminiCLIConfig: Sendable {
        // MARK: Lifecycle

        public init(
            binaryPath: String? = nil,
            model: String = "gemini-2.0-flash",
        ) {
            self.binaryPath = binaryPath
            self.model = model
        }

        // MARK: Public

        /// Path to the gemini binary.
        public let binaryPath: String?

        /// Model to use for translation.
        public let model: String

        public static func from(providerConfig: ProviderConfig?) -> GeminiCLIConfig {
            GeminiCLIConfig(
                binaryPath: providerConfig?.cliPath,
                model: providerConfig?.model ?? "gemini-2.0-flash",
            )
        }
    }

    public let identifier = "gemini-cli"
    public let displayName = "Gemini CLI"

    public func isAvailable() async -> Bool {
        binaryPath != nil
    }

    public func supportedLanguages() async throws -> [LanguagePair] {
        [] // Supports all languages
    }

    public func translate(
        _ strings: [String],
        from source: LanguageCode,
        to target: LanguageCode,
        context: TranslationContext?,
    ) async throws -> [TranslationResult] {
        guard let binary = binaryPath else {
            throw TranslationError.providerError(
                provider: identifier,
                message: "Gemini CLI not found. Install with: npm install -g @google/gemini-cli",
            )
        }

        let systemPrompt = promptBuilder.buildSystemPrompt(context: context, targetLanguage: target)
        let userPrompt = promptBuilder.buildUserPrompt(strings: strings, context: context, targetLanguage: target)
        let fullPrompt = "\(systemPrompt)\n\n---\n\n\(userPrompt)"

        // Execute gemini CLI
        let output = try await executeCommand(
            binary,
            arguments: [
                "--model", config.model,
                "-p", fullPrompt,
            ],
        )

        return try promptBuilder.parseResponse(output, originalStrings: strings, provider: identifier)
    }

    // MARK: Private

    private let config: GeminiCLIConfig
    private var binaryPath: String?
}

// MARK: - CopilotCLIProvider

/// Translation provider using GitHub Copilot CLI.
///
/// Requires GitHub Copilot CLI and an active subscription.
///
/// ## Configuration
/// ```json
/// {
///   "providers": {
///     "copilot-cli": {
///       "enabled": true,
///       "binaryPath": "~/.bun/bin/copilot"
///     }
///   }
/// }
/// ```
public final class CopilotCLIProvider: CLIProviderBase, TranslationProvider, @unchecked Sendable {
    // MARK: Lifecycle

    public init(config: CopilotCLIConfig = .init()) {
        self.config = config
        super.init()
        binaryPath = findBinary(name: "copilot", customPath: config.binaryPath)
    }

    // MARK: Public

    /// Configuration for the Copilot CLI provider.
    public struct CopilotCLIConfig: Sendable {
        // MARK: Lifecycle

        public init(binaryPath: String? = nil) {
            self.binaryPath = binaryPath
        }

        // MARK: Public

        /// Path to the copilot binary.
        public let binaryPath: String?

        public static func from(providerConfig: ProviderConfig?) -> CopilotCLIConfig {
            CopilotCLIConfig(binaryPath: providerConfig?.cliPath)
        }
    }

    public let identifier = "copilot-cli"
    public let displayName = "GitHub Copilot CLI"

    public func isAvailable() async -> Bool {
        binaryPath != nil
    }

    public func supportedLanguages() async throws -> [LanguagePair] {
        [] // Supports all languages
    }

    public func translate(
        _ strings: [String],
        from source: LanguageCode,
        to target: LanguageCode,
        context: TranslationContext?,
    ) async throws -> [TranslationResult] {
        guard let binary = binaryPath else {
            throw TranslationError.providerError(
                provider: identifier,
                message: "GitHub Copilot CLI not found. Install with: npm install -g @github/copilot-cli",
            )
        }

        let systemPrompt = promptBuilder.buildSystemPrompt(context: context, targetLanguage: target)
        let userPrompt = promptBuilder.buildUserPrompt(strings: strings, context: context, targetLanguage: target)
        let fullPrompt = "\(systemPrompt)\n\n---\n\n\(userPrompt)"

        // Execute copilot CLI in programmatic mode
        let output = try await executeCommand(
            binary,
            arguments: ["-p", fullPrompt],
        )

        return try promptBuilder.parseResponse(output, originalStrings: strings, provider: identifier)
    }

    // MARK: Private

    private let config: CopilotCLIConfig
    private var binaryPath: String?
}

// MARK: - CodexCLIProvider

/// Translation provider using OpenAI Codex CLI.
///
/// Requires OpenAI Codex CLI and a ChatGPT Plus/Pro/Business subscription.
///
/// ## Configuration
/// ```json
/// {
///   "providers": {
///     "codex-cli": {
///       "enabled": true,
///       "binaryPath": "/usr/local/bin/codex",
///       "approvalMode": "auto"
///     }
///   }
/// }
/// ```
public final class CodexCLIProvider: CLIProviderBase, TranslationProvider, @unchecked Sendable {
    // MARK: Lifecycle

    public init(config: CodexCLIConfig = .init()) {
        self.config = config
        super.init()
        binaryPath = findBinary(name: "codex", customPath: config.binaryPath)
    }

    // MARK: Public

    /// Configuration for the Codex CLI provider.
    public struct CodexCLIConfig: Sendable {
        // MARK: Lifecycle

        public init(
            binaryPath: String? = nil,
            approvalMode: ApprovalMode = .auto,
        ) {
            self.binaryPath = binaryPath
            self.approvalMode = approvalMode
        }

        // MARK: Public

        public enum ApprovalMode: String, Sendable {
            case auto = "auto-edit"
            case suggest
            case full = "full-auto"
        }

        /// Path to the codex binary.
        public let binaryPath: String?

        /// Approval mode for codex commands.
        public let approvalMode: ApprovalMode

        public static func from(providerConfig: ProviderConfig?) -> CodexCLIConfig {
            CodexCLIConfig(binaryPath: providerConfig?.cliPath)
        }
    }

    public let identifier = "codex-cli"
    public let displayName = "OpenAI Codex CLI"

    public func isAvailable() async -> Bool {
        binaryPath != nil
    }

    public func supportedLanguages() async throws -> [LanguagePair] {
        [] // Supports all languages
    }

    public func translate(
        _ strings: [String],
        from source: LanguageCode,
        to target: LanguageCode,
        context: TranslationContext?,
    ) async throws -> [TranslationResult] {
        guard let binary = binaryPath else {
            throw TranslationError.providerError(
                provider: identifier,
                message: "OpenAI Codex CLI not found. Install with: npm i -g @openai/codex",
            )
        }

        let systemPrompt = promptBuilder.buildSystemPrompt(context: context, targetLanguage: target)
        let userPrompt = promptBuilder.buildUserPrompt(strings: strings, context: context, targetLanguage: target)
        let fullPrompt = "\(systemPrompt)\n\n---\n\n\(userPrompt)"

        // Execute codex CLI
        // Note: Codex uses different invocation depending on version
        let output = try await executeCommand(
            binary,
            arguments: [
                "--quiet",
                "--approval-mode", config.approvalMode.rawValue,
                fullPrompt,
            ],
        )

        return try promptBuilder.parseResponse(output, originalStrings: strings, provider: identifier)
    }

    // MARK: Private

    private let config: CodexCLIConfig
    private var binaryPath: String?
}

// MARK: - GenericCLIProvider

/// A generic CLI provider that can wrap any LLM CLI tool.
///
/// Use this for CLI tools not explicitly supported by SwiftLocalize.
///
/// ## Configuration
/// ```json
/// {
///   "providers": {
///     "custom-cli": {
///       "enabled": true,
///       "cliPath": "/path/to/my-llm-cli",
///       "cliArgs": ["--json", "--prompt"]
///     }
///   }
/// }
/// ```
public final class GenericCLIProvider: CLIProviderBase, TranslationProvider, @unchecked Sendable {
    // MARK: Lifecycle

    public init(config: GenericCLIConfig) {
        self.config = config
        identifier = config.identifier
        displayName = config.displayName
        super.init()
        binaryPath = findBinary(name: config.binaryPath, customPath: config.binaryPath)
    }

    // MARK: Public

    /// Configuration for a generic CLI provider.
    public struct GenericCLIConfig: Sendable {
        // MARK: Lifecycle

        public init(
            identifier: String,
            displayName: String,
            binaryPath: String,
            prePromptArgs: [String] = [],
            postPromptArgs: [String] = [],
            useStdin: Bool = false,
        ) {
            self.identifier = identifier
            self.displayName = displayName
            self.binaryPath = binaryPath
            self.prePromptArgs = prePromptArgs
            self.postPromptArgs = postPromptArgs
            self.useStdin = useStdin
        }

        // MARK: Public

        /// Unique identifier for this provider.
        public let identifier: String

        /// Display name for this provider.
        public let displayName: String

        /// Path to the CLI binary.
        public let binaryPath: String

        /// Arguments to pass before the prompt.
        public let prePromptArgs: [String]

        /// Arguments to pass after the prompt.
        public let postPromptArgs: [String]

        /// Whether to pass the prompt as stdin instead of argument.
        public let useStdin: Bool
    }

    public let identifier: String
    public let displayName: String

    public func isAvailable() async -> Bool {
        binaryPath != nil
    }

    public func supportedLanguages() async throws -> [LanguagePair] {
        []
    }

    public func translate(
        _ strings: [String],
        from source: LanguageCode,
        to target: LanguageCode,
        context: TranslationContext?,
    ) async throws -> [TranslationResult] {
        guard let binary = binaryPath else {
            throw TranslationError.providerError(
                provider: identifier,
                message: "CLI binary not found at: \(config.binaryPath)",
            )
        }

        let systemPrompt = promptBuilder.buildSystemPrompt(context: context, targetLanguage: target)
        let userPrompt = promptBuilder.buildUserPrompt(strings: strings, context: context, targetLanguage: target)
        let fullPrompt = "\(systemPrompt)\n\n---\n\n\(userPrompt)"

        var args = config.prePromptArgs
        if !config.useStdin {
            args.append(fullPrompt)
        }
        args.append(contentsOf: config.postPromptArgs)

        let output = try await executeCommand(
            binary,
            arguments: args,
            input: config.useStdin ? fullPrompt : nil,
        )

        return try promptBuilder.parseResponse(output, originalStrings: strings, provider: identifier)
    }

    // MARK: Private

    private let config: GenericCLIConfig
    private var binaryPath: String?
}
