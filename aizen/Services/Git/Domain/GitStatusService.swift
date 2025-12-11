//
//  GitStatusService.swift
//  aizen
//
//  Domain service for Git status queries using libgit2
//

import Foundation

struct DetailedGitStatus {
    let stagedFiles: [String]
    let modifiedFiles: [String]
    let untrackedFiles: [String]
    let conflictedFiles: [String]
    let currentBranch: String?
    let aheadBy: Int
    let behindBy: Int
    let additions: Int
    let deletions: Int
}

actor GitStatusService {

    func getDetailedStatus(at path: String) async throws -> DetailedGitStatus {
        // Run libgit2 operations on background thread to avoid blocking
        return try await Task.detached {
            let repo = try Libgit2Repository(path: path)
            let status = try repo.status()

            // Get current branch name
            let currentBranch = try? repo.currentBranchName()

            // Get ahead/behind counts
            var aheadBy = 0
            var behindBy = 0

            if let branchName = currentBranch {
                let branches = try repo.listBranches(type: .local)
                if let branch = branches.first(where: { $0.name == branchName }) {
                    if let aheadBehind = branch.aheadBehind {
                        aheadBy = aheadBehind.ahead
                        behindBy = aheadBehind.behind
                    }
                }
            }

            // Calculate additions/deletions from diff
            let diffStats = try repo.diffStats()

            // Map entries to file paths
            let stagedFiles = status.staged.map { $0.path }
            let modifiedFiles = status.modified.map { $0.path }
            let untrackedFiles = status.untracked.map { $0.path }
            let conflictedFiles = status.conflicted.map { $0.path }

            return DetailedGitStatus(
                stagedFiles: stagedFiles,
                modifiedFiles: modifiedFiles,
                untrackedFiles: untrackedFiles,
                conflictedFiles: conflictedFiles,
                currentBranch: currentBranch,
                aheadBy: aheadBy,
                behindBy: behindBy,
                additions: diffStats.insertions,
                deletions: diffStats.deletions
            )
        }.value
    }

    func getCurrentBranch(at path: String) async throws -> String {
        return try await Task.detached {
            let repo = try Libgit2Repository(path: path)
            guard let branch = try repo.currentBranchName() else {
                throw Libgit2Error.referenceNotFound("HEAD")
            }
            return branch
        }.value
    }

    func getBranchStatus(at path: String) async throws -> (ahead: Int, behind: Int) {
        return try await Task.detached {
            let repo = try Libgit2Repository(path: path)

            guard let branchName = try repo.currentBranchName() else {
                return (0, 0)
            }

            let branches = try repo.listBranches(type: .local)
            if let branch = branches.first(where: { $0.name == branchName }) {
                if let aheadBehind = branch.aheadBehind {
                    return (aheadBehind.ahead, aheadBehind.behind)
                }
            }

            return (0, 0)
        }.value
    }

    func hasUnsavedChanges(at worktreePath: String) async throws -> Bool {
        return try await Task.detached {
            let repo = try Libgit2Repository(path: worktreePath)
            let status = try repo.status()
            return status.hasChanges
        }.value
    }
}
