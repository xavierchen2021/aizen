//
//  ACPToolTypes.swift
//  aizen
//
//  Agent Client Protocol - Tool Call Types
//

import Foundation

// MARK: - Tool Calls

struct ToolCall: Codable, Identifiable {
    let toolCallId: String
    let title: String
    let kind: ToolKind
    let status: ToolStatus
    let content: [ContentBlock]
    let locations: [ToolLocation]?
    let rawInput: AnyCodable?
    let rawOutput: AnyCodable?
    var timestamp: Date = Date()

    var id: String { toolCallId }

    enum CodingKeys: String, CodingKey {
        case toolCallId = "tool_call_id"
        case title, kind, status, content, locations
        case rawInput = "raw_input"
        case rawOutput = "raw_output"
    }
}

enum ToolKind: String, Codable {
    case read
    case edit
    case delete
    case move
    case search
    case execute
    case think
    case fetch
    case switchMode = "switch_mode"
    case plan
    case exitPlanMode = "exit_plan_mode"
    case other
}

enum ToolStatus: String, Codable {
    case pending
    case inProgress = "in_progress"
    case completed
    case failed
}

struct ToolLocation: Codable {
    let path: String?
    let line: Int?  // Line number (0-indexed position)
    let _meta: [String: AnyCodable]?

    enum CodingKeys: String, CodingKey {
        case path, line, _meta
    }
}

// MARK: - Available Commands

struct AvailableCommand: Codable {
    let name: String
    let description: String
    let input: CommandInputSpec?
    let _meta: [String: AnyCodable]?

    enum CodingKeys: String, CodingKey {
        case name, description, input, _meta
    }
}

struct CommandInputSpec: Codable {
    let type: String
    let properties: [String: AnyCodable]?
    let required: [String]?
}

// MARK: - Agent Plan

enum PlanPriority: String, Codable {
    case low
    case medium
    case high
}

enum PlanEntryStatus: String, Codable {
    case pending
    case inProgress = "in_progress"
    case completed
}

struct PlanEntry: Codable {
    let content: String
    let priority: PlanPriority
    let status: PlanEntryStatus
    let _meta: [String: AnyCodable]?

    enum CodingKeys: String, CodingKey {
        case content, priority, status, _meta
    }
}

struct Plan: Codable {
    let entries: [PlanEntry]
}
