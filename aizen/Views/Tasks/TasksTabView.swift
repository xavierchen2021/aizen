//
//  TasksTabView.swift
//  aizen
//
//  Main tasks management view
//

import SwiftUI
import CoreData

struct TasksTabView: View {
    let worktree: Worktree
    
    @Environment(\.managedObjectContext) private var viewContext
    @StateObject private var viewModel: TaskViewModel
    
    init(worktree: Worktree) {
        self.worktree = worktree
        let context = PersistenceController.shared.container.viewContext
        _viewModel = StateObject(wrappedValue: TaskViewModel(worktree: worktree, context: context))
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("tasks.title")
                    .font(.headline)
                
                Spacer()
                
                Button {
                    viewModel.editingTask = nil
                    viewModel.showingEditor = true
                } label: {
                    Label("tasks.addNew", systemImage: "plus")
                        .font(.system(size: 13))
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
            
            Divider()
            
            // Task List
            if viewModel.tasks.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(viewModel.tasks) { task in
                            TaskItemView(
                                task: task,
                                onEdit: {
                                    viewModel.editingTask = task
                                    viewModel.showingEditor = true
                                },
                                onDelete: {
                                    viewModel.deleteTask(task)
                                },
                                onCopyMarkdown: {
                                    viewModel.copyAsMarkdown(task)
                                },
                                onExecute: {
                                    viewModel.executeTask(task)
                                }
                            )
                        }
                    }
                    .padding()
                }
            }
        }
        .sheet(isPresented: $viewModel.showingEditor) {
            TaskEditorView(
                task: viewModel.editingTask,
                onSave: { title, description, resources, customPrefix, markdownTemplate in
                    if let task = viewModel.editingTask {
                        viewModel.updateTask(task, title: title, description: description, resources: resources, customPrefix: customPrefix, markdownTemplate: markdownTemplate)
                    } else {
                        viewModel.createTask(title: title, description: description, resources: resources, customPrefix: customPrefix, markdownTemplate: markdownTemplate)
                    }
                    viewModel.showingEditor = false
                },
                onCancel: {
                    viewModel.showingEditor = false
                }
            )
        }
    }
    
    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "checklist")
                .font(.system(size: 64))
                .foregroundStyle(.tertiary)
            
            Text("tasks.emptyState")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text("tasks.emptyState.hint")
                .font(.callout)
                .foregroundStyle(.secondary)
            
            Button {
                viewModel.editingTask = nil
                viewModel.showingEditor = true
            } label: {
                Label("tasks.addNew", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
