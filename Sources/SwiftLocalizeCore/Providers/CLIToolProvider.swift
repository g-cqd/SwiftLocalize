//
//  CLIToolProvider.swift
//  SwiftLocalize
//

import Foundation

// MARK: - CLI Tool Provider

/// Translation provider that wraps external CLI tools.
///
/// This provider allows using CLI tools like `gemini`, `copilot`, or custom scripts
/// for translation. The tool receives the translation prompt via stdin and returns
/// the translation result via stdout.
public final class CLIToolProvider: TranslationProvider, @unchecked Sendable {
    // MARK: Lifecycle

    public init(config: CLIToolProviderConfig) {
        self.config = config
        identifier = config.identifier
        displayName = config.displayName
        promptBuilder = TranslationPromptBuilder()
    }

    // MARK: Public

    /// Configuration for the CLI tool provider.
    public struct CLIToolProviderConfig: Sendable {
        // MARK: Lifecycle

        public init(
            identifier: String,
            displayName: String,
            toolPath: String,
            arguments: [String] = [],
            environment: [String: String] = [:],
            timeout: TimeInterval = 120,
            usesStdin: Bool = true,
            autoConfirm: Bool = true,
        ) {
            self.identifier = identifier
            self.displayName = displayName
            self.toolPath = toolPath
            self.arguments = arguments
            self.environment = environment
            self.timeout = timeout
            self.usesStdin = usesStdin
            self.autoConfirm = autoConfirm
        }

        // MARK: Public

        /// Provider identifier.
        public let identifier: String

        /// Display name.
        public let displayName: String

        /// Path to the CLI tool.
        public let toolPath: String

        /// Additional arguments to pass to the tool.
        public let arguments: [String]

        /// Environment variables to set.
        public let environment: [String: String]

        /// Timeout for tool execution in seconds.
        public let timeout: TimeInterval

        /// Whether the tool accepts input via stdin.
        public let usesStdin: Bool

        /// Whether to automatically confirm prompts (e.g., -y flag).
        public let autoConfirm: Bool

        /// Create config for the Gemini CLI tool.
        public static func geminiCLI(
            path: String = "/opt/homebrew/bin/gemini",
            arguments: [String] = ["-y"],
        ) -> CLIToolProviderConfig {
            CLIToolProviderConfig(
                identifier: "cli-gemini",
                displayName: "Gemini CLI",
                toolPath: path,
                arguments: arguments,
            )
        }

        /// Create config for GitHub Copilot CLI.
        public static func copilotCLI(
            path: String = "/usr/local/bin/gh",
            arguments: [String] = ["copilot", "suggest"],
        ) -> CLIToolProviderConfig {
            CLIToolProviderConfig(
                identifier: "cli-copilot",
                displayName: "GitHub Copilot CLI",
                toolPath: path,
                arguments: arguments,
            )
        }

        /// Create config from provider configuration.
        public static func from(
            providerConfig: ProviderConfig?,
            providerName: ProviderName,
        ) -> CLIToolProviderConfig? {
            guard let path = providerConfig?.path else { return nil }

            let identifier = providerName.rawValue
            let displayName = switch providerName {
            case .cliGemini: "Gemini CLI"
            case .cliCopilot: "GitHub Copilot CLI"
            default: "CLI Tool"
            }

            return CLIToolProviderConfig(
                identifier: identifier,
                displayName: displayName,
                toolPath: path,
                arguments: providerConfig?.args ?? [],
            )
        }
    }

    public let identifier: String
    public let displayName: String

    // MARK: - TranslationProvider

    public func isAvailable() async -> Bool {
        FileManager.default.isExecutableFile(atPath: config.toolPath)
    }

    public func supportedLanguages() async throws -> [LanguagePair] {
        // CLI tools typically support all language pairs through LLM
        []
    }

    public func translate(
        _ strings: [String],
        from source: LanguageCode,
        to target: LanguageCode,
        context: TranslationContext?,
    ) async throws -> [TranslationResult] {
        guard !strings.isEmpty else { return [] }

        let systemPrompt = promptBuilder.buildSystemPrompt(
            context: context,
            targetLanguage: target,
        )
        let userPrompt = promptBuilder.buildUserPrompt(
            strings: strings,
            context: context,
            targetLanguage: target,
        )

        let fullPrompt = """
        \(systemPrompt)

        ---

        \(userPrompt)
        """

        let output = try await runCLITool(with: fullPrompt)

        return try promptBuilder.parseResponse(
            output,
            originalStrings: strings,
            provider: identifier,
        )
    }

    // MARK: Private

    private let config: CLIToolProviderConfig
    private let promptBuilder: TranslationPromptBuilder

    // MARK: - CLI Execution

    private func runCLITool(with input: String) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: config.toolPath)
            process.arguments = config.arguments

            // Set up environment
            var env = ProcessInfo.processInfo.environment
            for (key, value) in config.environment {
                env[key] = value
            }
            process.environment = env

            let inputPipe = Pipe()
            let outputPipe = Pipe()
            let errorPipe = Pipe()

            process.standardInput = inputPipe
            process.standardOutput = outputPipe
            process.standardError = errorPipe

            // Write input to stdin
            if config.usesStdin {
                let inputData = Data(input.utf8)
                inputPipe.fileHandleForWriting.write(inputData)
                inputPipe.fileHandleForWriting.closeFile()
            }

            // Set up timeout
            let timeoutTask = Task {
                try await Task.sleep(for: .seconds(config.timeout))
                if process.isRunning {
                    process.terminate()
                }
            }

            do {
                try process.run()
                process.waitUntilExit()
                timeoutTask.cancel()

                let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
                let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()

                if process.terminationStatus != 0 {
                    let errorMessage = String(data: errorData, encoding: .utf8) ?? "Unknown error"
                    continuation.resume(throwing: TranslationError.providerError(
                        provider: identifier,
                        message: "CLI tool failed with exit code \(process.terminationStatus): \(errorMessage)",
                    ))
                    return
                }

                guard let output = String(data: outputData, encoding: .utf8) else {
                    continuation.resume(throwing: TranslationError.invalidResponse(
                        "CLI tool output is not valid UTF-8",
                    ))
                    return
                }

                continuation.resume(returning: output)
            } catch {
                timeoutTask.cancel()
                continuation.resume(throwing: TranslationError.providerError(
                    provider: identifier,
                    message: "Failed to run CLI tool: \(error.localizedDescription)",
                ))
            }
        }
    }
}
