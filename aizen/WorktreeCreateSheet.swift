//
//  WorktreeCreateSheet.swift
//  aizen
//
//  Created by Uladzislau Yakauleu on 17.10.25.
//

import SwiftUI

struct WorktreeCreateSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var repository: Repository
    @ObservedObject var repositoryManager: RepositoryManager

    @State private var worktreeName = ""
    @State private var selectedBranch: BranchInfo?
    @State private var branches: [BranchInfo] = []
    @State private var isLoadingBranches = true
    @State private var isProcessing = false
    @State private var errorMessage: String?

    private var currentBranch: String {
        // Get main branch from repository worktrees
        let worktrees = (repository.worktrees as? Set<Worktree>) ?? []
        return worktrees.first(where: { $0.isPrimary })?.branch ?? "main"
    }

    private var existingWorktreeNames: [String] {
        let worktrees = (repository.worktrees as? Set<Worktree>) ?? []
        return worktrees.compactMap { $0.branch }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Create Worktree")
                    .font(.title2)
                    .fontWeight(.semibold)

                Spacer()
            }
            .padding()

            Divider()

            // Content
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Branch Name")
                            .font(.headline)

                        Spacer()

                        Button {
                            generateRandomName()
                        } label: {
                            Image(systemName: "shuffle")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help("Generate random name")
                    }

                    TextField("e.g., feature-login, bugfix-auth", text: $worktreeName)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: worktreeName) { newValue in
                            // Slugify in real-time
                            let slugified = newValue
                                .replacingOccurrences(of: " ", with: "-")
                                .lowercased()

                            if slugified != newValue {
                                worktreeName = slugified
                            }
                        }
                        .onSubmit {
                            if !worktreeName.isEmpty {
                                createWorktree()
                            }
                        }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Base Branch")
                        .font(.headline)

                    if isLoadingBranches {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Picker("Base Branch", selection: $selectedBranch) {
                            ForEach(branches, id: \.id) { branch in
                                Text(branch.name)
                                    .tag(branch as BranchInfo?)
                            }
                        }
                        .labelsHidden()
                    }

                    Text("New branch will be created from this branch")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let error = errorMessage {
                    Text(error)
                        .font(.callout)
                        .foregroundStyle(.red)
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.red.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
                }
            }
            .padding()

            Spacer()

            Divider()

            // Footer
            HStack {
                Spacer()

                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button("Create") {
                    createWorktree()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(isProcessing || worktreeName.isEmpty)
            }
            .padding()
        }
        .frame(width: 450)
        .frame(minHeight: 300, maxHeight: 350)
        .onAppear {
            loadBranches()
            suggestWorktreeName()
        }
    }

    private func loadBranches() {
        isLoadingBranches = true

        Task {
            do {
                let loadedBranches = try await repositoryManager.getBranches(for: repository)
                await MainActor.run {
                    // Only local branches
                    branches = loadedBranches.filter { !$0.isRemote }
                    // Select current branch by default
                    selectedBranch = branches.first(where: { $0.name == currentBranch }) ?? branches.first
                    isLoadingBranches = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = "Failed to load branches: \(error.localizedDescription)"
                    isLoadingBranches = false
                }
            }
        }
    }

    private func suggestWorktreeName() {
        generateRandomName()
    }

    private func generateRandomName() {
        worktreeName = WorkspaceNameGenerator.generateUniqueName(excluding: existingWorktreeNames)
            .lowercased()
            .replacingOccurrences(of: " ", with: "-")
            .replacingOccurrences(of: "'", with: "")
    }

    private func createWorktree() {
        guard !isProcessing, !worktreeName.isEmpty else { return }
        guard let selectedBranch = selectedBranch else {
            errorMessage = "Please select a base branch"
            return
        }
        guard let repoPath = repository.path else {
            errorMessage = "Invalid repository path"
            return
        }

        isProcessing = true
        errorMessage = nil

        Task {
            do {
                // Build path: repo/.aizen/{branch-name}
                let repoURL = URL(fileURLWithPath: repoPath)
                let aizenDir = repoURL.appendingPathComponent(".aizen")
                let worktreePath = aizenDir.appendingPathComponent(worktreeName).path

                // Create new branch from selected base branch and create worktree
                _ = try await repositoryManager.addWorktree(
                    to: repository,
                    path: worktreePath,
                    branch: worktreeName,
                    createBranch: true,
                    baseBranch: selectedBranch.name
                )

                await MainActor.run {
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isProcessing = false
                }
            }
        }
    }
}

#Preview {
    WorktreeCreateSheet(
        repository: Repository(),
        repositoryManager: RepositoryManager(viewContext: PersistenceController.preview.container.viewContext)
    )
}
