//
//  RootView.swift
//  aizen
//
//  Root view that handles full-window overlays above the toolbar
//

import SwiftUI
import CoreData

struct RootView: View {
    let context: NSManagedObjectContext

    @State private var gitChangesContext: GitChangesContext?
    @State private var gitPanelController: GitPanelWindowController?
    @StateObject private var repositoryManager: RepositoryManager

    init(context: NSManagedObjectContext) {
        self.context = context
        _repositoryManager = StateObject(wrappedValue: RepositoryManager(viewContext: context))
    }

    var body: some View {
        ContentView(
            context: context,
            repositoryManager: repositoryManager,
            gitChangesContext: $gitChangesContext
        )
        .onChange(of: gitChangesContext) { newContext in
            if let context = newContext, !context.worktree.isDeleted {
                // Close existing window if any
                gitPanelController?.close()

                // Create and show new window
                gitPanelController = GitPanelWindowController(
                    context: context,
                    repositoryManager: repositoryManager,
                    onClose: {
                        gitChangesContext = nil
                        gitPanelController = nil
                    }
                )
                gitPanelController?.showWindow(nil)
            } else if newContext == nil {
                // Close window when context is cleared
                gitPanelController?.close()
                gitPanelController = nil
            }
        }
    }
}

// Context for git changes sheet
struct GitChangesContext: Identifiable, Equatable {
    let id = UUID()
    let worktree: Worktree
    let service: GitRepositoryService

    static func == (lhs: GitChangesContext, rhs: GitChangesContext) -> Bool {
        lhs.id == rhs.id
    }
}
