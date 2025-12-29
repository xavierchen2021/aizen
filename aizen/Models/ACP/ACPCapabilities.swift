//
//  ACPCapabilities.swift
//  aizen
//
//  Agent Client Protocol - Capability Types
//

import Foundation

// MARK: - Client Capabilities

struct ClientCapabilities: Codable {
    let fs: FileSystemCapabilities
    let terminal: Bool
    let meta: [String: AnyCodable]?

    init(fs: FileSystemCapabilities, terminal: Bool, meta: [String: AnyCodable]? = nil) {
        self.fs = fs
        self.terminal = terminal
        self.meta = meta
    }

    enum CodingKeys: String, CodingKey {
        case fs
        case terminal
        case meta
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

// MARK: - Agent Capabilities

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
