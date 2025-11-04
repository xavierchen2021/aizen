//
//  GitStatusService.swift
//  aizen
//
//  Domain service for Git status queries
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
}

actor GitStatusService {
    private let executor: GitCommandExecutor

    init(executor: GitCommandExecutor) {
        self.executor = executor
    }

    // MARK: - Private Helpers

    private func parseAheadBehind(from line: String) -> (ahead: Int, behind: Int) {
        var ahead = 0
        var behind = 0

        if let aheadRange = line.range(of: "ahead (\\d+)", options: .regularExpression) {
            let aheadStr = line[aheadRange].split(separator: " ").last.map(String.init) ?? "0"
            ahead = Int(aheadStr) ?? 0
        }

        if let behindRange = line.range(of: "behind (\\d+)", options: .regularExpression) {
            let behindStr = line[behindRange].split(separator: " ").last.map(String.init) ?? "0"
            behind = Int(behindStr) ?? 0
        }

        return (ahead, behind)
    }

    // MARK: - Public Methods

    func getDetailedStatus(at path: String) async throws -> DetailedGitStatus {
        let output = try await executor.executeGit(arguments: ["status", "--porcelain", "-b"], at: path)

        var stagedFiles: [String] = []
        var modifiedFiles: [String] = []
        var untrackedFiles: [String] = []
        var conflictedFiles: [String] = []
        var currentBranch: String?
        var aheadBy = 0
        var behindBy = 0

        let lines = output.split(separator: "\n").map(String.init)

        for line in lines {
            if line.hasPrefix("##") {
                // Parse branch info: ## main...origin/main [ahead 2, behind 1]
                // Or: ## No commits yet on main
                let branchLine = line.replacingOccurrences(of: "## ", with: "")

                // Handle "No commits yet on <branch>" format
                if branchLine.hasPrefix("No commits yet on ") {
                    currentBranch = branchLine.replacingOccurrences(of: "No commits yet on ", with: "")
                } else if let dotIndex = branchLine.firstIndex(of: ".") {
                    currentBranch = String(branchLine[..<dotIndex])
                } else if let spaceIndex = branchLine.firstIndex(of: " ") {
                    currentBranch = String(branchLine[..<spaceIndex])
                } else {
                    currentBranch = branchLine
                }

                let (ahead, behind) = parseAheadBehind(from: line)
                aheadBy = ahead
                behindBy = behind
                continue
            }

            // Parse file status: XY filename
            guard line.count >= 3 else { continue }

            let statusPrefix = String(line.prefix(2))
            var fileName = String(line.dropFirst(3))

            let stagingStatus = statusPrefix.first ?? " "
            let workingStatus = statusPrefix.last ?? " "

            // Handle renames: "R  old/path.swift -> new/path.swift"
            // Git expects just the new path for staging operations
            if statusPrefix.hasPrefix("R") || statusPrefix.hasPrefix("C") {
                // Extract new path from "old -> new" format
                if let arrowRange = fileName.range(of: " -> ") {
                    fileName = String(fileName[arrowRange.upperBound...])
                }
            }

            // Check for conflicts (UU, AA, DD, AU, UA, DU, UD)
            if stagingStatus == "U" || workingStatus == "U" ||
               (stagingStatus == "A" && workingStatus == "A") ||
               (stagingStatus == "D" && workingStatus == "D") {
                conflictedFiles.append(fileName)
                continue
            }

            // Check for untracked files first
            if statusPrefix == "??" {
                untrackedFiles.append(fileName)
                continue
            }

            // Categorize files (can be in both lists if both staged and modified)
            if stagingStatus != " " && stagingStatus != "?" {
                // File has staged changes
                stagedFiles.append(fileName)
            }

            if workingStatus == "M" || workingStatus == "D" {
                // File has unstaged changes in working directory
                modifiedFiles.append(fileName)
            }
        }

        return DetailedGitStatus(
            stagedFiles: stagedFiles,
            modifiedFiles: modifiedFiles,
            untrackedFiles: untrackedFiles,
            conflictedFiles: conflictedFiles,
            currentBranch: currentBranch,
            aheadBy: aheadBy,
            behindBy: behindBy
        )
    }

    func getCurrentBranch(at path: String) async throws -> String {
        let output = try await executor.executeGit(arguments: ["branch", "--show-current"], at: path)
        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func getBranchStatus(at path: String) async throws -> (ahead: Int, behind: Int) {
        let output = try await executor.executeGit(arguments: ["status", "-sb", "--porcelain"], at: path)

        // Parse output like "## main...origin/main [ahead 2, behind 1]"
        let lines = output.split(separator: "\n")
        guard let statusLine = lines.first, statusLine.hasPrefix("##") else {
            return (0, 0)
        }

        return parseAheadBehind(from: String(statusLine))
    }

    func hasUnsavedChanges(at worktreePath: String) async throws -> Bool {
        let output = try await executor.executeGit(arguments: ["status", "--porcelain"], at: worktreePath)
        return !output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
