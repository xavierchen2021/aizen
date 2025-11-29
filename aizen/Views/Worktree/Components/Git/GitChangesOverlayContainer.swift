//
//  GitChangesOverlayContainer.swift
//  aizen
//
//  Container that wraps GitChangesOverlayView with service injection
//

import SwiftUI
import os.log

struct GitChangesOverlayContainer: View {
    let worktree: Worktree
    let repository: Repository
    let repositoryManager: RepositoryManager
    @ObservedObject var gitRepositoryService: GitRepositoryService
    @Binding var showingGitChanges: Bool

    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.aizen", category: "GitChangesOverlay")

    private var gitOperations: WorktreeGitOperations {
        WorktreeGitOperations(
            gitRepositoryService: gitRepositoryService,
            repositoryManager: repositoryManager,
            worktree: worktree,
            logger: logger
        )
    }

    var body: some View {
        GitChangesOverlayView(
            worktreePath: worktree.path ?? "",
            repository: repository,
            repositoryManager: repositoryManager,
            gitStatus: gitRepositoryService.currentStatus,
            isOperationPending: gitRepositoryService.isOperationPending,
            onClose: {
                showingGitChanges = false
            },
            onStageFile: gitOperations.stageFile,
            onUnstageFile: gitOperations.unstageFile,
            onStageAll: gitOperations.stageAll,
            onUnstageAll: gitOperations.unstageAll,
            onCommit: gitOperations.commit,
            onAmendCommit: gitOperations.amendCommit,
            onCommitWithSignoff: gitOperations.commitWithSignoff,
            onSwitchBranch: gitOperations.switchBranch,
            onCreateBranch: gitOperations.createBranch,
            onFetch: gitOperations.fetch,
            onPull: gitOperations.pull,
            onPush: gitOperations.push
        )
        .onAppear {
            if let path = worktree.path {
                gitRepositoryService.updateWorktreePath(path)
            }
            gitRepositoryService.reloadStatus()
        }
    }
}
