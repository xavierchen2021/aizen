//
//  ACPTypes.swift
//  aizen
//
//  Agent Client Protocol type definitions
//

import Foundation

// MARK: - JSON-RPC Message Types

enum ACPMessage: Codable {
    case request(JSONRPCRequest)
    case response(JSONRPCResponse)
    case notification(JSONRPCNotification)

    enum CodingKeys: String, CodingKey {
        case jsonrpc, method, id
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let hasMethod = container.contains(.method)
        let hasId = container.contains(.id)

        if hasMethod && hasId {
            self = .request(try JSONRPCRequest(from: decoder))
        } else if hasMethod {
            self = .notification(try JSONRPCNotification(from: decoder))
        } else {
            self = .response(try JSONRPCResponse(from: decoder))
        }
    }

    func encode(to encoder: Encoder) throws {
        switch self {
        case .request(let req):
            try req.encode(to: encoder)
        case .response(let res):
            try res.encode(to: encoder)
        case .notification(let notif):
            try notif.encode(to: encoder)
        }
    }
}

struct JSONRPCRequest: Codable {
    let jsonrpc: String = "2.0"
    let id: RequestId
    let method: String
    let params: AnyCodable?

    enum CodingKeys: String, CodingKey {
        case jsonrpc, id, method, params
    }
}

struct JSONRPCResponse: Codable {
    let jsonrpc: String = "2.0"
    let id: RequestId
    let result: AnyCodable?
    let error: JSONRPCError?

    enum CodingKeys: String, CodingKey {
        case jsonrpc, id, result, error
    }
}

struct JSONRPCNotification: Codable {
    let jsonrpc: String = "2.0"
    let method: String
    let params: AnyCodable?

    enum CodingKeys: String, CodingKey {
        case jsonrpc, method, params
    }
}

struct JSONRPCError: Codable {
    let code: Int
    let message: String
    let data: AnyCodable?
}

enum RequestId: Codable, Hashable {
    case string(String)
    case number(Int)

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let str = try? container.decode(String.self) {
            self = .string(str)
        } else if let num = try? container.decode(Int.self) {
            self = .number(num)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid RequestId")
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let str):
            try container.encode(str)
        case .number(let num):
            try container.encode(num)
        }
    }
}

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

    enum CodingKeys: String, CodingKey {
        case loadSession = "load_session"
        case mcpCapabilities = "mcp_capabilities"
    }
}

struct MCPCapabilities: Codable {
    let http: Bool?
    let ssh: Bool?
}

// MARK: - Content Types

enum ContentBlock: Codable {
    case text(TextContent)
    case image(ImageContent)
    case resource(ResourceContent)
    case audio(AudioContent)
    case embeddedResource(EmbeddedResourceContent)
    case diff(DiffContent)
    case terminalEmbed(TerminalEmbedContent)

    enum CodingKeys: String, CodingKey {
        case type
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)

        switch type {
        case "text":
            self = .text(try TextContent(from: decoder))
        case "image":
            self = .image(try ImageContent(from: decoder))
        case "resource":
            self = .resource(try ResourceContent(from: decoder))
        case "audio":
            self = .audio(try AudioContent(from: decoder))
        case "embedded_resource":
            self = .embeddedResource(try EmbeddedResourceContent(from: decoder))
        case "diff":
            self = .diff(try DiffContent(from: decoder))
        case "terminal_embed":
            self = .terminalEmbed(try TerminalEmbedContent(from: decoder))
        default:
            throw DecodingError.dataCorruptedError(forKey: .type, in: container, debugDescription: "Unknown content type: \(type)")
        }
    }

    func encode(to encoder: Encoder) throws {
        switch self {
        case .text(let content):
            try content.encode(to: encoder)
        case .image(let content):
            try content.encode(to: encoder)
        case .resource(let content):
            try content.encode(to: encoder)
        case .audio(let content):
            try content.encode(to: encoder)
        case .embeddedResource(let content):
            try content.encode(to: encoder)
        case .diff(let content):
            try content.encode(to: encoder)
        case .terminalEmbed(let content):
            try content.encode(to: encoder)
        }
    }
}

struct TextContent: Codable {
    let type: String = "text"
    let text: String
}

struct ImageContent: Codable {
    let type: String = "image"
    let data: String
    let mimeType: String
}

struct ResourceContent: Codable {
    let type: String = "resource"
    let resource: ResourceData

    struct ResourceData: Codable {
        let uri: String
        let mimeType: String?
        let text: String?
        let blob: String?

        enum CodingKeys: String, CodingKey {
            case uri, mimeType, text, blob
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(uri, forKey: .uri)
            // Only encode non-nil optional fields
            if let mimeType = mimeType {
                try container.encode(mimeType, forKey: .mimeType)
            }
            if let text = text {
                try container.encode(text, forKey: .text)
            }
            if let blob = blob {
                try container.encode(blob, forKey: .blob)
            }
        }
    }

    init(uri: String, mimeType: String?, text: String?, blob: String?) {
        self.resource = ResourceData(uri: uri, mimeType: mimeType, text: text, blob: blob)
    }

    enum CodingKeys: String, CodingKey {
        case type, resource
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(type, forKey: .type)
        try container.encode(resource, forKey: .resource)
    }
}

struct AudioContent: Codable {
    let type: String = "audio"
    let data: String
    let mimeType: String
}

struct EmbeddedResourceContent: Codable {
    let type: String = "embedded_resource"
    let uri: String
    let mimeType: String?
    let content: [ContentBlock]
}

struct DiffContent: Codable {
    let type: String = "diff"
    let oldText: String
    let newText: String
    let path: String?

    enum CodingKeys: String, CodingKey {
        case type, path
        case oldText = "old_text"
        case newText = "new_text"
    }
}

struct TerminalEmbedContent: Codable {
    let type: String = "terminal_embed"
    let terminalId: TerminalId
    let command: String
    let output: String
    let exitCode: Int?

    enum CodingKeys: String, CodingKey {
        case type, command, output
        case terminalId = "terminal_id"
        case exitCode = "exit_code"
    }
}

// MARK: - Tool Calls

struct ToolCall: Codable, Identifiable {
    let toolCallId: String
    let title: String
    let kind: ToolKind
    let status: ToolStatus
    let content: [ContentBlock]

    var id: String { toolCallId }

    enum CodingKeys: String, CodingKey {
        case toolCallId = "tool_call_id"
        case title, kind, status, content
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

// MARK: - Request/Response Types

struct InitializeRequest: Codable {
    let protocolVersion: Int
    let clientCapabilities: ClientCapabilities

    enum CodingKeys: String, CodingKey {
        case protocolVersion
        case clientCapabilities
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

struct MCPServerConfig: Codable {
    let name: String
    let command: String
    let args: [String]?
    let env: [String: String]?
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
    let startLine: Int?
    let endLine: Int?

    enum CodingKeys: String, CodingKey {
        case path
        case startLine = "start_line"
        case endLine = "end_line"
    }
}

struct ReadTextFileResponse: Codable {
    let content: String
    let totalLines: Int

    enum CodingKeys: String, CodingKey {
        case content
        case totalLines = "total_lines"
    }
}

struct WriteTextFileRequest: Codable {
    let path: String
    let content: String
}

struct WriteTextFileResponse: Codable {
    let success: Bool
}

// MARK: - Terminal Types

struct TerminalId: Codable, Hashable {
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

struct CreateTerminalRequest: Codable {
    let command: String
    let args: [String]?
    let cwd: String?
    let env: [String: String]?
    let outputLimit: Int?

    enum CodingKeys: String, CodingKey {
        case command, args, cwd, env
        case outputLimit = "output_limit"
    }
}

struct CreateTerminalResponse: Codable {
    let terminalId: TerminalId

    enum CodingKeys: String, CodingKey {
        case terminalId = "terminal_id"
    }
}

struct TerminalOutputRequest: Codable {
    let terminalId: TerminalId

    enum CodingKeys: String, CodingKey {
        case terminalId = "terminal_id"
    }
}

struct TerminalOutputResponse: Codable {
    let output: String
    let exitCode: Int?

    enum CodingKeys: String, CodingKey {
        case output
        case exitCode = "exit_code"
    }
}

struct WaitForExitRequest: Codable {
    let terminalId: TerminalId

    enum CodingKeys: String, CodingKey {
        case terminalId = "terminal_id"
    }
}

struct KillTerminalRequest: Codable {
    let terminalId: TerminalId

    enum CodingKeys: String, CodingKey {
        case terminalId = "terminal_id"
    }
}

struct ReleaseTerminalRequest: Codable {
    let terminalId: TerminalId

    enum CodingKeys: String, CodingKey {
        case terminalId = "terminal_id"
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

// MARK: - Available Commands

struct AvailableCommand: Codable {
    let name: String
    let description: String
    let inputSpec: CommandInputSpec?

    enum CodingKeys: String, CodingKey {
        case name, description
        case inputSpec = "input_spec"
    }
}

struct CommandInputSpec: Codable {
    let type: String
    let properties: [String: AnyCodable]?
    let required: [String]?
}

// MARK: - Agent Plan

struct PlanEntry: Codable {
    let content: String
    let activeForm: String?
    let status: PlanEntryStatus

    enum CodingKeys: String, CodingKey {
        case content
        case activeForm = "active_form"
        case status
    }
}

enum PlanEntryStatus: String, Codable {
    case pending
    case inProgress = "in_progress"
    case completed
    case cancelled
}

struct Plan: Codable {
    let entries: [PlanEntry]
}

// MARK: - Session Update Types

enum SessionUpdateType: String, Codable {
    case userMessageChunk = "user_message_chunk"
    case agentMessageChunk = "agent_message_chunk"
    case agentThoughtChunk = "agent_thought_chunk"
    case toolCall = "tool_call"
    case toolCallUpdate = "tool_call_update"
    case plan = "plan"
    case availableCommandsUpdate = "available_commands_update"
    case currentModeUpdate = "current_mode_update"
}

struct SessionUpdateNotification: Codable {
    let sessionId: SessionId
    let update: SessionUpdate

    enum CodingKeys: String, CodingKey {
        case sessionId
        case update
    }
}

struct SessionUpdate: Codable {
    let sessionUpdate: String
    let content: AnyCodable? // Can be ContentBlock or array depending on update type
    let toolCalls: [ToolCall]?
    let plan: Plan?
    let availableCommands: [AvailableCommand]?
    let currentMode: SessionMode?

    // Individual tool call fields (when sessionUpdate is "tool_call" or "tool_call_update")
    let toolCallId: String?
    let title: String?
    let kind: ToolKind?
    let status: ToolStatus?
    let locations: [ToolLocation]?
    let rawInput: AnyCodable?

    enum CodingKeys: String, CodingKey {
        case sessionUpdate
        case content
        case toolCalls
        case plan
        case availableCommands
        case currentMode
        case toolCallId
        case title
        case kind
        case status
        case locations
        case rawInput
    }
}

struct ToolLocation: Codable {
    let path: String?
    let startLine: Int?
    let endLine: Int?

    enum CodingKeys: String, CodingKey {
        case path
        case startLine
        case endLine
    }
}

// MARK: - AnyCodable Helper

struct AnyCodable: Codable {
    let value: Any

    init(_ value: Any) {
        self.value = value
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if let bool = try? container.decode(Bool.self) {
            value = bool
        } else if let int = try? container.decode(Int.self) {
            value = int
        } else if let double = try? container.decode(Double.self) {
            value = double
        } else if let string = try? container.decode(String.self) {
            value = string
        } else if let array = try? container.decode([AnyCodable].self) {
            value = array.map { $0.value }
        } else if let dict = try? container.decode([String: AnyCodable].self) {
            value = dict.mapValues { $0.value }
        } else {
            value = NSNull()
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()

        switch value {
        case let bool as Bool:
            try container.encode(bool)
        case let int as Int:
            try container.encode(int)
        case let double as Double:
            try container.encode(double)
        case let string as String:
            try container.encode(string)
        case let array as [Any]:
            try container.encode(array.map { AnyCodable($0) })
        case let dict as [String: Any]:
            try container.encode(dict.mapValues { AnyCodable($0) })
        case is NSNull:
            try container.encodeNil()
        default:
            try container.encodeNil()
        }
    }
}
