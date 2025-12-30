//
//  AgentDefaults.swift
//  aizen
//
//  Created by Uladzislau Yakauleu on 17.10.25.
//

import Foundation

/// Default agent configurations
extension AgentRegistry {
    /// Base path for managed agent installations
    static let managedAgentsBasePath: String = {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return "\(home)/.aizen/agents"
    }()

    /// Get the managed executable path for a built-in agent
    /// Returns the path where the agent should be installed, regardless of whether it exists
    static func managedPath(for agentId: String) -> String {
        let basePath = managedAgentsBasePath
        switch agentId {
        case "claude":
            return "\(basePath)/claude/node_modules/.bin/claude-code-acp"
        case "codex":
            return "\(basePath)/codex/node_modules/.bin/codex-acp"
        case "gemini":
            return "\(basePath)/gemini/node_modules/.bin/gemini"
        case "kimi":
            return "\(basePath)/kimi/kimi"
        case "opencode":
            return "\(basePath)/opencode/node_modules/.bin/opencode"
        case "vibe":
            return "\(basePath)/vibe/vibe-acp"
        case "qwen":
            return "\(basePath)/qwen/node_modules/.bin/qwen"
        default:
            return "\(basePath)/\(agentId)/\(agentId)"
        }
    }

    /// Check if a built-in agent is installed at the managed path
    static func isInstalledAtManagedPath(_ agentId: String) -> Bool {
        let path = managedPath(for: agentId)
        return FileManager.default.isExecutableFile(atPath: path)
    }

    /// Discover an installed executable in the system PATH
    /// Returns the full path if found, otherwise nil
    private static func discoverExecutableInPath(_ executableName: String) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = [executableName]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) {
                return output.isEmpty ? nil : output
            }
        } catch {
            return nil
        }

        return nil
    }

    /// Initialize default built-in agents
    /// Tries to discover installed agents first, falls back to managed paths
    func initializeDefaultAgents() {
        var metadata = agentMetadata

        // Remove obsolete built-in agents that are no longer in our list
        metadata = metadata.filter { id, agent in
            if !agent.isBuiltIn {
                return true
            }
            return Self.builtInExecutableNames.keys.contains(id)
        }

        // Create or update default built-in agents
        // Try to discover installed executables first, then use managed paths
        updateBuiltInAgent("claude", in: &metadata) {
            let discoveredPath = Self.discoverExecutableInPath("claude-code-acp")
            let execPath = discoveredPath ?? Self.managedPath(for: "claude")
            return AgentMetadata(
                id: "claude",
                name: "Claude",
                description: "Agentic coding tool that understands your codebase",
                iconType: .builtin("claude"),
                isBuiltIn: true,
                isEnabled: true,
                executablePath: execPath,
                launchArgs: [],
                installMethod: .npm(package: "@zed-industries/claude-code-acp")
            )
        }

        updateBuiltInAgent("codex", in: &metadata) {
            let discoveredPath = Self.discoverExecutableInPath("codex-acp") 
                ?? Self.discoverExecutableInPath("codex")
            let execPath = discoveredPath ?? Self.managedPath(for: "codex")
            return AgentMetadata(
                id: "codex",
                name: "Codex",
                description: "Lightweight open-source coding agent by OpenAI",
                iconType: .builtin("openai"),
                isBuiltIn: true,
                isEnabled: true,
                executablePath: execPath,
                launchArgs: [],
                installMethod: .npm(package: "@zed-industries/codex-acp")
            )
        }

        updateBuiltInAgent("gemini", in: &metadata) {
            let discoveredPath = Self.discoverExecutableInPath("gemini")
            let execPath = discoveredPath ?? Self.managedPath(for: "gemini")
            return AgentMetadata(
                id: "gemini",
                name: "Gemini",
                description: "Open-source AI agent powered by Gemini models",
                iconType: .builtin("gemini"),
                isBuiltIn: true,
                isEnabled: true,
                executablePath: execPath,
                launchArgs: ["--experimental-acp"],
                installMethod: .npm(package: "@google/gemini-cli")
            )
        }

        updateBuiltInAgent("kimi", in: &metadata) {
            let discoveredPath = Self.discoverExecutableInPath("kimi")
            let execPath = discoveredPath ?? Self.managedPath(for: "kimi")
            return AgentMetadata(
                id: "kimi",
                name: "Kimi",
                description: "CLI agent powered by Kimi K2, a trillion-parameter MoE model",
                iconType: .builtin("kimi"),
                isBuiltIn: true,
                isEnabled: true,
                executablePath: execPath,
                launchArgs: ["--acp"],
                installMethod: .uv(package: "kimi-cli")
            )
        }

        updateBuiltInAgent("opencode", in: &metadata) {
            let discoveredPath = Self.discoverExecutableInPath("opencode")
            let execPath = discoveredPath ?? Self.managedPath(for: "opencode")
            return AgentMetadata(
                id: "opencode",
                name: "OpenCode",
                description: "Open-source coding agent with multi-session and LSP support",
                iconType: .builtin("opencode"),
                isBuiltIn: true,
                isEnabled: true,
                executablePath: execPath,
                launchArgs: ["acp"],
                installMethod: .npm(package: "opencode-ai@latest")
            )
        }

        updateBuiltInAgent("vibe", in: &metadata) {
            let discoveredPath = Self.discoverExecutableInPath("vibe-acp")
            let execPath = discoveredPath ?? Self.managedPath(for: "vibe")
            return AgentMetadata(
                id: "vibe",
                name: "Vibe",
                description: "Open-source coding assistant powered by Devstral",
                iconType: .builtin("vibe"),
                isBuiltIn: true,
                isEnabled: true,
                executablePath: execPath,
                launchArgs: [],
                installMethod: .uv(package: "mistral-vibe")
            )
        }

        updateBuiltInAgent("qwen", in: &metadata) {
            let discoveredPath = Self.discoverExecutableInPath("qwen")
            let execPath = discoveredPath ?? Self.managedPath(for: "qwen")
            return AgentMetadata(
                id: "qwen",
                name: "Qwen Code",
                description: "CLI tool for agentic coding, powered by Qwen3-Coder",
                iconType: .builtin("qwen"),
                isBuiltIn: true,
                isEnabled: true,
                executablePath: execPath,
                launchArgs: ["--experimental-acp"],
                installMethod: .npm(package: "@qwen-code/qwen-code")
            )
        }

        agentMetadata = metadata
    }

    /// Update a built-in agent, preserving user-configured executable path if valid
    /// Preserves user's enabled state and valid executable path
    private func updateBuiltInAgent(
        _ id: String,
        in metadata: inout [String: AgentMetadata],
        factory: () -> AgentMetadata
    ) {
        let template = factory()
        if var existing = metadata[id] {
            // Preserve enabled state and user-configured executable path if valid
            let userConfiguredPath = existing.executablePath
            let userConfiguredPathIsValid = userConfiguredPath != nil &&
                FileManager.default.fileExists(atPath: userConfiguredPath!) &&
                FileManager.default.isExecutableFile(atPath: userConfiguredPath!)

            // Only reset executable path to managed if user's path is invalid
            if !userConfiguredPathIsValid {
                existing.executablePath = template.executablePath
            }

            // Reset installMethod and launchArgs to match template
            existing.installMethod = template.installMethod
            existing.launchArgs = template.launchArgs
            metadata[id] = existing
        } else {
            metadata[id] = template
        }
    }
}
