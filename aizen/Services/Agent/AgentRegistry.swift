//
//  AgentRegistry.swift
//  aizen
//
//  Created by Uladzislau Yakauleu on 17.10.25.
//

import Foundation
import SwiftUI
import os.log

extension Notification.Name {
    static let agentMetadataDidChange = Notification.Name("agentMetadataDidChange")
}

/// Manages discovery and configuration of available ACP agents
class AgentRegistry {
    static let shared = AgentRegistry()

    private let defaults = UserDefaults.standard
    private let authPreferencesKey = "acpAgentAuthPreferences"
    private let metadataStoreKey = "agentMetadataStore"
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.aizen", category: "AgentRegistry")

    // Built-in agent executable names for discovery
    private static let builtInExecutableNames: [String: [String]] = [
        "claude": ["claude-code-acp"],
        "codex": ["codex-acp", "codex"],
        "gemini": ["gemini"]
    ]

    // MARK: - Agent Metadata Model

    enum IconType: Codable, Equatable {
        case builtin(String)      // "claude", "gemini", "openai"
        case sfSymbol(String)     // SF Symbol name
        case customImage(Data)    // Image file data

        enum CodingKeys: String, CodingKey {
            case type, value, data
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let type = try container.decode(String.self, forKey: .type)

            switch type {
            case "builtin":
                let value = try container.decode(String.self, forKey: .value)
                self = .builtin(value)
            case "sfSymbol":
                let value = try container.decode(String.self, forKey: .value)
                self = .sfSymbol(value)
            case "customImage":
                let data = try container.decode(Data.self, forKey: .data)
                self = .customImage(data)
            default:
                throw DecodingError.dataCorruptedError(forKey: .type, in: container, debugDescription: "Unknown icon type")
            }
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)

            switch self {
            case .builtin(let value):
                try container.encode("builtin", forKey: .type)
                try container.encode(value, forKey: .value)
            case .sfSymbol(let value):
                try container.encode("sfSymbol", forKey: .type)
                try container.encode(value, forKey: .value)
            case .customImage(let data):
                try container.encode("customImage", forKey: .type)
                try container.encode(data, forKey: .data)
            }
        }
    }

    enum InstallMethod: Codable, Equatable {
        case npm(package: String)
        case binary(url: String)

        enum CodingKeys: String, CodingKey {
            case type, package, url
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let type = try container.decode(String.self, forKey: .type)

            switch type {
            case "npm":
                let package = try container.decode(String.self, forKey: .package)
                self = .npm(package: package)
            case "binary":
                let url = try container.decode(String.self, forKey: .url)
                self = .binary(url: url)
            default:
                throw DecodingError.dataCorruptedError(forKey: .type, in: container, debugDescription: "Unknown install method")
            }
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)

            switch self {
            case .npm(let package):
                try container.encode("npm", forKey: .type)
                try container.encode(package, forKey: .package)
            case .binary(let url):
                try container.encode("binary", forKey: .type)
                try container.encode(url, forKey: .url)
            }
        }
    }

    struct AgentMetadata: Codable, Identifiable {
        let id: String
        var name: String
        var description: String?
        var iconType: IconType
        var isBuiltIn: Bool
        var isEnabled: Bool
        var executablePath: String?
        var launchArgs: [String]
        var installMethod: InstallMethod?

        init(
            id: String,
            name: String,
            description: String? = nil,
            iconType: IconType,
            isBuiltIn: Bool,
            isEnabled: Bool = true,
            executablePath: String? = nil,
            launchArgs: [String] = [],
            installMethod: InstallMethod? = nil
        ) {
            self.id = id
            self.name = name
            self.description = description
            self.iconType = iconType
            self.isBuiltIn = isBuiltIn
            self.isEnabled = isEnabled
            self.executablePath = executablePath
            self.launchArgs = launchArgs
            self.installMethod = installMethod
        }
    }

    // Agent metadata storage with in-memory cache
    private var metadataCache: [String: AgentMetadata]?

    private var agentMetadata: [String: AgentMetadata] {
        get {
            if let cache = metadataCache {
                return cache
            }

            guard let data = defaults.data(forKey: metadataStoreKey) else {
                return [:]
            }

            do {
                let decoder = JSONDecoder()
                let decoded = try decoder.decode([String: AgentMetadata].self, from: data)
                metadataCache = decoded
                return decoded
            } catch {
                logger.error("Failed to decode agent metadata: \(error.localizedDescription)")
                return [:]
            }
        }
        set {
            metadataCache = newValue
            do {
                let encoder = JSONEncoder()
                let data = try encoder.encode(newValue)
                defaults.set(data, forKey: metadataStoreKey)
                NotificationCenter.default.post(name: .agentMetadataDidChange, object: nil)
            } catch {
                logger.error("Failed to encode agent metadata: \(error.localizedDescription)")
            }
        }
    }

    private init() {
        initializeDefaultAgents()
    }

    // MARK: - Metadata Management

    /// Get all agents (enabled and disabled)
    var allAgents: [AgentMetadata] {
        Array(agentMetadata.values).sorted { $0.name < $1.name }
    }

    /// Get only enabled agents
    var enabledAgents: [AgentMetadata] {
        allAgents.filter { $0.isEnabled }
    }

    /// Get metadata for specific agent
    func getMetadata(for agentId: String) -> AgentMetadata? {
        return agentMetadata[agentId]
    }

    /// Add custom agent
    func addCustomAgent(
        name: String,
        description: String?,
        iconType: IconType,
        executablePath: String,
        launchArgs: [String]
    ) -> AgentMetadata {
        let id = "custom-\(UUID().uuidString)"
        let metadata = AgentMetadata(
            id: id,
            name: name,
            description: description,
            iconType: iconType,
            isBuiltIn: false,
            isEnabled: true,
            executablePath: executablePath,
            launchArgs: launchArgs,
            installMethod: nil
        )

        var store = agentMetadata
        store[id] = metadata
        agentMetadata = store

        return metadata
    }

    /// Update agent metadata
    func updateAgent(_ metadata: AgentMetadata) {
        var store = agentMetadata
        store[metadata.id] = metadata
        agentMetadata = store
    }

    /// Delete custom agent
    func deleteAgent(id: String) {
        guard let metadata = agentMetadata[id], !metadata.isBuiltIn else {
            return
        }

        var store = agentMetadata
        store.removeValue(forKey: id)
        agentMetadata = store
    }

    /// Toggle agent enabled status
    func toggleEnabled(for agentId: String) {
        guard var metadata = agentMetadata[agentId] else {
            return
        }

        metadata.isEnabled = !metadata.isEnabled

        var store = agentMetadata
        store[agentId] = metadata
        agentMetadata = store
    }

    // MARK: - Agent Path Management

    /// Get executable path for a specific agent by name
    func getAgentPath(for agentName: String) -> String? {
        return agentMetadata[agentName]?.executablePath
    }

    /// Get launch arguments for a specific agent
    func getAgentLaunchArgs(for agentName: String) -> [String] {
        return agentMetadata[agentName]?.launchArgs ?? []
    }

    /// Set executable path for a specific agent
    func setAgentPath(_ path: String, for agentName: String) {
        guard var metadata = agentMetadata[agentName] else {
            return
        }

        metadata.executablePath = path
        updateAgent(metadata)
    }

    /// Remove agent configuration
    func removeAgent(named agentName: String) {
        deleteAgent(id: agentName)
    }

    /// Get list of all available agent names
    var availableAgents: [String] {
        return agentMetadata.keys.sorted()
    }

    // MARK: - Agent Discovery

    /// Discover agents in common installation locations
    func discoverAgents() -> [String: String] {
        var discovered: [String: String] = [:]

        for (agentName, _) in Self.builtInExecutableNames {
            if let path = discoverAgent(named: agentName) {
                discovered[agentName] = path
            }
        }

        return discovered
    }

    /// Discover path for a specific agent
    func discoverAgent(named agentName: String) -> String? {
        let searchPaths = getSearchPaths(for: agentName)

        if let names = Self.builtInExecutableNames[agentName] {
            for execName in names {
                if let path = findExecutable(named: execName, in: searchPaths) {
                    return path
                }
            }
        }

        // Fallback: try agent name directly
        if let path = findExecutable(named: agentName, in: searchPaths) {
            return path
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

    private func initializeDefaultAgents() {
        // Only initialize if metadata is empty
        if !agentMetadata.isEmpty {
            return
        }

        // Try to discover agent paths
        let discovered = discoverAgents()

        // Create default built-in agents
        var metadata: [String: AgentMetadata] = [:]

        // Claude
        metadata["claude"] = AgentMetadata(
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

        // Codex
        metadata["codex"] = AgentMetadata(
            id: "codex",
            name: "Codex",
            description: "OpenAI's code generation model",
            iconType: .builtin("openai"),
            isBuiltIn: true,
            isEnabled: true,
            executablePath: discovered["codex"],
            launchArgs: [],
            installMethod: .binary(url: "https://github.com/openai/openai-agent/releases/download/v0.1.6/openai-agent-{arch}-apple-darwin.tar.gz")
        )

        // Gemini
        metadata["gemini"] = AgentMetadata(
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

        agentMetadata = metadata
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
