//
//  GitPanelWindowContent.swift
//  aizen
//
//  Main content view for the git panel window with toolbar tabs
//

import SwiftUI
import os.log

enum GitPanelTab: String, CaseIterable {
    case git = "Git"
    case history = "History"
    case comments = "Comments"

    var icon: String {
        switch self {
        case .git: return "tray.full"
        case .history: return "clock"
        case .comments: return "text.bubble"
        }
    }
}

struct GitPanelWindowContent: View {
    let context: GitChangesContext
    let repositoryManager: RepositoryManager
    @Binding var selectedTab: GitPanelTab
    let onClose: () -> Void

    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.aizen", category: "GitPanelWindow")
    @State private var selectedHistoryCommit: GitCommit?
    @State private var diffOutput: String = ""
    @State private var leftPanelWidth: CGFloat = 350
    @State private var visibleFile: String?
    @State private var scrollToFile: String?
    @State private var commentPopoverLine: DiffLine?
    @State private var commentPopoverFilePath: String?
    @State private var showAgentPicker: Bool = false
    @State private var cachedChangedFiles: [String] = []

    @StateObject private var reviewManager = ReviewSessionManager()

    @AppStorage("editorFontFamily") private var editorFontFamily: String = "Menlo"
    @AppStorage("diffFontSize") private var diffFontSize: Double = 11.0

    private let minLeftPanelWidth: CGFloat = 280
    private let maxLeftPanelWidth: CGFloat = 500

    private var worktree: Worktree { context.worktree }
    private var worktreePath: String { worktree.path ?? "" }
    private var gitRepositoryService: GitRepositoryService { context.service }

    private var gitOperations: WorktreeGitOperations {
        WorktreeGitOperations(
            gitRepositoryService: gitRepositoryService,
            repositoryManager: repositoryManager,
            worktree: worktree,
            logger: logger
        )
    }

    private var gitStatus: GitStatus {
        gitRepositoryService.currentStatus
    }

    private var allChangedFiles: [String] {
        cachedChangedFiles
    }

    var body: some View {
        HStack(spacing: 0) {
            // Left: Tab content
            leftPanel
                .frame(width: leftPanelWidth)

            // Resizable divider
            resizableDivider

            // Right: Diff view
            diffPanel
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear {
            if let path = worktree.path {
                gitRepositoryService.updateWorktreePath(path)
            }
            gitRepositoryService.reloadStatus()
            reviewManager.load(for: worktreePath)
            updateChangedFilesCache()
        }
        .onChange(of: gitStatus) { _ in
            updateChangedFilesCache()
        }
        .onChange(of: selectedHistoryCommit) { commit in
            Task {
                await loadDiff(for: commit)
            }
        }
        .sheet(item: $commentPopoverLine) { line in
            CommentPopover(
                diffLine: line,
                filePath: commentPopoverFilePath ?? "",
                existingComment: reviewManager.comments.first {
                    $0.filePath == commentPopoverFilePath && $0.lineNumber == line.lineNumber
                },
                onSave: { text in
                    if let existing = reviewManager.comments.first(where: {
                        $0.filePath == commentPopoverFilePath && $0.lineNumber == line.lineNumber
                    }) {
                        reviewManager.updateComment(id: existing.id, comment: text)
                    } else {
                        reviewManager.addComment(for: line, filePath: commentPopoverFilePath ?? "", comment: text)
                    }
                    commentPopoverLine = nil
                },
                onCancel: {
                    commentPopoverLine = nil
                },
                onDelete: reviewManager.comments.first(where: {
                    $0.filePath == commentPopoverFilePath && $0.lineNumber == line.lineNumber
                }).map { existing in
                    {
                        reviewManager.deleteComment(id: existing.id)
                        commentPopoverLine = nil
                    }
                }
            )
        }
        .sheet(isPresented: $showAgentPicker) {
            SendToAgentSheet(
                worktree: worktree,
                commentsMarkdown: reviewManager.exportToMarkdown(),
                onDismiss: {
                    showAgentPicker = false
                },
                onSend: {
                    reviewManager.clearAll()
                    onClose()
                }
            )
        }
    }

    // MARK: - Left Panel (Tab Content)

    @ViewBuilder
    private var leftPanel: some View {
        switch selectedTab {
        case .git:
            gitTabContent
        case .history:
            GitHistoryView(
                worktreePath: worktreePath,
                selectedCommit: selectedHistoryCommit,
                onSelectCommit: { commit in
                    selectedHistoryCommit = commit
                }
            )
        case .comments:
            ReviewCommentsPanel(
                reviewManager: reviewManager,
                onScrollToLine: { filePath, _ in
                    scrollToFile = filePath
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        scrollToFile = nil
                    }
                },
                onCopyAll: {
                    let markdown = reviewManager.exportToMarkdown()
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(markdown, forType: .string)
                },
                onSendToAgent: {
                    showAgentPicker = true
                }
            )
        }
    }

    private var gitTabContent: some View {
        GitSidebarView(
            worktreePath: worktreePath,
            onClose: onClose,
            gitStatus: gitStatus,
            isOperationPending: gitRepositoryService.isOperationPending,
            selectedDiffFile: visibleFile,
            onStageFile: { file in
                gitOperations.stageFile(file)
                reloadDiff()
            },
            onUnstageFile: { file in
                gitOperations.unstageFile(file)
                reloadDiff()
            },
            onStageAll: { completion in
                gitOperations.stageAll {
                    reloadDiff()
                    completion()
                }
            },
            onUnstageAll: {
                gitOperations.unstageAll()
                reloadDiff()
            },
            onCommit: { message in
                gitOperations.commit(message)
                reloadDiff()
            },
            onAmendCommit: { message in
                gitOperations.amendCommit(message)
                reloadDiff()
            },
            onCommitWithSignoff: { message in
                gitOperations.commitWithSignoff(message)
                reloadDiff()
            },
            onFileClick: { file in
                visibleFile = file
                scrollToFile = file
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    scrollToFile = nil
                }
            }
        )
    }

    // MARK: - Diff Panel

    private var diffPanelHeader: some View {
        HStack(spacing: 8) {
            Image(systemName: "arrow.triangle.branch")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)

            if let commit = selectedHistoryCommit {
                // Viewing a specific commit
                Text(commit.shortHash)
                    .font(.system(size: 13, weight: .medium, design: .monospaced))

                Text(commit.message)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer()

                Button("Back to Changes") {
                    selectedHistoryCommit = nil
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            } else {
                // Viewing working changes
                Text(gitStatus.currentBranch ?? "HEAD")
                    .font(.system(size: 13, weight: .medium))

                CopyButton(text: gitStatus.currentBranch ?? "", iconSize: 11)

                Spacer()

                HStack(spacing: 8) {
                    Text("+\(gitStatus.additions)")
                        .foregroundStyle(.green)
                    Text("-\(gitStatus.deletions)")
                        .foregroundStyle(.red)
                    Text("\(allChangedFiles.count) files")
                        .foregroundStyle(.secondary)
                }
                .font(.system(size: 12, weight: .medium, design: .monospaced))
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 44)
    }

    private var diffPanel: some View {
        VStack(spacing: 0) {
            diffPanelHeader
            Divider()

            if selectedHistoryCommit == nil && allChangedFiles.isEmpty {
                AllFilesDiffEmptyView()
            } else if diffOutput.isEmpty {
                VStack {
                    Spacer()
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("Loading diff...")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .padding(.top, 8)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                DiffView(
                    diffOutput: diffOutput,
                    fontSize: diffFontSize,
                    fontFamily: editorFontFamily,
                    repoPath: worktreePath,
                    scrollToFile: scrollToFile,
                    onFileVisible: { file in
                        visibleFile = file
                    },
                    onOpenFile: { file in
                        let fullPath = (worktreePath as NSString).appendingPathComponent(file)
                        NotificationCenter.default.post(
                            name: .openFileInEditor,
                            object: nil,
                            userInfo: ["path": fullPath]
                        )
                        onClose()
                    },
                    commentedLines: selectedHistoryCommit == nil ? reviewManager.commentedLineKeys : Set(),
                    onAddComment: selectedHistoryCommit == nil ? { line, filePath in
                        commentPopoverFilePath = filePath
                        commentPopoverLine = line
                    } : { _, _ in }
                )
            }
        }
        .task {
            await loadDiff(for: nil)
        }
        .onChange(of: diffOutput) { _ in
            validateCommentsAgainstDiff()
        }
    }

    // MARK: - Divider

    private var resizableDivider: some View {
        Rectangle()
            .fill(Color(NSColor.separatorColor))
            .frame(width: 1)
            .overlay(
                Rectangle()
                    .fill(Color.clear)
                    .frame(width: 8)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                let newWidth = leftPanelWidth + value.translation.width
                                leftPanelWidth = min(max(newWidth, minLeftPanelWidth), maxLeftPanelWidth)
                            }
                    )
                    .onHover { hovering in
                        if hovering {
                            NSCursor.resizeLeftRight.push()
                        } else {
                            NSCursor.pop()
                        }
                    }
            )
    }

    // MARK: - Helper Methods

    private func updateChangedFilesCache() {
        var files = Set<String>()
        files.formUnion(gitStatus.stagedFiles)
        files.formUnion(gitStatus.modifiedFiles)
        files.formUnion(gitStatus.untrackedFiles)
        files.formUnion(gitStatus.conflictedFiles)

        let sortedFiles = files.sorted()
        if sortedFiles != cachedChangedFiles {
            cachedChangedFiles = sortedFiles
        }
    }

    private func validateCommentsAgainstDiff() {
        guard selectedHistoryCommit == nil else { return }

        let filesInDiff = Set(allChangedFiles)
        let commentsToRemove = reviewManager.comments.filter { !filesInDiff.contains($0.filePath) }

        for comment in commentsToRemove {
            reviewManager.deleteComment(id: comment.id)
        }
    }

    private func loadDiff(for commit: GitCommit?) async {
        let executor = GitCommandExecutor()
        let path = worktreePath

        guard !path.isEmpty else { return }

        if let commit = commit {
            // Load diff for specific commit
            if let commitDiff = try? await executor.executeGit(
                arguments: ["show", "--format=", commit.id],
                at: path
            ) {
                diffOutput = commitDiff
            }
        } else {
            // Load working changes diff
            await loadWorkingDiff()
        }
    }

    private func loadWorkingDiff() async {
        let executor = GitCommandExecutor()
        let path = worktreePath

        guard !path.isEmpty else { return }

        // Try git diff HEAD first
        if let headDiff = try? await executor.executeGit(arguments: ["--no-pager", "diff", "HEAD"], at: path),
           !headDiff.isEmpty {
            diffOutput = headDiff
            return
        }

        // Fallback: cached diff
        if let cachedDiff = try? await executor.executeGit(arguments: ["--no-pager", "diff", "--cached"], at: path),
           !cachedDiff.isEmpty {
            diffOutput = cachedDiff
            return
        }

        // Fallback: unstaged diff
        if let unstagedDiff = try? await executor.executeGit(arguments: ["--no-pager", "diff"], at: path),
           !unstagedDiff.isEmpty {
            diffOutput = unstagedDiff
            return
        }

        // Last resort: untracked files
        if let untrackedOutput = try? await executor.executeGit(
            arguments: ["ls-files", "--others", "--exclude-standard"],
            at: path
        ) {
            let untrackedFiles = untrackedOutput
                .split(separator: "\n")
                .filter { !$0.isEmpty }

            if !untrackedFiles.isEmpty {
                var output = ""
                for file in untrackedFiles.prefix(50) {
                    output += Self.buildFileDiff(file: String(file), basePath: path)
                }
                diffOutput = output
            }
        }
    }

    private func reloadDiff() {
        Task {
            await loadDiff(for: selectedHistoryCommit)
        }
    }

    private static func buildFileDiff(file: String, basePath: String) -> String {
        let fullPath = (basePath as NSString).appendingPathComponent(file)
        guard let data = FileManager.default.contents(atPath: fullPath),
              let content = String(data: data, encoding: .utf8) else {
            return ""
        }

        let lines = content.split(separator: "\n", omittingEmptySubsequences: false)
        var parts = [String]()
        parts.reserveCapacity(lines.count + 5)

        parts.append("diff --git a/\(file) b/\(file)")
        parts.append("new file mode 100644")
        parts.append("--- /dev/null")
        parts.append("+++ b/\(file)")
        parts.append("@@ -0,0 +1,\(lines.count) @@")

        for line in lines {
            parts.append("+\(line)")
        }

        return parts.joined(separator: "\n") + "\n"
    }
}
