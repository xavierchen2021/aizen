//
//  AgentSession.swift
//  aizen
//
//  Created by Uladzislau Yakauleu on 17.10.25.
//

import Foundation
import Combine
import UniformTypeIdentifiers

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
    @Published var permissionRequest: RequestPermissionRequest?
    @Published var showingPermissionAlert: Bool = false
    @Published var availableModes: [ModeInfo] = []
    @Published var availableModels: [ModelInfo] = []
    @Published var currentModeId: String?
    @Published var currentModelId: String?

    // MARK: - Private Properties

    private var acpClient: ACPClient?
    private var cancellables = Set<AnyCancellable>()
    private var process: Process?
    private var terminals: [String: Process] = [:]
    private var terminalOutputs: [String: String] = [:]
    private var permissionContinuation: CheckedContinuation<RequestPermissionResponse, Never>?

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
        guard let agentPath = AgentRegistry.shared.getAgentPath(for: agentName) else {
            throw AgentSessionError.agentNotFound(agentName)
        }

        // Validate agent executable
        guard AgentRegistry.shared.validateAgent(named: agentName) else {
            throw AgentSessionError.agentNotExecutable(agentPath)
        }

        // Initialize ACP client
        let client = ACPClient()
        self.acpClient = client

        // Set self as delegate
        await client.setDelegate(self)

        // Get launch arguments for this agent
        let launchArgs = AgentRegistry.shared.getAgentLaunchArgs(for: agentName)

        // Launch the agent process
        try await client.launch(agentPath: agentPath, arguments: launchArgs)

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

        // Check if authentication is required
        if let authMethods = initResponse.authMethods, !authMethods.isEmpty {
            self.authMethods = authMethods

            // Check for saved auth preference
            if let savedAuthMethod = AgentRegistry.shared.getAuthPreference(for: agentName) {
                print("AgentSession: Found saved auth preference: \(savedAuthMethod)")

                if savedAuthMethod == "skip" {
                    // User chose to skip auth - create session directly
                    print("AgentSession: Skipping authentication as per saved preference")
                    try await createSessionDirectly(workingDir: workingDir, client: client)
                    return
                } else {
                    // Auto-authenticate with saved method
                    print("AgentSession: Auto-authenticating with saved method")
                    do {
                        try await performAuthentication(client: client, authMethodId: savedAuthMethod, workingDir: workingDir)
                        return
                    } catch {
                        print("AgentSession: Auto-auth failed, showing dialog: \(error)")
                        // Fall through to show auth dialog
                    }
                }
            }

            // No saved preference - show auth dialog
            self.needsAuthentication = true
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

        // Parse modes and models from session response
        if let modesInfo = sessionResponse.modes {
            self.availableModes = modesInfo.availableModes
            self.currentModeId = modesInfo.currentModeId
            print("AgentSession: Loaded \(modesInfo.availableModes.count) modes, current: \(modesInfo.currentModeId)")
        }

        if let modelsInfo = sessionResponse.models {
            self.availableModels = modelsInfo.availableModels
            self.currentModelId = modelsInfo.currentModelId
            print("AgentSession: Loaded \(modelsInfo.availableModels.count) models, current: \(modelsInfo.currentModelId)")
        }

        // Start listening for notifications
        startNotificationListener(client: client)

        addSystemMessage("Session started with \(agentName) in \(workingDir)")
    }

    /// Helper to create session directly
    private func createSessionDirectly(workingDir: String, client: ACPClient) async throws {
        let sessionResponse = try await client.newSession(
            workingDirectory: workingDir,
            mcpServers: []
        )

        print("AgentSession: Got session ID: \(sessionResponse.sessionId.value)")

        self.sessionId = sessionResponse.sessionId
        self.isActive = true

        // Parse modes and models from session response
        if let modesInfo = sessionResponse.modes {
            self.availableModes = modesInfo.availableModes
            self.currentModeId = modesInfo.currentModeId
            print("AgentSession: Loaded \(modesInfo.availableModes.count) modes, current: \(modesInfo.currentModeId)")
        }

        if let modelsInfo = sessionResponse.models {
            self.availableModels = modelsInfo.availableModels
            self.currentModelId = modelsInfo.currentModelId
            print("AgentSession: Loaded \(modelsInfo.availableModels.count) models, current: \(modelsInfo.currentModelId)")
        }

        startNotificationListener(client: client)
        addSystemMessage("Session started with \(agentName) in \(workingDir)")
    }

    /// Helper to perform authentication and create session
    private func performAuthentication(client: ACPClient, authMethodId: String, workingDir: String) async throws {
        let authResponse = try await client.authenticate(
            authMethodId: authMethodId,
            credentials: nil
        )

        if !authResponse.success {
            throw NSError(domain: "AgentSession", code: -1, userInfo: [
                NSLocalizedDescriptionKey: authResponse.error ?? "Authentication failed"
            ])
        }

        needsAuthentication = false
        try await createSessionDirectly(workingDir: workingDir, client: client)
    }

    /// Create session without authentication (for when auth method doesn't work)
    func createSessionWithoutAuth() async throws {
        guard let client = acpClient else {
            throw AgentSessionError.clientNotInitialized
        }

        print("AgentSession: Skipping authentication, creating session directly")

        // Save skip preference
        AgentRegistry.shared.saveSkipAuth(for: agentName)

        needsAuthentication = false
        try await createSessionDirectly(workingDir: workingDirectory, client: client)
    }

    /// Authenticate with the agent
    func authenticate(authMethodId: String) async throws {
        guard let client = acpClient else {
            throw AgentSessionError.clientNotInitialized
        }

        print("AgentSession: Attempting authentication with method: \(authMethodId)")

        // Save auth preference for next time
        AgentRegistry.shared.saveAuthPreference(agentName: agentName, authMethodId: authMethodId)

        try await performAuthentication(client: client, authMethodId: authMethodId, workingDir: workingDirectory)
    }

    /// Send a message to the agent with optional file attachments
    func sendMessage(content: String, attachments: [URL] = []) async throws {
        guard let sessionId = sessionId, isActive else {
            throw AgentSessionError.sessionNotActive
        }

        guard let client = acpClient else {
            throw AgentSessionError.clientNotInitialized
        }

        // Build content blocks array
        var contentBlocks: [ContentBlock] = []

        // Add text content
        contentBlocks.append(.text(TextContent(text: content)))

        // Add attachments as resource blocks
        for attachmentURL in attachments {
            if let resourceBlock = try? await createResourceBlock(from: attachmentURL) {
                contentBlocks.append(resourceBlock)
            }
        }

        // Add user message to UI with all content blocks
        addUserMessage(content, contentBlocks: contentBlocks)

        // Send to agent and wait for completion
        let promptResponse = try await client.sendPrompt(sessionId: sessionId, content: contentBlocks)

        // Mark the last incomplete agent message as complete
        if let lastIndex = messages.lastIndex(where: { $0.role == .agent && !$0.isComplete }) {
            var completedMessage = messages[lastIndex]
            messages[lastIndex] = MessageItem(
                id: completedMessage.id,
                role: completedMessage.role,
                content: completedMessage.content,
                timestamp: completedMessage.timestamp,
                toolCalls: completedMessage.toolCalls,
                contentBlocks: completedMessage.contentBlocks,
                isComplete: true
            )
            print("AgentSession: Marked message \(completedMessage.id) as complete (stopReason: \(promptResponse.stopReason.rawValue))")
        }
    }

    /// Create a resource content block from a file URL
    private func createResourceBlock(from url: URL) async throws -> ContentBlock {
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
            let resourceContent = ResourceContent(
                uri: url.absoluteString,
                mimeType: mimeType,
                text: text,
                blob: nil
            )
            return .resource(resourceContent)
        } else {
            // Read as binary and base64 encode
            let data = try Data(contentsOf: url)
            let base64 = data.base64EncodedString()
            let resourceContent = ResourceContent(
                uri: url.absoluteString,
                mimeType: mimeType,
                text: nil,
                blob: base64
            )
            return .resource(resourceContent)
        }
    }

    /// Get MIME type from file URL
    private func getMimeType(for url: URL) -> String? {
        if let utType = UTType(filenameExtension: url.pathExtension) {
            return utType.preferredMIMEType
        }
        return nil
    }

    /// Set mode by ID
    func setModeById(_ modeId: String) async throws {
        guard let sessionId = sessionId, let client = acpClient else {
            throw AgentSessionError.sessionNotActive
        }

        print("AgentSession: Setting mode to: \(modeId)")

        let response = try await client.setMode(sessionId: sessionId, modeId: modeId)
        if response.success {
            currentModeId = modeId
            if let modeName = availableModes.first(where: { $0.id == modeId })?.name {
                addSystemMessage("Mode changed to \(modeName)")
            }
            print("AgentSession: Mode changed successfully to \(modeId)")
        } else {
            print("AgentSession: Mode change failed")
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

        if let client = acpClient {
            await client.terminate()
        }

        acpClient = nil
        cancellables.removeAll()

        addSystemMessage("Session closed")
    }

    // MARK: - Notification Handling

    private func startNotificationListener(client: ACPClient) {
        Task { @MainActor in
            for await notification in await client.notifications {
                handleNotification(notification)
            }
        }
    }

    private func handleNotification(_ notification: JSONRPCNotification) {
        guard notification.method == "session/update" else {
            print("AgentSession: Received notification: \(notification.method)")
            return
        }

        do {
            let params = notification.params?.value as? [String: Any]
            let data = try JSONSerialization.data(withJSONObject: params ?? [:])
            let updateNotification = try JSONDecoder().decode(SessionUpdateNotification.self, from: data)

            let updateType = updateNotification.update.sessionUpdate
            print("AgentSession: session/update type: \(updateType)")
            print("AgentSession: Full update data: \(updateNotification.update)")

            // Handle different update types
            switch updateType {
            case "tool_call", "tool_call_update":
                // Tool call info is at the update level, not in an array
                if let toolCallId = updateNotification.update.toolCallId {
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
                                content: updated.content
                            )
                            print("AgentSession: Updated tool call \(toolCallId) status: \(status)")
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
                            content: []
                        )
                        toolCalls.append(toolCall)
                        print("AgentSession: New tool call - \(title) (\(status.rawValue)), kind: \(kind.rawValue)")
                    }
                }

            case "agent_message_chunk":
                if let contentAny = updateNotification.update.content?.value {
                    // Clear current thought when agent starts responding
                    currentThought = nil

                    // Content can be a dictionary (single ContentBlock) or string
                    if let contentDict = contentAny as? [String: Any],
                       let type = contentDict["type"] as? String,
                       type == "text",
                       let text = contentDict["text"] as? String {

                        print("AgentSession: Agent chunk text: '\(text)'")

                        // Append to last agent message or create new one
                        if let lastMessage = messages.last, lastMessage.role == .agent, !lastMessage.isComplete {
                            let newContent = lastMessage.content + text
                            print("AgentSession: Appending to existing message, new length: \(newContent.count)")
                            messages[messages.count - 1] = MessageItem(
                                id: lastMessage.id,
                                role: .agent,
                                content: newContent,
                                timestamp: lastMessage.timestamp,
                                toolCalls: toolCalls,
                                contentBlocks: lastMessage.contentBlocks,
                                isComplete: false
                            )
                        } else {
                            print("AgentSession: Creating new agent message")
                            addAgentMessage(text, toolCalls: toolCalls, isComplete: false)
                        }

                        print("AgentSession: Total messages: \(messages.count)")
                    } else {
                        print("AgentSession: Content format unexpected: \(contentAny)")
                    }
                } else {
                    print("AgentSession: No content in agent_message_chunk")
                }

            case "user_message_chunk":
                // User messages already added when sending
                break

            case "agent_thought_chunk":
                if let contentAny = updateNotification.update.content?.value,
                   let contentDict = contentAny as? [String: Any],
                   let text = contentDict["text"] as? String {
                    print("Agent thought: \(text)")
                    currentThought = text
                }

            case "plan":
                if let plan = updateNotification.update.plan {
                    print("AgentSession: Received plan with \(plan.entries.count) entries")
                    for (i, entry) in plan.entries.enumerated() {
                        print("  [\(i)] \(entry.status.rawValue): \(entry.content)")
                    }
                    agentPlan = plan
                } else {
                    print("AgentSession: Plan update received but no plan data in notification")
                }

            case "available_commands_update":
                if let commands = updateNotification.update.availableCommands {
                    print("AgentSession: Received \(commands.count) available commands")
                    for cmd in commands {
                        print("  - /\(cmd.name): \(cmd.description)")
                    }
                    availableCommands = commands
                }

            case "current_mode_update":
                if let mode = updateNotification.update.currentMode {
                    currentMode = mode
                }

            default:
                print("AgentSession: Unknown update type: \(updateType)")
            }
        } catch {
            print("AgentSession: Failed to parse session update: \(error.localizedDescription)")
            self.error = "Failed to parse session update: \(error.localizedDescription)"
        }
    }

    private func updateToolCalls(_ newToolCalls: [ToolCall]) {
        for newCall in newToolCalls {
            if let index = toolCalls.firstIndex(where: { $0.toolCallId == newCall.toolCallId }) {
                // Merge content instead of replacing entirely
                let existingContent = toolCalls[index].content
                let mergedContent = existingContent + newCall.content

                toolCalls[index] = ToolCall(
                    toolCallId: newCall.toolCallId,
                    title: newCall.title,
                    kind: newCall.kind,
                    status: newCall.status, // Update status
                    content: mergedContent
                )

                print("AgentSession: Updated tool call \(newCall.toolCallId) - kind: \(newCall.kind.rawValue), status: \(newCall.status.rawValue), content blocks: \(mergedContent.count)")
                for (i, block) in mergedContent.enumerated() {
                    print("AgentSession:   Content[\(i)]: \(block)")
                }
            } else {
                toolCalls.append(newCall)
                print("AgentSession: Added new tool call \(newCall.toolCallId) - \(newCall.title)")
            }
        }
    }

    // MARK: - Message Management

    private func addUserMessage(_ content: String, contentBlocks: [ContentBlock] = []) {
        messages.append(MessageItem(
            id: UUID().uuidString,
            role: .user,
            content: content,
            timestamp: Date(),
            contentBlocks: contentBlocks
        ))
    }

    private func addAgentMessage(_ content: String, toolCalls: [ToolCall] = [], isComplete: Bool = true) {
        let newMessage = MessageItem(
            id: UUID().uuidString,
            role: .agent,
            content: content,
            timestamp: Date(),
            toolCalls: toolCalls,
            isComplete: isComplete
        )
        messages.append(newMessage)
        print("AgentSession: Added agent message - ID: \(newMessage.id), content: '\(content)', tool calls: \(toolCalls.count), complete: \(isComplete), total messages: \(messages.count)")
    }

    private func addSystemMessage(_ content: String) {
        messages.append(MessageItem(
            id: UUID().uuidString,
            role: .system,
            content: content,
            timestamp: Date()
        ))
    }

    // MARK: - ACPClientDelegate Methods

    func handleFileReadRequest(_ path: String, startLine: Int?, endLine: Int?) async throws -> ReadTextFileResponse {
        let url = URL(fileURLWithPath: path)
        let content = try String(contentsOf: url, encoding: .utf8)
        let lines = content.components(separatedBy: .newlines)

        let filteredContent: String
        if let start = startLine, let end = endLine {
            let startIdx = max(0, start - 1)
            let endIdx = min(lines.count, end)
            filteredContent = lines[startIdx..<endIdx].joined(separator: "\n")
        } else {
            filteredContent = content
        }

        return ReadTextFileResponse(content: filteredContent, totalLines: lines.count)
    }

    func handleFileWriteRequest(_ path: String, content: String) async throws -> WriteTextFileResponse {
        let url = URL(fileURLWithPath: path)
        try content.write(to: url, atomically: true, encoding: .utf8)
        return WriteTextFileResponse(success: true)
    }

    func handleTerminalCreate(command: String, args: [String]?, cwd: String?, env: [String: String]?, outputLimit: Int?) async throws -> CreateTerminalResponse {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: command)
        process.arguments = args ?? []

        if let cwd = cwd {
            process.currentDirectoryURL = URL(fileURLWithPath: cwd)
        }

        if let env = env {
            process.environment = env
        }

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        let terminalIdValue = UUID().uuidString
        let terminalId = TerminalId(terminalIdValue)

        terminals[terminalIdValue] = process
        terminalOutputs[terminalIdValue] = ""

        // Capture output asynchronously
        outputPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if !data.isEmpty, let output = String(data: data, encoding: .utf8) {
                Task { @MainActor in
                    self?.terminalOutputs[terminalIdValue, default: ""] += output
                }
            }
        }

        errorPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if !data.isEmpty, let output = String(data: data, encoding: .utf8) {
                Task { @MainActor in
                    self?.terminalOutputs[terminalIdValue, default: ""] += output
                }
            }
        }

        try process.run()
        return CreateTerminalResponse(terminalId: terminalId)
    }

    func handleTerminalOutput(terminalId: TerminalId) async throws -> TerminalOutputResponse {
        guard let process = terminals[terminalId.value] else {
            throw NSError(domain: "AgentSession", code: -1, userInfo: [NSLocalizedDescriptionKey: "Terminal not found"])
        }

        let output = terminalOutputs[terminalId.value] ?? ""
        let exitCode = process.isRunning ? nil : Int(process.terminationStatus)

        // Clear the accumulated output after reading
        terminalOutputs[terminalId.value] = ""

        return TerminalOutputResponse(output: output, exitCode: exitCode)
    }

    func handlePermissionRequest(request: RequestPermissionRequest) async throws -> RequestPermissionResponse {
        print("AgentSession: Permission requested")
        if let toolCall = request.toolCall {
            print("AgentSession: For tool call: \(toolCall.toolCallId)")
        }
        if let msg = request.message {
            print("AgentSession: Message: \(msg)")
        }
        if let opts = request.options {
            print("AgentSession: Options: \(opts.map { $0.name }.joined(separator: ", "))")
        }

        // Show permission UI and wait for user decision
        return await withCheckedContinuation { continuation in
            print("AgentSession: Showing permission alert")
            self.permissionRequest = request
            self.showingPermissionAlert = true

            // Store continuation to resume when user makes decision
            self.permissionContinuation = continuation
        }
    }

    // Call this when user makes permission decision
    func respondToPermission(optionId: String) {
        print("AgentSession: User responded with optionId: \(optionId)")

        showingPermissionAlert = false
        permissionRequest = nil

        if let continuation = permissionContinuation {
            let outcome = PermissionOutcome(optionId: optionId)
            let response = RequestPermissionResponse(outcome: outcome)
            continuation.resume(returning: response)
            permissionContinuation = nil
            print("AgentSession: Sent permission response - outcome: selected, optionId: \(optionId)")
        }
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
