//
//  GitPanelWindowController.swift
//  aizen
//
//  Window controller for the git panel
//

import AppKit
import SwiftUI
import os.log

class GitPanelWindowController: NSWindowController {
    private var windowDelegate: GitPanelWindowDelegate?

    convenience init(context: GitChangesContext, repositoryManager: RepositoryManager, onClose: @escaping () -> Void) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1200, height: 800),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )

        // Set title to repository name, subtitle to worktree path
        let repoName = context.worktree.repository?.name ?? "Repository"
        let worktreePath = context.worktree.path ?? ""
        window.title = repoName
        window.minSize = NSSize(width: 900, height: 600)

        self.init(window: window)

        // Create content with SwiftUI toolbar
        let content = GitPanelWindowContentWithToolbar(
            context: context,
            repositoryManager: repositoryManager,
            onClose: {
                window.close()
                onClose()
            }
        )
        .navigationSubtitle(worktreePath)

        window.contentView = NSHostingView(rootView: content)
        window.center()

        // Set up delegate to handle window close
        windowDelegate = GitPanelWindowDelegate(onClose: onClose)
        window.delegate = windowDelegate
    }

    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        window?.makeKeyAndOrderFront(nil)
    }
}

private class GitPanelWindowDelegate: NSObject, NSWindowDelegate {
    let onClose: () -> Void

    init(onClose: @escaping () -> Void) {
        self.onClose = onClose
    }

    func windowWillClose(_ notification: Notification) {
        onClose()
    }
}

// MARK: - SwiftUI Wrapper with Toolbar

struct GitPanelWindowContentWithToolbar: View {
    let context: GitChangesContext
    let repositoryManager: RepositoryManager
    let onClose: () -> Void

    @State private var selectedTab: GitPanelTab = .git
    @State private var selectedBranchInfo: BranchInfo?
    @State private var showingBranchPicker: Bool = false
    @State private var currentOperation: GitToolbarOperation?

    @ObservedObject private var gitRepositoryService: GitRepositoryService

    private var worktree: Worktree { context.worktree }
    private var gitStatus: GitStatus { gitRepositoryService.currentStatus }
    private var isOperationPending: Bool { gitRepositoryService.isOperationPending }

    init(context: GitChangesContext, repositoryManager: RepositoryManager, onClose: @escaping () -> Void) {
        self.context = context
        self.repositoryManager = repositoryManager
        self.onClose = onClose
        self._gitRepositoryService = ObservedObject(wrappedValue: context.service)
    }

    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.aizen", category: "GitPanelToolbar")

    private var gitOperations: WorktreeGitOperations {
        WorktreeGitOperations(
            gitRepositoryService: gitRepositoryService,
            repositoryManager: repositoryManager,
            worktree: worktree,
            logger: logger
        )
    }

    private enum GitToolbarOperation: String {
        case fetch = "Fetching..."
        case pull = "Pulling..."
        case push = "Pushing..."
    }

    var body: some View {
        GitPanelWindowContent(
            context: context,
            repositoryManager: repositoryManager,
            selectedTab: $selectedTab,
            onClose: onClose
        )
        .toolbar {
             ToolbarItem(placement: .navigation) {
                    Picker("", selection: $selectedTab) {
                        ForEach(GitPanelTab.allCases, id: \.self) { tab in
                            Label(tab.rawValue, systemImage: tab.icon).tag(tab)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
            }
            
            
            ToolbarItem(placement: .navigation) {
                 Spacer().frame(width: 12)
            }
            
          
            
             ToolbarItem(placement: .navigation) {
                 branchSelector
            }
            

            ToolbarItem(placement: .primaryAction) {
                gitActionsToolbar
            }
        }
        .sheet(isPresented: $showingBranchPicker) {
            BranchSelectorView(
                repository: worktree.repository!,
                repositoryManager: repositoryManager,
                selectedBranch: $selectedBranchInfo,
                allowCreation: true,
                onCreateBranch: { branchName in
                    gitOperations.createBranch(branchName)
                }
            )
        }
        .onChange(of: selectedBranchInfo) { newBranch in
            if let branch = newBranch {
                gitOperations.switchBranch(branch.name)
            }
        }
    }

    private var branchSelector: some View {
        Button {
            showingBranchPicker = true
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "arrow.triangle.branch")
                Text(gitStatus.currentBranch ?? "HEAD")
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.bordered)
    }

    private var gitActionsToolbar: some View {
        HStack(spacing: 4) {
            if let operation = currentOperation {
                // Show loading state
                HStack(spacing: 6) {
                    ProgressView()
                        .controlSize(.small)
                    Text(operation.rawValue)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
            } else if gitStatus.aheadCount > 0 && gitStatus.behindCount > 0 {
                Button {
                    performOperation(.pull) { gitOperations.pull() }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.down")
                        Text("Pull (\(gitStatus.behindCount))")
                    }
                }
                .buttonStyle(.bordered)
                .disabled(isOperationPending)

                Button {
                    performOperation(.push) { gitOperations.push() }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.up")
                        Text("Push (\(gitStatus.aheadCount))")
                    }
                }
                .buttonStyle(.bordered)
                .disabled(isOperationPending)
            } else if gitStatus.aheadCount > 0 {
                Button {
                    performOperation(.push) { gitOperations.push() }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.up")
                        Text("Push (\(gitStatus.aheadCount))")
                    }
                }
                .buttonStyle(.bordered)
                .disabled(isOperationPending)
            } else {
                Button {
                    performOperation(.fetch) { gitOperations.fetch() }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.triangle.2.circlepath")
                        Text("Fetch")
                    }
                }
                .buttonStyle(.bordered)
                .disabled(isOperationPending)
            }

            if currentOperation == nil {
                Menu {
                    Button {
                        performOperation(.fetch) { gitOperations.fetch() }
                    } label: {
                        Label("Fetch", systemImage: "arrow.triangle.2.circlepath")
                    }
                    .disabled(isOperationPending)

                    Button {
                        performOperation(.pull) { gitOperations.pull() }
                    } label: {
                        Label("Pull", systemImage: "arrow.down")
                    }
                    .disabled(isOperationPending)

                    Button {
                        performOperation(.push) { gitOperations.push() }
                    } label: {
                        Label("Push", systemImage: "arrow.up")
                    }
                    .disabled(isOperationPending)
                } label: {
                    Image(systemName: "chevron.down")
                }
                .menuIndicator(.hidden)
                .buttonStyle(.bordered)
                .disabled(isOperationPending)
            }
        }
        .onChange(of: gitRepositoryService.isOperationPending) { pending in
            if !pending {
                currentOperation = nil
            }
        }
    }

    private func performOperation(_ operation: GitToolbarOperation, action: () -> Void) {
        currentOperation = operation
        action()
    }
}
