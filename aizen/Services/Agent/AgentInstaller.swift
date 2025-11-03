//
//  AgentInstaller.swift
//  aizen
//
//  Agent installation manager for downloading and setting up ACP agents
//

import Foundation

enum AgentInstallError: LocalizedError {
    case downloadFailed(message: String)
    case installFailed(message: String)
    case unsupportedPlatform
    case invalidResponse
    case fileSystemError(message: String)

    var errorDescription: String? {
        switch self {
        case .downloadFailed(let message):
            return "Download failed: \(message)"
        case .installFailed(let message):
            return "Installation failed: \(message)"
        case .unsupportedPlatform:
            return "Unsupported platform"
        case .invalidResponse:
            return "Invalid server response"
        case .fileSystemError(let message):
            return "File system error: \(message)"
        }
    }
}

actor AgentInstaller {
    static let shared = AgentInstaller()

    private let baseInstallPath: String

    private init() {
        let homeDir = FileManager.default.homeDirectoryForCurrentUser
        baseInstallPath = homeDir.appendingPathComponent(".aizen/agents").path
    }

    // MARK: - Installation Status

    func canInstall(_ metadata: AgentRegistry.AgentMetadata) -> Bool {
        return metadata.installMethod != nil
    }

    func isInstalled(_ agentName: String) -> Bool {
        let agentPath = getAgentExecutablePath(agentName)
        return FileManager.default.fileExists(atPath: agentPath) &&
               FileManager.default.isExecutableFile(atPath: agentPath)
    }

    func getAgentExecutablePath(_ agentName: String) -> String {
        let agentDir = (baseInstallPath as NSString).appendingPathComponent(agentName)

        switch agentName {
        case "claude":
            return (agentDir as NSString).appendingPathComponent("node_modules/.bin/claude-code-acp")
        case "codex":
            return (agentDir as NSString).appendingPathComponent("codex-acp")
        case "gemini":
            return (agentDir as NSString).appendingPathComponent("node_modules/.bin/gemini")
        default:
            return ""
        }
    }

    // MARK: - Installation

    func installAgent(_ metadata: AgentRegistry.AgentMetadata) async throws {
        guard let installMethod = metadata.installMethod else {
            throw AgentInstallError.installFailed(message: "Agent '\(metadata.name)' has no installation method")
        }

        let agentDir = (baseInstallPath as NSString).appendingPathComponent(metadata.id)

        // Create directory if needed
        try createDirectoryIfNeeded(agentDir)

        switch installMethod {
        case .npm(let package):
            try await installNpmAgent(
                name: metadata.id,
                package: package,
                targetDir: agentDir
            )
        case .binary(let urlString):
            // Replace {arch} placeholder
            let arch = getArchitecture()
            let resolvedURL = urlString.replacingOccurrences(of: "{arch}", with: arch)
            try await installBinaryFromURL(
                url: resolvedURL,
                agentId: metadata.id,
                targetDir: agentDir
            )
        }

        // Register the installed path
        let executablePath = getAgentExecutablePath(metadata.id)
        AgentRegistry.shared.setAgentPath(executablePath, for: metadata.id)
    }

    // Legacy method for backwards compatibility
    func installAgent(_ agentName: String) async throws {
        guard let metadata = AgentRegistry.shared.getMetadata(for: agentName) else {
            throw AgentInstallError.installFailed(message: "Unknown agent: \(agentName)")
        }

        try await installAgent(metadata)
    }

    // MARK: - NPM Installation

    private func installNpmAgent(name: String, package: String, targetDir: String) async throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["npm", "install", "--prefix", targetDir, package]

        // Load shell environment to get PATH with npm
        process.environment = loadShellEnvironment()

        let pipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = pipe
        process.standardError = errorPipe

        try process.run()
        process.waitUntilExit()

        if process.terminationStatus != 0 {
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let errorMessage = String(data: errorData, encoding: .utf8) ?? "Unknown error"
            throw AgentInstallError.installFailed(message: errorMessage)
        }
    }

    private func loadShellEnvironment() -> [String: String] {
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        let shellName = (shell as NSString).lastPathComponent

        let process = Process()
        process.executableURL = URL(fileURLWithPath: shell)

        // Use login shell to load profile
        let arguments: [String]
        switch shellName {
        case "fish":
            arguments = ["-l", "-c", "env"]
        case "zsh", "bash", "sh":
            arguments = ["-l", "-c", "env"]
        default:
            arguments = ["-c", "env"]
        }

        process.arguments = arguments

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        var shellEnv: [String: String] = [:]

        do {
            try process.run()
            process.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let output = String(data: data, encoding: .utf8) {
                for line in output.split(separator: "\n") {
                    if let equalsIndex = line.firstIndex(of: "=") {
                        let key = String(line[..<equalsIndex])
                        let value = String(line[line.index(after: equalsIndex)...])
                        shellEnv[key] = value
                    }
                }
            }
        } catch {
            // Fallback to basic environment
            return ProcessInfo.processInfo.environment
        }

        return shellEnv.isEmpty ? ProcessInfo.processInfo.environment : shellEnv
    }

    // MARK: - Binary Installation

    private func installBinaryFromURL(url: String, agentId: String, targetDir: String) async throws {
        guard let downloadURL = URL(string: url) else {
            throw AgentInstallError.downloadFailed(message: "Invalid URL: \(url)")
        }

        // Download
        let (tempFileURL, _) = try await URLSession.shared.download(from: downloadURL)

        // Determine if it's a tarball
        let isTarball = url.hasSuffix(".tar.gz") || url.hasSuffix(".tgz")

        if isTarball {
            // Extract tarball
            let filename = (url as NSString).lastPathComponent
            let tarPath = (targetDir as NSString).appendingPathComponent(filename)
            try FileManager.default.copyItem(at: tempFileURL, to: URL(fileURLWithPath: tarPath))

            // Untar
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
            process.arguments = ["-xzf", filename, "-C", targetDir]
            process.currentDirectoryURL = URL(fileURLWithPath: targetDir)

            let errorPipe = Pipe()
            process.standardError = errorPipe

            try process.run()
            process.waitUntilExit()

            // Clean up tar file
            try? FileManager.default.removeItem(atPath: tarPath)

            if process.terminationStatus != 0 {
                let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                let errorMessage = String(data: errorData, encoding: .utf8) ?? "Unknown error"
                throw AgentInstallError.installFailed(message: "Extraction failed: \(errorMessage)")
            }

            // Find and make executable
            let executablePath = findExecutableInDirectory(targetDir, preferredName: agentId)
            if let execPath = executablePath {
                let attributes = [FileAttributeKey.posixPermissions: 0o755]
                try FileManager.default.setAttributes(attributes, ofItemAtPath: execPath)
            }
        } else {
            // Direct binary
            let executablePath = (targetDir as NSString).appendingPathComponent(agentId)
            try FileManager.default.copyItem(at: tempFileURL, to: URL(fileURLWithPath: executablePath))

            // Make executable
            let attributes = [FileAttributeKey.posixPermissions: 0o755]
            try FileManager.default.setAttributes(attributes, ofItemAtPath: executablePath)
        }
    }

    private func findExecutableInDirectory(_ directory: String, preferredName: String) -> String? {
        let fileManager = FileManager.default

        guard let contents = try? fileManager.contentsOfDirectory(atPath: directory) else {
            return nil
        }

        // Look for preferred name first
        let preferredPath = (directory as NSString).appendingPathComponent(preferredName)
        if fileManager.fileExists(atPath: preferredPath) {
            return preferredPath
        }

        // Look for any executable file
        for item in contents {
            let itemPath = (directory as NSString).appendingPathComponent(item)
            var isDirectory: ObjCBool = false
            if fileManager.fileExists(atPath: itemPath, isDirectory: &isDirectory) {
                if !isDirectory.boolValue && fileManager.isExecutableFile(atPath: itemPath) {
                    return itemPath
                }
            }
        }

        return nil
    }

    private func getArchitecture() -> String {
        #if arch(arm64)
        return "aarch64"
        #elseif arch(x86_64)
        return "x86_64"
        #else
        return "unknown"
        #endif
    }

    // MARK: - Uninstallation

    func uninstallAgent(_ agentName: String) async throws {
        let agentDir = (baseInstallPath as NSString).appendingPathComponent(agentName)

        if FileManager.default.fileExists(atPath: agentDir) {
            try FileManager.default.removeItem(atPath: agentDir)
        }

        AgentRegistry.shared.removeAgent(named: agentName)
    }

    // MARK: - Helpers

    private func createDirectoryIfNeeded(_ path: String) throws {
        let fileManager = FileManager.default
        if !fileManager.fileExists(atPath: path) {
            try fileManager.createDirectory(
                atPath: path,
                withIntermediateDirectories: true,
                attributes: nil
            )
        }
    }
}
