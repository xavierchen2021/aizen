import SwiftUI

struct BranchSelectorView: View {
    let repository: Repository
    let repositoryManager: RepositoryManager
    @Binding var selectedBranch: BranchInfo?

    // Optional: Allow branch creation
    var allowCreation: Bool = false
    var onCreateBranch: ((String) -> Void)?

    @State private var searchText: String = ""
    @State private var branches: [BranchInfo] = []
    @State private var filteredBranches: [BranchInfo] = []
    @State private var isLoading: Bool = true
    @State private var errorMessage: String?

    private let pageSize = 30
    @State private var displayedCount = 30

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            // Search field
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)

                TextField(allowCreation ? "Search or create new one" : "Search branches", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .onSubmit {
                        if allowCreation && !searchText.isEmpty && filteredBranches.isEmpty {
                            createBranch()
                        }
                    }

                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(12)
            .background(Color(nsColor: .textBackgroundColor))
            .cornerRadius(6)
            .padding()

            Divider()

            // Branch list
            if isLoading {
                VStack(spacing: 12) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Loading branches...")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = errorMessage {
                VStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 24))
                        .foregroundStyle(.orange)
                    Text(error)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()
            } else if filteredBranches.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 24))
                        .foregroundStyle(.tertiary)
                    Text(searchText.isEmpty ? "No branches found" : "No branches match '\(searchText)'")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(filteredBranches.prefix(displayedCount)), id: \.id) { branch in
                            branchRow(branch)
                        }

                        // Create branch option if no matches and creation allowed
                        if allowCreation && !searchText.isEmpty && filteredBranches.isEmpty {
                            Button {
                                createBranch()
                            } label: {
                                HStack {
                                    Image(systemName: "plus.circle")
                                        .font(.system(size: 12))
                                        .foregroundStyle(.blue)

                                    Text("Create branch: \(searchText)")
                                        .font(.system(size: 12))
                                        .foregroundStyle(.primary)

                                    Spacer()
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 12)
                            }
                            .buttonStyle(.plain)
                        }

                        // Load more row
                        if displayedCount < filteredBranches.count {
                            Button {
                                withAnimation {
                                    displayedCount = min(displayedCount + pageSize, filteredBranches.count)
                                }
                            } label: {
                                HStack {
                                    Image(systemName: "arrow.down.circle")
                                        .font(.system(size: 11))
                                        .foregroundStyle(.blue)

                                    Text("Load \(min(pageSize, filteredBranches.count - displayedCount)) more...")
                                        .font(.system(size: 11))
                                        .foregroundStyle(.blue)

                                    Spacer()

                                    Text("\(displayedCount) of \(filteredBranches.count)")
                                        .font(.system(size: 10, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 12)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .frame(width: 350, height: 400)
        .onAppear {
            loadBranches()
        }
        .onChange(of: searchText) { _ in
            filterBranches()
        }
    }

    private func branchRow(_ branch: BranchInfo) -> some View {
        Button {
            selectedBranch = branch
            if !allowCreation {
                dismiss()
            }
        } label: {
            HStack {
                Image(systemName: "arrow.triangle.branch")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)

                Text(branch.name)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(branch.id == selectedBranch?.id ? .primary : .secondary)

                Spacer()

                if branch.id == selectedBranch?.id {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10))
                        .foregroundStyle(.blue)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(branch.id == selectedBranch?.id ? Color.accentColor.opacity(0.1) : Color.clear)
        }
        .buttonStyle(.plain)
    }

    private func createBranch() {
        guard !searchText.isEmpty else { return }
        onCreateBranch?(searchText)
        dismiss()
    }

    private func loadBranches() {
        isLoading = true
        errorMessage = nil

        Task {
            do {
                let loadedBranches = try await repositoryManager.getBranches(for: repository)
                await MainActor.run {
                    branches = loadedBranches
                    filterBranches()
                    isLoading = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = "Failed to load branches: \(error.localizedDescription)"
                    isLoading = false
                }
            }
        }
    }

    private func filterBranches() {
        if searchText.isEmpty {
            filteredBranches = branches
        } else {
            filteredBranches = branches.filter {
                $0.name.localizedCaseInsensitiveContains(searchText)
            }
        }
        // Reset pagination when filtering changes
        displayedCount = pageSize
    }
}

// MARK: - Compact Display Button

struct BranchSelectorButton: View {
    let selectedBranch: BranchInfo?
    let defaultBranch: String
    @Binding var isPresented: Bool

    var body: some View {
        Button {
            isPresented = true
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "arrow.triangle.branch")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)

                Text(selectedBranch?.name ?? defaultBranch)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(6)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color(nsColor: .separatorColor).opacity(0.3), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    BranchSelectorView(
        repository: Repository(),
        repositoryManager: RepositoryManager(viewContext: PersistenceController.preview.container.viewContext),
        selectedBranch: .constant(nil)
    )
}
