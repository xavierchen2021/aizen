//
//  GitRemoteService.swift
//  aizen
//
//  Domain service for Git remote operations using libgit2
//

import Foundation

actor GitRemoteService {

    func fetch(at path: String) async throws {
        try await Task.detached {
            let repo = try Libgit2Repository(path: path)
            try repo.fetch()
        }.value
    }

    func pull(at path: String) async throws {
        try await Task.detached {
            let repo = try Libgit2Repository(path: path)
            try repo.pull()
        }.value
    }

    func push(at path: String, setUpstream: Bool = false, force: Bool = false) async throws {
        try await Task.detached {
            let repo = try Libgit2Repository(path: path)

            // Build refspecs if force push
            var refspecs: [String]? = nil
            if force {
                if let branch = try repo.currentBranchName() {
                    refspecs = ["+refs/heads/\(branch):refs/heads/\(branch)"]
                }
            }

            try repo.push(refspecs: refspecs, setUpstream: setUpstream)
        }.value
    }

    func clone(url: String, to path: String) async throws {
        try await Task.detached {
            _ = try Libgit2Repository(cloneFrom: url, to: path)
        }.value
    }

    func initRepository(at path: String, initialBranch: String = "main") async throws {
        try await Task.detached {
            // Create directory if doesn't exist
            try FileManager.default.createDirectory(
                atPath: path,
                withIntermediateDirectories: true,
                attributes: nil
            )

            // Initialize git repository
            _ = try Libgit2Repository(initAt: path)

            // Set initial branch name - libgit2 defaults to "master", so rename if needed
            if initialBranch != "master" {
                // Use shell command for this edge case
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
                process.arguments = ["symbolic-ref", "HEAD", "refs/heads/\(initialBranch)"]
                process.currentDirectoryURL = URL(fileURLWithPath: path)
                process.standardOutput = FileHandle.nullDevice
                process.standardError = FileHandle.nullDevice
                try process.run()
                process.waitUntilExit()
            }
        }.value
    }

    func getRepositoryName(at path: String) async throws -> String {
        return try await Task.detached {
            let repo = try Libgit2Repository(path: path)
            return try repo.repositoryName()
        }.value
    }
}
