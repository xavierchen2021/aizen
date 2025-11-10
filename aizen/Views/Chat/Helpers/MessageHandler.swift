//
//  MessageHandler.swift
//  aizen
//
//  Handles message persistence to Core Data
//

import CoreData
import Foundation
import os.log

@MainActor
class MessageHandler {
    private let viewContext: NSManagedObjectContext
    private let session: ChatSession
    private let logger = Logger.forCategory("MessageHandler")

    init(viewContext: NSManagedObjectContext, session: ChatSession) {
        self.viewContext = viewContext
        self.session = session
    }

    func saveMessage(content: String, role: String, agentName: String) {
        let message = ChatMessage(context: viewContext)
        message.id = UUID()
        message.timestamp = Date()
        message.role = role
        message.agentName = agentName
        message.contentJSON = content
        message.session = session

        session.lastMessageAt = Date()

        do {
            try viewContext.save()
        } catch {
            logger.error("Failed to save message: \(error.localizedDescription)")
        }
    }
}
