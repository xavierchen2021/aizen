//
//  GitBranchService.swift
//  aizen
//
//  Domain service for Git branch operations
//

import Foundation

struct BranchInfo: Hashable, Identifiable {
    let id = UUID()
    let name: String
    let commit: String
    let isRemote: Bool
}

actor GitBranchService: GitDomainService {
    let executor: GitCommandExecutor

    init(executor: GitCommandExecutor) {
        self.executor = executor
    }

    func listBranches(at repoPath: String, includeRemote: Bool = true) async throws -> [BranchInfo] {
        var arguments = ["branch", "-v", "--no-color"]
        if includeRemote {
            arguments.append("-a")
        }

        let output = try await executor.executeGit(arguments: arguments, at: repoPath)
        return parseBranchList(output)
    }

    func checkoutBranch(at path: String, branch: String) async throws {
        try await executeVoid(["checkout", branch], at: path)
    }

    func createBranch(at path: String, name: String, from baseBranch: String? = nil) async throws {
        var arguments = ["checkout", "-b", name]
        if let baseBranch = baseBranch {
            arguments.append(baseBranch)
        }
        try await executeVoid(arguments, at: path)
    }

    func deleteBranch(at path: String, name: String, force: Bool = false) async throws {
        let flag = force ? "-D" : "-d"
        try await executeVoid(["branch", flag, name], at: path)
    }

    func mergeBranch(at path: String, branch: String) async throws -> MergeResult {
        do {
            let output = try await executor.executeGit(arguments: ["merge", branch], at: path)

            if output.contains("Already up to date") || output.contains("Already up-to-date") {
                return .alreadyUpToDate
            }

            return .success
        } catch {
            let errorMessage = error.localizedDescription

            if errorMessage.contains("CONFLICT") || errorMessage.contains("Merge conflict") {
                let conflictedFiles = try await parseConflictedFiles(at: path)
                return .conflict(files: conflictedFiles)
            }

            throw error
        }
    }

    // MARK: - Private Helpers

    private func parseConflictedFiles(at path: String) async throws -> [String] {
        let output = try await executor.executeGit(arguments: ["diff", "--name-only", "--diff-filter=U"], at: path)
        return output.split(separator: "\n").map { String($0).trimmingCharacters(in: .whitespaces) }
    }

    private func parseBranchList(_ output: String) -> [BranchInfo] {
        let lines = output.split(separator: "\n").map(String.init)
        var branches: [BranchInfo] = []

        for line in lines {
            let cleaned = line.trimmingCharacters(in: .whitespaces)
                .replacingOccurrences(of: "* ", with: "")
                .replacingOccurrences(of: "+ ", with: "")
                .replacingOccurrences(of: "  ", with: " ")

            let components = cleaned.split(separator: " ", maxSplits: 2).map(String.init)
            guard components.count >= 2 else { continue }

            let name = components[0]
            let commit = components[1]
            let isRemote = name.hasPrefix("remotes/")

            branches.append(BranchInfo(
                name: name.replacingOccurrences(of: "remotes/", with: ""),
                commit: commit,
                isRemote: isRemote
            ))
        }

        return branches
    }
}
