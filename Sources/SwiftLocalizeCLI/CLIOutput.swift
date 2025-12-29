//
//  CLIOutput.swift
//  SwiftLocalize
//

import Foundation

// MARK: - CLIOutput

enum CLIOutput {
    static func printError(_ message: String) {
        fputs("Error: \(message)\n", stderr)
    }

    static func printWarning(_ message: String) {
        fputs("Warning: \(message)\n", stderr)
    }
}
