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
actor AgentRegistry {
    static let shared = AgentRegistry()

    private let defaults: UserDefaults
    private let authPreferencesKey = "acpAgentAuthPreferences"
    private let metadataStoreKey = "agentMetadataStore"
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.aizen", category: "AgentRegistry")

    // MARK: - Persistence

    /// Agent metadata storage with in-memory cache
    private var metadataCache: [String: AgentMetadata]?

    internal var agentMetadata: [String: AgentMetadata] {
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
                Task { @MainActor in
                    NotificationCenter.default.post(name: .agentMetadataDidChange, object: nil)
                }
            } catch {
                logger.error("Failed to encode agent metadata: \(error.localizedDescription)")
            }
        }
    }

    private init(defaults: UserDefaults = .app) {
        self.defaults = defaults
        // Initialize agents in background task
        Task {
            await self.initializeDefaultAgents()
        }
    }

    // MARK: - Metadata Management

    /// Load metadata directly from UserDefaults (thread-safe)
    private nonisolated func loadMetadataFromDefaults() -> [String: AgentMetadata] {
        guard let data = defaults.data(forKey: metadataStoreKey) else {
            return [:]
        }

        do {
            let decoder = JSONDecoder()
            return try decoder.decode([String: AgentMetadata].self, from: data)
        } catch {
            return [:]
        }
    }

    /// Get all agents (enabled and disabled)
    nonisolated func getAllAgents() -> [AgentMetadata] {
        let metadata = loadMetadataFromDefaults()
        return Array(metadata.values).sorted { $0.name < $1.name }
    }

    /// Get only enabled agents
    nonisolated func getEnabledAgents() -> [AgentMetadata] {
        getAllAgents().filter { $0.isEnabled }
    }

    /// Get metadata for specific agent
    nonisolated func getMetadata(for agentId: String) -> AgentMetadata? {
        let metadata = loadMetadataFromDefaults()
        return metadata[agentId]
    }

    /// Add custom agent
    func addCustomAgent(
        name: String,
        description: String?,
        iconType: AgentIconType,
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
    nonisolated func getAgentPath(for agentName: String) -> String? {
        let metadata = loadMetadataFromDefaults()
        
        // Get stored executable path
        if let storedPath = metadata[agentName]?.executablePath {
            // If the stored path exists and is executable, use it
            if FileManager.default.fileExists(atPath: storedPath) && 
               FileManager.default.isExecutableFile(atPath: storedPath) {
                return storedPath
            }
            
            // Otherwise try to discover the agent in system PATH
            if let discoveredPath = discoverExecutableInPath(for: agentName) {
                return discoveredPath
            }
        }
        
        // If no metadata exists, try to discover in system PATH
        if let discoveredPath = discoverExecutableInPath(for: agentName) {
            return discoveredPath
        }
        
        // Fall back to managed path if all else fails
        return Self.managedPath(for: agentName)
    }
    
    /// Discover agent executable in system PATH
    nonisolated private func discoverExecutableInPath(for agentName: String) -> String? {
        let executableNames: [String]

        switch agentName {
        case "claude":
            executableNames = ["claude-code-acp"]
        case "codex":
            executableNames = ["codex-acp", "codex"]
        case "gemini":
            executableNames = ["gemini"]
        case "kimi":
            executableNames = ["kimi"]
        case "opencode":
            executableNames = ["opencode"]
        case "vibe":
            executableNames = ["vibe-acp"]
        case "qwen":
            executableNames = ["qwen"]
        default:
            return nil
        }

        for executableName in executableNames {
            // 合并 PATH 检测结果
            if let path = discoverExecutableInSystemPath(executableName: executableName) {
                return path
            }
        }

        // 检查常用安装路径（适用于所有代理）
        if let path = checkCommonInstallPaths(for: agentName) {
            return path
        }

        return nil
    }

    /// 在系统 PATH 中查找可执行文件（合并两种检测方式的结果）
    nonisolated private func discoverExecutableInSystemPath(executableName: String) -> String? {
        // 首先使用 which 查找
        if let path = discoverExecutableUsingWhich(executableName: executableName) {
            return path
        }

        // Finder 启动时常缺失用户 shell PATH；用登录 shell 复查一次
        if let path = discoverExecutableUsingLoginShell(executableName: executableName) {
            return path
        }

        return nil
    }

    /// 检查常用安装路径
    nonisolated private func checkCommonInstallPaths(for agentName: String) -> String? {
        let home = FileManager.default.homeDirectoryForCurrentUser

        let pathsByAgent: [String: [String]] = [
            "claude": [
                "\(home.path)/.claude/node_modules/.bin/claude-code-acp",
                "\(home.path)/.claude/local/node_modules/.bin/claude-code-acp",
                "\(home.path)/.npm/_npx/*/node_modules/.bin/claude-code-acp",
                "/usr/local/bin/claude-code-acp",
                "\(home.path)/.local/bin/claude-code-acp",
                "\(home.path)/.nvm/versions/node/*/bin/claude-code-acp"
            ],
            "codex": [
                "\(home.path)/.npm/_npx/*/node_modules/.bin/codex-acp",
                "\(home.path)/.npm/_npx/*/node_modules/.bin/codex",
                "/usr/local/bin/codex-acp",
                "/usr/local/bin/codex",
                "\(home.path)/.local/bin/codex-acp",
                "\(home.path)/.local/bin/codex"
            ],
            "gemini": [
                "\(home.path)/.gemini",
                "/usr/local/bin/gemini",
                "\(home.path)/.local/bin/gemini"
            ],
            "kimi": [
                "\(home.path)/.kimi",
                "/usr/local/bin/kimi",
                "\(home.path)/.local/bin/kimi"
            ],
            "opencode": [
                "\(home.path)/.npm/_npx/*/node_modules/.bin/opencode",
                "/usr/local/bin/opencode",
                "\(home.path)/.local/bin/opencode"
            ],
            "vibe": [
                "\(home.path)/.npm/_npx/*/node_modules/.bin/vibe-acp",
                "/usr/local/bin/vibe-acp",
                "\(home.path)/.local/bin/vibe-acp"
            ],
            "qwen": [
                "\(home.path)/.qwen",
                "/usr/local/bin/qwen",
                "\(home.path)/.local/bin/qwen"
            ]
        ]

        guard let paths = pathsByAgent[agentName] else {
            return nil
        }

        for pathPattern in paths {
            // 处理通配符路径
            if pathPattern.contains("*") {
                if let expandedPath = expandGlobPattern(pathPattern) {
                    return expandedPath
                }
            } else {
                if FileManager.default.isExecutableFile(atPath: pathPattern) {
                    return pathPattern
                }
            }
        }

        return nil
    }

    /// 展开通配符路径
    nonisolated private func expandGlobPattern(_ pattern: String) -> String? {
        let directory = (pattern as NSString).deletingLastPathComponent
        let filename = (pattern as NSString).lastPathComponent

        guard let enumerator = FileManager.default.enumerator(
            atPath: directory
        ) else {
            return nil
        }

        for case let item as String in enumerator {
            if globMatch(filename, pattern: item) {
                return (directory as NSString).appendingPathComponent(item)
            }
        }

        return nil
    }

    /// 简单的通配符匹配（支持 * 和 ?）
    nonisolated private func globMatch(_ string: String, pattern: String) -> Bool {
        var stringIndex = string.startIndex
        var patternIndex = pattern.startIndex
        var starIndices: [(String.Index, String.Index)] = []
        var sIndex = 0

        for (i, char) in pattern.enumerated() {
            if char == "*" {
                let idx = pattern.index(pattern.startIndex, offsetBy: i)
                starIndices.append((idx, idx))
                sIndex = string.count
            }
        }

        if starIndices.isEmpty {
            return string == pattern
        }

        var pIndex = pattern.startIndex
        for (i, char) in string.enumerated() {
            if pIndex < pattern.endIndex && (pattern[pIndex] == char || pattern[pIndex] == "*") {
                if pattern[pIndex] != "*" {
                    pIndex = pattern.index(after: pIndex)
                }
            } else if !starIndices.isEmpty {
                let (_, p) = starIndices.removeFirst()
                if sIndex > 0 {
                    let prevStringIndex = string.index(string.startIndex, offsetBy: sIndex - 1)
                    if prevStringIndex > stringIndex {
                        pIndex = pattern.index(after: p)
                        sIndex -= 1
                        stringIndex = string.index(string.startIndex, offsetBy: i)
                    }
                }
            } else {
                return false
            }
        }

        while let (s, p) = starIndices.first, p < pattern.endIndex, pattern[p] == "*" {
            starIndices.removeFirst()
        }

        return starIndices.isEmpty && pIndex >= pattern.endIndex
    }

    // MARK: - Executable Discovery Helpers

    nonisolated private func discoverExecutableUsingWhich(executableName: String) -> String? {
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
            let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let path = output?.split(separator: "\n").first.map(String.init), !path.isEmpty else {
                return nil
            }
            return FileManager.default.isExecutableFile(atPath: path) ? path : nil
        } catch {
            return nil
        }
    }

    nonisolated private func discoverExecutableUsingLoginShell(executableName: String) -> String? {
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        let shellName = (shell as NSString).lastPathComponent

        let escaped = shellEscape(executableName)
        let command = "command -v \(escaped)"

        let process = Process()
        process.executableURL = URL(fileURLWithPath: shell)

        // 使用登录 shell 读取用户配置，获得更完整的 PATH
        switch shellName {
        case "fish":
            process.arguments = ["-l", "-c", command]
        case "zsh", "bash", "sh":
            process.arguments = ["-l", "-c", command]
        default:
            process.arguments = ["-c", command]
        }

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let candidate = output?.split(separator: "\n").first.map(String.init), !candidate.isEmpty else {
                return nil
            }
            return FileManager.default.isExecutableFile(atPath: candidate) ? candidate : nil
        } catch {
            return nil
        }
    }

    nonisolated private func shellEscape(_ raw: String) -> String {
        // 单引号安全转义：' -> '\''
        let escaped = raw.replacingOccurrences(of: "'", with: "'\\''")
        return "'\(escaped)'"
    }

    /// Get launch arguments for a specific agent
    nonisolated func getAgentLaunchArgs(for agentName: String) -> [String] {
        let metadata = loadMetadataFromDefaults()
        return metadata[agentName]?.launchArgs ?? []
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
    func getAvailableAgents() -> [String] {
        return agentMetadata.keys.sorted()
    }

    // MARK: - Auth Preferences

    /// Save preferred auth method for an agent
    nonisolated func saveAuthPreference(agentName: String, authMethodId: String) {
        var prefs = defaults.dictionary(forKey: authPreferencesKey) as? [String: String] ?? [:]
        prefs[agentName] = authMethodId
        defaults.set(prefs, forKey: authPreferencesKey)
    }

    /// Get saved auth preference for an agent
    nonisolated func getAuthPreference(for agentName: String) -> String? {
        let prefs = defaults.dictionary(forKey: authPreferencesKey) as? [String: String] ?? [:]
        return prefs[agentName]
    }

    /// Save that an agent should skip authentication
    nonisolated func saveSkipAuth(for agentName: String) {
        saveAuthPreference(agentName: agentName, authMethodId: "skip")
    }

    /// Check if agent should skip authentication
    nonisolated func shouldSkipAuth(for agentName: String) -> Bool {
        return getAuthPreference(for: agentName) == "skip"
    }

    /// Clear saved auth preference for an agent
    nonisolated func clearAuthPreference(for agentName: String) {
        var prefs = defaults.dictionary(forKey: authPreferencesKey) as? [String: String] ?? [:]
        prefs.removeValue(forKey: agentName)
        defaults.set(prefs, forKey: authPreferencesKey)
    }

    /// Get displayable auth method name for an agent
    nonisolated func getAuthMethodName(for agentName: String) -> String? {
        guard let authMethodId = getAuthPreference(for: agentName) else {
            return nil
        }

        if authMethodId == "skip" {
            return "None"
        }

        return authMethodId
    }
}
