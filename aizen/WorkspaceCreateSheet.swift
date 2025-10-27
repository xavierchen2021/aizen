//
//  WorkspaceCreateSheet.swift
//  aizen
//
//  Created by Uladzislau Yakauleu on 17.10.25.
//

import SwiftUI

struct WorkspaceCreateSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var repositoryManager: RepositoryManager

    @State private var workspaceName = ""
    @State private var selectedColor: Color = .blue
    @State private var errorMessage: String?

    let availableColors: [Color] = [
        .blue, .purple, .pink, .red, .orange, .yellow, .green, .teal, .cyan, .indigo
    ]

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Create Workspace")
                    .font(.title2)
                    .fontWeight(.semibold)

                Spacer()
            }
            .padding()

            Divider()

            // Content
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Workspace Name")
                            .font(.headline)

                        TextField("e.g., Work, Personal, Open Source", text: $workspaceName)
                            .textFieldStyle(.roundedBorder)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Color (Optional)")
                            .font(.headline)

                        HStack(spacing: 12) {
                            ForEach(availableColors, id: \.self) { color in
                                Circle()
                                    .fill(color)
                                    .frame(width: 30, height: 30)
                                    .overlay {
                                        if selectedColor == color {
                                            Circle()
                                                .strokeBorder(.white, lineWidth: 3)
                                            Image(systemName: "checkmark")
                                                .foregroundStyle(.white)
                                                .font(.caption)
                                        }
                                    }
                                    .onTapGesture {
                                        selectedColor = color
                                    }
                            }
                        }
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

                Button("Create") {
                    createWorkspace()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(workspaceName.isEmpty)
            }
            .padding()
        }
        .frame(width: 450)
        .frame(minHeight: 250, maxHeight: 400)
    }

    private func createWorkspace() {
        do {
            let colorHex = selectedColor.toHex()
            _ = try repositoryManager.createWorkspace(name: workspaceName, colorHex: colorHex)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

#Preview {
    WorkspaceCreateSheet(
        repositoryManager: RepositoryManager(viewContext: PersistenceController.preview.container.viewContext)
    )
}
