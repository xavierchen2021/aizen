//
//  AgentSessionNotifications.swift
//  aizen
//
//  Notification handling logic for AgentSession
//

import Foundation
import os.log

// MARK: - AgentSession + Notifications

@MainActor
extension AgentSession {
    /// Start listening for notifications from the ACP client
    func startNotificationListener(client: ACPClient) {
        notificationTask = Task { @MainActor in
            for await notification in await client.notifications {
                handleNotification(notification)
            }
        }
    }

    /// Handle incoming session update notifications
    func handleNotification(_ notification: JSONRPCNotification) {
        guard notification.method == "session/update" else {
            return
        }

        do {
            let params = notification.params?.value as? [String: Any]
            let data = try JSONSerialization.data(withJSONObject: params ?? [:])
            let updateNotification = try JSONDecoder().decode(SessionUpdateNotification.self, from: data)

            let updateType = updateNotification.update.sessionUpdate

            // Handle different update types
            switch updateType {
            case "tool_call", "tool_call_update":
                // Tool call info is at the update level, not in an array
                if let toolCallId = updateNotification.update.toolCallId {
                    // If this is a new tool call (not an update), mark current message complete
                    // This creates a visual break between agent message and tool calls

                    if updateNotification.update.sessionUpdate == "tool_call" &&
                       !toolCalls.contains(where: { $0.toolCallId == toolCallId }) {
                        markLastMessageComplete()
                    }

                    // Check if this is an existing tool call
                    if let existingIndex = toolCalls.firstIndex(where: { $0.toolCallId == toolCallId }) {
                        // Update existing tool call with new fields
                        var updated = toolCalls[existingIndex]

                        if let status = updateNotification.update.status {
                            updated = ToolCall(
                                toolCallId: updated.toolCallId,
                                title: updateNotification.update.title ?? updated.title,
                                kind: updateNotification.update.kind ?? updated.kind,
                                status: status,
                                content: updated.content,
                                timestamp: updated.timestamp
                            )
                        }

                        toolCalls[existingIndex] = updated
                    } else if let title = updateNotification.update.title,
                              let kind = updateNotification.update.kind,
                              let status = updateNotification.update.status {
                        // New tool call
                        let toolCall = ToolCall(
                            toolCallId: toolCallId,
                            title: title,
                            kind: kind,
                            status: status,
                            content: [],
                            timestamp: Date()
                        )
                        toolCalls.append(toolCall)
                    }
                }

            case "agent_message_chunk":
                if let contentAny = updateNotification.update.content?.value {
                    currentThought = nil

                    if let contentDict = contentAny as? [String: Any],
                       let type = contentDict["type"] as? String,
                       type == "text",
                       let text = contentDict["text"] as? String {

                        // Append to last agent message if it exists and is still being streamed
                        if let lastMessage = messages.last,
                           lastMessage.role == .agent,
                           !lastMessage.isComplete {
                            let newContent = lastMessage.content + text
                            messages[messages.count - 1] = MessageItem(
                                id: lastMessage.id,
                                role: .agent,
                                content: newContent,
                                timestamp: lastMessage.timestamp,
                                toolCalls: lastMessage.toolCalls,
                                contentBlocks: lastMessage.contentBlocks,
                                isComplete: false,
                                startTime: lastMessage.startTime,
                                executionTime: lastMessage.executionTime,
                                requestId: lastMessage.requestId
                            )
                        } else {
                            // Start a new agent message
                            addAgentMessage(text, isComplete: false, startTime: Date())
                        }

                    }
                }

            case "user_message_chunk":
                // User messages already added when sending
                break

            case "agent_thought_chunk":
                if let contentAny = updateNotification.update.content?.value,
                   let contentDict = contentAny as? [String: Any],
                   let text = contentDict["text"] as? String {
                    logger.debug("Agent thought: \(text)")
                    // Accumulate thought chunks instead of replacing
                    if let existing = currentThought {
                        currentThought = existing + text
                    } else {
                        currentThought = text
                    }
                }

            case "plan":
                if let plan = updateNotification.update.plan {
                    agentPlan = plan
                }

            case "available_commands_update":
                if let commands = updateNotification.update.availableCommands {
                    availableCommands = commands
                }

            case "current_mode_update":
                if let mode = updateNotification.update.currentMode {
                    currentMode = mode
                }

            default:
                break
            }
        } catch {
            self.error = "Failed to parse session update: \(error.localizedDescription)"
        }
    }

    /// Update tool calls with new information
    func updateToolCalls(_ newToolCalls: [ToolCall]) {
        for newCall in newToolCalls {
            if let index = toolCalls.firstIndex(where: { $0.toolCallId == newCall.toolCallId }) {
                // Merge content instead of replacing entirely
                let existingContent = toolCalls[index].content
                let mergedContent = existingContent + newCall.content

                toolCalls[index] = ToolCall(
                    toolCallId: newCall.toolCallId,
                    title: newCall.title,
                    kind: newCall.kind,
                    status: newCall.status,
                    content: mergedContent
                )
            } else {
                toolCalls.append(newCall)
            }
        }
    }
}
