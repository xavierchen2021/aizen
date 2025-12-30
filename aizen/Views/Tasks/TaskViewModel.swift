//
//  TaskViewModel.swift
//  aizen
//
//  View model for task management
//

import Foundation
import SwiftUI
import CoreData
import Combine
import os.log

@MainActor
class TaskViewModel: ObservableObject {
    let worktree: Worktree
    let viewContext: NSManagedObjectContext
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.aizen", category: "TaskViewModel")
    
    @Published var tasks: [TaskItem] = []
    @Published var showingEditor = false
    @Published var editingTask: TaskItem?
    
    init(worktree: Worktree, context: NSManagedObjectContext) {
        self.worktree = worktree
        self.viewContext = context
        loadTasks()
    }
    
    // MARK: - Load Tasks
    
    func loadTasks() {
        let request: NSFetchRequest<TaskItem> = TaskItem.fetchRequest()
        request.predicate = NSPredicate(format: "worktree == %@", worktree)
        request.sortDescriptors = [NSSortDescriptor(keyPath: \TaskItem.createdAt, ascending: false)]
        
        do {
            tasks = try viewContext.fetch(request)
        } catch {
            logger.error("Failed to load tasks: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Create Task
    
    func createTask(title: String, description: String, resources: String, customPrefix: String, markdownTemplate: String) {
        let task = TaskItem(context: viewContext)
        task.id = UUID()
        task.title = title
        task.taskDescription = description
        task.resources = resources
        task.customPrefix = customPrefix
        task.markdownTemplate = markdownTemplate
        task.createdAt = Date()
        task.updatedAt = Date()
        task.worktree = worktree
        
        do {
            try viewContext.save()
            loadTasks()
            logger.info("Created task: \(title, privacy: .public)")
        } catch {
            logger.error("Failed to create task: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Update Task
    
    func updateTask(_ task: TaskItem, title: String, description: String, resources: String, customPrefix: String, markdownTemplate: String) {
        task.title = title
        task.taskDescription = description
        task.resources = resources
        task.customPrefix = customPrefix
        task.markdownTemplate = markdownTemplate
        task.updatedAt = Date()
        
        do {
            try viewContext.save()
            loadTasks()
            logger.info("Updated task: \(title, privacy: .public)")
        } catch {
            logger.error("Failed to update task: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Delete Task
    
    func deleteTask(_ task: TaskItem) {
        viewContext.delete(task)
        
        do {
            try viewContext.save()
            loadTasks()
            logger.info("Deleted task: \(task.title ?? "unknown", privacy: .public)")
        } catch {
            logger.error("Failed to delete task: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Copy as Markdown
    
    func copyAsMarkdown(_ task: TaskItem) {
        let markdown = task.toMarkdown()
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(markdown, forType: .string)
        
        ToastManager.shared.show("已复制为 Markdown", type: .success)
    }
    
    // MARK: - Execute Task
    
    func executeTask(_ task: TaskItem) {
        let markdown = task.toMarkdown()
        
        // Create a new chat session or use existing one
        guard let context = worktree.managedObjectContext else { return }
        
        // Get the most recent chat session for this worktree
        let chatSessions = (worktree.chatSessions as? Set<ChatSession>) ?? []
        let sortedSessions = chatSessions
            .filter { !$0.isDeleted }
            .sorted { ($0.createdAt ?? Date.distantPast) > ($1.createdAt ?? Date.distantPast) }
        
        if let recentSession = sortedSessions.first, let sessionId = recentSession.id {
            // Use most recent session
            let attachment = ChatAttachment.reviewComments(markdown)
            ChatSessionManager.shared.setPendingAttachments([attachment], for: sessionId)
            
            NotificationCenter.default.post(
                name: .switchToChat,
                object: nil,
                userInfo: ["sessionId": sessionId]
            )
            
            ToastManager.shared.show("已跳转到聊天", type: .success)
        } else {
            // Create new chat session with a valid default agent
            Task {
                let validAgent = await AgentRouter().getValidDefaultAgent()
                
                let session = ChatSession(context: context)
                session.id = UUID()
                session.agentName = validAgent
                session.createdAt = Date()
                session.worktree = worktree
                session.title = validAgent
                
                do {
                    try context.save()
                    let newSessionId = session.id!
                    
                    // Set pending attachment with markdown content
                    let attachment = ChatAttachment.reviewComments(markdown)
                    ChatSessionManager.shared.setPendingAttachments([attachment], for: newSessionId)
                    
                    // Post notification to switch to chat
                    NotificationCenter.default.post(
                        name: .switchToChat,
                        object: nil,
                        userInfo: ["sessionId": newSessionId]
                    )
                    
                    await MainActor.run {
                        ToastManager.shared.show("已跳转到聊天", type: .success)
                    }
                } catch {
                    logger.error("Failed to create chat session: \(error.localizedDescription)")
                }
            }
        }
    }
}
