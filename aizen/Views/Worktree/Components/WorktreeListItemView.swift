//
//  WorktreeListItemView.swift
//  aizen
//
//  Created by Uladzislau Yakauleu on 17.10.25.
//

import SwiftUI

struct WorktreeListItemView: View {
    @ObservedObject var worktree: Worktree
    let isSelected: Bool
    @ObservedObject var repositoryManager: RepositoryManager
    let allWorktrees: [Worktree]
    @Binding var selectedWorktree: Worktree?
    @ObservedObject var tabStateManager: WorktreeTabStateManager

    @State private var showingDetails = false
    @State private var showingDeleteConfirmation = false
    @State private var hasUnsavedChanges = false
    @State private var errorMessage: String?
    @State private var worktreeStatuses: [WorktreeStatusInfo] = []
    @State private var isLoadingStatuses = false
    @State private var mergeErrorMessage: String?
    @State private var mergeConflictFiles: [String] = []
    @State private var showingMergeConflict = false
    @State private var showingMergeSuccess = false
    @State private var mergeSuccessMessage = ""

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: worktree.isPrimary ? "arrow.triangle.branch" : "arrow.triangle.2.circlepath")
                .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                .imageScale(.medium)
                .frame(width: 20, height: 20)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(worktree.branch ?? String(localized: "worktree.list.unknown"))
                        .font(.headline)
                        .foregroundStyle(isSelected ? Color.accentColor : Color.primary)

                    if worktree.isPrimary {
                        Text("worktree.detail.main", bundle: .main)
                            .font(.caption2)
                            .fontWeight(.semibold)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.blue, in: Capsule())
                    }
                }

                Text(worktree.path ?? "")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                if let lastAccessed = worktree.lastAccessed {
                    Text(String(localized: "worktree.list.lastAccessed \(lastAccessed.formatted(.relative(presentation: .named)))"))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }

                ActiveTabIndicatorView(
                    worktree: worktree,
                    tabStateManager: tabStateManager
                )
            }

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            isSelected
                ? RoundedRectangle(cornerRadius: 6)
                    .fill(Color.accentColor.opacity(0.15))
                : nil
        )
        .contentShape(Rectangle())
        .contextMenu {
            Button {
                showingDetails = true
            } label: {
                Label(String(localized: "worktree.detail.showDetails"), systemImage: "info.circle")
            }

            Divider()

            Button {
                if let path = worktree.path {
                    repositoryManager.openInTerminal(path)
                }
            } label: {
                Label(String(localized: "worktree.detail.openTerminal"), systemImage: "terminal")
            }

            Button {
                if let path = worktree.path {
                    repositoryManager.openInFinder(path)
                }
            } label: {
                Label(String(localized: "worktree.detail.openFinder"), systemImage: "folder")
            }

            Button {
                if let path = worktree.path {
                    repositoryManager.openInEditor(path)
                }
            } label: {
                Label(String(localized: "worktree.detail.openEditor"), systemImage: "chevron.left.forwardslash.chevron.right")
            }

            Divider()

            Menu {
                ForEach(worktreeStatuses.filter { $0.worktree.id != worktree.id }, id: \.worktree.id) { statusInfo in
                    Button {
                        performMerge(from: statusInfo.worktree, to: worktree)
                    } label: {
                        HStack {
                            Text(statusInfo.branch)
                            if statusInfo.hasUncommittedChanges {
                                Image(systemName: "exclamationmark.triangle")
                                    .foregroundStyle(.orange)
                            }
                        }
                    }
                }
            } label: {
                Label("Pull from", systemImage: "arrow.down.circle")
            }

            if !worktree.isPrimary {
                Divider()

                Button(role: .destructive) {
                    checkUnsavedChanges()
                } label: {
                    Label(String(localized: "worktree.detail.delete"), systemImage: "trash")
                }
            }
        }
        .sheet(isPresented: $showingDetails) {
            WorktreeDetailsSheet(worktree: worktree, repositoryManager: repositoryManager)
        }
        .alert(hasUnsavedChanges ? String(localized: "worktree.detail.unsavedChangesTitle") : String(localized: "worktree.detail.deleteConfirmTitle"), isPresented: $showingDeleteConfirmation) {
            Button(String(localized: "worktree.create.cancel"), role: .cancel) {}
            Button(String(localized: "worktree.detail.delete"), role: .destructive) {
                deleteWorktree()
            }
        } message: {
            if hasUnsavedChanges {
                Text(String(localized: "worktree.detail.unsavedChangesMessage \(worktree.branch ?? String(localized: "worktree.list.unknown"))"))
            } else {
                Text(String(localized: "worktree.detail.deleteConfirmMessageWithName \(worktree.branch ?? String(localized: "worktree.list.unknown"))"))
            }
        }
        .alert(String(localized: "worktree.list.error"), isPresented: .constant(errorMessage != nil)) {
            Button(String(localized: "worktree.list.ok")) {
                errorMessage = nil
            }
        } message: {
            if let error = errorMessage {
                Text(error)
            }
        }
        .alert("Merge Conflict", isPresented: $showingMergeConflict) {
            Button("OK") {
                mergeConflictFiles = []
            }
        } message: {
            VStack(alignment: .leading) {
                Text("Merge conflicts detected in the following files:")
                ForEach(mergeConflictFiles, id: \.self) { file in
                    Text("• \(file)")
                }
                Text("\nResolve conflicts manually and commit the changes.")
            }
        }
        .alert("Merge Successful", isPresented: $showingMergeSuccess) {
            Button("OK") {}
        } message: {
            Text(mergeSuccessMessage)
        }
        .alert("Merge Error", isPresented: .constant(mergeErrorMessage != nil)) {
            Button("OK") {
                mergeErrorMessage = nil
            }
        } message: {
            if let error = mergeErrorMessage {
                Text(error)
            }
        }
        .onAppear {
            loadWorktreeStatuses()
        }
    }

    // MARK: - Private Methods

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
                // Find closest worktree to select after deletion
                if let currentIndex = allWorktrees.firstIndex(where: { $0.id == worktree.id }) {
                    let nextWorktree: Worktree?

                    // Try next worktree, then previous, then nil
                    if currentIndex + 1 < allWorktrees.count {
                        nextWorktree = allWorktrees[currentIndex + 1]
                    } else if currentIndex > 0 {
                        nextWorktree = allWorktrees[currentIndex - 1]
                    } else {
                        nextWorktree = nil
                    }

                    try await repositoryManager.deleteWorktree(worktree, force: hasUnsavedChanges)

                    await MainActor.run {
                        selectedWorktree = nextWorktree
                    }
                } else {
                    try await repositoryManager.deleteWorktree(worktree, force: hasUnsavedChanges)
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                }
            }
        }
    }

    private func loadWorktreeStatuses() {
        guard !isLoadingStatuses else { return }

        Task {
            await MainActor.run {
                isLoadingStatuses = true
            }

            var statuses: [WorktreeStatusInfo] = []

            for wt in allWorktrees {
                do {
                    let hasChanges = try await repositoryManager.hasUnsavedChanges(wt)
                    let branch = wt.branch ?? "unknown"
                    statuses.append(WorktreeStatusInfo(
                        worktree: wt,
                        hasUncommittedChanges: hasChanges,
                        branch: branch
                    ))
                } catch {
                    // Skip worktrees with errors
                    continue
                }
            }

            await MainActor.run {
                worktreeStatuses = statuses
                isLoadingStatuses = false
            }
        }
    }

    private func performMerge(from source: Worktree, to target: Worktree) {
        Task {
            do {
                let result = try await repositoryManager.mergeFromWorktree(target: target, source: source)

                await MainActor.run {
                    switch result {
                    case .success:
                        mergeSuccessMessage = "Successfully merged \(source.branch ?? "unknown") into \(target.branch ?? "unknown")"
                        showingMergeSuccess = true

                    case .conflict(let files):
                        mergeConflictFiles = files
                        showingMergeConflict = true

                    case .alreadyUpToDate:
                        mergeSuccessMessage = "Already up to date with \(source.branch ?? "unknown")"
                        showingMergeSuccess = true
                    }

                    // Reload statuses after merge
                    loadWorktreeStatuses()
                }
            } catch {
                await MainActor.run {
                    mergeErrorMessage = error.localizedDescription
                }
            }
        }
    }
}
