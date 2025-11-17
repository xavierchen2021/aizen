//
//  GitDiffProvider.swift
//  aizen
//
//  Git diff provider for tracking file changes in the editor gutter
//

import Foundation
import CodeEditSourceEditor

/// Provides git diff information for files
actor GitDiffProvider {
    private let executor: GitCommandExecutor

    init(executor: GitCommandExecutor = GitCommandExecutor()) {
        self.executor = executor
    }

    /// Get git diff status for each line in a file
    /// - Parameters:
    ///   - filePath: Absolute path to the file
    ///   - repoPath: Path to the git repository root
    /// - Returns: Dictionary mapping line numbers to their diff status
    func getLineDiff(filePath: String, repoPath: String) async throws -> [Int: GitDiffLineStatus] {
        // Get relative path from repo root
        let fileURL = URL(fileURLWithPath: filePath)
        let repoURL = URL(fileURLWithPath: repoPath)

        guard let relativePath = fileURL.path.replacingOccurrences(
            of: repoURL.path + "/",
            with: ""
        ).addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else {
            return [:]
        }

        // Run git diff to get changes for this file
        // --unified=0 gives us just the changed lines without context
        // HEAD compares working directory to last commit
        let result = try await executor.executeGit(
            arguments: ["diff", "--unified=0", "HEAD", "--", relativePath.removingPercentEncoding ?? relativePath],
            at: repoPath
        )

        return parseDiffOutput(result)
    }

    /// Parse git diff output into line status mapping
    private func parseDiffOutput(_ diffOutput: String) -> [Int: GitDiffLineStatus] {
        var lineStatus: [Int: GitDiffLineStatus] = [:]

        let lines = diffOutput.components(separatedBy: .newlines)

        for line in lines {
            // Look for hunk headers like: @@ -10,3 +12,4 @@
            if line.hasPrefix("@@") {
                let parts = line.components(separatedBy: " ")
                guard parts.count >= 4 else { continue }

                let newSection = parts[2] // +12,4 format
                guard newSection.hasPrefix("+") else { continue }

                let numbers = newSection.dropFirst().components(separatedBy: ",")
                guard let startLine = Int(numbers[0]) else { continue }
                let count = numbers.count > 1 ? (Int(numbers[1]) ?? 1) : 1

                // Parse what kind of change this is by looking at old section
                let oldSection = parts[1] // -10,3 format
                let oldNumbers = oldSection.dropFirst().components(separatedBy: ",")
                let oldCount = oldNumbers.count > 1 ? (Int(oldNumbers[1]) ?? 1) : 1

                if oldCount == 0 {
                    // Lines were added (old count is 0)
                    for offset in 0..<count {
                        lineStatus[startLine + offset] = .added
                    }
                } else if count == 0 {
                    // Lines were deleted (new count is 0)
                    if let oldStart = Int(oldNumbers[0]) {
                        lineStatus[oldStart] = .deleted(afterLine: startLine - 1)
                    }
                } else {
                    // Lines were modified
                    for offset in 0..<count {
                        lineStatus[startLine + offset] = .modified
                    }
                }
            }
        }

        return lineStatus
    }

    /// Check if a file is tracked by git
    func isFileTracked(filePath: String, repoPath: String) async -> Bool {
        let fileURL = URL(fileURLWithPath: filePath)
        let repoURL = URL(fileURLWithPath: repoPath)

        guard let relativePath = fileURL.path.replacingOccurrences(
            of: repoURL.path + "/",
            with: ""
        ).addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else {
            return false
        }

        do {
            let result = try await executor.executeGit(
                arguments: ["ls-files", "--error-unmatch", relativePath.removingPercentEncoding ?? relativePath],
                at: repoPath
            )
            return !result.isEmpty
        } catch {
            return false
        }
    }
}
