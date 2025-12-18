//
//  GitIndexWatcher.swift
//  aizen
//
//  Monitors .git/index file and working directory for changes
//  Uses polling approach (more reliable than FSEvents for .git files)
//

import Foundation

class GitIndexWatcher {
    private let worktreePath: String
    private let gitIndexPath: String
    private let pollInterval: TimeInterval = 1.0  // Poll every 1 second
    private let workdirCheckInterval: TimeInterval = 3.0  // Check workdir less frequently
    private let debounceInterval: TimeInterval = 0.5  // Debounce rapid changes
    private var pollingTask: Task<Void, Never>?
    private var debounceTask: Task<Void, Never>?
    private var pollCount: Int = 0
    private let lastIndexModificationDateLock = NSLock()
    private var _lastIndexModificationDate: Date?
    private var lastIndexModificationDate: Date? {
        get {
            lastIndexModificationDateLock.lock()
            defer { lastIndexModificationDateLock.unlock() }
            return _lastIndexModificationDate
        }
        set {
            lastIndexModificationDateLock.lock()
            defer { lastIndexModificationDateLock.unlock() }
            _lastIndexModificationDate = newValue
        }
    }
    private let lastWorkdirChecksumLock = NSLock()
    private var _lastWorkdirChecksum: String?
    private var lastWorkdirChecksum: String? {
        get {
            lastWorkdirChecksumLock.lock()
            defer { lastWorkdirChecksumLock.unlock() }
            return _lastWorkdirChecksum
        }
        set {
            lastWorkdirChecksumLock.lock()
            defer { lastWorkdirChecksumLock.unlock() }
            _lastWorkdirChecksum = newValue
        }
    }
    private let onChangeLock = NSLock()
    private var _onChange: (@Sendable () -> Void)?
    private var onChange: (@Sendable () -> Void)? {
        get {
            onChangeLock.lock()
            defer { onChangeLock.unlock() }
            return _onChange
        }
        set {
            onChangeLock.lock()
            defer { onChangeLock.unlock() }
            _onChange = newValue
        }
    }
    private let pendingCallbackLock = NSLock()
    private var _hasPendingCallback = false
    private var hasPendingCallback: Bool {
        get {
            pendingCallbackLock.lock()
            defer { pendingCallbackLock.unlock() }
            return _hasPendingCallback
        }
        set {
            pendingCallbackLock.lock()
            defer { pendingCallbackLock.unlock() }
            _hasPendingCallback = newValue
        }
    }

    init(worktreePath: String) {
        self.worktreePath = worktreePath

        // Resolve .git path (handles linked worktrees)
        let gitPath = (worktreePath as NSString).appendingPathComponent(".git")

        // Check if .git is a file (linked worktree) or directory
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: gitPath, isDirectory: &isDirectory)

        if exists && !isDirectory.boolValue {
            // Linked worktree - .git is a file containing gitdir path
            if let gitContent = try? String(contentsOfFile: gitPath, encoding: .utf8),
               gitContent.hasPrefix("gitdir: ") {
                let gitdir = gitContent
                    .replacingOccurrences(of: "gitdir: ", with: "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)

                // gitdir points to .git/worktrees/<name>
                // The index is at .git/worktrees/<name>/index (not worktree/.git/index)
                self.gitIndexPath = (gitdir as NSString).appendingPathComponent("index")
            } else {
                // Fallback if we can't parse
                self.gitIndexPath = (worktreePath as NSString).appendingPathComponent(".git/index")
            }
        } else {
            // Primary worktree - standard .git/index path
            self.gitIndexPath = (worktreePath as NSString).appendingPathComponent(".git/index")
        }
    }

    func startWatching(onChange: @escaping @Sendable () -> Void) {
        self.onChange = onChange

        guard FileManager.default.fileExists(atPath: gitIndexPath) else {
            return
        }

        // Get initial modification date and checksum
        lastIndexModificationDate = try? FileManager.default.attributesOfItem(atPath: gitIndexPath)[.modificationDate] as? Date
        Task {
            self.lastWorkdirChecksum = await self.computeWorkdirChecksum()
        }

        // Start polling task on BACKGROUND thread
        pollingTask = Task.detached { [weak self] in
            guard let self = self else { return }

            // Calculate how many polls equal the workdir check interval
            let workdirCheckFrequency = max(1, Int(self.workdirCheckInterval / self.pollInterval))

            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .seconds(self.pollInterval))

                    guard !Task.isCancelled else { break }

                    self.pollCount += 1
                    var hasChanges = false
                    var indexChanged = false

                    // Check if index was modified (cheap file stat)
                    if let attrs = try? FileManager.default.attributesOfItem(atPath: self.gitIndexPath),
                       let modDate = attrs[.modificationDate] as? Date {

                        if let lastDate = self.lastIndexModificationDate, modDate > lastDate {
                            self.lastIndexModificationDate = modDate
                            hasChanges = true
                            indexChanged = true
                        } else if self.lastIndexModificationDate == nil {
                            self.lastIndexModificationDate = modDate
                        }
                    }

                    // Only check working directory status when:
                    // 1. The index file changed (indicating a git operation)
                    // 2. OR periodically (every workdirCheckFrequency polls)
                    let shouldCheckWorkdir = indexChanged || (self.pollCount % workdirCheckFrequency == 0)

                    if shouldCheckWorkdir {
                        let currentChecksum = await self.computeWorkdirChecksum()
                        if currentChecksum != self.lastWorkdirChecksum {
                            self.lastWorkdirChecksum = currentChecksum
                            hasChanges = true
                        }
                    }

                    if hasChanges {
                        self.scheduleDebounceCallback()
                    }
                } catch {
                    break
                }
            }
        }
    }

    func stopWatching() {
        pollingTask?.cancel()
        pollingTask = nil
        debounceTask?.cancel()
        debounceTask = nil
        onChange = nil
        lastIndexModificationDate = nil
        lastWorkdirChecksum = nil
        hasPendingCallback = false
        pollCount = 0
    }

    private func scheduleDebounceCallback() {
        // If already pending, the existing debounce will fire
        guard !hasPendingCallback else { return }
        hasPendingCallback = true

        // Cancel any existing debounce task
        debounceTask?.cancel()

        debounceTask = Task.detached { [weak self] in
            guard let self = self else { return }

            // Wait for debounce interval
            do {
                try await Task.sleep(for: .seconds(self.debounceInterval))
            } catch {
                return  // Cancelled
            }

            guard !Task.isCancelled else { return }

            // Clear pending flag and fire callback
            self.hasPendingCallback = false
            self.onChange?()
        }
    }

    private func computeWorkdirChecksum() async -> String {
        // Get git status output hash to detect working directory changes
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .background).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
                process.arguments = ["status", "--porcelain"]
                process.currentDirectoryURL = URL(fileURLWithPath: self.worktreePath)

                let pipe = Pipe()
                let errorPipe = Pipe()
                process.standardOutput = pipe
                process.standardError = errorPipe

                defer {
                    try? pipe.fileHandleForReading.close()
                    try? errorPipe.fileHandleForReading.close()
                }

                do {
                    try process.run()
                    process.waitUntilExit()

                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    let result = String(data: data, encoding: .utf8) ?? ""
                    continuation.resume(returning: result)
                } catch {
                    continuation.resume(returning: "")
                }
            }
        }
    }
}
