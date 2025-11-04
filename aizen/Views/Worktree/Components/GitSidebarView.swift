import SwiftUI

struct GitSidebarView: View {
    let worktreePath: String
    let repository: Repository
    let repositoryManager: RepositoryManager
    let onClose: () -> Void

    // Single source of truth - no bindings, no optimistic updates
    let gitStatus: GitStatus
    let isOperationPending: Bool

    // Callbacks for operations
    var onStageFile: (String) -> Void
    var onUnstageFile: (String) -> Void
    var onStageAll: (@escaping () -> Void) -> Void  // Now takes completion callback
    var onUnstageAll: () -> Void
    var onCommit: (String) -> Void
    var onAmendCommit: (String) -> Void
    var onCommitWithSignoff: (String) -> Void
    var onSwitchBranch: (String) -> Void
    var onCreateBranch: (String) -> Void
    var onFetch: () -> Void
    var onPull: () -> Void
    var onPush: () -> Void

    @State private var commitMessage: String = ""
    @State private var selectedBranchInfo: BranchInfo?
    @State private var showingBranchPicker: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerView

            Divider()

            // File list (fills remaining space)
            ScrollView {
                if gitStatus.stagedFiles.isEmpty && gitStatus.modifiedFiles.isEmpty && gitStatus.untrackedFiles.isEmpty {
                    // Empty state - centered
                    VStack(spacing: 12) {
                        Image(systemName: "tray")
                            .font(.system(size: 48))
                            .foregroundStyle(.tertiary)

                        Text("No changes to commit")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .frame(minHeight: 300)
                } else {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        fileListContent
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                }
            }

            Divider()

            // Bottom section (branch + commit)
            bottomSection
                .padding(12)
        }
        .background(.ultraThinMaterial)
        .sheet(isPresented: $showingBranchPicker) {
            BranchSelectorView(
                repository: repository,
                repositoryManager: repositoryManager,
                selectedBranch: $selectedBranchInfo,
                allowCreation: true,
                onCreateBranch: { branchName in
                    onCreateBranch(branchName)
                }
            )
        }
        .onChange(of: selectedBranchInfo) { newBranch in
            if let branch = newBranch {
                onSwitchBranch(branch.name)
            }
        }
    }

    // MARK: - Header

    private var headerView: some View {
        HStack {
            Text(headerTitle)
                .font(.system(size: 13, weight: .semibold))

            if isOperationPending {
                ProgressView()
                    .controlSize(.small)
                    .scaleEffect(0.7)
            }

            Spacer()

            Button(hasUnstagedChanges ? "Stage All" : "Unstage All") {
                if hasUnstagedChanges {
                    onStageAll({})
                } else {
                    onUnstageAll()
                }
            }
            .buttonStyle(.borderless)
            .font(.system(size: 11))
            .disabled(isOperationPending || (gitStatus.stagedFiles.isEmpty && gitStatus.modifiedFiles.isEmpty && gitStatus.untrackedFiles.isEmpty))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private var headerTitle: String {
        let total = gitStatus.stagedFiles.count + gitStatus.modifiedFiles.count + gitStatus.untrackedFiles.count
        return total == 0 ? "No Changes" : "\(total) Change\(total == 1 ? "" : "s")"
    }

    private var hasUnstagedChanges: Bool {
        !gitStatus.modifiedFiles.isEmpty || !gitStatus.untrackedFiles.isEmpty
    }

    // MARK: - Bottom Section

    private var bottomSection: some View {
        VStack(spacing: 8) {
            // Branch row
            HStack {
                // Branch selector (clickable with arrow)
                Button {
                    showingBranchPicker = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.triangle.branch")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)

                        Text("\(repositoryName) / \(gitStatus.currentBranch)")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)

                        Image(systemName: "chevron.down")
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)

                Spacer()

                HStack(spacing: 8) {
                    // Show different buttons based on git status
                    if gitStatus.aheadCount > 0 && gitStatus.behindCount > 0 {
                        // Both ahead and behind - show pull/push combined button
                        HStack(spacing: 0) {
                            Button {
                                onPull()
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "arrow.down")
                                        .font(.system(size: 9))
                                    Text("(\(gitStatus.behindCount))")
                                        .font(.system(size: 10, weight: .medium))
                                }
                            }
                            .buttonStyle(.plain)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)

                            Rectangle()
                                .fill(Color.accentColor.opacity(0.3))
                                .frame(width: 1, height: 16)

                            Button {
                                onPush()
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "arrow.up")
                                        .font(.system(size: 9))
                                    Text("(\(gitStatus.aheadCount))")
                                        .font(.system(size: 10, weight: .medium))
                                }
                            }
                            .buttonStyle(.plain)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)

                            Rectangle()
                                .fill(Color.accentColor.opacity(0.3))
                                .frame(width: 1, height: 16)

                            Menu {
                                Button("Fetch") {
                                    onFetch()
                                }
                                Button("Pull") {
                                    onPull()
                                }
                                Button("Push") {
                                    onPush()
                                }
                            } label: {
                                Image(systemName: "chevron.down")
                                    .font(.system(size: 8))
                            }
                            .menuStyle(.borderlessButton)
                            .menuIndicator(.hidden)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 4)
                            .frame(width: 20)
                        }
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color.accentColor.opacity(0.12))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .strokeBorder(Color.accentColor.opacity(0.3), lineWidth: 1)
                        )
                    } else if gitStatus.aheadCount > 0 {
                        // Only ahead - show push button
                        HStack(spacing: 0) {
                            Button {
                                onPush()
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "arrow.up")
                                        .font(.system(size: 9))
                                    Text("Push")
                                        .font(.system(size: 11))
                                    Text("(\(gitStatus.aheadCount))")
                                        .font(.system(size: 10, weight: .medium))
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .buttonStyle(.plain)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)

                            Rectangle()
                                .fill(Color.accentColor.opacity(0.3))
                                .frame(width: 1, height: 16)

                            Menu {
                                Button("Fetch") {
                                    onFetch()
                                }
                                Button("Pull") {
                                    onPull()
                                }
                                Button("Push") {
                                    onPush()
                                }
                            } label: {
                                Image(systemName: "chevron.down")
                                    .font(.system(size: 8))
                            }
                            .menuStyle(.borderlessButton)
                            .menuIndicator(.hidden)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 4)
                            .frame(width: 20)
                        }
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color.accentColor.opacity(0.12))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .strokeBorder(Color.accentColor.opacity(0.3), lineWidth: 1)
                        )
                    } else {
                        // Default - show fetch button only
                        HStack(spacing: 0) {
                            Button {
                                onFetch()
                            } label: {
                                Text("Fetch")
                                    .font(.system(size: 11))
                            }
                            .buttonStyle(.plain)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)

                            Rectangle()
                                .fill(Color.accentColor.opacity(0.3))
                                .frame(width: 1, height: 16)

                            Menu {
                                Button("Fetch") {
                                    onFetch()
                                }
                                Button("Pull") {
                                    onPull()
                                }
                                Button("Push") {
                                    onPush()
                                }
                            } label: {
                                Image(systemName: "chevron.down")
                                    .font(.system(size: 8))
                            }
                            .menuStyle(.borderlessButton)
                            .menuIndicator(.hidden)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 4)
                            .frame(width: 20)
                        }
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color.accentColor.opacity(0.12))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .strokeBorder(Color.accentColor.opacity(0.3), lineWidth: 1)
                        )
                    }
                }
            }

            // Commit message
            ZStack(alignment: .topLeading) {
                if commitMessage.isEmpty {
                    Text("Enter commit message")
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)
                        .padding(.leading, 8)
                        .padding(.top, 8)
                        .allowsHitTesting(false)
                }

                CommitTextEditor(text: $commitMessage)
                    .frame(height: 100)
            }
            .background(Color(nsColor: .textBackgroundColor))
            .cornerRadius(6)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color(nsColor: .separatorColor).opacity(0.3), lineWidth: 1)
            )

            // Commit button menu
            HStack(spacing: 0) {
                // Main commit button
                Button {
                    onCommit(commitMessage)
                    commitMessage = ""
                } label: {
                    Text("Commit")
                        .font(.system(size: 12, weight: .medium))
                        .frame(maxWidth: .infinity)
                        .frame(height: 32)
                }
                .buttonStyle(.plain)
                .background(Color.accentColor)
                .foregroundColor(.white)
                .disabled(commitMessage.isEmpty || gitStatus.stagedFiles.isEmpty || isOperationPending)

                // Divider
                Rectangle()
                    .fill(Color.black.opacity(0.2))
                    .frame(width: 1, height: 32)

                // Dropdown menu
                Menu {
                    Button("Commit All") {
                        commitAllAction()
                    }
                    Divider()
                    Button("Amend Last Commit") {
                        onAmendCommit(commitMessage)
                        commitMessage = ""
                    }
                    .disabled(gitStatus.stagedFiles.isEmpty)
                    Button("Commit with Sign-off") {
                        onCommitWithSignoff(commitMessage)
                        commitMessage = ""
                    }
                    .disabled(gitStatus.stagedFiles.isEmpty)
                } label: {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8))
                        .foregroundColor(.white)
                        .frame(width: 44, height: 32)
                }
                .menuStyle(.borderlessButton)
                .frame(width: 36)
                .menuIndicator(.hidden)
                .background(Color.accentColor)
                .disabled(commitMessage.isEmpty || isOperationPending)
            }
            .fixedSize(horizontal: false, vertical: true)
            .background(Color.accentColor)
            .cornerRadius(6)
        }
    }

    private var repositoryName: String {
        repository.name ?? "repo"
    }

    private func commitAllAction() {
        let message = commitMessage

        // Stage all files, then commit when staging completes
        onStageAll { [self] in
            onCommit(message)
            commitMessage = ""
        }
    }

    // MARK: - File List Content

    @ViewBuilder
    private var fileListContent: some View {
        // Conflicted files (red indicator, non-toggleable)
        if !gitStatus.conflictedFiles.isEmpty {
            ForEach(gitStatus.conflictedFiles, id: \.self) { file in
                conflictRow(file: file)
            }
        }

        // Get all unique files
        let allFiles = Set(gitStatus.stagedFiles + gitStatus.modifiedFiles + gitStatus.untrackedFiles)

        ForEach(Array(allFiles).sorted(), id: \.self) { file in
            let isStaged = gitStatus.stagedFiles.contains(file)
            let isModified = gitStatus.modifiedFiles.contains(file)
            let isUntracked = gitStatus.untrackedFiles.contains(file)

            if isStaged && isModified {
                // File has both staged and unstaged changes - show mixed state
                fileRow(
                    file: file,
                    isStaged: nil,  // Mixed state
                    statusColor: .orange,
                    statusIcon: "circle.lefthalf.filled"
                )
            } else if isStaged {
                // File is only staged
                fileRow(
                    file: file,
                    isStaged: true,
                    statusColor: .green,
                    statusIcon: "checkmark.circle.fill"
                )
            } else if isModified {
                // File is only modified (not staged)
                fileRow(
                    file: file,
                    isStaged: false,
                    statusColor: .orange,
                    statusIcon: "circle.fill"
                )
            } else if isUntracked {
                // File is untracked
                fileRow(
                    file: file,
                    isStaged: false,
                    statusColor: .blue,
                    statusIcon: "circle.fill"
                )
            }
        }
    }

    // MARK: - File Row

    private func fileRow(file: String, isStaged: Bool?, statusColor: Color, statusIcon: String) -> some View {
        HStack(spacing: 8) {
            if let staged = isStaged {
                // Normal checkbox for fully staged or unstaged files
                Toggle(isOn: Binding(
                    get: { staged },
                    set: { newValue in
                        // No optimistic updates - just call the operation
                        if newValue {
                            onStageFile(file)
                        } else {
                            onUnstageFile(file)
                        }
                    }
                )) {
                    EmptyView()
                }
                .toggleStyle(.checkbox)
                .labelsHidden()
                .disabled(isOperationPending)
            } else {
                // Mixed state checkbox (shows dash/minus)
                Button {
                    // Clicking stages the remaining changes
                    onStageFile(file)
                } label: {
                    Image(systemName: "minus.square")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .disabled(isOperationPending)
            }

            Image(systemName: statusIcon)
                .font(.system(size: 8))
                .foregroundStyle(statusColor)

            Text(file)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(.vertical, 2)
    }

    private func conflictRow(file: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 12))
                .foregroundStyle(.red)
                .frame(width: 14)

            Text(file)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(.vertical, 2)
        .padding(.leading, 8)
    }

}

// MARK: - Commit Text Editor

struct CommitTextEditor: NSViewRepresentable {
    @Binding var text: String

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        let textView = scrollView.documentView as! NSTextView

        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay

        textView.delegate = context.coordinator
        textView.font = .systemFont(ofSize: 12)
        textView.isRichText = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 8, height: 8)
        textView.textContainer?.lineFragmentPadding = 0

        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        let textView = nsView.documentView as! NSTextView
        if textView.string != text {
            textView.string = text
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    class Coordinator: NSObject, NSTextViewDelegate {
        @Binding var text: String

        init(text: Binding<String>) {
            _text = text
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            text = textView.string
        }
    }
}

// MARK: - Preview

#Preview {
    GitSidebarView(
        worktreePath: "/path/to/worktree",
        repository: Repository(),
        repositoryManager: RepositoryManager(viewContext: PersistenceController.preview.container.viewContext),
        onClose: {},
        gitStatus: GitStatus(
            stagedFiles: ["src/main.swift", "src/views/GitSidebarView.swift"],
            modifiedFiles: ["README.md", "Package.swift"],
            untrackedFiles: ["newfile.txt"],
            conflictedFiles: [],
            currentBranch: "main",
            aheadCount: 2,
            behindCount: 1,
            additions: 45,
            deletions: 12
        ),
        isOperationPending: false,
        onStageFile: { _ in },
        onUnstageFile: { _ in },
        onStageAll: { completion in completion() },
        onUnstageAll: {},
        onCommit: { _ in },
        onAmendCommit: { _ in },
        onCommitWithSignoff: { _ in },
        onSwitchBranch: { _ in },
        onCreateBranch: { _ in },
        onFetch: {},
        onPull: {},
        onPush: {}
    )
}
