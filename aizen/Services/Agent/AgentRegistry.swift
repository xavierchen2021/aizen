//
//  AgentRegistry.swift
//  aizen
//
//  Created by Uladzislau Yakauleu on 17.10.25.
//

import Foundation

/// Manages discovery and configuration of available ACP agents
class AgentRegistry {
    static let shared = AgentRegistry()

    private let defaults = UserDefaults.standard
    private let agentPathsKey = "acpAgentPaths"
    private let authPreferencesKey = "acpAgentAuthPreferences"

    private let defaultKnownAgents = ["claude", "codex", "gemini"]

    // Agent-specific launch configurations
    private let agentConfigs: [String: AgentConfig] = [
        "claude": AgentConfig(
            executableNames: ["claude-code-acp"],
            launchArgs: []
        ),
        "codex": AgentConfig(
            executableNames: ["codex-acp", "codex"],
            launchArgs: []
        ),
        "gemini": AgentConfig(
            executableNames: ["gemini"],
            launchArgs: ["--experimental-acp"]
        )
    ]

    struct AgentConfig {
        let executableNames: [String]
        let launchArgs: [String]
    }

    private init() {
        initializeDefaultAgentsIfNeeded()
    }

    // MARK: - Agent Path Management

    /// Get all configured agent paths
    var agentPaths: [String: String] {
        get {
            defaults.dictionary(forKey: agentPathsKey) as? [String: String] ?? [:]
        }
        set {
            defaults.set(newValue, forKey: agentPathsKey)
        }
    }

    /// Get executable path for a specific agent by name
    func getAgentPath(for agentName: String) -> String? {
        return agentPaths[agentName]
    }

    /// Get launch arguments for a specific agent
    func getAgentLaunchArgs(for agentName: String) -> [String] {
        return agentConfigs[agentName]?.launchArgs ?? []
    }

    /// Set executable path for a specific agent
    func setAgentPath(_ path: String, for agentName: String) {
        var paths = agentPaths
        paths[agentName] = path
        agentPaths = paths
    }

    /// Remove agent configuration
    func removeAgent(named agentName: String) {
        var paths = agentPaths
        paths.removeValue(forKey: agentName)
        agentPaths = paths
    }

    /// Get list of all available agent names (both configured and known)
    var availableAgents: [String] {
        // Combine configured agents with default known agents
        let configured = Set(agentPaths.keys)
        let known = Set(defaultKnownAgents)
        return Array(configured.union(known)).sorted()
    }

    // MARK: - Agent Discovery

    /// Discover agents in common installation locations
    func discoverAgents() -> [String: String] {
        var discovered: [String: String] = [:]

        for agentName in defaultKnownAgents {
            if let path = discoverAgent(named: agentName) {
                discovered[agentName] = path
            }
        }

        return discovered
    }

    /// Discover path for a specific agent
    func discoverAgent(named agentName: String) -> String? {
        let searchPaths = getSearchPaths(for: agentName)

        if let config = agentConfigs[agentName] {
            for executableName in config.executableNames {
                if let path = findExecutable(named: executableName, in: searchPaths) {
                    return path
                }
            }
        } else {
            // Fallback: try agent name directly
            if let path = findExecutable(named: agentName, in: searchPaths) {
                return path
            }
        }

        return nil
    }

    // MARK: - Validation

    /// Check if agent executable exists and is executable
    func validateAgent(named agentName: String) -> Bool {
        guard let path = getAgentPath(for: agentName) else {
            return false
        }

        let fileManager = FileManager.default
        return fileManager.fileExists(atPath: path) && fileManager.isExecutableFile(atPath: path)
    }

    /// Validate all configured agents and return status
    func validateAllAgents() -> [String: Bool] {
        var status: [String: Bool] = [:]
        for agentName in availableAgents {
            status[agentName] = validateAgent(named: agentName)
        }
        return status
    }

    // MARK: - Auth Preferences

    /// Save preferred auth method for an agent
    func saveAuthPreference(agentName: String, authMethodId: String) {
        var prefs = defaults.dictionary(forKey: authPreferencesKey) as? [String: String] ?? [:]
        prefs[agentName] = authMethodId
        defaults.set(prefs, forKey: authPreferencesKey)
    }

    /// Get saved auth preference for an agent
    func getAuthPreference(for agentName: String) -> String? {
        let prefs = defaults.dictionary(forKey: authPreferencesKey) as? [String: String] ?? [:]
        return prefs[agentName]
    }

    /// Save that an agent should skip authentication
    func saveSkipAuth(for agentName: String) {
        saveAuthPreference(agentName: agentName, authMethodId: "skip")
    }

    /// Check if agent should skip authentication
    func shouldSkipAuth(for agentName: String) -> Bool {
        return getAuthPreference(for: agentName) == "skip"
    }

    // MARK: - Private Helpers

    private func initializeDefaultAgentsIfNeeded() {
        if agentPaths.isEmpty {
            let discovered = discoverAgents()
            agentPaths = discovered
        }
    }

    private func getSearchPaths(for agentName: String) -> [String] {
        let homeDir = FileManager.default.homeDirectoryForCurrentUser
        return [
            homeDir.appendingPathComponent(".aizen/agents/\(agentName)").path,
            "/usr/local/bin",
            "/opt/homebrew/bin",
            "/usr/bin",
            homeDir.appendingPathComponent(".local/bin").path,
            homeDir.appendingPathComponent("bin").path,
            homeDir.appendingPathComponent(".cargo/bin").path,
            homeDir.appendingPathComponent(".npm-global/bin").path,
            "/usr/local/lib/node_modules/.bin",
        ]
    }

    private func findExecutable(named name: String, in paths: [String]) -> String? {
        let fileManager = FileManager.default

        for directory in paths {
            let fullPath = (directory as NSString).appendingPathComponent(name)
            if fileManager.fileExists(atPath: fullPath) && fileManager.isExecutableFile(atPath: fullPath) {
                return fullPath
            }
        }

        return nil
    }
}
