//
//  GitHostingService.swift
//  aizen
//
//  Service for detecting Git hosting providers and managing PR operations
//

import Foundation
import AppKit
import os.log

// MARK: - Types

enum GitHostingProvider: String, Sendable {
    case github
    case gitlab
    case bitbucket
    case azureDevOps
    case unknown

    var displayName: String {
        switch self {
        case .github: return "GitHub"
        case .gitlab: return "GitLab"
        case .bitbucket: return "Bitbucket"
        case .azureDevOps: return "Azure DevOps"
        case .unknown: return "Unknown"
        }
    }

    var cliName: String? {
        switch self {
        case .github: return "gh"
        case .gitlab: return "glab"
        case .azureDevOps: return "az"
        case .bitbucket, .unknown: return nil
        }
    }

    var prTerminology: String {
        switch self {
        case .gitlab: return "Merge Request"
        default: return "Pull Request"
        }
    }

    var installInstructions: String {
        switch self {
        case .github: return "brew install gh && gh auth login"
        case .gitlab: return "brew install glab && glab auth login"
        case .azureDevOps: return "brew install azure-cli && az login"
        case .bitbucket, .unknown: return ""
        }
    }
}

struct GitHostingInfo: Sendable {
    let provider: GitHostingProvider
    let owner: String
    let repo: String
    let baseURL: String
    let cliInstalled: Bool
    let cliAuthenticated: Bool
}

enum PRStatus: Sendable, Equatable {
    case unknown
    case noPR
    case open(number: Int, url: String, mergeable: Bool, title: String)
    case merged
    case closed

    static func == (lhs: PRStatus, rhs: PRStatus) -> Bool {
        switch (lhs, rhs) {
        case (.unknown, .unknown), (.noPR, .noPR), (.merged, .merged), (.closed, .closed):
            return true
        case let (.open(n1, u1, m1, t1), .open(n2, u2, m2, t2)):
            return n1 == n2 && u1 == u2 && m1 == m2 && t1 == t2
        default:
            return false
        }
    }
}

enum GitHostingAction {
    case createPR(sourceBranch: String, targetBranch: String?)
    case viewPR(number: Int)
    case viewRepo
}

enum GitHostingError: LocalizedError {
    case cliNotInstalled(provider: GitHostingProvider)
    case cliNotAuthenticated(provider: GitHostingProvider)
    case commandFailed(message: String)
    case unsupportedProvider
    case noRemoteFound

    var errorDescription: String? {
        switch self {
        case .cliNotInstalled(let provider):
            return "\(provider.cliName ?? "CLI") is not installed"
        case .cliNotAuthenticated(let provider):
            return "\(provider.cliName ?? "CLI") is not authenticated"
        case .commandFailed(let message):
            return message
        case .unsupportedProvider:
            return "This Git hosting provider is not supported"
        case .noRemoteFound:
            return "No remote repository found"
        }
    }
}

// MARK: - Service

actor GitHostingService {
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.aizen", category: "GitHostingService")

    // Cache CLI paths
    private var cliPathCache: [GitHostingProvider: String?] = [:]

    // MARK: - Provider Detection

    func detectProvider(from remoteURL: String) -> GitHostingProvider {
        let lowercased = remoteURL.lowercased()

        if lowercased.contains("github.com") {
            return .github
        } else if lowercased.contains("gitlab.com") || lowercased.contains("gitlab.") {
            return .gitlab
        } else if lowercased.contains("bitbucket.org") {
            return .bitbucket
        } else if lowercased.contains("dev.azure.com") || lowercased.contains("visualstudio.com") {
            return .azureDevOps
        }

        return .unknown
    }

    func parseOwnerRepo(from remoteURL: String) -> (owner: String, repo: String)? {
        // Handle SSH format: git@github.com:owner/repo.git
        if remoteURL.contains("@") && remoteURL.contains(":") {
            let parts = remoteURL.components(separatedBy: ":")
            guard parts.count >= 2 else { return nil }
            let pathPart = parts[1]
            return parsePathComponents(pathPart)
        }

        // Handle HTTPS format: https://github.com/owner/repo.git
        guard let url = URL(string: remoteURL) else { return nil }
        let path = url.path
        return parsePathComponents(path)
    }

    private func parsePathComponents(_ path: String) -> (owner: String, repo: String)? {
        var cleanPath = path
        if cleanPath.hasPrefix("/") {
            cleanPath = String(cleanPath.dropFirst())
        }
        if cleanPath.hasSuffix(".git") {
            cleanPath = String(cleanPath.dropLast(4))
        }

        let components = cleanPath.components(separatedBy: "/")
        guard components.count >= 2 else { return nil }

        return (owner: components[0], repo: components[1])
    }

    func getHostingInfo(for repoPath: String) async -> GitHostingInfo? {
        // Run libgit2 operations on background thread
        let remoteURL: String?
        do {
            remoteURL = try await Task.detached {
                let repo = try Libgit2Repository(path: repoPath)
                guard let remote = try repo.defaultRemote() else {
                    return nil
                }
                return remote.url
            }.value
        } catch {
            logger.error("Failed to get hosting info: \(error.localizedDescription)")
            return nil
        }

        guard let remoteURL = remoteURL else { return nil }

        let provider = detectProvider(from: remoteURL)
        guard let (owner, repo) = parseOwnerRepo(from: remoteURL) else {
            return nil
        }

        let baseURL = extractBaseURL(from: remoteURL, provider: provider)
        let (cliInstalled, _) = await checkCLIInstalled(for: provider)
        let cliAuthenticated = cliInstalled ? await checkCLIAuthenticated(for: provider, repoPath: repoPath) : false

        return GitHostingInfo(
            provider: provider,
            owner: owner,
            repo: repo,
            baseURL: baseURL,
            cliInstalled: cliInstalled,
            cliAuthenticated: cliAuthenticated
        )
    }

    private func extractBaseURL(from remoteURL: String, provider: GitHostingProvider) -> String {
        switch provider {
        case .github:
            return "https://github.com"
        case .gitlab:
            if let url = URL(string: remoteURL), let host = url.host {
                return "https://\(host)"
            }
            return "https://gitlab.com"
        case .bitbucket:
            return "https://bitbucket.org"
        case .azureDevOps:
            if let url = URL(string: remoteURL), let host = url.host {
                return "https://\(host)"
            }
            return "https://dev.azure.com"
        case .unknown:
            return ""
        }
    }

    // MARK: - CLI Detection

    func checkCLIInstalled(for provider: GitHostingProvider) async -> (installed: Bool, path: String?) {
        guard let cliName = provider.cliName else {
            return (false, nil)
        }

        // Check cache
        if let cachedPath = cliPathCache[provider] {
            return (cachedPath != nil, cachedPath)
        }

        // Common paths to check
        let commonPaths = [
            "/opt/homebrew/bin/\(cliName)",
            "/usr/local/bin/\(cliName)",
            "/usr/bin/\(cliName)"
        ]

        for path in commonPaths {
            if FileManager.default.isExecutableFile(atPath: path) {
                cliPathCache[provider] = path
                return (true, path)
            }
        }

        // Try which command
        do {
            let result = try await ProcessExecutor.shared.executeWithOutput(
                executable: "/usr/bin/which",
                arguments: [cliName],
                workingDirectory: nil
            )
            let path = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            if !path.isEmpty && FileManager.default.isExecutableFile(atPath: path) {
                cliPathCache[provider] = path
                return (true, path)
            }
        } catch {
            logger.debug("CLI \(cliName) not found via which")
        }

        cliPathCache[provider] = nil
        return (false, nil)
    }

    func checkCLIAuthenticated(for provider: GitHostingProvider, repoPath: String) async -> Bool {
        guard let cliName = provider.cliName else { return false }
        let (installed, path) = await checkCLIInstalled(for: provider)
        guard installed, let cliPath = path else { return false }

        do {
            switch provider {
            case .github:
                let result = try await ProcessExecutor.shared.executeWithOutput(
                    executable: cliPath,
                    arguments: ["auth", "status"],
                    workingDirectory: repoPath
                )
                return result.exitCode == 0

            case .gitlab:
                let result = try await ProcessExecutor.shared.executeWithOutput(
                    executable: cliPath,
                    arguments: ["auth", "status"],
                    workingDirectory: repoPath
                )
                return result.exitCode == 0

            case .azureDevOps:
                let result = try await ProcessExecutor.shared.executeWithOutput(
                    executable: cliPath,
                    arguments: ["account", "show"],
                    workingDirectory: repoPath
                )
                return result.exitCode == 0

            default:
                return false
            }
        } catch {
            logger.debug("CLI auth check failed: \(error.localizedDescription)")
            return false
        }
    }

    // MARK: - PR Status

    func getPRStatus(repoPath: String, branch: String) async -> PRStatus {
        guard let info = await getHostingInfo(for: repoPath) else {
            return .unknown
        }

        guard info.cliInstalled && info.cliAuthenticated else {
            return .unknown
        }

        let (_, cliPath) = await checkCLIInstalled(for: info.provider)
        guard let path = cliPath else { return .unknown }

        do {
            switch info.provider {
            case .github:
                return try await getGitHubPRStatus(cliPath: path, repoPath: repoPath, branch: branch)
            case .gitlab:
                return try await getGitLabMRStatus(cliPath: path, repoPath: repoPath, branch: branch)
            default:
                return .unknown
            }
        } catch {
            logger.error("Failed to get PR status: \(error.localizedDescription)")
            return .unknown
        }
    }

    private func getGitHubPRStatus(cliPath: String, repoPath: String, branch: String) async throws -> PRStatus {
        let result = try await ProcessExecutor.shared.executeWithOutput(
            executable: cliPath,
            arguments: ["pr", "view", "--json", "number,url,state,mergeable,title", "--head", branch],
            workingDirectory: repoPath
        )

        if result.exitCode != 0 {
            // No PR found
            if result.stderr.contains("no pull requests found") || result.stderr.contains("Could not resolve") {
                return .noPR
            }
            return .unknown
        }

        guard let data = result.stdout.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return .unknown
        }

        let state = json["state"] as? String ?? ""
        let number = json["number"] as? Int ?? 0
        let url = json["url"] as? String ?? ""
        let mergeable = json["mergeable"] as? String ?? ""
        let title = json["title"] as? String ?? ""

        switch state.uppercased() {
        case "OPEN":
            return .open(number: number, url: url, mergeable: mergeable == "MERGEABLE", title: title)
        case "MERGED":
            return .merged
        case "CLOSED":
            return .closed
        default:
            return .unknown
        }
    }

    private func getGitLabMRStatus(cliPath: String, repoPath: String, branch: String) async throws -> PRStatus {
        let result = try await ProcessExecutor.shared.executeWithOutput(
            executable: cliPath,
            arguments: ["mr", "view", "--output", "json", branch],
            workingDirectory: repoPath
        )

        if result.exitCode != 0 {
            if result.stderr.contains("no merge request") || result.stderr.contains("not found") {
                return .noPR
            }
            return .unknown
        }

        guard let data = result.stdout.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return .unknown
        }

        let state = json["state"] as? String ?? ""
        let iid = json["iid"] as? Int ?? 0
        let webUrl = json["web_url"] as? String ?? ""
        let mergeStatus = json["merge_status"] as? String ?? ""
        let title = json["title"] as? String ?? ""

        switch state.lowercased() {
        case "opened":
            return .open(number: iid, url: webUrl, mergeable: mergeStatus == "can_be_merged", title: title)
        case "merged":
            return .merged
        case "closed":
            return .closed
        default:
            return .unknown
        }
    }

    // MARK: - PR Operations

    func createPR(repoPath: String, sourceBranch: String) async throws {
        guard let info = await getHostingInfo(for: repoPath) else {
            throw GitHostingError.noRemoteFound
        }

        if !info.cliInstalled {
            throw GitHostingError.cliNotInstalled(provider: info.provider)
        }

        if !info.cliAuthenticated {
            throw GitHostingError.cliNotAuthenticated(provider: info.provider)
        }

        let (_, cliPath) = await checkCLIInstalled(for: info.provider)
        guard let path = cliPath else {
            throw GitHostingError.cliNotInstalled(provider: info.provider)
        }

        // Open interactive PR creation in terminal
        switch info.provider {
        case .github:
            let result = try await ProcessExecutor.shared.executeWithOutput(
                executable: path,
                arguments: ["pr", "create", "--web"],
                workingDirectory: repoPath
            )
            if result.exitCode != 0 && !result.stderr.isEmpty {
                throw GitHostingError.commandFailed(message: result.stderr)
            }

        case .gitlab:
            let result = try await ProcessExecutor.shared.executeWithOutput(
                executable: path,
                arguments: ["mr", "create", "--web"],
                workingDirectory: repoPath
            )
            if result.exitCode != 0 && !result.stderr.isEmpty {
                throw GitHostingError.commandFailed(message: result.stderr)
            }

        case .azureDevOps:
            let result = try await ProcessExecutor.shared.executeWithOutput(
                executable: path,
                arguments: ["repos", "pr", "create", "--open"],
                workingDirectory: repoPath
            )
            if result.exitCode != 0 && !result.stderr.isEmpty {
                throw GitHostingError.commandFailed(message: result.stderr)
            }

        default:
            throw GitHostingError.unsupportedProvider
        }
    }

    func mergePR(repoPath: String, prNumber: Int) async throws {
        guard let info = await getHostingInfo(for: repoPath) else {
            throw GitHostingError.noRemoteFound
        }

        if !info.cliInstalled {
            throw GitHostingError.cliNotInstalled(provider: info.provider)
        }

        if !info.cliAuthenticated {
            throw GitHostingError.cliNotAuthenticated(provider: info.provider)
        }

        let (_, cliPath) = await checkCLIInstalled(for: info.provider)
        guard let path = cliPath else {
            throw GitHostingError.cliNotInstalled(provider: info.provider)
        }

        switch info.provider {
        case .github:
            let result = try await ProcessExecutor.shared.executeWithOutput(
                executable: path,
                arguments: ["pr", "merge", String(prNumber), "--merge"],
                workingDirectory: repoPath
            )
            if result.exitCode != 0 {
                throw GitHostingError.commandFailed(message: result.stderr)
            }

        case .gitlab:
            let result = try await ProcessExecutor.shared.executeWithOutput(
                executable: path,
                arguments: ["mr", "merge", String(prNumber)],
                workingDirectory: repoPath
            )
            if result.exitCode != 0 {
                throw GitHostingError.commandFailed(message: result.stderr)
            }

        default:
            throw GitHostingError.unsupportedProvider
        }
    }

    // MARK: - Browser Fallback

    func openInBrowser(info: GitHostingInfo, action: GitHostingAction) {
        guard let url = buildURL(info: info, action: action) else {
            logger.error("Failed to build URL for action")
            return
        }

        NSWorkspace.shared.open(url)
    }

    nonisolated func buildURL(info: GitHostingInfo, action: GitHostingAction) -> URL? {
        switch action {
        case .createPR(let sourceBranch, let targetBranch):
            return buildCreatePRURL(info: info, sourceBranch: sourceBranch, targetBranch: targetBranch)
        case .viewPR(let number):
            return buildViewPRURL(info: info, number: number)
        case .viewRepo:
            return buildRepoURL(info: info)
        }
    }

    private nonisolated func buildCreatePRURL(info: GitHostingInfo, sourceBranch: String, targetBranch: String?) -> URL? {
        let target = targetBranch ?? "main"
        let encodedSource = sourceBranch.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? sourceBranch
        let encodedTarget = target.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? target

        switch info.provider {
        case .github:
            return URL(string: "\(info.baseURL)/\(info.owner)/\(info.repo)/compare/\(encodedTarget)...\(encodedSource)?expand=1")

        case .gitlab:
            return URL(string: "\(info.baseURL)/\(info.owner)/\(info.repo)/-/merge_requests/new?merge_request[source_branch]=\(encodedSource)&merge_request[target_branch]=\(encodedTarget)")

        case .bitbucket:
            return URL(string: "\(info.baseURL)/\(info.owner)/\(info.repo)/pull-requests/new?source=\(encodedSource)&dest=\(encodedTarget)")

        case .azureDevOps:
            return URL(string: "\(info.baseURL)/\(info.owner)/_git/\(info.repo)/pullrequestcreate?sourceRef=\(encodedSource)&targetRef=\(encodedTarget)")

        case .unknown:
            return nil
        }
    }

    private nonisolated func buildViewPRURL(info: GitHostingInfo, number: Int) -> URL? {
        switch info.provider {
        case .github:
            return URL(string: "\(info.baseURL)/\(info.owner)/\(info.repo)/pull/\(number)")
        case .gitlab:
            return URL(string: "\(info.baseURL)/\(info.owner)/\(info.repo)/-/merge_requests/\(number)")
        case .bitbucket:
            return URL(string: "\(info.baseURL)/\(info.owner)/\(info.repo)/pull-requests/\(number)")
        case .azureDevOps:
            return URL(string: "\(info.baseURL)/\(info.owner)/_git/\(info.repo)/pullrequest/\(number)")
        case .unknown:
            return nil
        }
    }

    private nonisolated func buildRepoURL(info: GitHostingInfo) -> URL? {
        switch info.provider {
        case .github:
            return URL(string: "\(info.baseURL)/\(info.owner)/\(info.repo)")
        case .gitlab:
            return URL(string: "\(info.baseURL)/\(info.owner)/\(info.repo)")
        case .bitbucket:
            return URL(string: "\(info.baseURL)/\(info.owner)/\(info.repo)")
        case .azureDevOps:
            return URL(string: "\(info.baseURL)/\(info.owner)/_git/\(info.repo)")
        case .unknown:
            return nil
        }
    }
}
