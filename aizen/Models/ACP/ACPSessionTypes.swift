//
//  ACPSessionTypes.swift
//  aizen
//
//  Agent Client Protocol - Session, Mode, Model, and Request/Response Types
//

import Foundation

// MARK: - ACP Protocol Types

struct SessionId: Codable, Hashable {
    let value: String

    init(_ value: String) {
        self.value = value
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        value = try container.decode(String.self)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(value)
    }
}

// MARK: - Capabilities

struct ClientCapabilities: Codable {
    let fs: FileSystemCapabilities
    let terminal: Bool

    enum CodingKeys: String, CodingKey {
        case fs
        case terminal
    }
}

struct FileSystemCapabilities: Codable {
    let readTextFile: Bool
    let writeTextFile: Bool

    enum CodingKeys: String, CodingKey {
        case readTextFile
        case writeTextFile
    }
}

struct AgentCapabilities: Codable {
    let loadSession: Bool?
    let mcpCapabilities: MCPCapabilities?
    let promptCapabilities: PromptCapabilities?
    let sessionCapabilities: SessionCapabilities?

    enum CodingKeys: String, CodingKey {
        case loadSession
        case mcpCapabilities
        case promptCapabilities
        case sessionCapabilities
    }
}

struct MCPCapabilities: Codable {
    let http: Bool?
    let sse: Bool?

    enum CodingKeys: String, CodingKey {
        case http
        case sse
    }
}

struct PromptCapabilities: Codable {
    let audio: Bool?
    let embeddedContext: Bool?
    let image: Bool?
}

struct SessionCapabilities: Codable {
    let _meta: [String: AnyCodable]?
}

// MARK: - Client Info

struct ClientInfo: Codable {
    let name: String
    let title: String?
    let version: String?
}

// MARK: - Request/Response Types

struct InitializeRequest: Codable {
    let protocolVersion: Int
    let clientCapabilities: ClientCapabilities
    let clientInfo: ClientInfo?

    enum CodingKeys: String, CodingKey {
        case protocolVersion
        case clientCapabilities
        case clientInfo
    }
}

struct InitializeResponse: Codable {
    let protocolVersion: Int
    let agentInfo: AgentInfo?
    let agentCapabilities: AgentCapabilities
    let authMethods: [AuthMethod]?

    enum CodingKeys: String, CodingKey {
        case protocolVersion
        case agentInfo
        case agentCapabilities
        case authMethods
    }
}

struct AgentInfo: Codable {
    let name: String
    let version: String
}

struct NewSessionRequest: Codable {
    let cwd: String
    let mcpServers: [MCPServerConfig]

    enum CodingKeys: String, CodingKey {
        case cwd
        case mcpServers
    }
}

// Type discriminator for MCP servers
enum MCPServerConfig: Codable {
    case stdio(StdioServerConfig)
    case http(HTTPServerConfig)
    case sse(SSEServerConfig)

    enum CodingKeys: String, CodingKey {
        case type
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)

        switch type {
        case "stdio":
            self = .stdio(try StdioServerConfig(from: decoder))
        case "http":
            self = .http(try HTTPServerConfig(from: decoder))
        case "sse":
            self = .sse(try SSEServerConfig(from: decoder))
        default:
            throw DecodingError.dataCorruptedError(forKey: .type, in: container, debugDescription: "Unknown MCP server type: \(type)")
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case .stdio(let config):
            try container.encode("stdio", forKey: .type)
            try config.encode(to: encoder)
        case .http(let config):
            try container.encode("http", forKey: .type)
            try config.encode(to: encoder)
        case .sse(let config):
            try container.encode("sse", forKey: .type)
            try config.encode(to: encoder)
        }
    }
}

struct StdioServerConfig: Codable {
    let name: String
    let command: String  // Required for stdio
    let args: [String]  // Required for stdio
    let env: [EnvVariable]  // Required for stdio
    let _meta: [String: AnyCodable]?

    enum CodingKeys: String, CodingKey {
        case name, command, args, env, _meta
    }
}

struct HTTPServerConfig: Codable {
    let name: String
    let url: String  // Required for http
    let headers: [HTTPHeader]?  // Optional for http
    let _meta: [String: AnyCodable]?

    enum CodingKeys: String, CodingKey {
        case name, url, headers, _meta
    }
}

struct SSEServerConfig: Codable {
    let name: String
    let url: String  // Required for sse
    let headers: [HTTPHeader]?  // Optional for sse
    let _meta: [String: AnyCodable]?

    enum CodingKeys: String, CodingKey {
        case name, url, headers, _meta
    }
}

struct HTTPHeader: Codable {
    let name: String
    let value: String
    let _meta: [String: AnyCodable]?

    enum CodingKeys: String, CodingKey {
        case name, value, _meta
    }
}

struct NewSessionResponse: Codable {
    let sessionId: SessionId
    let modes: ModesInfo?
    let models: ModelsInfo?

    enum CodingKeys: String, CodingKey {
        case sessionId
        case modes
        case models
    }
}

struct LoadSessionRequest: Codable {
    let sessionId: SessionId
    let cwd: String?
    let mcpServers: [MCPServerConfig]?

    enum CodingKeys: String, CodingKey {
        case sessionId
        case cwd
        case mcpServers
    }
}

struct LoadSessionResponse: Codable {
    let sessionId: SessionId

    enum CodingKeys: String, CodingKey {
        case sessionId
    }
}

struct CancelSessionRequest: Codable {
    let sessionId: SessionId

    enum CodingKeys: String, CodingKey {
        case sessionId
    }
}

struct SessionPromptRequest: Codable {
    let sessionId: SessionId
    let prompt: [ContentBlock]

    enum CodingKeys: String, CodingKey {
        case sessionId
        case prompt
    }
}

struct SessionPromptResponse: Codable {
    let stopReason: StopReason

    enum CodingKeys: String, CodingKey {
        case stopReason
    }
}

enum StopReason: String, Codable {
    case endTurn = "end_turn"
    case maxTokens = "max_tokens"
    case maxTurnRequests = "max_turn_requests"
    case refusal = "refusal"
    case cancelled = "cancelled"
}

// MARK: - Session Mode Types

enum SessionMode: String, Codable {
    case code
    case chat
    case ask
}

struct ModeInfo: Codable, Hashable {
    let id: String
    let name: String
    let description: String?
}

struct ModesInfo: Codable {
    let currentModeId: String
    let availableModes: [ModeInfo]

    enum CodingKeys: String, CodingKey {
        case currentModeId = "currentModeId"
        case availableModes = "availableModes"
    }
}

struct SetModeRequest: Codable {
    let sessionId: SessionId
    let modeId: String

    enum CodingKeys: String, CodingKey {
        case sessionId
        case modeId
    }
}

struct SetModeResponse: Codable {
    let success: Bool
}

// MARK: - Model Selection Types

struct ModelInfo: Codable, Hashable {
    let modelId: String
    let name: String
    let description: String?

    enum CodingKeys: String, CodingKey {
        case modelId = "modelId"
        case name
        case description
    }
}

struct ModelsInfo: Codable {
    let currentModelId: String
    let availableModels: [ModelInfo]

    enum CodingKeys: String, CodingKey {
        case currentModelId = "currentModelId"
        case availableModels = "availableModels"
    }
}

struct SetModelRequest: Codable {
    let sessionId: SessionId
    let modelId: String

    enum CodingKeys: String, CodingKey {
        case sessionId
        case modelId
    }
}

struct SetModelResponse: Codable {
    let success: Bool
}

// MARK: - Authentication Types

struct AuthMethod: Codable {
    let id: String
    let name: String
    let description: String?
}

struct AuthenticateRequest: Codable {
    let methodId: String
    let credentials: [String: String]?

    enum CodingKeys: String, CodingKey {
        case methodId
        case credentials
    }
}

struct AuthenticateResponse: Codable {
    let success: Bool
    let error: String?
}

// MARK: - File System Types

struct ReadTextFileRequest: Codable {
    let path: String
    let line: Int?  // Start line (1-based per ACP spec)
    let limit: Int?  // Number of lines to read
    let sessionId: String
    let _meta: [String: AnyCodable]?

    enum CodingKeys: String, CodingKey {
        case path, line, limit, sessionId, _meta
    }
}

struct ReadTextFileResponse: Codable {
    let content: String
    let totalLines: Int?
    let _meta: [String: AnyCodable]?

    enum CodingKeys: String, CodingKey {
        case content
        case totalLines = "total_lines"
        case _meta
    }
}

struct WriteTextFileRequest: Codable {
    let path: String
    let content: String
    let sessionId: String
    let _meta: [String: AnyCodable]?

    enum CodingKeys: String, CodingKey {
        case path, content, sessionId, _meta
    }
}

struct WriteTextFileResponse: Codable {
    let _meta: [String: AnyCodable]?

    enum CodingKeys: String, CodingKey {
        case _meta
    }
}

// MARK: - Permission Types

struct RequestPermissionRequest: Codable {
    let message: String?
    let options: [PermissionOption]?
    let sessionId: SessionId?
    let toolCall: PermissionToolCall?

    enum CodingKeys: String, CodingKey {
        case message
        case options
        case sessionId
        case toolCall
    }
}

struct PermissionOption: Codable {
    let kind: String
    let name: String
    let optionId: String

    enum CodingKeys: String, CodingKey {
        case kind
        case name
        case optionId
    }
}

struct PermissionToolCall: Codable {
    let toolCallId: String
    let rawInput: AnyCodable?

    enum CodingKeys: String, CodingKey {
        case toolCallId
        case rawInput
    }
}

enum PermissionDecision: String, Codable {
    case allowOnce = "allow_once"
    case allowAlways = "allow_always"
    case rejectOnce = "reject_once"
    case rejectAlways = "reject_always"
}

struct RequestPermissionResponse: Codable {
    let outcome: PermissionOutcome

    enum CodingKeys: String, CodingKey {
        case outcome
    }
}

struct PermissionOutcome: Codable {
    let outcome: String // "selected" or "cancelled"
    let optionId: String?

    enum CodingKeys: String, CodingKey {
        case outcome
        case optionId
    }

    init(optionId: String) {
        self.outcome = "selected"
        self.optionId = optionId
    }

    init(cancelled: Bool) {
        self.outcome = "cancelled"
        self.optionId = nil
    }
}

// MARK: - Session Update Types

struct SessionUpdateNotification: Codable {
    let sessionId: SessionId
    let update: SessionUpdate
    let _meta: [String: AnyCodable]?

    enum CodingKeys: String, CodingKey {
        case sessionId, update, _meta
    }
}

enum SessionUpdate: Codable {
    case userMessageChunk(ContentBlock)
    case agentMessageChunk(ContentBlock)
    case agentThoughtChunk(ContentBlock)
    case toolCall(ToolCallUpdate)
    case toolCallUpdate(ToolCallUpdateDetails)
    case plan(Plan)
    case availableCommandsUpdate([AvailableCommand])
    case currentModeUpdate(String)

    enum CodingKeys: String, CodingKey {
        case sessionUpdate
        case content  // For ContentChunk types (user/agent/thought message chunks)
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let updateType = try container.decode(String.self, forKey: .sessionUpdate)

        switch updateType {
        case "user_message_chunk":
            // ContentChunk wraps content in a "content" field
            let content = try container.decode(ContentBlock.self, forKey: .content)
            self = .userMessageChunk(content)
        case "agent_message_chunk":
            // ContentChunk wraps content in a "content" field
            let content = try container.decode(ContentBlock.self, forKey: .content)
            self = .agentMessageChunk(content)
        case "agent_thought_chunk":
            // ContentChunk wraps content in a "content" field
            let content = try container.decode(ContentBlock.self, forKey: .content)
            self = .agentThoughtChunk(content)
        case "tool_call":
            let toolCall = try ToolCallUpdate(from: decoder)
            self = .toolCall(toolCall)
        case "tool_call_update":
            let details = try ToolCallUpdateDetails(from: decoder)
            self = .toolCallUpdate(details)
        case "plan":
            let plan = try Plan(from: decoder)
            self = .plan(plan)
        case "available_commands_update":
            let commands = try decoder.container(keyedBy: AnyCodingKey.self).decode([AvailableCommand].self, forKey: AnyCodingKey(stringValue: "availableCommands")!)
            self = .availableCommandsUpdate(commands)
        case "current_mode_update":
            let modeId = try decoder.container(keyedBy: AnyCodingKey.self).decode(String.self, forKey: AnyCodingKey(stringValue: "currentModeId")!)
            self = .currentModeUpdate(modeId)
        default:
            throw DecodingError.dataCorruptedError(forKey: .sessionUpdate, in: container, debugDescription: "Unknown session update type: \(updateType)")
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case .userMessageChunk(let content):
            try container.encode("user_message_chunk", forKey: .sessionUpdate)
            try container.encode(content, forKey: .content)
        case .agentMessageChunk(let content):
            try container.encode("agent_message_chunk", forKey: .sessionUpdate)
            try container.encode(content, forKey: .content)
        case .agentThoughtChunk(let content):
            try container.encode("agent_thought_chunk", forKey: .sessionUpdate)
            try container.encode(content, forKey: .content)
        case .toolCall(let toolCall):
            try container.encode("tool_call", forKey: .sessionUpdate)
            try toolCall.encode(to: encoder)
        case .toolCallUpdate(let details):
            try container.encode("tool_call_update", forKey: .sessionUpdate)
            try details.encode(to: encoder)
        case .plan(let plan):
            try container.encode("plan", forKey: .sessionUpdate)
            try plan.encode(to: encoder)
        case .availableCommandsUpdate(let commands):
            try container.encode("available_commands_update", forKey: .sessionUpdate)
            var innerContainer = encoder.container(keyedBy: AnyCodingKey.self)
            try innerContainer.encode(commands, forKey: AnyCodingKey(stringValue: "availableCommands")!)
        case .currentModeUpdate(let modeId):
            try container.encode("current_mode_update", forKey: .sessionUpdate)
            var innerContainer = encoder.container(keyedBy: AnyCodingKey.self)
            try innerContainer.encode(modeId, forKey: AnyCodingKey(stringValue: "currentModeId")!)
        }
    }
}

struct ToolCallUpdate: Codable {
    let toolCallId: String
    let title: String
    let kind: ToolKind
    let status: ToolStatus
    let content: [ToolCallContent]
    let locations: [ToolLocation]?
    let rawInput: AnyCodable?
    let rawOutput: AnyCodable?
    let _meta: [String: AnyCodable]?

    enum CodingKeys: String, CodingKey {
        case toolCallId
        case title, kind, status, content, locations
        case rawInput
        case rawOutput
        case _meta
    }
}

struct ToolCallUpdateDetails: Codable {
    let toolCallId: String
    let status: ToolStatus?
    let locations: [ToolLocation]?
    let kind: ToolKind?
    let title: String?
    let content: [ToolCallContent]?
    let rawInput: AnyCodable?
    let rawOutput: AnyCodable?
    let _meta: [String: AnyCodable]?

    enum CodingKeys: String, CodingKey {
        case toolCallId
        case status, locations, kind, title, content
        case rawInput
        case rawOutput
        case _meta
    }
}

// Helper for encoding arbitrary keys
private struct AnyCodingKey: CodingKey {
    let stringValue: String
    let intValue: Int?

    init?(stringValue: String) {
        self.stringValue = stringValue
        self.intValue = nil
    }

    init?(intValue: Int) {
        self.stringValue = String(intValue)
        self.intValue = intValue
    }
}

// MARK: - Convenience accessors for SessionUpdate

extension SessionUpdate {
    /// Discriminant for UI handling
    var sessionUpdate: String {
        switch self {
        case .userMessageChunk: return "user_message_chunk"
        case .agentMessageChunk: return "agent_message_chunk"
        case .agentThoughtChunk: return "agent_thought_chunk"
        case .toolCall: return "tool_call"
        case .toolCallUpdate: return "tool_call_update"
        case .plan: return "plan"
        case .availableCommandsUpdate: return "available_commands_update"
        case .currentModeUpdate: return "current_mode_update"
        }
    }

    /// Raw content as JSON-friendly structure
    var content: AnyCodable? {
        switch self {
        case .userMessageChunk(let block),
             .agentMessageChunk(let block),
             .agentThoughtChunk(let block):
            return AnyCodable(block.toDictionary())
        case .toolCall(let call):
            let blocks = call.content.map { $0.toDictionary() }
            return AnyCodable(blocks)
        case .toolCallUpdate(let details):
            if let raw = details.rawOutput {
                return raw
            }
            return nil
        default:
            return nil
        }
    }

    var toolCalls: [ToolCall]? {
        switch self {
        case .toolCall(let update):
            return [
                ToolCall(
                    toolCallId: update.toolCallId,
                    title: update.title,
                    kind: update.kind,
                    status: update.status,
                    content: update.content,
                    locations: update.locations,
                    rawInput: update.rawInput,
                    rawOutput: update.rawOutput,
                    timestamp: Date()
                )
            ]
        default:
            return nil
        }
    }

    var toolCallId: String? {
        switch self {
        case .toolCall(let update): return update.toolCallId
        case .toolCallUpdate(let details): return details.toolCallId
        default: return nil
        }
    }

    var title: String? {
        switch self {
        case .toolCall(let update): return update.title
        case .toolCallUpdate: return nil
        default: return nil
        }
    }

    var kind: ToolKind? {
        switch self {
        case .toolCall(let update): return update.kind
        default: return nil
        }
    }

    var status: ToolStatus? {
        switch self {
        case .toolCall(let update): return update.status
        case .toolCallUpdate(let details): return details.status
        default: return nil
        }
    }

    var locations: [ToolLocation]? {
        switch self {
        case .toolCall(let update): return update.locations
        case .toolCallUpdate(let details): return details.locations
        default: return nil
        }
    }

    var rawInput: AnyCodable? {
        switch self {
        case .toolCall(let update): return update.rawInput
        default: return nil
        }
    }

    var rawOutput: AnyCodable? {
        switch self {
        case .toolCall(let update): return update.rawOutput
        case .toolCallUpdate(let details): return details.rawOutput
        default: return nil
        }
    }

    var plan: Plan? {
        switch self {
        case .plan(let plan): return plan
        default: return nil
        }
    }

    var availableCommands: [AvailableCommand]? {
        switch self {
        case .availableCommandsUpdate(let commands): return commands
        default: return nil
        }
    }

    var currentMode: String? {
        switch self {
        case .currentModeUpdate(let mode): return mode
        default: return nil
        }
    }
}

// MARK: - ContentBlock helpers

private extension ContentBlock {
    func toDictionary() -> [String: Any] {
        guard let data = try? JSONEncoder().encode(self),
              let object = try? JSONSerialization.jsonObject(with: data),
              let dict = object as? [String: Any] else {
            return [:]
        }
        return dict
    }
}

private extension ToolCallContent {
    func toDictionary() -> [String: Any] {
        guard let data = try? JSONEncoder().encode(self),
              let object = try? JSONSerialization.jsonObject(with: data),
              let dict = object as? [String: Any] else {
            return [:]
        }
        return dict
    }
}
