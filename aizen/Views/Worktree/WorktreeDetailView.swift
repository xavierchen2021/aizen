//
//  WorktreeDetailView.swift
//  aizen
//
//  Created by Uladzislau Yakauleu on 17.10.25.
//

import SwiftUI
import os.log

struct WorktreeDetailView: View {
    @ObservedObject var worktree: Worktree
    @ObservedObject var repositoryManager: RepositoryManager
    @ObservedObject var appDetector = AppDetector.shared
    var onWorktreeDeleted: ((Worktree?) -> Void)?

    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.aizen", category: "WorktreeDetailView")

    @State private var selectedTab = "chat"
    @State private var selectedChatSessionId: UUID?
    @State private var selectedTerminalSessionId: UUID?
    @State private var lastOpenedApp: DetectedApp?
    @State private var showingGitSidebar = false
    @StateObject private var gitRepositoryService: GitRepositoryService
    @State private var gitIndexWatcher: GitIndexWatcher?
    @State private var sidebarWidth: CGFloat = 350

    init(worktree: Worktree, repositoryManager: RepositoryManager, onWorktreeDeleted: ((Worktree?) -> Void)? = nil) {
        self.worktree = worktree
        self.repositoryManager = repositoryManager
        self.onWorktreeDeleted = onWorktreeDeleted
        _gitRepositoryService = StateObject(wrappedValue: GitRepositoryService(worktreePath: worktree.path ?? ""))
    }

    var chatSessions: [ChatSession] {
        let sessions = (worktree.chatSessions as? Set<ChatSession>) ?? []
        return sessions.sorted { ($0.createdAt ?? Date()) < ($1.createdAt ?? Date()) }
    }

    var terminalSessions: [TerminalSession] {
        let sessions = (worktree.terminalSessions as? Set<TerminalSession>) ?? []
        return sessions.sorted { ($0.createdAt ?? Date()) < ($1.createdAt ?? Date()) }
    }

    var hasActiveSessions: Bool {
        (selectedTab == "chat" && !chatSessions.isEmpty) || (selectedTab == "terminal" && !terminalSessions.isEmpty)
    }

    var hasGitChanges: Bool {
        gitRepositoryService.currentStatus.additions > 0 ||
        gitRepositoryService.currentStatus.deletions > 0 ||
        gitRepositoryService.currentStatus.untrackedFiles.count > 0
    }



    @ViewBuilder
    var contentView: some View {
        Group {
            if selectedTab == "chat" {
                ChatTabView(
                    worktree: worktree,
                    selectedSessionId: $selectedChatSessionId
                )
            } else {
                TerminalTabView(
                    worktree: worktree,
                    selectedSessionId: $selectedTerminalSessionId,
                    repositoryManager: repositoryManager
                )
            }
        }
    }

    @ToolbarContentBuilder
    var sessionToolbarItems: some ToolbarContent {

        ToolbarItem(placement: .automatic) {
            SessionTabsScrollView(
                selectedTab: selectedTab,
                chatSessions: chatSessions,
                terminalSessions: terminalSessions,
                selectedChatSessionId: $selectedChatSessionId,
                selectedTerminalSessionId: $selectedTerminalSessionId,
                onCloseChatSession: closeChatSession,
                onCloseTerminalSession: closeTerminalSession
            )
        }

        ToolbarItem(placement: .automatic) {
            if selectedTab == "chat" {
                Button {
                    createNewChatSession()
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 11))
                }
                .help(String(localized: "worktree.session.newChat"))
            } else {
                Button {
                    createNewTerminalSession()
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 11))
                }
                .help(String(localized: "worktree.session.newTerminal"))
            }
        }

    }

    @ToolbarContentBuilder
    var appAndGitToolbarItems: some ToolbarContent {
        ToolbarItem {
            OpenInAppButton(
                lastOpenedApp: lastOpenedApp,
                appDetector: appDetector,
                onOpenInLastApp: openInLastApp,
                onOpenInDetectedApp: openInDetectedApp
            )
        }

        if #available(macOS 26.0, *) {
            ToolbarSpacer(.fixed)
        } else {
            ToolbarItem(placement: .automatic) {
                Spacer().fixedSize()
            }
        }

        ToolbarItem(placement: .automatic) {
            if hasGitChanges {
                GitStatusView(
                    additions: gitRepositoryService.currentStatus.additions,
                    deletions: gitRepositoryService.currentStatus.deletions,
                    untrackedFiles: gitRepositoryService.currentStatus.untrackedFiles.count
                )
            }
        }

        ToolbarItem(placement: .automatic) {
            Button(action: {
                showingGitSidebar.toggle()
            }) {
                Label("Git Changes", systemImage: "sidebar.right")
            }
            .labelStyle(.iconOnly)
            .help("Show Git Changes")
        }
    }

    var body: some View {
        NavigationStack {
            contentView
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .safeAreaInset(edge: .trailing, spacing: 0) {
                    if showingGitSidebar {
                        GitSidebarView(
                            worktreePath: worktree.path ?? "",
                            repository: worktree.repository!,
                            repositoryManager: repositoryManager,
                            onClose: { showingGitSidebar = false },
                            gitStatus: gitRepositoryService.currentStatus,
                            isOperationPending: gitRepositoryService.isOperationPending,
                            onStageFile: stageFile,
                            onUnstageFile: unstageFile,
                            onStageAll: stageAllFiles,
                            onUnstageAll: unstageAllFiles,
                            onCommit: commitChanges,
                            onAmendCommit: amendCommit,
                            onCommitWithSignoff: commitWithSignoff,
                            onSwitchBranch: switchBranch,
                            onCreateBranch: createBranch,
                            onFetch: fetchChanges,
                            onPull: pullChanges,
                            onPush: pushChanges
                        )
                        .frame(width: sidebarWidth)
                        .id(gitRepositoryService.currentStatus.id)
                        .transition(.move(edge: .trailing))
                    }
                }
                .animation(.easeInOut(duration: 0.2), value: showingGitSidebar)
            .navigationTitle(worktree.branch ?? String(localized: "worktree.session.worktree"))
            .toolbarBackground(.visible, for: .windowToolbar)
            .toast()
            .toolbar {
                ToolbarItem(placement: .automatic) {
                    Picker(String(localized: "worktree.session.tab"), selection: $selectedTab) {
                        Label(String(localized: "worktree.session.chat"), systemImage: "message").tag("chat")
                        Label(String(localized: "worktree.session.terminal"), systemImage: "terminal").tag("terminal")
                    }
                    .pickerStyle(.segmented)
                }


                if #available(macOS 26.0, *) {
                    ToolbarSpacer()
                } else {
                    ToolbarItem(placement: .automatic) {
                        Spacer().fixedSize()
                    }
                }

                if hasActiveSessions {
                    sessionToolbarItems
                }

                if #available(macOS 26.0, *) {
                    ToolbarSpacer()
                } else {
                    ToolbarItem(placement: .automatic) {
                        Spacer().fixedSize()
                    }
                }

                appAndGitToolbarItems
            }
            .task {
                await setupGitMonitoring()
            }
            .onChange(of: worktree.id) { newId in
                Task {
                    await setupGitMonitoring()
                }
            }
            .onDisappear {
                gitIndexWatcher?.stopWatching()
            }
        }
    }

    private func setupGitMonitoring() async {
        guard let worktreePath = worktree.path else { return }

        // Initial load
        gitRepositoryService.reloadStatus()

        // Setup file system watcher (now a regular class, non-blocking)
        let watcher = GitIndexWatcher(worktreePath: worktreePath)
        watcher.startWatching { [weak gitRepositoryService] in
            gitRepositoryService?.reloadStatus()
        }
        gitIndexWatcher = watcher
    }


    private func closeChatSession(_ session: ChatSession) {
        guard let context = worktree.managedObjectContext else { return }

        if let id = session.id {
            ChatSessionManager.shared.removeAgentSession(for: id)
        }

        if selectedChatSessionId == session.id {
            if let index = chatSessions.firstIndex(where: { $0.id == session.id }) {
                if index > 0 {
                    selectedChatSessionId = chatSessions[index - 1].id
                } else if chatSessions.count > 1 {
                    selectedChatSessionId = chatSessions[index + 1].id
                } else {
                    selectedChatSessionId = nil
                }
            }
        }

        context.delete(session)

        do {
            try context.save()
        } catch {
            logger.error("Failed to delete chat session: \(error.localizedDescription)")
        }
    }

    private func closeTerminalSession(_ session: TerminalSession) {
        guard let context = worktree.managedObjectContext else { return }

        if let id = session.id {
            TerminalSessionManager.shared.removeAllTerminals(for: id)
        }

        if selectedTerminalSessionId == session.id {
            if let index = terminalSessions.firstIndex(where: { $0.id == session.id }) {
                if index > 0 {
                    selectedTerminalSessionId = terminalSessions[index - 1].id
                } else if terminalSessions.count > 1 {
                    selectedTerminalSessionId = terminalSessions[index + 1].id
                } else {
                    selectedTerminalSessionId = nil
                }
            }
        }

        context.delete(session)

        do {
            try context.save()
        } catch {
            logger.error("Failed to delete terminal session: \(error.localizedDescription)")
        }
    }

    private func openInLastApp() {
        guard let app = lastOpenedApp else {
            // Open in Finder by default
            if let finder = appDetector.getApps(for: .finder).first {
                openInDetectedApp(finder)
            }
            return
        }
        openInDetectedApp(app)
    }

    private func openInDetectedApp(_ app: DetectedApp) {
        guard let path = worktree.path else { return }
        lastOpenedApp = app
        appDetector.openPath(path, with: app)
    }

    private func createNewChatSession() {
        guard let context = worktree.managedObjectContext else { return }

        let session = ChatSession(context: context)
        session.id = UUID()
        let defaultAgent = AgentRouter().defaultAgent
        let displayName = AgentRegistry.shared.getMetadata(for: defaultAgent)?.name ?? defaultAgent.capitalized
        session.title = displayName
        session.agentName = defaultAgent
        session.createdAt = Date()
        session.worktree = worktree

        do {
            try context.save()
            selectedChatSessionId = session.id
        } catch {
            logger.error("Failed to create chat session: \(error.localizedDescription)")
        }
    }

    private func createNewTerminalSession() {
        guard let context = worktree.managedObjectContext else { return }

        let terminalSessions = (worktree.terminalSessions as? Set<TerminalSession>) ?? []

        let session = TerminalSession(context: context)
        session.id = UUID()
        session.title = String(localized: "worktree.session.terminalTitle \(terminalSessions.count + 1)")
        session.createdAt = Date()
        session.worktree = worktree

        do {
            try context.save()
            selectedTerminalSessionId = session.id
        } catch {
            logger.error("Failed to create terminal session: \(error.localizedDescription)")
        }
    }

    // MARK: - Git Operations

    private func stageFile(_ file: String) {
        gitRepositoryService.stageFile(file) { error in
            ToastManager.shared.show("Failed to stage file", type: .error)
            logger.error("Failed to stage file: \(error)")
        }
    }

    private func unstageFile(_ file: String) {
        gitRepositoryService.unstageFile(file) { error in
            ToastManager.shared.show("Failed to unstage file", type: .error)
            logger.error("Failed to unstage file: \(error)")
        }
    }

    private func stageAllFiles(onComplete: @escaping () -> Void) {
        gitRepositoryService.stageAll(
            onSuccess: {
                onComplete()
            },
            onError: { error in
                ToastManager.shared.show("Failed to stage files", type: .error)
                logger.error("Failed to stage all files: \(error)")
            }
        )
    }

    private func commitChanges(_ message: String) {
        ToastManager.shared.showLoading("Committing changes...")
        gitRepositoryService.commit(message: message,
            onSuccess: {
                ToastManager.shared.show("Changes committed", type: .success)
            },
            onError: { error in
                ToastManager.shared.show("Commit failed: \(error.localizedDescription)", type: .error, duration: 5.0)
                logger.error("Failed to commit changes: \(error)")
            }
        )
    }

    private func amendCommit(_ message: String) {
        ToastManager.shared.showLoading("Amending commit...")
        gitRepositoryService.amendCommit(message: message,
            onSuccess: {
                ToastManager.shared.show("Commit amended", type: .success)
            },
            onError: { error in
                ToastManager.shared.show("Amend failed: \(error.localizedDescription)", type: .error, duration: 5.0)
                logger.error("Failed to amend commit: \(error)")
            }
        )
    }

    private func commitWithSignoff(_ message: String) {
        ToastManager.shared.showLoading("Committing with sign-off...")
        gitRepositoryService.commitWithSignoff(message: message,
            onSuccess: {
                ToastManager.shared.show("Changes committed", type: .success)
            },
            onError: { error in
                ToastManager.shared.show("Commit failed: \(error.localizedDescription)", type: .error, duration: 5.0)
                logger.error("Failed to commit with signoff: \(error)")
            }
        )
    }

    private func switchBranch(_ branch: String) {
        gitRepositoryService.checkoutBranch(branch) { error in
            ToastManager.shared.show("Failed to switch branch: \(error.localizedDescription)", type: .error, duration: 5.0)
            logger.error("Failed to switch branch: \(error)")
        }

        // Update Core Data with new branch info
        if let repository = worktree.repository {
            Task {
                try? await repositoryManager.refreshRepository(repository)
            }
        }
    }

    private func createBranch(_ name: String) {
        gitRepositoryService.createBranch(name) { error in
            ToastManager.shared.show("Failed to create branch: \(error.localizedDescription)", type: .error, duration: 5.0)
            logger.error("Failed to create branch: \(error)")
        }

        // Update Core Data with new branch info
        if let repository = worktree.repository {
            Task {
                try? await repositoryManager.refreshRepository(repository)
            }
        }
    }

    private func unstageAllFiles() {
        gitRepositoryService.unstageAll { error in
            ToastManager.shared.show("Failed to unstage files", type: .error)
            logger.error("Failed to unstage all files: \(error)")
        }
    }

    private func fetchChanges() {
        ToastManager.shared.showLoading("Fetching changes...")
        gitRepositoryService.fetch(
            onSuccess: {
                ToastManager.shared.show("Fetch completed successfully", type: .success)
            },
            onError: { error in
                ToastManager.shared.show("Fetch failed: \(error.localizedDescription)", type: .error, duration: 5.0)
                logger.error("Failed to fetch changes: \(error)")
            }
        )

        // Update Core Data with new remote info
        if let repository = worktree.repository {
            Task {
                try? await repositoryManager.refreshRepository(repository)
            }
        }
    }

    private func pullChanges() {
        ToastManager.shared.showLoading("Pulling changes...")
        gitRepositoryService.pull(
            onSuccess: {
                ToastManager.shared.show("Pull completed successfully", type: .success)
            },
            onError: { error in
                ToastManager.shared.show("Pull failed: \(error.localizedDescription)", type: .error, duration: 5.0)
                logger.error("Failed to pull changes: \(error)")
            }
        )

        // Update Core Data with new changes
        if let repository = worktree.repository {
            Task {
                try? await repositoryManager.refreshRepository(repository)
            }
        }
    }

    private func pushChanges() {
        ToastManager.shared.showLoading("Checking remote...")

        // Fetch first to check for remote changes
        gitRepositoryService.fetch(
            onSuccess: { [self] in
                // After fetch, check if we're behind
                let status = gitRepositoryService.currentStatus
                if status.behindCount > 0 {
                    ToastManager.shared.show("Remote has \(status.behindCount) new commit(s). Pull manually before pushing.", type: .error, duration: 5.0)
                } else {
                    // No remote changes, proceed with push
                    ToastManager.shared.showLoading("Pushing changes...")
                    gitRepositoryService.push(
                        onSuccess: {
                            ToastManager.shared.show("Push completed successfully", type: .success)
                        },
                        onError: { error in
                            ToastManager.shared.show("Push failed: \(error.localizedDescription)", type: .error, duration: 5.0)
                            logger.error("Failed to push changes: \(error)")
                        }
                    )
                }
            },
            onError: { error in
                // Fetch failed, try push anyway
                ToastManager.shared.showLoading("Pushing changes...")
                gitRepositoryService.push(
                    onSuccess: {
                        ToastManager.shared.show("Push completed successfully", type: .success)
                    },
                    onError: { error in
                        ToastManager.shared.show("Push failed: \(error.localizedDescription)", type: .error, duration: 5.0)
                        logger.error("Failed to push changes: \(error)")
                    }
                )
            }
        )

        // Update Core Data with new remote info
        if let repository = worktree.repository {
            Task {
                try? await repositoryManager.refreshRepository(repository)
            }
        }
    }
}

#Preview {
    WorktreeDetailView(
        worktree: Worktree(),
        repositoryManager: RepositoryManager(viewContext: PersistenceController.preview.container.viewContext)
    )
}
