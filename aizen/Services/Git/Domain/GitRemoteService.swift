//
//  GitRemoteService.swift
//  aizen
//
//  Domain service for Git remote operations
//

import Foundation

actor GitRemoteService {
    private let executor: GitCommandExecutor

    init(executor: GitCommandExecutor) {
        self.executor = executor
    }

    func fetch(at path: String) async throws {
        _ = try await executor.executeGit(arguments: ["fetch"], at: path)
    }

    func pull(at path: String) async throws {
        _ = try await executor.executeGit(arguments: ["pull"], at: path)
    }

    func push(at path: String, setUpstream: Bool = false, force: Bool = false) async throws {
        var arguments = ["push"]

        if setUpstream {
            arguments.append("--set-upstream")
            arguments.append("origin")
            arguments.append("HEAD")
        }

        if force {
            arguments.append("--force")
        }

        _ = try await executor.executeGit(arguments: arguments, at: path)
    }

    func clone(url: String, to path: String) async throws {
        _ = try await executor.executeGit(arguments: ["clone", url, path], at: nil)
    }

    func initRepository(at path: String, initialBranch: String = "main") async throws {
        // Create directory if doesn't exist
        try FileManager.default.createDirectory(
            atPath: path,
            withIntermediateDirectories: true,
            attributes: nil
        )

        // Initialize git repository
        _ = try await executor.executeGit(
            arguments: ["init", "--initial-branch=\(initialBranch)"],
            at: path
        )
    }

    func getRepositoryName(at path: String) async throws -> String {
        // Try to get name from git config first
        if let configName = try? await executor.executeGit(
            arguments: ["config", "--get", "remote.origin.url"],
            at: path
        ) {
            // Extract repo name from URL (e.g., github.com/user/repo.git -> repo)
            let trimmed = configName.trimmingCharacters(in: .whitespacesAndNewlines)
            if let lastComponent = trimmed.split(separator: "/").last {
                let repoName = String(lastComponent).replacingOccurrences(of: ".git", with: "")
                if !repoName.isEmpty {
                    return repoName
                }
            }
        }

        // Fallback to directory name
        return URL(fileURLWithPath: path).lastPathComponent
    }
}
