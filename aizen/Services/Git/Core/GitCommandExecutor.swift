//
//  GitCommandExecutor.swift
//  aizen
//
//  Low-level Git command execution
//  Shared by all domain services
//

import Foundation

enum GitError: LocalizedError {
    case commandFailed(message: String)
    case invalidPath
    case notAGitRepository
    case worktreeNotFound
    case timeout

    var errorDescription: String? {
        switch self {
        case .commandFailed(let message):
            return String(localized: "error.git.commandFailed \(message)")
        case .invalidPath:
            return String(localized: "error.git.invalidPath")
        case .notAGitRepository:
            return String(localized: "error.git.notRepository")
        case .worktreeNotFound:
            return String(localized: "error.git.worktreeNotFound")
        case .timeout:
            return String(localized: "error.git.timeout")
        }
    }
}

actor GitCommandExecutor {

    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    private func getShellEnvironment() -> [String: String] {
        return ShellEnvironment.loadUserShellEnvironment()
    }

    /// Execute a git command fully asynchronously without blocking
    func executeGit(arguments: [String], at workingDirectory: String?, timeout: TimeInterval = 30) async throws -> String {
        return try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
            process.arguments = arguments

            if let workingDirectory = workingDirectory {
                process.currentDirectoryURL = URL(fileURLWithPath: workingDirectory)
            }

            var environment = self.getShellEnvironment()
            environment["GIT_PAGER"] = "cat"
            environment["GIT_TERMINAL_PROMPT"] = "0"
            environment["GIT_SSH_COMMAND"] = "ssh -o BatchMode=yes -o ConnectTimeout=10"
            environment["GIT_ASKPASS"] = "echo"
            process.environment = environment

            let pipe = Pipe()
            let errorPipe = Pipe()
            process.standardOutput = pipe
            process.standardError = errorPipe

            var hasResumed = false
            let resumeLock = NSLock()

            // Collect output data as it comes in to avoid pipe buffer deadlock
            var outputData = Data()
            var errorData = Data()
            let dataLock = NSLock()

            pipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                if !data.isEmpty {
                    dataLock.lock()
                    outputData.append(data)
                    dataLock.unlock()
                }
            }

            errorPipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                if !data.isEmpty {
                    dataLock.lock()
                    errorData.append(data)
                    dataLock.unlock()
                }
            }

            // Set up timeout
            let timer = DispatchSource.makeTimerSource(queue: .global())
            timer.schedule(deadline: .now() + timeout)
            timer.setEventHandler {
                resumeLock.lock()
                defer { resumeLock.unlock() }

                if !hasResumed {
                    hasResumed = true
                    pipe.fileHandleForReading.readabilityHandler = nil
                    errorPipe.fileHandleForReading.readabilityHandler = nil
                    process.terminate()
                    continuation.resume(throwing: GitError.timeout)
                }
                timer.cancel()
            }
            timer.resume()

            // Set up async termination handler
            process.terminationHandler = { [dataLock] process in
                // Read any remaining data
                pipe.fileHandleForReading.readabilityHandler = nil
                errorPipe.fileHandleForReading.readabilityHandler = nil

                dataLock.lock()
                let remainingOut = pipe.fileHandleForReading.readDataToEndOfFile()
                outputData.append(remainingOut)
                let remainingErr = errorPipe.fileHandleForReading.readDataToEndOfFile()
                errorData.append(remainingErr)
                dataLock.unlock()

                resumeLock.lock()
                defer { resumeLock.unlock() }

                if hasResumed {
                    return
                }
                hasResumed = true
                timer.cancel()

                dataLock.lock()
                let stdout = String(data: outputData, encoding: .utf8) ?? ""
                let stderr = String(data: errorData, encoding: .utf8) ?? ""
                dataLock.unlock()

                if process.terminationStatus != 0 {
                    let errorMessage = stderr.isEmpty ? String(localized: "error.git.unknownError") : stderr
                    continuation.resume(throwing: GitError.commandFailed(message: errorMessage))
                } else {
                    continuation.resume(returning: stdout)
                }
            }

            do {
                try process.run()
            } catch {
                resumeLock.lock()
                defer { resumeLock.unlock() }

                if !hasResumed {
                    hasResumed = true
                    timer.cancel()
                    pipe.fileHandleForReading.readabilityHandler = nil
                    errorPipe.fileHandleForReading.readabilityHandler = nil
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    /// Check if a path is a git repository
    func isGitRepository(at path: String) -> Bool {
        let gitPath = (path as NSString).appendingPathComponent(".git")
        var isDirectory: ObjCBool = false
        let exists = fileManager.fileExists(atPath: gitPath, isDirectory: &isDirectory)

        if exists && isDirectory.boolValue {
            return true
        }

        // Check if it's a worktree (has .git file pointing to main repo)
        if fileManager.fileExists(atPath: gitPath) {
            return true
        }

        return false
    }

    /// Get main repository path (handles worktrees)
    func getMainRepositoryPath(at path: String) -> String {
        let gitPath = (path as NSString).appendingPathComponent(".git")

        if let gitContent = try? String(contentsOfFile: gitPath, encoding: .utf8),
           gitContent.hasPrefix("gitdir: ") {
            // Parse gitdir path and extract main repo location
            let gitdir = gitContent
                .replacingOccurrences(of: "gitdir: ", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)

            // gitdir points to .git/worktrees/<name>, we need to go up to main repo
            let gitdirURL = URL(fileURLWithPath: gitdir)
            let mainGitPath = gitdirURL.deletingLastPathComponent().deletingLastPathComponent().path
            return mainGitPath.replacingOccurrences(of: "/.git", with: "")
        }

        // This is the main repository
        return path
    }
}
