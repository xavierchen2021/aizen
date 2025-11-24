//
//  AgentFileSystemDelegate.swift
//  aizen
//
//  Created by Uladzislau Yakauleu on 17.10.25.
//

import Foundation

/// Actor responsible for handling file system operations for agent sessions
actor AgentFileSystemDelegate {

    // MARK: - Initialization

    init() {}

    // MARK: - File Operations

    /// Handle file read request from agent
    /// - Parameters:
    ///   - path: File path to read
    ///   - sessionId: Session identifier (for tracking/logging)
    ///   - line: Starting line number (0-indexed position)
    ///   - limit: Number of lines to read
    func handleFileReadRequest(_ path: String, sessionId: String, line: Int?, limit: Int?) async throws -> ReadTextFileResponse {
        let url = URL(fileURLWithPath: path)
        let content = try String(contentsOf: url, encoding: .utf8)
        let lines = content.components(separatedBy: .newlines)

        let filteredContent: String
        if let startLine = line, let lineLimit = limit {
            let startIdx = max(0, startLine)
            let endIdx = min(lines.count, startLine + lineLimit)
            filteredContent = lines[startIdx..<endIdx].joined(separator: "\n")
        } else if let startLine = line {
            let startIdx = max(0, startLine)
            filteredContent = lines[startIdx...].joined(separator: "\n")
        } else {
            filteredContent = content
        }

        return ReadTextFileResponse(content: filteredContent, totalLines: lines.count, _meta: nil)
    }

    /// Handle file write request from agent
    func handleFileWriteRequest(_ path: String, content: String, sessionId: String) async throws -> WriteTextFileResponse {
        let url = URL(fileURLWithPath: path)
        try content.write(to: url, atomically: true, encoding: .utf8)
        return WriteTextFileResponse(_meta: nil)
    }
}
