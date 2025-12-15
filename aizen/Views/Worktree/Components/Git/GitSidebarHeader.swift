import SwiftUI

struct GitSidebarHeader: View {
    let gitStatus: GitStatus
    let isOperationPending: Bool
    let hasUnstagedChanges: Bool
    let onStageAll: (@escaping () -> Void) -> Void
    let onUnstageAll: () -> Void
    let onDiscardAll: () -> Void
    let onCleanUntracked: () -> Void

    @State private var showDiscardConfirmation = false
    @State private var showCleanConfirmation = false

    var body: some View {
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

            Menu {
                Button {
                    showDiscardConfirmation = true
                } label: {
                    Label("Discard All Changes", systemImage: "arrow.uturn.backward")
                }
                .disabled(gitStatus.stagedFiles.isEmpty && gitStatus.modifiedFiles.isEmpty)

                Button {
                    showCleanConfirmation = true
                } label: {
                    Label("Remove Untracked Files", systemImage: "trash")
                }
                .disabled(gitStatus.untrackedFiles.isEmpty)
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .frame(width: 20)
            .disabled(isOperationPending)
        }
        .padding(.horizontal, 12)
        .frame(height: 44)
        .alert("Discard All Changes?", isPresented: $showDiscardConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Discard", role: .destructive) {
                onDiscardAll()
            }
        } message: {
            Text("This will reset all staged and modified files to HEAD. This cannot be undone.")
        }
        .alert("Remove Untracked Files?", isPresented: $showCleanConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Remove", role: .destructive) {
                onCleanUntracked()
            }
        } message: {
            Text("This will permanently delete \(gitStatus.untrackedFiles.count) untracked file(s). This cannot be undone.")
        }
    }

    private var headerTitle: String {
        let total = gitStatus.stagedFiles.count + gitStatus.modifiedFiles.count + gitStatus.untrackedFiles.count
        return total == 0 ? "No Changes" : "\(total) Change\(total == 1 ? "" : "s")"
    }
}
