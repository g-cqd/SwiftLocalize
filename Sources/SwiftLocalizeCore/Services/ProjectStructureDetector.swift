//
//  ProjectStructureDetector.swift
//  SwiftLocalize
//
//  Detects project structure and localization targets for multi-package support.

import Foundation

// MARK: - ProjectType

/// Type of project detected.
public enum ProjectType: String, Sendable, Codable, Equatable {
    case xcodeProject
    case swiftPackage
    case workspace
    case monorepo
    case unknown
}

// MARK: - TargetType

/// Type of localization target.
public enum TargetType: String, Sendable, Codable, Equatable {
    case mainApp
    case framework
    case swiftPackage
    case appExtension
    case widget
    case test
    case unknown
}

// MARK: - ProjectStructure

/// Represents the detected project structure.
public struct ProjectStructure: Sendable, Equatable {
    // MARK: Lifecycle

    public init(
        type: ProjectType,
        rootURL: URL,
        targets: [LocalizationTarget],
        packages: [PackageInfo] = [],
    ) {
        self.type = type
        self.rootURL = rootURL
        self.targets = targets
        self.packages = packages
    }

    // MARK: Public

    /// The type of project.
    public let type: ProjectType

    /// Root URL of the project.
    public let rootURL: URL

    /// All detected localization targets.
    public let targets: [LocalizationTarget]

    /// All detected packages (for monorepos).
    public let packages: [PackageInfo]
}

// MARK: - LocalizationTarget

/// A target containing localization files.
public struct LocalizationTarget: Sendable, Equatable {
    // MARK: Lifecycle

    public init(
        name: String,
        type: TargetType,
        xcstringsURL: URL,
        bundleIdentifier: String? = nil,
        defaultLocalization: String = "en",
        parentPackage: String? = nil,
    ) {
        self.name = name
        self.type = type
        self.xcstringsURL = xcstringsURL
        self.bundleIdentifier = bundleIdentifier
        self.defaultLocalization = defaultLocalization
        self.parentPackage = parentPackage
    }

    // MARK: Public

    /// Target name.
    public let name: String

    /// Type of target.
    public let type: TargetType

    /// URL to the xcstrings file.
    public let xcstringsURL: URL

    /// Bundle identifier if available.
    public let bundleIdentifier: String?

    /// Default localization language.
    public let defaultLocalization: String

    /// Parent package name for SPM targets.
    public let parentPackage: String?

    /// Relative path from project root.
    public var relativePath: String {
        xcstringsURL.path
    }
}

// MARK: - PackageInfo

/// Information about a Swift package.
public struct PackageInfo: Sendable, Equatable {
    // MARK: Lifecycle

    public init(
        name: String,
        url: URL,
        isLocal: Bool = true,
        localizationTargets: [String] = [],
    ) {
        self.name = name
        self.url = url
        self.isLocal = isLocal
        self.localizationTargets = localizationTargets
    }

    // MARK: Public

    /// Package name.
    public let name: String

    /// Package root URL.
    public let url: URL

    /// Whether this is a local package.
    public let isLocal: Bool

    /// Localization targets in this package.
    public let localizationTargets: [String]
}

// MARK: - ProjectStructureDetector

/// Detects project layout and localization targets.
///
/// Supports:
/// - Xcode projects (.xcodeproj)
/// - Swift packages (Package.swift)
/// - Workspaces (.xcworkspace)
/// - Monorepos with multiple packages
///
/// ## Usage
/// ```swift
/// let detector = ProjectStructureDetector()
/// let structure = try await detector.detect(at: projectRoot)
///
/// for target in structure.targets {
///     print("\(target.name): \(target.xcstringsURL)")
/// }
/// ```
public actor ProjectStructureDetector {
    // MARK: Lifecycle

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    // MARK: Public

    // MARK: - Detection

    /// Detect project structure at the given root URL.
    ///
    /// - Parameter rootURL: The project root directory.
    /// - Returns: The detected project structure.
    public func detect(at rootURL: URL) async throws -> ProjectStructure {
        let type = detectProjectType(at: rootURL)
        var targets: [LocalizationTarget] = []
        var packages: [PackageInfo] = []

        switch type {
        case .swiftPackage:
            let (pkgTargets, pkgInfo) = try await detectSwiftPackage(at: rootURL)
            targets = pkgTargets
            if let info = pkgInfo {
                packages = [info]
            }

        case .xcodeProject:
            targets = try await detectXcodeProject(at: rootURL)

        case .workspace:
            let (wsTargets, wsPackages) = try await detectWorkspace(at: rootURL)
            targets = wsTargets
            packages = wsPackages

        case .monorepo:
            let (monoTargets, monoPackages) = try await detectMonorepo(at: rootURL)
            targets = monoTargets
            packages = monoPackages

        case .unknown:
            // Fall back to finding all xcstrings files
            targets = try await findAllLocalizationFiles(at: rootURL)
        }

        return ProjectStructure(
            type: type,
            rootURL: rootURL,
            targets: targets,
            packages: packages,
        )
    }

    /// Find all xcstrings files and their targets.
    public func findLocalizationFiles(in project: ProjectStructure) async throws -> [LocalizationTarget] {
        project.targets
    }

    // MARK: Private

    private let fileManager: FileManager

    // MARK: - Project Type Detection

    private func detectProjectType(at url: URL) -> ProjectType {
        // Check for workspace first (highest priority)
        if hasWorkspace(at: url) {
            return .workspace
        }

        // Check for Xcode project
        if hasXcodeProject(at: url) {
            return .xcodeProject
        }

        // Check for Swift package
        if hasPackageSwift(at: url) {
            // Could be a monorepo if it has nested packages
            if hasNestedPackages(at: url) {
                return .monorepo
            }
            return .swiftPackage
        }

        // Check for monorepo structure (Packages/ or LocalPackages/ directory)
        if hasPackagesDirectory(at: url) {
            return .monorepo
        }

        return .unknown
    }

    private func hasWorkspace(at url: URL) -> Bool {
        do {
            let contents = try fileManager.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)
            return contents.contains { $0.pathExtension == "xcworkspace" }
        } catch {
            return false
        }
    }

    private func hasXcodeProject(at url: URL) -> Bool {
        do {
            let contents = try fileManager.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)
            return contents.contains { $0.pathExtension == "xcodeproj" }
        } catch {
            return false
        }
    }

    private func hasPackageSwift(at url: URL) -> Bool {
        let packageURL = url.appendingPathComponent("Package.swift")
        return fileManager.fileExists(atPath: packageURL.path)
    }

    private func hasNestedPackages(at url: URL) -> Bool {
        let packagesDir = url.appendingPathComponent("Packages")
        let localPackagesDir = url.appendingPathComponent("LocalPackages")
        return fileManager.fileExists(atPath: packagesDir.path) ||
            fileManager.fileExists(atPath: localPackagesDir.path)
    }

    private func hasPackagesDirectory(at url: URL) -> Bool {
        hasNestedPackages(at: url)
    }

    // MARK: - Swift Package Detection

    private func detectSwiftPackage(at url: URL) async throws -> ([LocalizationTarget], PackageInfo?) {
        var targets: [LocalizationTarget] = []
        let packageName = extractPackageName(at: url) ?? url.lastPathComponent
        let defaultLocalization = extractDefaultLocalization(at: url)

        // Find xcstrings in Sources/
        let sourcesURL = url.appendingPathComponent("Sources")
        if fileManager.fileExists(atPath: sourcesURL.path) {
            let sourceTargets = try await findTargetsInSources(
                at: sourcesURL,
                parentPackage: packageName,
                defaultLocalization: defaultLocalization,
            )
            targets.append(contentsOf: sourceTargets)
        }

        let packageInfo = PackageInfo(
            name: packageName,
            url: url,
            isLocal: true,
            localizationTargets: targets.map(\.name),
        )

        return (targets, packageInfo)
    }

    private func findTargetsInSources(
        at sourcesURL: URL,
        parentPackage: String,
        defaultLocalization: String,
    ) async throws -> [LocalizationTarget] {
        var targets: [LocalizationTarget] = []

        guard let sourceContents = try? fileManager.contentsOfDirectory(
            at: sourcesURL,
            includingPropertiesForKeys: [.isDirectoryKey],
        ) else {
            return targets
        }

        for item in sourceContents {
            var isDir: ObjCBool = false
            guard fileManager.fileExists(atPath: item.path, isDirectory: &isDir),
                  isDir.boolValue else { continue }

            let targetName = item.lastPathComponent

            // Look for xcstrings files
            let xcstringsFiles = try findXCStringsFiles(in: item)
            for xcstringsURL in xcstringsFiles {
                let target = LocalizationTarget(
                    name: targetName,
                    type: .swiftPackage,
                    xcstringsURL: xcstringsURL,
                    defaultLocalization: defaultLocalization,
                    parentPackage: parentPackage,
                )
                targets.append(target)
            }
        }

        return targets
    }

    // MARK: - Xcode Project Detection

    private func detectXcodeProject(at url: URL) async throws -> [LocalizationTarget] {
        var targets: [LocalizationTarget] = []

        // Find the .xcodeproj
        guard let contents = try? fileManager.contentsOfDirectory(at: url, includingPropertiesForKeys: nil),
              let projectURL = contents.first(where: { $0.pathExtension == "xcodeproj" })
        else {
            return targets
        }

        let projectName = projectURL.deletingPathExtension().lastPathComponent

        // Scan common locations for xcstrings
        let possibleDirs = [
            url.appendingPathComponent(projectName),
            url.appendingPathComponent("Sources"),
            url.appendingPathComponent("Source"),
            url,
        ]

        for dir in possibleDirs where fileManager.fileExists(atPath: dir.path) {
            let xcstringsFiles = try findXCStringsFiles(in: dir)
            for xcstringsURL in xcstringsFiles {
                let targetName = inferTargetName(from: xcstringsURL, projectName: projectName)
                let targetType = inferTargetType(from: xcstringsURL, projectName: projectName)

                let target = LocalizationTarget(
                    name: targetName,
                    type: targetType,
                    xcstringsURL: xcstringsURL,
                    defaultLocalization: "en",
                )
                targets.append(target)
            }
        }

        // Remove duplicates by URL
        return targets.reduce(into: []) { result, target in
            if !result.contains(where: { $0.xcstringsURL == target.xcstringsURL }) {
                result.append(target)
            }
        }
    }

    // MARK: - Workspace Detection

    private func detectWorkspace(at url: URL) async throws -> ([LocalizationTarget], [PackageInfo]) {
        var allTargets: [LocalizationTarget] = []
        var allPackages: [PackageInfo] = []

        // Scan the root for projects and packages
        guard let contents = try? fileManager.contentsOfDirectory(at: url, includingPropertiesForKeys: nil) else {
            return ([], [])
        }

        for item in contents {
            if item.pathExtension == "xcodeproj" {
                let projectDir = url.appendingPathComponent(item.deletingPathExtension().lastPathComponent)
                if fileManager.fileExists(atPath: projectDir.path) {
                    let projectTargets = try await detectXcodeProject(at: url)
                    allTargets.append(contentsOf: projectTargets)
                }
            }

            if item.lastPathComponent == "Package.swift" {
                let (pkgTargets, pkgInfo) = try await detectSwiftPackage(at: url)
                allTargets.append(contentsOf: pkgTargets)
                if let info = pkgInfo {
                    allPackages.append(info)
                }
            }
        }

        // Check for nested packages
        let (monoTargets, monoPackages) = try await detectMonorepo(at: url)
        allTargets.append(contentsOf: monoTargets)
        allPackages.append(contentsOf: monoPackages)

        return (allTargets, allPackages)
    }

    // MARK: - Monorepo Detection

    private func detectMonorepo(at url: URL) async throws -> ([LocalizationTarget], [PackageInfo]) {
        var allTargets: [LocalizationTarget] = []
        var allPackages: [PackageInfo] = []

        // Look in Packages/ and LocalPackages/
        let packageDirs = ["Packages", "LocalPackages"]

        for dirName in packageDirs {
            let packagesURL = url.appendingPathComponent(dirName)
            guard fileManager.fileExists(atPath: packagesURL.path) else { continue }

            guard let contents = try? fileManager.contentsOfDirectory(
                at: packagesURL,
                includingPropertiesForKeys: [.isDirectoryKey],
            ) else { continue }

            for item in contents {
                var isDir: ObjCBool = false
                guard fileManager.fileExists(atPath: item.path, isDirectory: &isDir),
                      isDir.boolValue else { continue }

                // Check if this is a package
                if hasPackageSwift(at: item) {
                    let (pkgTargets, pkgInfo) = try await detectSwiftPackage(at: item)
                    allTargets.append(contentsOf: pkgTargets)
                    if let info = pkgInfo {
                        allPackages.append(info)
                    }
                }
            }
        }

        return (allTargets, allPackages)
    }

    // MARK: - Fallback Detection

    private func findAllLocalizationFiles(at url: URL) async throws -> [LocalizationTarget] {
        let xcstringsFiles = try findXCStringsFiles(in: url, recursive: true)

        return xcstringsFiles.map { xcstringsURL in
            let targetName = xcstringsURL.deletingLastPathComponent().lastPathComponent
            return LocalizationTarget(
                name: targetName,
                type: .unknown,
                xcstringsURL: xcstringsURL,
                defaultLocalization: "en",
            )
        }
    }

    // MARK: - File Search

    private func findXCStringsFiles(in directory: URL, recursive: Bool = false) throws -> [URL] {
        var results: [URL] = []

        let enumerator = fileManager.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: recursive ? [] : [.skipsSubdirectoryDescendants],
        )

        while let url = enumerator?.nextObject() as? URL {
            if url.pathExtension == "xcstrings" {
                results.append(url)
            }
            // Skip hidden directories and build directories
            if url.lastPathComponent.hasPrefix(".") ||
                url.lastPathComponent == "Build" ||
                url.lastPathComponent == ".build" ||
                url.lastPathComponent == "DerivedData"
            {
                enumerator?.skipDescendants()
            }
        }

        return results
    }

    // MARK: - Helpers

    private func extractPackageName(at url: URL) -> String? {
        let packageURL = url.appendingPathComponent("Package.swift")
        guard let content = try? String(contentsOf: packageURL, encoding: .utf8) else {
            return nil
        }

        // Simple regex to extract package name from: name: "PackageName"
        let pattern = #"name:\s*"([^"]+)""#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(
                  in: content,
                  range: NSRange(content.startIndex..., in: content),
              ),
              let nameRange = Range(match.range(at: 1), in: content)
        else {
            return nil
        }

        return String(content[nameRange])
    }

    private func extractDefaultLocalization(at url: URL) -> String {
        let packageURL = url.appendingPathComponent("Package.swift")
        guard let content = try? String(contentsOf: packageURL, encoding: .utf8) else {
            return "en"
        }

        // Look for defaultLocalization: "xx"
        let pattern = #"defaultLocalization:\s*"([^"]+)""#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(
                  in: content,
                  range: NSRange(content.startIndex..., in: content),
              ),
              let langRange = Range(match.range(at: 1), in: content)
        else {
            return "en"
        }

        return String(content[langRange])
    }

    private func inferTargetName(from xcstringsURL: URL, projectName: String) -> String {
        let pathComponents = xcstringsURL.pathComponents

        // Look for known target directory patterns
        for (index, component) in pathComponents.enumerated() {
            // After Sources/ or the project name directory
            if component == "Sources" || component == projectName,
               index + 1 < pathComponents.count
            {
                return pathComponents[index + 1]
            }
        }

        // Fall back to parent directory
        return xcstringsURL.deletingLastPathComponent().lastPathComponent
    }

    private func inferTargetType(from xcstringsURL: URL, projectName: String) -> TargetType {
        let path = xcstringsURL.path.lowercased()

        if path.contains("test") {
            return .test
        }
        if path.contains("widget") {
            return .widget
        }
        if path.contains("extension") || path.contains("intent") {
            return .appExtension
        }
        if path.contains("kit") || path.contains("framework") {
            return .framework
        }

        let targetName = inferTargetName(from: xcstringsURL, projectName: projectName)
        if targetName == projectName {
            return .mainApp
        }

        return .unknown
    }
}

// MARK: - ProjectDiscoveryReport

/// Report from project structure detection.
public struct ProjectDiscoveryReport: Sendable {
    // MARK: Lifecycle

    public init(structure: ProjectStructure, warnings: [String] = []) {
        self.structure = structure
        self.warnings = warnings
    }

    // MARK: Public

    /// The detected project structure.
    public let structure: ProjectStructure

    /// Warnings encountered during detection.
    public let warnings: [String]

    /// Summary statistics.
    public var summary: String {
        """
        Project Type: \(structure.type.rawValue)
        Targets: \(structure.targets.count)
        Packages: \(structure.packages.count)
        """
    }
}
