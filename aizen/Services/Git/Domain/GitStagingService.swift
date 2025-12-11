//
//  GitStagingService.swift
//  aizen
//
//  Domain service for Git staging operations using libgit2
//

import Foundation

actor GitStagingService {

    func stageFile(at path: String, file: String) async throws {
        try await Task.detached {
            let repo = try Libgit2Repository(path: path)
            try repo.stageFile(file)
        }.value
    }

    func unstageFile(at path: String, file: String) async throws {
        try await Task.detached {
            let repo = try Libgit2Repository(path: path)
            try repo.unstageFile(file)
        }.value
    }

    func stageAll(at path: String) async throws {
        try await Task.detached {
            let repo = try Libgit2Repository(path: path)
            try repo.stageAll()
        }.value
    }

    func unstageAll(at path: String) async throws {
        try await Task.detached {
            let repo = try Libgit2Repository(path: path)
            try repo.unstageAll()
        }.value
    }

    func commit(at path: String, message: String) async throws {
        try await Task.detached {
            let repo = try Libgit2Repository(path: path)
            _ = try repo.commit(message: message)
        }.value
    }

    func amendCommit(at path: String, message: String) async throws {
        try await Task.detached {
            let repo = try Libgit2Repository(path: path)
            _ = try repo.commit(message: message, amend: true)
        }.value
    }

    func commitWithSignoff(at path: String, message: String) async throws {
        try await Task.detached {
            let repo = try Libgit2Repository(path: path)
            let sigInfo = try repo.getSignatureInfo()
            let signoffMessage = "\(message)\n\nSigned-off-by: \(sigInfo.name) <\(sigInfo.email)>"
            _ = try repo.commit(message: signoffMessage)
        }.value
    }

    func discardChanges(at path: String, file: String) async throws {
        try await Task.detached {
            let repo = try Libgit2Repository(path: path)
            try repo.discardChanges(file)
        }.value
    }
}
