//
//  GitChangesOverlayView.swift
//  aizen
//
//  Full-screen overlay for viewing all git changes
//

import SwiftUI

struct GitChangesOverlayView: View {
    let worktreePath: String
    let worktree: Worktree?
    let repository: Repository
    let repositoryManager: RepositoryManager
    let gitStatus: GitStatus
    let isOperationPending: Bool
    let onClose: () -> Void

    // Git operation callbacks
    var onStageFile: (String) -> Void
    var onUnstageFile: (String) -> Void
    var onStageAll: (@escaping () -> Void) -> Void
    var onUnstageAll: () -> Void
    var onCommit: (String) -> Void
    var onAmendCommit: (String) -> Void
    var onCommitWithSignoff: (String) -> Void
    var onSwitchBranch: (String) -> Void
    var onCreateBranch: (String) -> Void
    var onFetch: () -> Void
    var onPull: () -> Void
    var onPush: () -> Void

    @State private var diffOutput: String = ""
    @State private var rightPanelWidth: CGFloat = 350
    @State private var leftPanelWidth: CGFloat = 250
    @State private var leftPanelWidthStart: CGFloat = 250
    @State private var visibleFile: String?
    @State private var scrollToFile: String?
    @State private var showCommentsPanel: Bool = false
    @State private var commentPopoverLine: DiffLine?
    @State private var commentPopoverFilePath: String?
    @State private var showAgentPicker: Bool = false

    @StateObject private var reviewManager = ReviewSessionManager()

    @AppStorage("editorFontFamily") private var editorFontFamily: String = "Menlo"
    @AppStorage("diffFontSize") private var diffFontSize: Double = 11.0

    private let minRightPanelWidth: CGFloat = 300
    private let maxRightPanelWidth: CGFloat = 500
    private let minLeftPanelWidth: CGFloat = 200
    private let maxLeftPanelWidth: CGFloat = 400

    @State private var cachedChangedFiles: [String] = []

    private var allChangedFiles: [String] {
        cachedChangedFiles
    }

    private func updateChangedFilesCache() {
        var files = Set<String>()
        files.formUnion(gitStatus.stagedFiles)
        files.formUnion(gitStatus.modifiedFiles)
        files.formUnion(gitStatus.untrackedFiles)
        files.formUnion(gitStatus.conflictedFiles)

        let sortedFiles = files.sorted()
        // Only update if changed
        if sortedFiles != cachedChangedFiles {
            cachedChangedFiles = sortedFiles
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            // Left: Comments panel (auto-show when comments exist)
            if showCommentsPanel {
                commentsPanel
                    .frame(width: leftPanelWidth)

                commentsPanelDivider
            }

            // Center: All files diff scroll
            diffPanel
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .layoutPriority(1)

            // Divider
            resizableDivider

            // Right: Git sidebar
            rightPanel
                .frame(width: rightPanelWidth)
        }
        .animation(nil, value: gitStatus)
        .background(Color(NSColor.windowBackgroundColor))
        .onExitCommand {
            onClose()
        }
        .onAppear {
            reviewManager.load(for: worktreePath)
            updateChangedFilesCache()
        }
        .onChange(of: gitStatus) { _ in
            updateChangedFilesCache()
        }
        .onChange(of: reviewManager.comments.count) { newCount in
            // Auto-show panel when first comment is added
            if newCount > 0 && !showCommentsPanel {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showCommentsPanel = true
                }
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
                    // Clear comments after sending to agent
                    reviewManager.clearAll()
                    onClose()
                }
            )
        }
    }

    private var diffPanelHeader: some View {
        HStack(spacing: 8) {
            Button { onClose() } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)

            Image(systemName: "arrow.triangle.branch")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)

            Text(gitStatus.currentBranch ?? "HEAD")
                .font(.system(size: 13, weight: .medium))

            CopyButton(text: gitStatus.currentBranch ?? "", iconSize: 11)

            Spacer()

            // Toggle comments panel button (with count badge)
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showCommentsPanel.toggle()
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: showCommentsPanel ? "text.bubble.fill" : "text.bubble")
                        .font(.system(size: 11))
                    if !reviewManager.comments.isEmpty {
                        Text("\(reviewManager.comments.count)")
                            .font(.system(size: 11, weight: .medium))
                    }
                }
                .foregroundStyle(reviewManager.comments.isEmpty ? Color.secondary : Color.blue)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(showCommentsPanel ? Color.blue.opacity(0.15) : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)
            .help(showCommentsPanel ? "Hide comments" : "Show comments")

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
        .padding(.horizontal, 12)
        .frame(height: 44)
        .background(Color(NSColor.windowBackgroundColor))
    }

    private var diffPanel: some View {
        VStack(spacing: 0) {
            diffPanelHeader
            Divider()

            if allChangedFiles.isEmpty {
                AllFilesDiffEmptyView()
            } else if diffOutput.isEmpty {
                // Loading state while diff is being fetched
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
                    commentedLines: reviewManager.commentedLineKeys,
                    onAddComment: { line, filePath in
                        commentPopoverFilePath = filePath
                        commentPopoverLine = line
                    }
                )
            }
        }
        .task {
            await loadFullDiff()
        }
        .onChange(of: diffOutput) { _ in
            validateCommentsAgainstDiff()
        }
    }

    private func validateCommentsAgainstDiff() {
        // Remove comments for files that are no longer in the diff
        let filesInDiff = Set(allChangedFiles)
        let commentsToRemove = reviewManager.comments.filter { !filesInDiff.contains($0.filePath) }

        for comment in commentsToRemove {
            reviewManager.deleteComment(id: comment.id)
        }
    }

    private var commentsPanel: some View {
        ReviewCommentsPanel(
            reviewManager: reviewManager,
            onScrollToLine: { filePath, lineNumber in
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

    private var commentsPanelDivider: some View {
        Rectangle()
            .fill(Color(NSColor.separatorColor))
            .frame(width: 1)
            .overlay(
                Rectangle()
                    .fill(Color.clear)
                    .frame(width: 8)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(coordinateSpace: .global)
                            .onChanged { value in
                                let delta = value.translation.width
                                let newWidth = leftPanelWidthStart + delta
                                leftPanelWidth = min(max(newWidth, minLeftPanelWidth), maxLeftPanelWidth)
                            }
                            .onEnded { _ in
                                leftPanelWidthStart = leftPanelWidth
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
            .onAppear {
                leftPanelWidthStart = leftPanelWidth
            }
    }

    private func loadFullDiff() async {
        let executor = GitCommandExecutor()
        let path = worktreePath

        guard !path.isEmpty else { return }

        // Try git diff HEAD first - this handles most cases including staged new files
        if let headDiff = try? await executor.executeGit(arguments: ["--no-pager", "diff", "HEAD"], at: path),
           !headDiff.isEmpty {
            diffOutput = headDiff
            return
        }

        // Fallback: cached diff (for repos with commits but no HEAD changes)
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

        // Last resort: get untracked files only
        if let untrackedOutput = try? await executor.executeGit(
            arguments: ["ls-files", "--others", "--exclude-standard"],
            at: path
        ) {
            let untrackedFiles = untrackedOutput
                .split(separator: "\n")
                .filter { !$0.isEmpty }

            if !untrackedFiles.isEmpty {
                var output = ""
                for file in untrackedFiles.prefix(50) { // Limit to 50 files for performance
                    output += Self.buildFileDiff(file: String(file), basePath: path)
                }
                diffOutput = output
            }
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

    private func reloadDiff() {
        Task {
            await loadFullDiff()
        }
    }

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
                                let newWidth = rightPanelWidth - value.translation.width
                                rightPanelWidth = min(max(newWidth, minRightPanelWidth), maxRightPanelWidth)
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

    private var rightPanel: some View {
        GitSidebarView(
            worktreePath: worktreePath,
            repository: repository,
            repositoryManager: repositoryManager,
            onClose: onClose,
            gitStatus: gitStatus,
            isOperationPending: isOperationPending,
            selectedDiffFile: visibleFile,
            onStageFile: { file in
                onStageFile(file)
                reloadDiff()
            },
            onUnstageFile: { file in
                onUnstageFile(file)
                reloadDiff()
            },
            onStageAll: { completion in
                onStageAll {
                    reloadDiff()
                    completion()
                }
            },
            onUnstageAll: {
                onUnstageAll()
                reloadDiff()
            },
            onCommit: { message in
                onCommit(message)
                reloadDiff()
            },
            onAmendCommit: { message in
                onAmendCommit(message)
                reloadDiff()
            },
            onCommitWithSignoff: { message in
                onCommitWithSignoff(message)
                reloadDiff()
            },
            onSwitchBranch: { branch in
                onSwitchBranch(branch)
                reloadDiff()
            },
            onCreateBranch: onCreateBranch,
            onFetch: onFetch,
            onPull: {
                onPull()
                reloadDiff()
            },
            onPush: onPush,
            onFileClick: { file in
                visibleFile = file  // Immediately highlight
                scrollToFile = file
                // Reset after a moment to allow re-clicking the same file
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    scrollToFile = nil
                }
            }
        )
    }
}
