//
//  GitLogService.swift
//  aizen
//
//  Service for fetching git commit history
//

import Foundation

actor GitLogService {
    private let executor: GitCommandExecutor

    init(executor: GitCommandExecutor = GitCommandExecutor()) {
        self.executor = executor
    }

    /// Get commit history for a repository with pagination
    /// - Parameters:
    ///   - repoPath: Path to the git repository
    ///   - limit: Maximum number of commits to fetch
    ///   - skip: Number of commits to skip (for pagination)
    /// - Returns: Array of GitCommit objects
    func getCommitHistory(at repoPath: String, limit: Int = 30, skip: Int = 0) async throws -> [GitCommit] {
        // Use --shortstat in the log command to get stats in one call
        // Format: hash|short_hash|subject|author|date followed by shortstat line
        let format = "%H%x00%h%x00%s%x00%an%x00%aI"

        let output = try await executor.executeGit(
            arguments: [
                "log",
                "--format=\(format)",
                "--shortstat",
                "-n", "\(limit)",
                "--skip=\(skip)"
            ],
            at: repoPath
        )

        return parseLogOutput(output)
    }

    /// Parse log output with shortstat
    private func parseLogOutput(_ output: String) -> [GitCommit] {
        var commits: [GitCommit] = []
        let lines = output.components(separatedBy: .newlines)

        var i = 0
        while i < lines.count {
            let line = lines[i]

            // Skip empty lines
            if line.isEmpty {
                i += 1
                continue
            }

            // Check if this is a commit line (contains null separators)
            let parts = line.components(separatedBy: "\0")
            if parts.count >= 5 {
                let hash = parts[0]
                let shortHash = parts[1]
                let message = parts[2]
                let author = parts[3]
                let dateString = parts[4]

                let date = parseISO8601Date(dateString) ?? Date()

                // Look for shortstat in the next non-empty line
                var filesChanged = 0
                var additions = 0
                var deletions = 0

                // Check next lines for shortstat
                var j = i + 1
                while j < lines.count && j < i + 3 {
                    let nextLine = lines[j]
                    if nextLine.contains("changed") || nextLine.contains("insertion") || nextLine.contains("deletion") {
                        let stats = parseShortstat(nextLine)
                        filesChanged = stats.filesChanged
                        additions = stats.additions
                        deletions = stats.deletions
                        break
                    } else if !nextLine.isEmpty && nextLine.contains("\0") {
                        // Next commit line, no stats for this commit
                        break
                    }
                    j += 1
                }

                let commit = GitCommit(
                    id: hash,
                    shortHash: shortHash,
                    message: message,
                    author: author,
                    date: date,
                    filesChanged: filesChanged,
                    additions: additions,
                    deletions: deletions
                )

                commits.append(commit)
            }

            i += 1
        }

        return commits
    }

    /// Get diff output for a specific commit
    func getCommitDiff(hash: String, at repoPath: String) async throws -> String {
        return try await executor.executeGit(
            arguments: ["show", "--format=", hash],
            at: repoPath
        )
    }

    /// Parse shortstat output like "3 files changed, 10 insertions(+), 5 deletions(-)"
    private func parseShortstat(_ line: String) -> (filesChanged: Int, additions: Int, deletions: Int) {
        var filesChanged = 0
        var additions = 0
        var deletions = 0

        // Parse "X file(s) changed"
        if let range = line.range(of: #"(\d+) files? changed"#, options: .regularExpression) {
            let match = line[range]
            if let number = Int(match.components(separatedBy: " ").first ?? "") {
                filesChanged = number
            }
        }

        // Parse "X insertion(s)(+)"
        if let range = line.range(of: #"(\d+) insertions?\(\+\)"#, options: .regularExpression) {
            let match = line[range]
            if let number = Int(match.components(separatedBy: " ").first ?? "") {
                additions = number
            }
        }

        // Parse "X deletion(s)(-)"
        if let range = line.range(of: #"(\d+) deletions?\(-\)"#, options: .regularExpression) {
            let match = line[range]
            if let number = Int(match.components(separatedBy: " ").first ?? "") {
                deletions = number
            }
        }

        return (filesChanged, additions, deletions)
    }

    /// Parse ISO 8601 date string
    private func parseISO8601Date(_ dateString: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        if let date = formatter.date(from: dateString) {
            return date
        }

        // Try without fractional seconds
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: dateString)
    }
}
