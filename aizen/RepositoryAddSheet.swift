//
//  RepositoryAddSheet.swift
//  aizen
//
//  Created by Uladzislau Yakauleu on 17.10.25.
//

import SwiftUI

enum AddRepositoryMode {
    case clone
    case existing
}

struct RepositoryAddSheet: View {
    @Environment(\.dismiss) private var dismiss
    let workspace: Workspace
    @ObservedObject var repositoryManager: RepositoryManager

    @State private var mode: AddRepositoryMode = .existing
    @State private var cloneURL = ""
    @State private var selectedPath = ""
    @State private var isProcessing = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Add Repository")
                    .font(.title2)
                    .fontWeight(.semibold)

                Spacer()
            }
            .padding()

            Divider()

            // Content
            ScrollView {
                VStack(spacing: 20) {
                    // Mode picker
                    Picker("Mode", selection: $mode) {
                        Label("Open Existing", systemImage: "folder")
                            .tag(AddRepositoryMode.existing)
                        Label("Clone from URL", systemImage: "arrow.down.circle")
                            .tag(AddRepositoryMode.clone)
                    }
                    .pickerStyle(.segmented)
                    .padding(.top)

                    if mode == .clone {
                        cloneView
                    } else {
                        existingView
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
            }

            Divider()

            // Footer
            HStack {
                Spacer()

                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button(mode == .clone ? "Clone" : "Add") {
                    addRepository()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(isProcessing || !isValid)
            }
            .padding()
        }
        .frame(width: 550)
        .frame(minHeight: 300, maxHeight: 500)
    }

    private var cloneView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Repository URL")
                .font(.headline)

            TextField("https://github.com/user/repo.git", text: $cloneURL)
                .textFieldStyle(.roundedBorder)

            Text("Clone Location")
                .font(.headline)
                .padding(.top, 8)

            HStack {
                TextField("Select destination folder", text: $selectedPath)
                    .textFieldStyle(.roundedBorder)
                    .disabled(true)

                Button("Choose...") {
                    selectCloneDestination()
                }
            }

            Text("The repository will be cloned to the selected location")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var existingView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Repository Location")
                .font(.headline)

            HStack {
                TextField("Select repository folder", text: $selectedPath)
                    .textFieldStyle(.roundedBorder)
                    .disabled(true)

                Button("Choose...") {
                    selectExistingRepository()
                }
            }

            Text("Select a folder containing a git repository")
                .font(.caption)
                .foregroundStyle(.secondary)

            if !selectedPath.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Selected:")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text(selectedPath)
                        .font(.caption)
                        .fontDesign(.monospaced)
                        .foregroundStyle(.primary)
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
                }
                .padding(.top, 8)
            }
        }
    }

    private var isValid: Bool {
        if mode == .clone {
            return !cloneURL.isEmpty && !selectedPath.isEmpty
        } else {
            return !selectedPath.isEmpty
        }
    }

    private func selectExistingRepository() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Select a git repository folder"

        if panel.runModal() == .OK, let url = panel.url {
            selectedPath = url.path
        }
    }

    private func selectCloneDestination() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Select where to clone the repository"

        if panel.runModal() == .OK, let url = panel.url {
            selectedPath = url.path
        }
    }

    private func addRepository() {
        guard !isProcessing else { return }

        isProcessing = true
        errorMessage = nil

        Task {
            do {
                if mode == .clone {
                    _ = try await repositoryManager.cloneRepository(
                        url: cloneURL,
                        destinationPath: selectedPath,
                        workspace: workspace
                    )
                } else {
                    _ = try await repositoryManager.addExistingRepository(
                        path: selectedPath,
                        workspace: workspace
                    )
                }

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
    RepositoryAddSheet(
        workspace: Workspace(),
        repositoryManager: RepositoryManager(viewContext: PersistenceController.preview.container.viewContext)
    )
}
