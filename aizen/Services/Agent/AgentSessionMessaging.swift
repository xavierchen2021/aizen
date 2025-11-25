//
//  AgentSessionMessaging.swift
//  aizen
//
//  Messaging logic for AgentSession
//

import Foundation
import UniformTypeIdentifiers
import os.log

// MARK: - AgentSession + Messaging

@MainActor
extension AgentSession {
    /// Send a message to the agent with optional file attachments
    func sendMessage(content: String, attachments: [URL] = []) async throws {
        guard let sessionId = sessionId, isActive else {
            throw AgentSessionError.sessionNotActive
        }

        guard let client = acpClient else {
            throw AgentSessionError.clientNotInitialized
        }

        // Clear tool calls from previous message
        toolCalls = []

        // Mark any incomplete agent message as complete before starting new conversation turn
        markLastMessageComplete()

        // Build content blocks array
        var contentBlocks: [ContentBlock] = []

        // Add text content
        contentBlocks.append(.text(TextContent(text: content, annotations: nil, _meta: nil)))

        // Add attachments as resource blocks
        for attachmentURL in attachments {
            if let resourceBlock = try? await createResourceBlock(from: attachmentURL) {
                contentBlocks.append(resourceBlock)
            }
        }

        // Add user message to UI with all content blocks
        addUserMessage(content, contentBlocks: contentBlocks)

        // Send to agent - notifications will arrive asynchronously
        // Tool calls will mark messages complete, or if no tools, the final chunk completes it
        let response = try await client.sendPrompt(sessionId: sessionId, content: contentBlocks)

        // Mark the agent message as complete when the prompt finishes
        markLastMessageComplete()

        logger.debug("Prompt completed with stop reason: \(response.stopReason.rawValue)")
    }

    /// Cancel the current prompt turn
    func cancelCurrentPrompt() async {
        guard let sessionId = sessionId, isActive else {
            return
        }

        guard let client = acpClient else {
            return
        }

        do {
            // Send cancel notification
            try await client.sendCancelNotification(sessionId: sessionId)

            // Add system message indicating cancellation
            let cancelMessage = MessageItem(
                id: UUID().uuidString,
                role: .system,
                content: "Agent stopped by user",
                timestamp: Date()
            )
            messages.append(cancelMessage)

            // Clear current thought
            currentThought = nil
        } catch {
            logger.error("Error cancelling prompt: \(error.localizedDescription)")
        }
    }

    /// Create a resource content block from a file URL
    func createResourceBlock(from url: URL) async throws -> ContentBlock {
        // Ensure we can access the file
        guard url.startAccessingSecurityScopedResource() else {
            throw AgentSessionError.custom("Cannot access file: \(url.lastPathComponent)")
        }
        defer { url.stopAccessingSecurityScopedResource() }

        // Get MIME type
        let mimeType = getMimeType(for: url)

        // Determine if file is text or binary based on MIME type
        let isTextFile = mimeType?.hasPrefix("text/") ?? false ||
                        mimeType == "application/json" ||
                        mimeType == "application/xml" ||
                        mimeType == "application/javascript"

        if isTextFile {
            // Read as text
            let text = try String(contentsOf: url, encoding: .utf8)
            let textResource = EmbeddedTextResourceContents(
                text: text,
                mimeType: mimeType,
                uri: url.absoluteString,
                _meta: nil
            )
            let resourceContent = ResourceContent(
                resource: .text(textResource),
                annotations: nil,
                _meta: nil
            )
            return .resource(resourceContent)
        } else {
            // Read as binary and base64 encode
            let data = try Data(contentsOf: url)
            let base64 = data.base64EncodedString()
            let blobResource = EmbeddedBlobResourceContents(
                blob: base64,
                mimeType: mimeType,
                uri: url.absoluteString,
                _meta: nil
            )
            let resourceContent = ResourceContent(
                resource: .blob(blobResource),
                annotations: nil,
                _meta: nil
            )
            return .resource(resourceContent)
        }
    }

    /// Get MIME type from file URL
    func getMimeType(for url: URL) -> String? {
        if let utType = UTType(filenameExtension: url.pathExtension) {
            return utType.preferredMIMEType
        }
        return nil
    }

    // MARK: - Message Management

    func addUserMessage(_ content: String, contentBlocks: [ContentBlock] = []) {
        messages.append(MessageItem(
            id: UUID().uuidString,
            role: .user,
            content: content,
            timestamp: Date(),
            contentBlocks: contentBlocks
        ))
    }

    func markLastMessageComplete() {
        if let lastIndex = messages.lastIndex(where: { $0.role == .agent && !$0.isComplete }) {
            let completedMessage = messages[lastIndex]
            let executionTime = completedMessage.startTime.map { Date().timeIntervalSince($0) }
            messages[lastIndex] = MessageItem(
                id: completedMessage.id,
                role: completedMessage.role,
                content: completedMessage.content,
                timestamp: completedMessage.timestamp,
                toolCalls: completedMessage.toolCalls,
                contentBlocks: completedMessage.contentBlocks,
                isComplete: true,
                startTime: completedMessage.startTime,
                executionTime: executionTime,
                requestId: completedMessage.requestId
            )
        }
    }

    func addAgentMessage(
        _ content: String,
        toolCalls: [ToolCall] = [],
        contentBlocks: [ContentBlock] = [],
        isComplete: Bool = true,
        startTime: Date? = nil,
        requestId: String? = nil
    ) {
        let newMessage = MessageItem(
            id: UUID().uuidString,
            role: .agent,
            content: content,
            timestamp: Date(),
            toolCalls: toolCalls,
            contentBlocks: contentBlocks,
            isComplete: isComplete,
            startTime: startTime,
            executionTime: nil,
            requestId: requestId
        )
        messages.append(newMessage)
    }

    func addSystemMessage(_ content: String) {
        messages.append(MessageItem(
            id: UUID().uuidString,
            role: .system,
            content: content,
            timestamp: Date()
        ))
    }
}
