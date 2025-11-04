//
//  GitStagingService.swift
//  aizen
//
//  Domain service for Git staging operations
//

import Foundation

actor GitStagingService {
    private let executor: GitCommandExecutor

    init(executor: GitCommandExecutor) {
        self.executor = executor
    }

    func stageFile(at path: String, file: String) async throws {
        _ = try await executor.executeGit(arguments: ["add", file], at: path)
    }

    func unstageFile(at path: String, file: String) async throws {
        _ = try await executor.executeGit(arguments: ["restore", "--staged", file], at: path)
    }

    func stageAll(at path: String) async throws {
        _ = try await executor.executeGit(arguments: ["add", "-A"], at: path)
    }

    func unstageAll(at path: String) async throws {
        _ = try await executor.executeGit(arguments: ["restore", "--staged", "."], at: path)
    }

    func commit(at path: String, message: String) async throws {
        _ = try await executor.executeGit(arguments: ["commit", "-m", message], at: path)
    }

    func amendCommit(at path: String, message: String) async throws {
        _ = try await executor.executeGit(arguments: ["commit", "--amend", "-m", message], at: path)
    }

    func commitWithSignoff(at path: String, message: String) async throws {
        _ = try await executor.executeGit(arguments: ["commit", "-m", message, "--signoff"], at: path)
    }
}
