//
//  TimelineItem.swift
//  aizen
//
//  Timeline item combining messages and tool calls
//

import Foundation

enum TimelineItem {
    case message(MessageItem)
    case toolCall(ToolCall)

    /// Dynamic id that changes when content changes - used by SwiftUI ForEach to force re-renders
    var id: String {
        switch self {
        case .message(let msg):
            // Include content length so SwiftUI re-renders when streaming content changes
            return "\(msg.id)-\(msg.content.count)"
        case .toolCall(let tool):
            // Include status so SwiftUI re-renders when tool status changes
            return "\(tool.id)-\(tool.status.rawValue)"
        }
    }

    /// Stable id for indexing - doesn't change when content updates
    var stableId: String {
        switch self {
        case .message(let msg):
            return msg.id
        case .toolCall(let tool):
            return tool.id
        }
    }

    var timestamp: Date {
        switch self {
        case .message(let msg):
            return msg.timestamp
        case .toolCall(let tool):
            return tool.timestamp
        }
    }
}
