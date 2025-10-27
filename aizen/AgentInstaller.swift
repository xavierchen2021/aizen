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

    func installAgent(_ agentName: String) async throws {
        let agentDir = (baseInstallPath as NSString).appendingPathComponent(agentName)

        // Create directory if needed
        try createDirectoryIfNeeded(agentDir)

        switch agentName {
        case "claude":
            try await installNpmAgent(
                name: "claude",
                package: "@zed-industries/claude-code-acp",
                targetDir: agentDir
            )
        case "codex":
            try await installCodexBinary(targetDir: agentDir)
        case "gemini":
            try await installNpmAgent(
                name: "gemini",
                package: "@google/gemini-cli",
                targetDir: agentDir
            )
        default:
            throw AgentInstallError.installFailed(message: "Unknown agent: \(agentName)")
        }

        // Register the installed path
        let executablePath = getAgentExecutablePath(agentName)
        AgentRegistry.shared.setAgentPath(executablePath, for: agentName)
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

    // MARK: - Codex Binary Installation

    private func installCodexBinary(targetDir: String) async throws {
        // Determine architecture
        let arch = getArchitecture()
        let version = "v0.1.6"
        let filename = "codex-acp-\(version)-\(arch)-apple-darwin.tar.gz"
        let downloadURL = "https://github.com/cola-io/codex-acp/releases/download/\(version)/\(filename)"

        // Download
        guard let url = URL(string: downloadURL) else {
            throw AgentInstallError.downloadFailed(message: "Invalid URL")
        }

        let (tempFileURL, _) = try await URLSession.shared.download(from: url)

        // Extract
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

        // Make executable
        let executablePath = (targetDir as NSString).appendingPathComponent("codex-acp")
        let attributes = [FileAttributeKey.posixPermissions: 0o755]
        try FileManager.default.setAttributes(attributes, ofItemAtPath: executablePath)
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
