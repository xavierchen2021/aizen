//
//  AgentVersionChecker.swift
//  aizen
//
//  Service to check ACP agent versions and suggest updates
//

import Foundation
import os.log

struct AgentVersionInfo: Codable {
    let current: String?
    let latest: String?
    let isOutdated: Bool
    let updateAvailable: Bool
}

actor AgentVersionChecker {
    static let shared = AgentVersionChecker()

    private var versionCache: [String: AgentVersionInfo] = [:]
    private var lastCheckTime: [String: Date] = [:]
    private let cacheExpiration: TimeInterval = 3600 // 1 hour
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.aizen.app", category: "AgentVersion")

    private init() {}

    /// Check if an agent's version is outdated
    func checkVersion(for agentName: String) async -> AgentVersionInfo {
        // Check cache first
        if let cached = versionCache[agentName],
           let lastCheck = lastCheckTime[agentName],
           Date().timeIntervalSince(lastCheck) < cacheExpiration {
            return cached
        }

        let metadata = AgentRegistry.shared.getMetadata(for: agentName)
        guard let agentPath = metadata?.executablePath else {
            return AgentVersionInfo(current: nil, latest: nil, isOutdated: false, updateAvailable: false)
        }

        // Detect actual install method by inspecting the binary
        let actualInstallMethod = await detectInstallMethod(agentPath: agentPath, configuredMethod: metadata?.installMethod)

        let info: AgentVersionInfo

        switch actualInstallMethod {
        case .npm(let package):
            info = await checkNpmVersion(package: package, agentPath: agentPath)
        case .uv:
            // For uv packages, just get version from --version flag
            info = await checkBinaryVersion(agentPath: agentPath)
        case .githubRelease(let repo, _):
            info = await checkGithubVersion(repo: repo, agentPath: agentPath)
        default:
            info = AgentVersionInfo(current: nil, latest: nil, isOutdated: false, updateAvailable: false)
        }

        // Cache the result
        versionCache[agentName] = info
        lastCheckTime[agentName] = Date()

        return info
    }

    /// Detect actual install method by inspecting the binary
    private func detectInstallMethod(agentPath: String, configuredMethod: AgentInstallMethod?) async -> AgentInstallMethod? {
        // Check if it's a symlink to node_modules (npm install)
        if let resolvedPath = try? FileManager.default.destinationOfSymbolicLink(atPath: agentPath),
           resolvedPath.contains("node_modules") {
            // Extract package name from path like: ../lib/node_modules/@scope/package/dist/index.js
            if let packageMatch = resolvedPath.range(of: #"node_modules/([^/]+(?:/[^/]+)?)"#, options: .regularExpression) {
                let packagePath = String(resolvedPath[packageMatch])
                let packageName = packagePath.replacingOccurrences(of: "node_modules/", with: "")
                return .npm(package: packageName)
            }
            // Fallback to configured method if we found node_modules but couldn't extract package
            if case .npm(let package) = configuredMethod {
                return .npm(package: package)
            }
        }

        // If not npm, return configured method
        return configuredMethod
    }

    /// Check NPM package version
    private func checkNpmVersion(package: String, agentPath: String?) async -> AgentVersionInfo {
        // Get current installed version
        let currentVersion = await getCurrentNpmVersion(package: package)

        // Get latest version from npm registry
        let latestVersion = await getLatestNpmVersion(package: package)

        let isOutdated = compareVersions(current: currentVersion, latest: latestVersion)

        return AgentVersionInfo(
            current: currentVersion,
            latest: latestVersion,
            isOutdated: isOutdated,
            updateAvailable: isOutdated
        )
    }

    /// Get current installed NPM package version
    private func getCurrentNpmVersion(package: String) async -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["npm", "list", "-g", package, "--json"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()

            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let dependencies = json["dependencies"] as? [String: Any],
               let packageInfo = dependencies[package] as? [String: Any],
               let version = packageInfo["version"] as? String {
                return version
            }
        } catch {
            logger.error("Failed to get current npm version for \(package): \(error)")
        }

        return nil
    }

    /// Get latest NPM package version from registry
    private func getLatestNpmVersion(package: String) async -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["npm", "view", package, "version"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let version = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
               !version.isEmpty {
                return version
            }
        } catch {
            logger.error("Failed to get latest npm version for \(package): \(error)")
        }

        return nil
    }

    /// Check binary version (for uv packages - just current version, no latest check)
    private func checkBinaryVersion(agentPath: String?) async -> AgentVersionInfo {
        let currentVersion = await getCurrentBinaryVersion(agentPath: agentPath)
        return AgentVersionInfo(
            current: currentVersion,
            latest: nil,
            isOutdated: false,
            updateAvailable: false
        )
    }

    /// Check GitHub release version
    private func checkGithubVersion(repo: String, agentPath: String?) async -> AgentVersionInfo {
        // Get current version from binary
        let currentVersion = await getCurrentBinaryVersion(agentPath: agentPath)

        // Get latest version from GitHub API
        let latestVersion = await getLatestGithubVersion(repo: repo)

        let isOutdated = compareVersions(current: currentVersion, latest: latestVersion)

        return AgentVersionInfo(
            current: currentVersion,
            latest: latestVersion,
            isOutdated: isOutdated,
            updateAvailable: isOutdated
        )
    }

    /// Get current binary version by executing with --version flag
    private func getCurrentBinaryVersion(agentPath: String?) async -> String? {
        guard let agentPath = agentPath else { return nil }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: agentPath)
        process.arguments = ["--version"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
               !output.isEmpty {
                // Extract version number from output (handles formats like "v1.2.3" or "agent version 1.2.3")
                return extractVersionNumber(from: output)
            }
        } catch {
            logger.error("Failed to get binary version for \(agentPath): \(error)")
        }

        return nil
    }

    /// Get latest GitHub release version via API
    private func getLatestGithubVersion(repo: String) async -> String? {
        guard let apiURL = URL(string: "https://api.github.com/repos/\(repo)/releases/latest") else {
            return nil
        }

        var request = URLRequest(url: apiURL, timeoutInterval: 30)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else {
                return nil
            }

            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let tagName = json["tag_name"] as? String {
                // Remove 'v' prefix if present
                return tagName.hasPrefix("v") ? String(tagName.dropFirst()) : tagName
            }
        } catch {
            logger.error("Failed to get latest GitHub version for \(repo): \(error)")
        }

        return nil
    }

    /// Extract version number from version string
    private func extractVersionNumber(from output: String) -> String? {
        // Match version pattern with 2 or 3 parts (e.g., "1.2", "1.2.3", "v1.2.3")
        let pattern = #"v?(\d+\.\d+(?:\.\d+)?)"#
        if let range = output.range(of: pattern, options: .regularExpression),
           let match = output[range].firstMatch(of: /v?(\d+\.\d+(?:\.\d+)?)/) {
            return String(match.1)
        }
        return nil
    }

    /// Compare semantic versions
    private func compareVersions(current: String?, latest: String?) -> Bool {
        guard let current = current, let latest = latest else {
            return false
        }

        let currentParts = current.split(separator: ".").compactMap { Int($0) }
        let latestParts = latest.split(separator: ".").compactMap { Int($0) }

        for i in 0..<max(currentParts.count, latestParts.count) {
            let currentPart = i < currentParts.count ? currentParts[i] : 0
            let latestPart = i < latestParts.count ? latestParts[i] : 0

            if latestPart > currentPart {
                return true // Outdated
            } else if latestPart < currentPart {
                return false // Newer than latest (dev version?)
            }
        }

        return false // Same version
    }

    /// Clear cache for an agent
    func clearCache(for agentName: String) {
        versionCache.removeValue(forKey: agentName)
        lastCheckTime.removeValue(forKey: agentName)
    }

    /// Clear all caches
    func clearAllCaches() {
        versionCache.removeAll()
        lastCheckTime.removeAll()
    }
}
