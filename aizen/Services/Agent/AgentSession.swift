//
//  AgentSession.swift
//  aizen
//
//  Created by Uladzislau Yakauleu on 17.10.25.
//

import Foundation
import Combine
import UniformTypeIdentifiers
import os.log

/// ObservableObject that wraps ACPClient for managing an agent session
@MainActor
class AgentSession: ObservableObject, ACPClientDelegate {
    // MARK: - Published Properties

    @Published var sessionId: SessionId?
    @Published var agentName: String
    @Published var workingDirectory: String
    @Published var toolCalls: [ToolCall] = []
    @Published var messages: [MessageItem] = []
    @Published var isActive: Bool = false
    @Published var currentThought: String?
    @Published var error: String?

    @Published var authMethods: [AuthMethod] = []
    @Published var needsAuthentication: Bool = false
    @Published var availableCommands: [AvailableCommand] = []
    @Published var currentMode: SessionMode?
    @Published var agentPlan: Plan?
    @Published var availableModes: [ModeInfo] = []
    @Published var availableModels: [ModelInfo] = []
    @Published var currentModeId: String?
    @Published var currentModelId: String?

    // Agent setup state
    @Published var needsAgentSetup: Bool = false
    @Published var missingAgentName: String?
    @Published var setupError: String?

    // Version update state
    @Published var needsUpdate: Bool = false
    @Published var versionInfo: AgentVersionInfo?

    // MARK: - Internal Properties

    var acpClient: ACPClient?
    var cancellables = Set<AnyCancellable>()
    var process: Process?
    var notificationTask: Task<Void, Never>?
    let logger = Logger.forCategory("AgentSession")

    // Delegates
    private let fileSystemDelegate = AgentFileSystemDelegate()
    private let terminalDelegate = AgentTerminalDelegate()
    let permissionHandler = AgentPermissionHandler()

    // MARK: - Initialization

    init(agentName: String = "", workingDirectory: String = "") {
        self.agentName = agentName
        self.workingDirectory = workingDirectory
    }

    // MARK: - Session Management

    /// Start a new agent session
    func start(agentName: String, workingDir: String) async throws {
        guard !isActive else {
            throw AgentSessionError.sessionAlreadyActive
        }

        self.agentName = agentName
        self.workingDirectory = workingDir

        // Get agent executable path from registry
        let agentPath = AgentRegistry.shared.getAgentPath(for: agentName)
        let isValid = await AgentRegistry.shared.validateAgent(named: agentName)

        guard let agentPath = agentPath, isValid else {
            // Agent not configured or invalid - trigger setup dialog
            needsAgentSetup = true
            missingAgentName = agentName
            setupError = nil
            return
        }

        // Initialize ACP client
        let client = ACPClient()
        self.acpClient = client

        // Set self as delegate
        await client.setDelegate(self)

        // Get launch arguments for this agent
        let launchArgs = AgentRegistry.shared.getAgentLaunchArgs(for: agentName)

        // Launch the agent process with correct working directory
        try await client.launch(agentPath: agentPath, arguments: launchArgs, workingDirectory: workingDir)

        // Initialize protocol
        let initResponse = try await client.initialize(
            protocolVersion: 1,
            capabilities: ClientCapabilities(
                fs: FileSystemCapabilities(
                    readTextFile: true,
                    writeTextFile: true
                ),
                terminal: true
            )
        )

        // Check agent version in background (non-blocking)
        Task {
            let versionInfo = await AgentVersionChecker.shared.checkVersion(for: agentName)
            await MainActor.run {
                if versionInfo.isOutdated {
                    self.versionInfo = versionInfo
                    self.needsUpdate = true
                    self.addSystemMessage("⚠️ Update available: \(agentName) v\(versionInfo.current ?? "?") → v\(versionInfo.latest ?? "?")")
                }
            }
        }

        if let authMethods = initResponse.authMethods, !authMethods.isEmpty {
            self.authMethods = authMethods

            if let savedAuthMethod = AgentRegistry.shared.getAuthPreference(for: agentName) {
                if savedAuthMethod == "skip" {
                    try await createSessionDirectly(workingDir: workingDir, client: client)
                    return
                } else {
                    do {
                        try await performAuthentication(client: client, authMethodId: savedAuthMethod, workingDir: workingDir)
                        return
                    } catch {
                        logger.error("Saved auth method '\(savedAuthMethod)' failed for \(agentName): \(error.localizedDescription)")
                        addSystemMessage("⚠️ Saved authentication method failed. Please re-authenticate.")
                        // Fall through to show auth dialog
                    }
                }
            }

            // No saved preference or auth failed - show auth dialog
            // Set session as active so UI can display properly, even though we're waiting for auth
            self.isActive = true
            self.needsAuthentication = true
            startNotificationListener(client: client)

            addSystemMessage("Authentication required for \(agentName). Available methods: \(authMethods.map { $0.name }.joined(separator: ", "))")
            return
        }

        // Create new session
        let sessionResponse = try await client.newSession(
            workingDirectory: workingDir,
            mcpServers: []
        )

        self.sessionId = sessionResponse.sessionId
        self.isActive = true

        if let modesInfo = sessionResponse.modes {
            self.availableModes = modesInfo.availableModes
            self.currentModeId = modesInfo.currentModeId
        }

        if let modelsInfo = sessionResponse.models {
            self.availableModels = modelsInfo.availableModels
            self.currentModelId = modelsInfo.currentModelId
        }

        startNotificationListener(client: client)

        let metadata = AgentRegistry.shared.getMetadata(for: agentName)
        let displayName = metadata?.name ?? agentName
        addSystemMessage("Session started with \(displayName) in \(workingDir)")
    }

    /// Set mode by ID
    func setModeById(_ modeId: String) async throws {
        guard let sessionId = sessionId, let client = acpClient else {
            throw AgentSessionError.sessionNotActive
        }

        let response = try await client.setMode(sessionId: sessionId, modeId: modeId)
        if response.success {
            currentModeId = modeId
            if let modeName = availableModes.first(where: { $0.id == modeId })?.name {
                addSystemMessage("Mode changed to \(modeName)")
            }
        }
    }

    /// Set model
    func setModel(_ modelId: String) async throws {
        guard let sessionId = sessionId, let client = acpClient else {
            throw AgentSessionError.sessionNotActive
        }

        let response = try await client.setModel(sessionId: sessionId, modelId: modelId)
        if response.success {
            currentModelId = modelId
            if let model = availableModels.first(where: { $0.modelId == modelId }) {
                addSystemMessage("Model changed to \(model.name)")
            } else {
                addSystemMessage("Model changed to \(modelId)")
            }
        }
    }

    /// Close the session
    func close() async {
        isActive = false

        // Cancel notification listener
        notificationTask?.cancel()
        notificationTask = nil

        if let client = acpClient {
            await client.terminate()
        }

        // Clean up delegates
        await terminalDelegate.cleanup()
        permissionHandler.cancelPendingRequest()

        acpClient = nil
        cancellables.removeAll()

        addSystemMessage("Session closed")
    }

    /// Retry starting the session after agent setup is completed
    func retryStart() async throws {
        // Reset setup state
        needsAgentSetup = false
        missingAgentName = nil
        setupError = nil

        // Attempt to start session again
        try await start(agentName: agentName, workingDir: workingDirectory)
    }

    // MARK: - ACPClientDelegate Methods

    func handleFileReadRequest(_ path: String, sessionId: String, line: Int?, limit: Int?) async throws -> ReadTextFileResponse {
        return try await fileSystemDelegate.handleFileReadRequest(path, sessionId: sessionId, line: line, limit: limit)
    }

    func handleFileWriteRequest(_ path: String, content: String, sessionId: String) async throws -> WriteTextFileResponse {
        return try await fileSystemDelegate.handleFileWriteRequest(path, content: content, sessionId: sessionId)
    }

    func handleTerminalCreate(command: String, sessionId: String, args: [String]?, cwd: String?, env: [EnvVariable]?, outputByteLimit: Int?) async throws -> CreateTerminalResponse {
        return try await terminalDelegate.handleTerminalCreate(
            command: command,
            sessionId: sessionId,
            args: args,
            cwd: cwd,
            env: env,
            outputByteLimit: outputByteLimit
        )
    }

    func handleTerminalOutput(terminalId: TerminalId, sessionId: String) async throws -> TerminalOutputResponse {
        return try await terminalDelegate.handleTerminalOutput(terminalId: terminalId, sessionId: sessionId)
    }

    func handleTerminalWaitForExit(terminalId: TerminalId, sessionId: String) async throws -> WaitForExitResponse {
        return try await terminalDelegate.handleTerminalWaitForExit(terminalId: terminalId, sessionId: sessionId)
    }

    func handleTerminalKill(terminalId: TerminalId, sessionId: String) async throws -> KillTerminalResponse {
        return try await terminalDelegate.handleTerminalKill(terminalId: terminalId, sessionId: sessionId)
    }

    func handleTerminalRelease(terminalId: TerminalId, sessionId: String) async throws -> ReleaseTerminalResponse {
        return try await terminalDelegate.handleTerminalRelease(terminalId: terminalId, sessionId: sessionId)
    }

    func handlePermissionRequest(request: RequestPermissionRequest) async throws -> RequestPermissionResponse {
        return await permissionHandler.handlePermissionRequest(request: request)
    }

    /// Respond to a permission request - delegates to permission handler
    func respondToPermission(optionId: String) {
        permissionHandler.respondToPermission(optionId: optionId)
    }

    // MARK: - Terminal Output Access

    /// Get terminal output for display in UI
    func getTerminalOutput(terminalId: String) async -> String? {
        return await terminalDelegate.getOutput(terminalId: TerminalId(terminalId))
    }

    /// Check if terminal is still running
    func isTerminalRunning(terminalId: String) async -> Bool {
        return await terminalDelegate.isRunning(terminalId: TerminalId(terminalId))
    }
}

// MARK: - Supporting Types

struct MessageItem: Identifiable {
    let id: String
    let role: MessageRole
    let content: String
    let timestamp: Date
    var toolCalls: [ToolCall] = []
    var contentBlocks: [ContentBlock] = []
    var isComplete: Bool = true
    var startTime: Date? // When agent started responding (first chunk)
    var executionTime: TimeInterval? // Time taken to generate response in seconds
    var requestId: String? // Track which user request this response belongs to
}

enum MessageRole {
    case user
    case agent
    case system
}

enum AgentSessionError: LocalizedError {
    case sessionAlreadyActive
    case sessionNotActive
    case agentNotFound(String)
    case agentNotExecutable(String)
    case clientNotInitialized
    case custom(String)

    var errorDescription: String? {
        switch self {
        case .sessionAlreadyActive:
            return "Session is already active"
        case .sessionNotActive:
            return "No active session"
        case .agentNotFound(let name):
            return "Agent '\(name)' not configured. Please set the executable path in Settings → AI Agents, or click 'Auto Discover' to find it automatically."
        case .agentNotExecutable(let path):
            return "Agent at '\(path)' is not executable"
        case .clientNotInitialized:
            return "ACP client not initialized"
        case .custom(let message):
            return message
        }
    }
}
