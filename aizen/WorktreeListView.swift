//
//  WorktreeListView.swift
//  aizen
//
//  Created by Uladzislau Yakauleu on 17.10.25.
//

import SwiftUI

struct WorktreeListView: View {
    @ObservedObject var repository: Repository
    @Binding var selectedWorktree: Worktree?
    @ObservedObject var repositoryManager: RepositoryManager

    @State private var showingCreateWorktree = false
    @State private var searchText = ""

    var worktrees: [Worktree] {
        let wts = (repository.worktrees as? Set<Worktree>) ?? []
        let sorted = wts.sorted { wt1, wt2 in
            if wt1.isPrimary != wt2.isPrimary {
                return wt1.isPrimary
            }
            return (wt1.branch ?? "") < (wt2.branch ?? "")
        }

        if searchText.isEmpty {
            return sorted
        } else {
            return sorted.filter { worktree in
                (worktree.branch ?? "").localizedCaseInsensitiveContains(searchText) ||
                (worktree.path ?? "").localizedCaseInsensitiveContains(searchText)
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Search field
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search worktrees", text: $searchText)
                    .textFieldStyle(.plain)

                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            List {
                ForEach(worktrees, id: \.id) { worktree in
                    WorktreeListRowView(
                        worktree: worktree,
                        isSelected: selectedWorktree?.id == worktree.id,
                        repositoryManager: repositoryManager
                    )
                    .onTapGesture {
                        selectedWorktree = worktree
                    }
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
        }
        .navigationTitle(repository.name ?? "Unknown")
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Spacer()
            }
            ToolbarItem(placement: .automatic) {
                Button {
                    showingCreateWorktree = true
                } label: {
                    Label("Add Worktree", systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $showingCreateWorktree) {
            WorktreeCreateSheet(
                repository: repository,
                repositoryManager: repositoryManager
            )
        }
    }
}

struct WorktreeListRowView: View {
    @ObservedObject var worktree: Worktree
    let isSelected: Bool
    @ObservedObject var repositoryManager: RepositoryManager

    @State private var showingDetails = false
    @State private var showingDeleteConfirmation = false
    @State private var hasUnsavedChanges = false
    @State private var errorMessage: String?

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: worktree.isPrimary ? "arrow.triangle.branch" : "arrow.triangle.2.circlepath")
                .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                .imageScale(.medium)
                .frame(width: 20, height: 20)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(worktree.branch ?? "Unknown")
                        .font(.headline)
                        .foregroundStyle(isSelected ? Color.accentColor : Color.primary)

                    if worktree.isPrimary {
                        Text("MAIN")
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
                    Text("Last accessed: \(lastAccessed, style: .relative)")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
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
                Label("Show Details", systemImage: "info.circle")
            }

            Divider()

            Button {
                if let path = worktree.path {
                    repositoryManager.openInTerminal(path)
                }
            } label: {
                Label("Open in Terminal", systemImage: "terminal")
            }

            Button {
                if let path = worktree.path {
                    repositoryManager.openInFinder(path)
                }
            } label: {
                Label("Open in Finder", systemImage: "folder")
            }

            Button {
                if let path = worktree.path {
                    repositoryManager.openInEditor(path)
                }
            } label: {
                Label("Open in Editor", systemImage: "chevron.left.forwardslash.chevron.right")
            }

            if !worktree.isPrimary {
                Divider()

                Button(role: .destructive) {
                    checkUnsavedChanges()
                } label: {
                    Label("Delete Worktree", systemImage: "trash")
                }
            }
        }
        .sheet(isPresented: $showingDetails) {
            WorktreeDetailsSheet(worktree: worktree, repositoryManager: repositoryManager)
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
                Text("Are you sure you want to delete the worktree '\(worktree.branch ?? "Unknown")'? This action cannot be undone.")
            }
        }
        .alert("Error", isPresented: .constant(errorMessage != nil)) {
            Button("OK") {
                errorMessage = nil
            }
        } message: {
            if let error = errorMessage {
                Text(error)
            }
        }
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
}

struct WorktreeDetailsSheet: View {
    @ObservedObject var worktree: Worktree
    @ObservedObject var repositoryManager: RepositoryManager
    @Environment(\.dismiss) private var dismiss

    @State private var currentBranch = ""
    @State private var ahead = 0
    @State private var behind = 0
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(worktree.branch ?? "Unknown")
                        .font(.title2)
                        .fontWeight(.bold)

                    if worktree.isPrimary {
                        Text("PRIMARY WORKTREE")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(.blue, in: Capsule())
                    }
                }

                Spacer()

                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding()

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Branch status
                    if isLoading {
                        HStack {
                            ProgressView()
                            Text("Loading status...")
                                .foregroundStyle(.secondary)
                        }
                    } else if ahead > 0 || behind > 0 {
                        HStack(spacing: 16) {
                            if ahead > 0 {
                                Label("\(ahead) ahead", systemImage: "arrow.up.circle.fill")
                                    .foregroundStyle(.green)
                            }
                            if behind > 0 {
                                Label("\(behind) behind", systemImage: "arrow.down.circle.fill")
                                    .foregroundStyle(.orange)
                            }
                        }
                    } else {
                        Label("Up to date", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    }

                    // Info
                    GroupBox("Information") {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text("Path")
                                    .foregroundStyle(.secondary)
                                    .frame(width: 80, alignment: .leading)
                                Text(worktree.path ?? "Unknown")
                                    .textSelection(.enabled)
                            }

                            Divider()

                            HStack {
                                Text("Branch")
                                    .foregroundStyle(.secondary)
                                    .frame(width: 80, alignment: .leading)
                                Text(currentBranch.isEmpty ? (worktree.branch ?? "Unknown") : currentBranch)
                                    .textSelection(.enabled)
                            }

                            if let lastAccessed = worktree.lastAccessed {
                                Divider()
                                HStack {
                                    Text("Last Accessed")
                                        .foregroundStyle(.secondary)
                                        .frame(width: 80, alignment: .leading)
                                    Text(lastAccessed.formatted(date: .abbreviated, time: .shortened))
                                }
                            }
                        }
                        .padding(8)
                    }

                    if let error = errorMessage {
                        Text(error)
                            .foregroundStyle(.red)
                            .padding()
                            .background(.red.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
                    }
                }
                .padding()
            }
        }
        .frame(width: 500, height: 400)
        .onAppear {
            refreshStatus()
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
}

#Preview {
    WorktreeListView(
        repository: Repository(),
        selectedWorktree: .constant(nil),
        repositoryManager: RepositoryManager(viewContext: PersistenceController.preview.container.viewContext)
    )
}
