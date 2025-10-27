//
//  ContentView.swift
//  aizen
//
//  Created by Uladzislau Yakauleu on 17.10.25.
//

import SwiftUI
import CoreData

struct ContentView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @StateObject private var repositoryManager: RepositoryManager

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Workspace.order, ascending: true)],
        animation: .default)
    private var workspaces: FetchedResults<Workspace>

    @State private var selectedWorkspace: Workspace?
    @State private var selectedRepository: Repository?
    @State private var selectedWorktree: Worktree?
    @State private var searchText = ""
    @State private var showingAddRepository = false
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var previousWorktree: Worktree?

    init(context: NSManagedObjectContext) {
        _repositoryManager = StateObject(wrappedValue: RepositoryManager(viewContext: context))
    }

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            // Left sidebar - workspaces and repositories
            WorkspaceSidebarView(
                workspaces: Array(workspaces),
                selectedWorkspace: $selectedWorkspace,
                selectedRepository: $selectedRepository,
                selectedWorktree: $selectedWorktree,
                searchText: $searchText,
                showingAddRepository: $showingAddRepository,
                repositoryManager: repositoryManager
            )
            .navigationSplitViewColumnWidth(min: 200, ideal: 250, max: 300)
        } content: {
            // Middle panel - worktree list or detail
            if let repository = selectedRepository {
                WorktreeListView(
                    repository: repository,
                    selectedWorktree: $selectedWorktree,
                    repositoryManager: repositoryManager
                )
                .navigationSplitViewColumnWidth(min: 250, ideal: 300, max: 400)
            } else {
                ContentUnavailableView(
                    "Select a Repository",
                    systemImage: "folder.badge.gearshape",
                    description: Text("Choose a repository to view its worktrees")
                )
                .navigationSplitViewColumnWidth(min: 250, ideal: 300, max: 400)
            }
        } detail: {
            // Right panel - worktree details
            if let worktree = selectedWorktree {
                WorktreeDetailView(
                    worktree: worktree,
                    repositoryManager: repositoryManager
                )
            } else {
                ContentUnavailableView(
                    "Select a Worktree",
                    systemImage: "arrow.triangle.branch",
                    description: Text("Choose a worktree to view details and actions")
                )
            }
        }
        .sheet(isPresented: $showingAddRepository) {
            if let workspace = selectedWorkspace ?? workspaces.first {
                RepositoryAddSheet(
                    workspace: workspace,
                    repositoryManager: repositoryManager
                )
            }
        }
        .onAppear {
            if selectedWorkspace == nil {
                selectedWorkspace = workspaces.first
            }
        }
        .onChange(of: selectedWorktree) { oldValue, newValue in
            if let newWorktree = newValue, previousWorktree != newWorktree {
                withAnimation(.easeInOut(duration: 0.3)) {
                    columnVisibility = .doubleColumn
                }
                previousWorktree = newWorktree
            }
        }
    }
}

#Preview {
    ContentView(context: PersistenceController.preview.container.viewContext)
        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
}
