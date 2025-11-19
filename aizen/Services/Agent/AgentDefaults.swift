//
//  AgentDefaults.swift
//  aizen
//
//  Created by Uladzislau Yakauleu on 17.10.25.
//

import Foundation

/// Default agent configurations
extension AgentRegistry {
    /// Initialize default built-in agents with discovery
    func initializeDefaultAgents() {
        // Get existing metadata
        var metadata = agentMetadata

        // Try to discover agent paths
        let discovered = discoverAgents()

        // Remove obsolete built-in agents that are no longer in our list
        metadata = metadata.filter { id, agent in
            // Keep custom agents (not built-in)
            if !agent.isBuiltIn {
                return true
            }
            // Keep built-in agents that are in builtInExecutableNames
            return Self.builtInExecutableNames.keys.contains(id)
        }

        // Create or update default built-in agents
        // Only add if not already present to preserve user settings

        addAgentIfMissing("claude", to: &metadata, discovered: discovered) {
            AgentMetadata(
                id: "claude",
                name: "Claude",
                description: "Anthropic's AI assistant with advanced coding capabilities",
                iconType: .builtin("claude"),
                isBuiltIn: true,
                isEnabled: true,
                executablePath: discovered["claude"],
                launchArgs: [],
                installMethod: .npm(package: "@zed-industries/claude-code-acp")
            )
        }

        addAgentIfMissing("codex", to: &metadata, discovered: discovered) {
            AgentMetadata(
                id: "codex",
                name: "Codex",
                description: "OpenAI's code generation model",
                iconType: .builtin("openai"),
                isBuiltIn: true,
                isEnabled: true,
                executablePath: discovered["codex"],
                launchArgs: [],
                installMethod: .npm(package: "@zed-industries/codex-acp")
            )
        }

        addAgentIfMissing("gemini", to: &metadata, discovered: discovered) {
            AgentMetadata(
                id: "gemini",
                name: "Gemini",
                description: "Google's multimodal AI model",
                iconType: .builtin("gemini"),
                isBuiltIn: true,
                isEnabled: true,
                executablePath: discovered["gemini"],
                launchArgs: ["--experimental-acp"],
                installMethod: .npm(package: "@google/gemini-cli")
            )
        }

        addAgentIfMissing("kimi", to: &metadata, discovered: discovered) {
            AgentMetadata(
                id: "kimi",
                name: "Kimi",
                description: "Moonshot AI assistant",
                iconType: .builtin("kimi"),
                isBuiltIn: true,
                isEnabled: true,
                executablePath: discovered["kimi"],
                launchArgs: ["--acp"],
                installMethod: .githubRelease(
                    repo: "MoonshotAI/kimi-cli",
                    assetPattern: "kimi-{version}-{arch}-apple-darwin.tar.gz"
                )
            )
        }

        addAgentIfMissing("opencode", to: &metadata, discovered: discovered) {
            AgentMetadata(
                id: "opencode",
                name: "OpenCode",
                description: "OpenCode AI assistant",
                iconType: .builtin("opencode"),
                isBuiltIn: true,
                isEnabled: true,
                executablePath: discovered["opencode"],
                launchArgs: ["acp"],
                installMethod: .npm(package: "opencode-ai@latest")
            )
        }

        agentMetadata = metadata
    }

    /// Helper to add agent if not already present, preserving user settings
    func addAgentIfMissing(
        _ id: String,
        to metadata: inout [String: AgentMetadata],
        discovered: [String: String],
        factory: () -> AgentMetadata
    ) {
        if metadata[id] == nil {
            metadata[id] = factory()
        } else if var existing = metadata[id], existing.isBuiltIn {
            // Update install method for built-in agents to fix outdated configurations
            let template = factory()
            existing.installMethod = template.installMethod
            metadata[id] = existing
        }
    }
}
