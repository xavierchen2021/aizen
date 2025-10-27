//
//  WorktreeDetailView.swift
//  aizen
//
//  Created by Uladzislau Yakauleu on 17.10.25.
//

import SwiftUI

struct WorktreeDetailView: View {
    @ObservedObject var worktree: Worktree
    @ObservedObject var repositoryManager: RepositoryManager
    @ObservedObject var appDetector = AppDetector.shared

    @State private var selectedTab = "chat"
    @State private var selectedChatSessionId: UUID?
    @State private var selectedTerminalSessionId: UUID?
    @State private var gitAdditions = 0
    @State private var gitDeletions = 0
    @State private var gitUntrackedFiles = 0
    @State private var isLoadingGitStatus = false
    @State private var gitStatusTimer: Timer?
    @State private var lastOpenedApp: String?

    var chatSessions: [ChatSession] {
        let sessions = (worktree.chatSessions as? Set<ChatSession>) ?? []
        return sessions.sorted { ($0.createdAt ?? Date()) < ($1.createdAt ?? Date()) }
    }

    var terminalSessions: [TerminalSession] {
        let sessions = (worktree.terminalSessions as? Set<TerminalSession>) ?? []
        return sessions.sorted { ($0.createdAt ?? Date()) < ($1.createdAt ?? Date()) }
    }

    var body: some View {
        NavigationStack {
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
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .navigationTitle(worktree.branch ?? "Worktree")
            .toolbarBackground(.visible, for: .windowToolbar)
            .toolbar {
                ToolbarItem(placement: .automatic) {
                    Picker("Tab", selection: $selectedTab) {
                        Label("Chat", systemImage: "message").tag("chat")
                        Label("Terminal", systemImage: "terminal").tag("terminal")
                    }
                    .pickerStyle(.segmented)
                }

                ToolbarItem(placement: .automatic) {
                    Spacer()
                }

                ToolbarItemGroup(placement: .automatic) {
                    if selectedTab == "chat" && !chatSessions.isEmpty {
                        ForEach(chatSessions) { session in
                            Button {
                                selectedChatSessionId = session.id
                            } label: {
                                HStack(spacing: 6) {
                                    AgentIconView(agent: session.agentName ?? "claude", size: 14)

                                    Text(session.title ?? session.agentName?.capitalized ?? "Chat")
                                        .font(.callout)

                                    Button {
                                        closeChatSession(session)
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .font(.system(size: 10))
                                            .foregroundStyle(.secondary)
                                    }
                                    .buttonStyle(.borderless)
                                }
                            }
                            .buttonStyle(.automatic)
                            .foregroundStyle(selectedChatSessionId == session.id ? .primary : .secondary)
                        }
                    } else if selectedTab == "terminal" && !terminalSessions.isEmpty {
                        ForEach(terminalSessions) { session in
                            Button {
                                selectedTerminalSessionId = session.id
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "terminal")
                                        .font(.system(size: 12))
                                    Text(session.title ?? "Terminal")
                                        .font(.callout)

                                    Button {
                                        closeTerminalSession(session)
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .font(.system(size: 10))
                                            .foregroundStyle(.secondary)
                                    }
                                    .buttonStyle(.borderless)
                                }
                            }
                            .buttonStyle(.automatic)
                            .foregroundStyle(selectedTerminalSessionId == session.id ? .primary : .secondary)
                        }
                    }
                }
        

                ToolbarItem(placement: .automatic) {
                    if selectedTab == "chat" {
                        if !chatSessions.isEmpty {
                            Button {
                                createNewChatSession()
                            } label: {
                                Image(systemName: "plus")
                                    .font(.system(size: 11))
                            }
                            .help("New chat session")
                        }
                    } else {
                        if !terminalSessions.isEmpty {
                            Button {
                                createNewTerminalSession()
                            } label: {
                                Image(systemName: "plus")
                                    .font(.system(size: 11))
                            }
                            .help("New terminal session")
                        }
                    }
                }

                ToolbarItem(placement: .automatic) {
                    Spacer()
                }

    
              
                

                ToolbarItemGroup(placement: .automatic) {
                    HStack(spacing: 0) {
                        Button {
                            openInLastApp()
                        } label: {
                            Image(systemName: "arrow.up.forward.app")
                                .font(.system(size: 11))
                        }
                        
                        .help(lastOpenedApp ?? "Open in app")

                        Divider()
                            .frame(height: 16)

                        Menu {
                            // System apps
                            if let finder = appDetector.getApps(for: .finder).first {
                                Button {
                                    openInDetectedApp(finder)
                                } label: {
                                    AppMenuLabel(app: finder)
                                }
                            }

                            // Terminals
                            let terminals = appDetector.getTerminals()
                            if !terminals.isEmpty {
                                Divider()
                                ForEach(terminals) { app in
                                    Button {
                                        openInDetectedApp(app)
                                    } label: {
                                        AppMenuLabel(app: app)
                                    }
                                }
                            }

                            // Editors
                            let editors = appDetector.getEditors()
                            if !editors.isEmpty {
                                Divider()
                                ForEach(editors) { app in
                                    Button {
                                        openInDetectedApp(app)
                                    } label: {
                                        AppMenuLabel(app: app)
                                    }
                                }
                            }
                        } label: {
                            Image(systemName: "chevron.down")
                                .font(.system(size: 9))
                        }
                        .menuIndicator(.hidden)
                        .fixedSize()
                    }
                    
                    HStack(spacing: 8) {
                        if gitAdditions > 0 {
                            Text("+\(gitAdditions)")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.green)
                                .transition(.opacity)
                        }

                        if gitDeletions > 0 {
                            Text("-\(gitDeletions)")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.red)
                                .transition(.opacity)
                        }

                        if gitUntrackedFiles > 0 {
                            HStack(spacing: 4) {
                                Image(systemName: "questionmark.circle.fill")
                                    .font(.system(size: 10))
                                Text("\(gitUntrackedFiles)")
                                    .font(.system(size: 11, weight: .medium))
                            }
                            .foregroundStyle(.orange)
                            .transition(.opacity)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .opacity((gitAdditions > 0 || gitDeletions > 0 || gitUntrackedFiles > 0) ? 1 : 0)
                    .animation(.easeInOut(duration: 0.2), value: gitAdditions)
                    .animation(.easeInOut(duration: 0.2), value: gitDeletions)
                    .animation(.easeInOut(duration: 0.2), value: gitUntrackedFiles)
                    .frame(width: .infinity)
                    
                }
            }
            .task {
                await loadGitStatus()
                startPeriodicRefresh()
            }
            .onDisappear {
                gitStatusTimer?.invalidate()
                gitStatusTimer = nil
            }
        }
    }

    private func startPeriodicRefresh() {
        gitStatusTimer?.invalidate()
        gitStatusTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { _ in
            Task {
                await loadGitStatus()
            }
        }
    }

    private func loadGitStatus() async {
        isLoadingGitStatus = true
        defer { isLoadingGitStatus = false }

        guard let path = worktree.path else { return }

        do {
            // Get numstat for additions/deletions
            let diffProcess = Process()
            diffProcess.executableURL = URL(fileURLWithPath: "/usr/bin/git")
            diffProcess.arguments = ["diff", "--numstat"]
            diffProcess.currentDirectoryURL = URL(fileURLWithPath: path)

            let diffPipe = Pipe()
            diffProcess.standardOutput = diffPipe

            try diffProcess.run()
            diffProcess.waitUntilExit()

            let diffData = diffPipe.fileHandleForReading.readDataToEndOfFile()
            let diffOutput = String(data: diffData, encoding: .utf8) ?? ""

            var additions = 0
            var deletions = 0

            for line in diffOutput.components(separatedBy: .newlines) {
                let parts = line.split(separator: "\t")
                if parts.count >= 2 {
                    if let add = Int(parts[0]) {
                        additions += add
                    }
                    if let del = Int(parts[1]) {
                        deletions += del
                    }
                }
            }

            // Get untracked files count
            let statusProcess = Process()
            statusProcess.executableURL = URL(fileURLWithPath: "/usr/bin/git")
            statusProcess.arguments = ["status", "--porcelain"]
            statusProcess.currentDirectoryURL = URL(fileURLWithPath: path)

            let statusPipe = Pipe()
            statusProcess.standardOutput = statusPipe

            try statusProcess.run()
            statusProcess.waitUntilExit()

            let statusData = statusPipe.fileHandleForReading.readDataToEndOfFile()
            let statusOutput = String(data: statusData, encoding: .utf8) ?? ""

            let untrackedCount = statusOutput.components(separatedBy: .newlines)
                .filter { $0.hasPrefix("??") }
                .count

            await MainActor.run {
                gitAdditions = additions
                gitDeletions = deletions
                gitUntrackedFiles = untrackedCount
            }
        } catch {
            print("Failed to load git status: \(error)")
        }
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
            print("Failed to delete chat session: \(error)")
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
            print("Failed to delete terminal session: \(error)")
        }
    }

    private func openInLastApp() {
        guard let app = lastOpenedApp else {
            openInApp("Terminal")
            return
        }
        openInApp(app)
    }

    private func openInApp(_ appName: String) {
        guard let path = worktree.path else { return }

        lastOpenedApp = appName

        switch appName {
        case "Terminal":
            repositoryManager.openInTerminal(path)
        case "Finder":
            repositoryManager.openInFinder(path)
        case "Xcode":
            openWithApplication(path: path, applicationName: "Xcode")
        case "VS Code":
            openWithApplication(path: path, applicationName: "Visual Studio Code")
        case "Cursor":
            openWithApplication(path: path, applicationName: "Cursor")
        default:
            repositoryManager.openInEditor(path)
        }
    }

    private func openWithApplication(path: String, applicationName: String) {
        let pathURL = URL(fileURLWithPath: path)
        let workspace = NSWorkspace.shared

        if let appURL = workspace.urlForApplication(withBundleIdentifier: bundleIdentifier(for: applicationName))
            ?? workspace.urlForApplication(toOpen: pathURL) {
            let configuration = NSWorkspace.OpenConfiguration()
            workspace.open([pathURL], withApplicationAt: appURL, configuration: configuration) { _, error in
                if let error = error {
                    print("Failed to open \(path) with \(applicationName): \(error)")
                }
            }
        }
    }

    private func bundleIdentifier(for appName: String) -> String {
        switch appName {
        case "Xcode":
            return "com.apple.dt.Xcode"
        case "Visual Studio Code":
            return "com.microsoft.VSCode"
        case "Cursor":
            return "com.todesktop.230313mzl4w4u92"
        default:
            return ""
        }
    }

    private func openInDetectedApp(_ app: DetectedApp) {
        guard let path = worktree.path else { return }
        lastOpenedApp = app.name
        appDetector.openPath(path, with: app)
    }

    private func createNewChatSession() {
        guard let context = worktree.managedObjectContext else { return }

        let session = ChatSession(context: context)
        session.id = UUID()
        let defaultAgent = AgentRouter().defaultAgent
        session.title = defaultAgent.capitalized
        session.agentName = defaultAgent
        session.createdAt = Date()
        session.worktree = worktree

        do {
            try context.save()
            selectedChatSessionId = session.id
        } catch {
            print("Failed to create chat session: \(error)")
        }
    }

    private func createNewTerminalSession() {
        guard let context = worktree.managedObjectContext else { return }

        let terminalSessions = (worktree.terminalSessions as? Set<TerminalSession>) ?? []

        let session = TerminalSession(context: context)
        session.id = UUID()
        session.title = "Terminal \(terminalSessions.count + 1)"
        session.createdAt = Date()
        session.worktree = worktree

        do {
            try context.save()
            selectedTerminalSessionId = session.id
        } catch {
            print("Failed to create terminal session: \(error)")
        }
    }
}

struct DetailsTabView: View {
    @ObservedObject var worktree: Worktree
    @ObservedObject var repositoryManager: RepositoryManager

    @State private var currentBranch = ""
    @State private var ahead = 0
    @State private var behind = 0
    @State private var isLoading = false
    @State private var showingDeleteConfirmation = false
    @State private var hasUnsavedChanges = false
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Header
                VStack(spacing: 8) {
                    Image(systemName: worktree.isPrimary ? "arrow.triangle.branch" : "arrow.triangle.2.circlepath")
                        .font(.system(size: 48))
                        .foregroundStyle(.blue)

                    Text(worktree.branch ?? "Unknown")
                        .font(.title)
                        .fontWeight(.bold)

                    if worktree.isPrimary {
                        Text("PRIMARY WORKTREE")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 4)
                            .background(.blue, in: Capsule())
                    }
                }
                .padding(.top, 32)

                // Branch status
                if isLoading {
                    ProgressView()
                        .controlSize(.large)
                } else {
                    VStack(spacing: 12) {
                        if ahead > 0 || behind > 0 {
                            HStack(spacing: 20) {
                                if ahead > 0 {
                                    Label {
                                        Text("\(ahead) ahead")
                                    } icon: {
                                        Image(systemName: "arrow.up.circle.fill")
                                            .foregroundStyle(.green)
                                    }
                                }

                                if behind > 0 {
                                    Label {
                                        Text("\(behind) behind")
                                    } icon: {
                                        Image(systemName: "arrow.down.circle.fill")
                                            .foregroundStyle(.orange)
                                    }
                                }
                            }
                            .font(.callout)
                        } else {
                            Label("Up to date", systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        }
                    }
                }

                // Info section
                GroupBox {
                    VStack(alignment: .leading, spacing: 12) {
                        InfoRow(label: "Path", value: worktree.path ?? "Unknown")
                        Divider()
                        InfoRow(label: "Branch", value: currentBranch.isEmpty ? (worktree.branch ?? "Unknown") : currentBranch)

                        if let lastAccessed = worktree.lastAccessed {
                            Divider()
                            InfoRow(label: "Last Accessed", value: lastAccessed.formatted(date: .abbreviated, time: .shortened))
                        }
                    }
                    .padding(4)
                }
                .padding(.horizontal)

                // Actions
                VStack(spacing: 12) {
                    Text("Actions")
                        .font(.headline)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal)

                    VStack(spacing: 8) {
                        ActionButton(
                            title: "Open in Terminal",
                            icon: "terminal",
                            color: .blue
                        ) {
                            openInTerminal()
                        }

                        ActionButton(
                            title: "Open in Finder",
                            icon: "folder",
                            color: .orange
                        ) {
                            openInFinder()
                        }

                        ActionButton(
                            title: "Open in Editor",
                            icon: "chevron.left.forwardslash.chevron.right",
                            color: .purple
                        ) {
                            openInEditor()
                        }

                        if !worktree.isPrimary {
                            ActionButton(
                                title: "Delete Worktree",
                                icon: "trash",
                                color: .red
                            ) {
                                checkUnsavedChanges()
                            }
                        }
                    }
                    .padding(.horizontal)
                }

                if let error = errorMessage {
                    Text(error)
                        .font(.callout)
                        .foregroundStyle(.red)
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.red.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
                        .padding(.horizontal)
                }

                Spacer()
            }
        }
        .navigationTitle("Worktree Details")
        .toolbar {
            Button {
                refreshStatus()
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
        }
        .task {
            refreshStatus()
        }
        .alert(hasUnsavedChanges ? "Unsaved Changes" : "Delete Worktree", isPresented: $showingDeleteConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                deleteWorktree()
            }
        } message: {
            if hasUnsavedChanges {
                Text("The worktree '\(worktree.branch ?? "Unknown")' contains modified or untracked files. Delete anyway?")
            } else {
                Text("Are you sure you want to delete this worktree? This action cannot be undone.")
            }
        }
    }

    private func refreshStatus() {
        isLoading = true
        errorMessage = nil

        Task {
            do {
                let status = try await repositoryManager.getWorktreeStatus(worktree)
                await MainActor.run {
                    currentBranch = status.branch
                    ahead = status.ahead
                    behind = status.behind
                    isLoading = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isLoading = false
                }
            }
        }
    }

    private func openInTerminal() {
        guard let path = worktree.path else { return }
        repositoryManager.openInTerminal(path)
        updateLastAccessed()
    }

    private func openInFinder() {
        guard let path = worktree.path else { return }
        repositoryManager.openInFinder(path)
        updateLastAccessed()
    }

    private func openInEditor() {
        guard let path = worktree.path else { return }
        repositoryManager.openInEditor(path)
        updateLastAccessed()
    }

    private func checkUnsavedChanges() {
        Task {
            do {
                let changes = try await repositoryManager.hasUnsavedChanges(worktree)
                await MainActor.run {
                    hasUnsavedChanges = changes
                    showingDeleteConfirmation = true
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                }
            }
        }
    }

    private func deleteWorktree() {
        Task {
            do {
                try await repositoryManager.deleteWorktree(worktree, force: hasUnsavedChanges)
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                }
            }
        }
    }

    private func updateLastAccessed() {
        do {
            try repositoryManager.updateWorktreeAccess(worktree)
        } catch {
            print("Failed to update last accessed: \(error)")
        }
    }
}

struct InfoRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(width: 100, alignment: .leading)

            Text(value)
                .font(.subheadline)
                .textSelection(.enabled)

            Spacer()
        }
    }
}

struct ActionButton: View {
    let title: String
    let icon: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Image(systemName: icon)
                    .foregroundStyle(color)
                    .frame(width: 20)

                Text(title)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: "chevron.right")
                    .foregroundStyle(.tertiary)
                    .font(.caption)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - App Menu Label with Icon

struct AppMenuLabel: View {
    let app: DetectedApp

    var body: some View {
        HStack(spacing: 8) {
            if let icon = app.icon {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 16, height: 16)
            }
            Text(app.name)
        }
    }
}

#Preview {
    WorktreeDetailView(
        worktree: Worktree(),
        repositoryManager: RepositoryManager(viewContext: PersistenceController.preview.container.viewContext)
    )
}
