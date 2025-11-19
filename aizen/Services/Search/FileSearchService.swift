//
//  FileSearchService.swift
//  aizen
//
//  Created on 2025-11-19.
//

import Foundation

struct FileSearchIndexResult: Identifiable, Sendable {
    let path: String
    let relativePath: String
    let isDirectory: Bool
    var matchScore: Double = 0

    var id: String { path }
}

actor FileSearchService {
    static let shared = FileSearchService()

    private var cachedResults: [String: [FileSearchIndexResult]] = [:]
    private var recentFiles: [String: [String]] = [:]
    private let maxRecentFiles = 10
    private var gitignorePatterns: [String] = []

    private init() {}

    // Index files in directory recursively
    func indexDirectory(_ path: String) async throws -> [FileSearchIndexResult] {
        // Check cache first
        if let cached = cachedResults[path] {
            return cached
        }

        // Load gitignore patterns
        await loadGitignorePatterns(at: path)

        var results: [FileSearchIndexResult] = []
        let fileManager = FileManager.default

        guard let enumerator = fileManager.enumerator(
            at: URL(fileURLWithPath: path),
            includingPropertiesForKeys: [.isDirectoryKey, .isHiddenKey],
            options: [.skipsPackageDescendants]
        ) else {
            return []
        }

        let basePath = path

        while let fileURL = enumerator.nextObject() as? URL {
            // Skip hidden files and directories
            if let resourceValues = try? fileURL.resourceValues(forKeys: [.isHiddenKey]),
               resourceValues.isHidden == true {
                continue
            }

            let isDirectory = fileURL.hasDirectoryPath

            // Skip directories - only index files
            if isDirectory {
                let dirName = fileURL.lastPathComponent
                let dirRelativePath = fileURL.path.replacingOccurrences(of: basePath + "/", with: "")
                if matchesGitignore(dirRelativePath) || matchesGitignore(dirName) {
                    enumerator.skipDescendants()
                }
                continue
            }

            let fileName = fileURL.lastPathComponent
            let fullPath = fileURL.path
            let relativePath = fullPath.replacingOccurrences(of: basePath + "/", with: "")

            // Skip if matches gitignore patterns
            if matchesGitignore(relativePath) || matchesGitignore(fileName) {
                continue
            }

            let result = FileSearchIndexResult(
                path: fullPath,
                relativePath: relativePath,
                isDirectory: false
            )
            results.append(result)
        }

        // Cache results
        cachedResults[path] = results
        return results
    }

    // Load gitignore patterns from .gitignore file
    private func loadGitignorePatterns(at path: String) async {
        gitignorePatterns = []
        let gitignorePath = (path as NSString).appendingPathComponent(".gitignore")

        guard let content = try? String(contentsOfFile: gitignorePath, encoding: .utf8) else {
            // If no .gitignore, add minimal essential patterns
            gitignorePatterns = [".git"]
            return
        }

        gitignorePatterns = content
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") }

        // Always ignore .git directory even if not in .gitignore
        if !gitignorePatterns.contains(".git") {
            gitignorePatterns.append(".git")
        }
    }

    // Check if path matches gitignore patterns
    private func matchesGitignore(_ path: String) -> Bool {
        for pattern in gitignorePatterns {
            // Handle negation patterns (start with !)
            if pattern.hasPrefix("!") {
                continue // Skip negation for now (would need more complex logic)
            }

            var workingPattern = pattern
            var matchAnywhere = true

            // If pattern starts with /, it's anchored to root
            if workingPattern.hasPrefix("/") {
                workingPattern = String(workingPattern.dropFirst())
                matchAnywhere = false
            }

            // If pattern ends with /, it only matches directories
            let dirOnly = workingPattern.hasSuffix("/")
            if dirOnly {
                workingPattern = String(workingPattern.dropLast())
            }

            // Convert gitignore pattern to regex
            var regexPattern = "^"

            // If not anchored, match anywhere in path
            if matchAnywhere {
                regexPattern = "(^|.*/)"
            }

            // Build regex pattern
            for char in workingPattern {
                switch char {
                case "*":
                    // ** matches across directories, * matches within directory
                    if workingPattern.contains("**") {
                        regexPattern += ".*"
                    } else {
                        regexPattern += "[^/]*"
                    }
                case "?":
                    regexPattern += "[^/]"
                case ".":
                    regexPattern += "\\."
                case "+", "(", ")", "[", "]", "{", "}", "^", "$", "|", "\\":
                    regexPattern += "\\\(char)"
                default:
                    regexPattern.append(char)
                }
            }

            // Handle ** properly
            regexPattern = regexPattern.replacingOccurrences(of: "[^/]*[^/]*", with: ".*")

            // End pattern
            if dirOnly {
                regexPattern += "(/|$)"
            } else {
                regexPattern += "(/.*)?$"
            }

            // Try to match
            if let regex = try? NSRegularExpression(pattern: regexPattern, options: []) {
                let range = NSRange(path.startIndex..., in: path)
                if regex.firstMatch(in: path, range: range) != nil {
                    return true
                }
            }

            // Simple fallback: exact component match
            let pathComponents = path.components(separatedBy: "/")
            let cleanPattern = workingPattern.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            if pathComponents.contains(cleanPattern) {
                return true
            }
        }

        return false
    }

    // Fuzzy search with scoring
    func search(query: String, in results: [FileSearchIndexResult], worktreePath: String) async -> [FileSearchIndexResult] {
        guard !query.isEmpty else {
            // Return recent files when query is empty
            return getRecentFileResults(for: worktreePath, from: results)
        }

        let lowercaseQuery = query.lowercased()
        var scoredResults: [FileSearchIndexResult] = []

        for var result in results {
            let targetName = result.path
                .split(separator: "/")
                .last
                .map { String($0).lowercased() } ?? result.path.lowercased()
            let score = fuzzyMatch(query: lowercaseQuery, target: targetName)
            if score > 0 {
                result.matchScore = score
                scoredResults.append(result)
            }
        }

        // Sort by score (higher is better)
        return scoredResults.sorted { $0.matchScore > $1.matchScore }
    }

    // Track recently opened files
    func addRecentFile(_ path: String, worktreePath: String) {
        var files = recentFiles[worktreePath] ?? []
        files.removeAll { $0 == path }
        files.insert(path, at: 0)
        if files.count > maxRecentFiles {
            files.removeLast()
        }
        recentFiles[worktreePath] = files
    }

    // Get recent files as results
    private func getRecentFileResults(for worktreePath: String, from allResults: [FileSearchIndexResult]) -> [FileSearchIndexResult] {
        guard let files = recentFiles[worktreePath] else { return [] }

        var results: [FileSearchIndexResult] = []
        for recentPath in files {
            if let result = allResults.first(where: { $0.path == recentPath }) {
                results.append(result)
            }
        }
        return results
    }

    // Clear cache for specific path
    func clearCache(for path: String) {
        cachedResults.removeValue(forKey: path)
        recentFiles.removeValue(forKey: path)
    }

    // Clear all caches
    func clearAllCaches() {
        cachedResults.removeAll()
        recentFiles.removeAll()
    }

    // MARK: - Private Helpers

    // Fuzzy matching algorithm with scoring
    private func fuzzyMatch(query: String, target: String) -> Double {
        guard !query.isEmpty else { return 0 }

        var score: Double = 0
        var queryIndex = query.startIndex
        var lastMatchIndex: String.Index?
        var consecutiveMatches = 0

        // Bonus for exact match
        if target == query {
            return 1000.0
        }

        // Bonus for prefix match
        if target.hasPrefix(query) {
            return 500.0 + Double(query.count)
        }

        // Fuzzy matching
        for (targetIndex, targetChar) in target.enumerated() {
            if queryIndex < query.endIndex && targetChar == query[queryIndex] {
                // Base score for match
                score += 10.0

                // Bonus for consecutive matches
                if let last = lastMatchIndex, target.index(after: last) == target.index(target.startIndex, offsetBy: targetIndex) {
                    consecutiveMatches += 1
                    score += Double(consecutiveMatches) * 5.0
                } else {
                    consecutiveMatches = 0
                }

                // Bonus for matching start of word
                if targetIndex == 0 || target[target.index(target.startIndex, offsetBy: targetIndex - 1)] == "/" || target[target.index(target.startIndex, offsetBy: targetIndex - 1)] == "." {
                    score += 15.0
                }

                // Bonus for uppercase match (camelCase)
                if targetChar.isUppercase {
                    score += 10.0
                }

                lastMatchIndex = target.index(target.startIndex, offsetBy: targetIndex)
                queryIndex = query.index(after: queryIndex)
            }
        }

        // Check if all query characters were matched
        if queryIndex == query.endIndex {
            // Penalty for longer paths (prefer shorter paths)
            score -= Double(target.count) * 0.1
            return score
        }

        return 0
    }
}
