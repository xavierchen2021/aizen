//
//  ACPClient.swift
//  aizen
//
//  Actor-based ACP agent subprocess manager
//

import Foundation

enum ACPClientError: Error, LocalizedError {
    case processNotRunning
    case processFailed(Int32)
    case invalidResponse
    case requestTimeout
    case encodingError
    case decodingError(Error)
    case agentError(JSONRPCError)
    case delegateNotSet
    case fileNotFound(String)
    case fileOperationFailed(String)

    var errorDescription: String? {
        switch self {
        case .processNotRunning:
            return "Agent process is not running"
        case .processFailed(let code):
            return "Agent process failed with exit code \(code)"
        case .invalidResponse:
            return "Invalid response from agent"
        case .requestTimeout:
            return "Request timed out"
        case .encodingError:
            return "Failed to encode request"
        case .decodingError(let error):
            return "Failed to decode response: \(error.localizedDescription)"
        case .agentError(let jsonError):
            // Extract the actual error message from the JSON-RPC error

            // Case 1: data is a plain string (Codex)
            if let dataString = jsonError.data?.value as? String {
                return dataString
            }

            // Case 2: data is an object with details
            if let data = jsonError.data?.value as? [String: Any],
               let details = data["details"] as? String {
                // Try to parse nested error details (Gemini)
                if let detailsData = details.data(using: .utf8),
                   let json = try? JSONSerialization.jsonObject(with: detailsData) as? [String: Any],
                   let error = json["error"] as? [String: Any],
                   let message = error["message"] as? String {
                    return message
                }
                return details
            }

            // Case 3: Fallback to generic message
            return jsonError.message
        case .delegateNotSet:
            return "Internal error: Delegate not set"
        case .fileNotFound(let path):
            return "File not found: \(path)"
        case .fileOperationFailed(let message):
            return "File operation failed: \(message)"
        }
    }
}

protocol ACPClientDelegate: AnyObject {
    func handleFileReadRequest(_ path: String, startLine: Int?, endLine: Int?) async throws -> ReadTextFileResponse
    func handleFileWriteRequest(_ path: String, content: String) async throws -> WriteTextFileResponse
    func handleTerminalCreate(command: String, args: [String]?, cwd: String?, env: [String: String]?, outputLimit: Int?) async throws -> CreateTerminalResponse
    func handleTerminalOutput(terminalId: TerminalId) async throws -> TerminalOutputResponse
    func handlePermissionRequest(request: RequestPermissionRequest) async throws -> RequestPermissionResponse
}

actor ACPClient {
    // MARK: - Properties

    private var process: Process?
    private var stdinPipe: Pipe?
    private var stdoutPipe: Pipe?
    private var stderrPipe: Pipe?

    private var readTask: Task<Void, Never>?
    private var pendingRequests: [RequestId: CheckedContinuation<JSONRPCResponse, Error>] = [:]
    private var nextRequestId: Int = 1
    private var readBuffer: Data = Data()

    private let notificationContinuation: AsyncStream<JSONRPCNotification>.Continuation
    private let notificationStream: AsyncStream<JSONRPCNotification>

    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    weak var delegate: ACPClientDelegate?

    // MARK: - Initialization

    init() {
        // Set up JSON decoder/encoder
        // Note: We manually handle camelCase/snake_case in CodingKeys where needed
        decoder = JSONDecoder()
        encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]

        // Create notification stream
        var continuation: AsyncStream<JSONRPCNotification>.Continuation!
        notificationStream = AsyncStream { cont in
            continuation = cont
        }
        notificationContinuation = continuation
    }

    // MARK: - Public API

    var notifications: AsyncStream<JSONRPCNotification> {
        notificationStream
    }

    func setDelegate(_ delegate: ACPClientDelegate?) {
        self.delegate = delegate
    }

    func launch(agentPath: String, arguments: [String] = []) throws {
        guard process == nil else {
            throw ACPClientError.processNotRunning
        }

        print("ACPClient: Launching agent at \(agentPath) with args: \(arguments)")

        let proc = Process()

        // Resolve symlinks to get the actual file
        let resolvedPath = (try? FileManager.default.destinationOfSymbolicLink(atPath: agentPath)) ?? agentPath
        let actualPath = resolvedPath.hasPrefix("/") ? resolvedPath : ((agentPath as NSString).deletingLastPathComponent as NSString).appendingPathComponent(resolvedPath)

        // If this is a Node.js script (has #!/usr/bin/env node), invoke node directly
        let isNodeScript = (try? String(contentsOf: URL(fileURLWithPath: actualPath), encoding: .utf8))?.hasPrefix("#!/usr/bin/env node") ?? false

        if isNodeScript {

            // Try to find node in multiple locations
            let searchPaths = [
                (agentPath as NSString).deletingLastPathComponent, // Original directory (for symlinks like /opt/homebrew/bin)
                (actualPath as NSString).deletingLastPathComponent, // Actual file directory
                "/opt/homebrew/bin",
                "/usr/local/bin",
                "/usr/bin"
            ]

            var foundNode: String?
            for searchPath in searchPaths {
                let nodePath = (searchPath as NSString).appendingPathComponent("node")
                if FileManager.default.fileExists(atPath: nodePath) {
                    foundNode = nodePath
                    break
                }
            }

            if let nodePath = foundNode {
                proc.executableURL = URL(fileURLWithPath: nodePath)
                proc.arguments = [actualPath] + arguments
            } else {
                proc.executableURL = URL(fileURLWithPath: agentPath)
                proc.arguments = arguments
            }
        } else {
            proc.executableURL = URL(fileURLWithPath: agentPath)
            proc.arguments = arguments
        }

        // Load user's shell environment for full access to their commands
        var environment = loadUserShellEnvironment()

        // Get the directory containing the agent executable (for node, etc.)
        let agentDir = (agentPath as NSString).deletingLastPathComponent

        // Prepend agent directory to PATH (highest priority)
        if let existingPath = environment["PATH"] {
            environment["PATH"] = "\(agentDir):\(existingPath)"
        } else {
            environment["PATH"] = agentDir
        }


        proc.environment = environment

        let stdin = Pipe()
        let stdout = Pipe()
        let stderr = Pipe()

        proc.standardInput = stdin
        proc.standardOutput = stdout
        proc.standardError = stderr

        stdinPipe = stdin
        stdoutPipe = stdout
        stderrPipe = stderr

        proc.terminationHandler = { [weak self] process in
            Task {
                await self?.handleTermination(exitCode: process.terminationStatus)
            }
        }

        try proc.run()
        process = proc

        print("ACPClient: Agent process started with PID: \(proc.processIdentifier)")

        // Start reading stdout in background
        startReading()

        // Also log stderr for debugging
        startReadingStderr()
    }

    func initialize(
        protocolVersion: Int = 1,
        capabilities: ClientCapabilities
    ) async throws -> InitializeResponse {
        let request = InitializeRequest(
            protocolVersion: protocolVersion,
            clientCapabilities: capabilities
        )

        let response = try await sendRequest(method: "initialize", params: request)

        guard let result = response.result else {
            if let error = response.error {
                throw ACPClientError.agentError(error)
            }
            throw ACPClientError.invalidResponse
        }

        let data = try encoder.encode(result)
        return try decoder.decode(InitializeResponse.self, from: data)
    }

    func newSession(
        workingDirectory: String,
        mcpServers: [MCPServerConfig] = []
    ) async throws -> NewSessionResponse {
        let request = NewSessionRequest(
            cwd: workingDirectory,
            mcpServers: mcpServers
        )

        let response = try await sendRequest(method: "session/new", params: request)

        guard let result = response.result else {
            if let error = response.error {
                throw ACPClientError.agentError(error)
            }
            throw ACPClientError.invalidResponse
        }

        let data = try encoder.encode(result)
        return try decoder.decode(NewSessionResponse.self, from: data)
    }

    func sendPrompt(
        sessionId: SessionId,
        content: [ContentBlock]
    ) async throws -> SessionPromptResponse {
        let request = SessionPromptRequest(
            sessionId: sessionId,
            prompt: content
        )

        let response = try await sendRequest(method: "session/prompt", params: request)

        if let error = response.error {
            throw ACPClientError.agentError(error)
        }

        guard let result = response.result else {
            throw ACPClientError.invalidResponse
        }

        let data = try encoder.encode(result)
        return try decoder.decode(SessionPromptResponse.self, from: data)
    }

    func authenticate(
        authMethodId: String,
        credentials: [String: String]? = nil
    ) async throws -> AuthenticateResponse {
        let request = AuthenticateRequest(
            methodId: authMethodId,
            credentials: credentials
        )

        let response = try await sendRequest(method: "authenticate", params: request)

        // Check for errors first
        if let error = response.error {
            throw ACPClientError.agentError(error)
        }

        // For authenticate, null or empty object result means success
        if response.result == nil || (response.result?.value is NSNull) {
            return AuthenticateResponse(success: true, error: nil)
        }

        // Check for empty object (Codex returns {})
        if let dict = response.result?.value as? [String: Any], dict.isEmpty {
            return AuthenticateResponse(success: true, error: nil)
        }

        // Otherwise try to decode the result
        do {
            let data = try encoder.encode(response.result!)
            return try decoder.decode(AuthenticateResponse.self, from: data)
        } catch {
            // If decoding fails but there's no error, treat as success
            return AuthenticateResponse(success: true, error: nil)
        }
    }

    func setMode(
        sessionId: SessionId,
        modeId: String
    ) async throws -> SetModeResponse {
        let request = SetModeRequest(
            sessionId: sessionId,
            modeId: modeId
        )

        let response = try await sendRequest(method: "session/set_mode", params: request)

        // Check for errors
        if let error = response.error {
            throw ACPClientError.agentError(error)
        }

        // Empty object or null = success
        return SetModeResponse(success: true)
    }

    func setModel(
        sessionId: SessionId,
        modelId: String
    ) async throws -> SetModelResponse {
        let request = SetModelRequest(
            sessionId: sessionId,
            modelId: modelId
        )

        let response = try await sendRequest(method: "session/set_model", params: request)

        // Check for errors
        if let error = response.error {
            throw ACPClientError.agentError(error)
        }

        // Empty object or null = success
        return SetModelResponse(success: true)
    }

    func cancelSession(sessionId: SessionId) async throws {
        let request = CancelSessionRequest(sessionId: sessionId)

        let response = try await sendRequest(method: "session/cancel", params: request)

        if let error = response.error {
            throw ACPClientError.agentError(error)
        }
    }

    func loadSession(
        sessionId: SessionId,
        cwd: String? = nil,
        mcpServers: [MCPServerConfig]? = nil
    ) async throws -> LoadSessionResponse {
        let request = LoadSessionRequest(
            sessionId: sessionId,
            cwd: cwd,
            mcpServers: mcpServers
        )

        let response = try await sendRequest(method: "session/load", params: request)

        guard let result = response.result else {
            if let error = response.error {
                throw ACPClientError.agentError(error)
            }
            throw ACPClientError.invalidResponse
        }

        let data = try encoder.encode(result)
        return try decoder.decode(LoadSessionResponse.self, from: data)
    }

    func sendRequest<T: Encodable>(
        method: String,
        params: T
    ) async throws -> JSONRPCResponse {
        guard process?.isRunning == true else {
            throw ACPClientError.processNotRunning
        }

        let requestId = RequestId.number(nextRequestId)
        nextRequestId += 1

        let paramsData = try encoder.encode(params)
        let paramsValue = try decoder.decode(AnyCodable.self, from: paramsData)

        let request = JSONRPCRequest(
            id: requestId,
            method: method,
            params: paramsValue
        )

        return try await withCheckedThrowingContinuation { continuation in
            Task {
                await self.registerRequest(id: requestId, continuation: continuation)

                do {
                    try await self.writeMessage(request)
                } catch {
                    await self.failRequest(id: requestId, error: error)
                }
            }
        }
    }

    func terminate() async {
        readTask?.cancel()
        readTask = nil

        process?.terminate()
        process = nil

        stdinPipe = nil
        stdoutPipe = nil
        stderrPipe = nil

        // Fail all pending requests
        for (id, continuation) in pendingRequests {
            continuation.resume(throwing: ACPClientError.processNotRunning)
        }
        pendingRequests.removeAll()

        notificationContinuation.finish()
    }

    // MARK: - Private Methods

    private func startReading() {
        guard let stdout = stdoutPipe?.fileHandleForReading else { return }

        // Use readabilityHandler for non-blocking async I/O
        stdout.readabilityHandler = { [weak self] handle in
            let data = handle.availableData

            guard !data.isEmpty else {
                // EOF or pipe closed
                handle.readabilityHandler = nil
                return
            }

            Task {
                await self?.processIncomingData(data)
            }
        }
    }

    private func startReadingStderr() {
        guard let stderr = stderrPipe?.fileHandleForReading else { return }

        stderr.readabilityHandler = { handle in
            let data = handle.availableData
            if !data.isEmpty, let message = String(data: data, encoding: .utf8) {
                print("ACPClient stderr: \(message)")
            }
        }
    }

    private func processIncomingData(_ data: Data) async {
        readBuffer.append(data)

        // Process complete lines
        while let newlineIndex = readBuffer.firstIndex(of: 0x0A) {
            let lineData = readBuffer[..<newlineIndex]
            readBuffer.removeSubrange(...newlineIndex)

            await handleMessage(data: Data(lineData))
        }
    }

    private func handleMessage(data: Data) async {
        do {
            let message = try decoder.decode(ACPMessage.self, from: data)

            switch message {
            case .response(let response):
                await handleResponse(response)

            case .notification(let notification):
                notificationContinuation.yield(notification)

            case .request(let request):
                await handleIncomingRequest(request)
            }
        } catch {
            print("ACPClient: Failed to decode message: \(error)")
        }
    }

    private func handleResponse(_ response: JSONRPCResponse) async {
        guard let continuation = pendingRequests.removeValue(forKey: response.id) else {
            return
        }

        continuation.resume(returning: response)
    }

    private func handleIncomingRequest(_ request: JSONRPCRequest) async {
        do {
            let response: AnyCodable

            switch request.method {
            case "fs/read_text_file":
                response = try await handleFileRead(request)
            case "fs/write_text_file":
                response = try await handleFileWrite(request)
            case "terminal/create":
                response = try await handleTerminalCreateRequest(request)
            case "terminal/output":
                response = try await handleTerminalOutputRequest(request)
            case "terminal/wait_for_exit":
                response = try await handleTerminalWaitForExit(request)
            case "terminal/kill":
                response = try await handleTerminalKill(request)
            case "terminal/release":
                response = try await handleTerminalRelease(request)
            case "request_permission", "session/request_permission":
                response = try await handlePermissionRequestMethod(request)
            default:
                try await sendErrorResponse(
                    requestId: request.id,
                    code: -32601,
                    message: "Method not found: \(request.method)"
                )
                return
            }

            try await sendSuccessResponse(requestId: request.id, result: response)
        } catch {
            print("ACPClient: Error handling request \(request.method): \(error)")
            try? await sendErrorResponse(
                requestId: request.id,
                code: -32603,
                message: "Internal error: \(error.localizedDescription)"
            )
        }
    }

    private func handleFileRead(_ request: JSONRPCRequest) async throws -> AnyCodable {
        guard let delegate = delegate else {
            throw ACPClientError.delegateNotSet
        }

        guard let params = request.params else {
            throw ACPClientError.invalidResponse
        }

        let data = try encoder.encode(params)
        let req = try decoder.decode(ReadTextFileRequest.self, from: data)

        let response = try await delegate.handleFileReadRequest(
            req.path,
            startLine: req.startLine,
            endLine: req.endLine
        )

        let responseData = try encoder.encode(response)
        return try decoder.decode(AnyCodable.self, from: responseData)
    }

    private func handleFileWrite(_ request: JSONRPCRequest) async throws -> AnyCodable {
        guard let delegate = delegate else {
            throw ACPClientError.delegateNotSet
        }

        guard let params = request.params else {
            throw ACPClientError.invalidResponse
        }

        let data = try encoder.encode(params)
        let req = try decoder.decode(WriteTextFileRequest.self, from: data)

        let response = try await delegate.handleFileWriteRequest(req.path, content: req.content)

        let responseData = try encoder.encode(response)
        return try decoder.decode(AnyCodable.self, from: responseData)
    }

    private func handleTerminalCreateRequest(_ request: JSONRPCRequest) async throws -> AnyCodable {
        guard let delegate = delegate else {
            throw ACPClientError.delegateNotSet
        }

        guard let params = request.params else {
            throw ACPClientError.invalidResponse
        }

        let data = try encoder.encode(params)
        let req = try decoder.decode(CreateTerminalRequest.self, from: data)

        let response = try await delegate.handleTerminalCreate(
            command: req.command,
            args: req.args,
            cwd: req.cwd,
            env: req.env,
            outputLimit: req.outputLimit
        )

        let responseData = try encoder.encode(response)
        return try decoder.decode(AnyCodable.self, from: responseData)
    }

    private func handleTerminalOutputRequest(_ request: JSONRPCRequest) async throws -> AnyCodable {
        guard let delegate = delegate else {
            throw ACPClientError.delegateNotSet
        }

        guard let params = request.params else {
            throw ACPClientError.invalidResponse
        }

        let data = try encoder.encode(params)
        let req = try decoder.decode(TerminalOutputRequest.self, from: data)

        let response = try await delegate.handleTerminalOutput(terminalId: req.terminalId)

        let responseData = try encoder.encode(response)
        return try decoder.decode(AnyCodable.self, from: responseData)
    }

    private func handleTerminalWaitForExit(_ request: JSONRPCRequest) async throws -> AnyCodable {
        guard let params = request.params else {
            throw ACPClientError.invalidResponse
        }

        let data = try encoder.encode(params)
        let req = try decoder.decode(WaitForExitRequest.self, from: data)

        // Wait for terminal to exit - this would be handled by the terminal manager
        // For now, just return the terminal ID
        let response = ["terminal_id": req.terminalId.value]

        let responseData = try encoder.encode(response)
        return try decoder.decode(AnyCodable.self, from: responseData)
    }

    private func handleTerminalKill(_ request: JSONRPCRequest) async throws -> AnyCodable {
        guard let params = request.params else {
            throw ACPClientError.invalidResponse
        }

        let data = try encoder.encode(params)
        let req = try decoder.decode(KillTerminalRequest.self, from: data)

        // Kill terminal - this would be handled by the terminal manager
        let response = ["success": true]

        let responseData = try encoder.encode(response)
        return try decoder.decode(AnyCodable.self, from: responseData)
    }

    private func handleTerminalRelease(_ request: JSONRPCRequest) async throws -> AnyCodable {
        guard let params = request.params else {
            throw ACPClientError.invalidResponse
        }

        let data = try encoder.encode(params)
        let req = try decoder.decode(ReleaseTerminalRequest.self, from: data)

        // Release terminal - this would be handled by the terminal manager
        let response = ["success": true]

        let responseData = try encoder.encode(response)
        return try decoder.decode(AnyCodable.self, from: responseData)
    }

    private func handlePermissionRequestMethod(_ request: JSONRPCRequest) async throws -> AnyCodable {
        print("ACPClient: handlePermissionRequestMethod started")

        guard let delegate = delegate else {
            print("ACPClient: No delegate set!")
            throw ACPClientError.delegateNotSet
        }

        guard let params = request.params else {
            print("ACPClient: No params in request!")
            throw ACPClientError.invalidResponse
        }

        let data = try encoder.encode(params)
        let req = try decoder.decode(RequestPermissionRequest.self, from: data)

        print("ACPClient: Decoded permission request - options: \(req.options?.count ?? 0)")
        print("ACPClient: Calling delegate.handlePermissionRequest...")

        let response = try await delegate.handlePermissionRequest(request: req)

        print("ACPClient: Got permission response - outcome: \(response.outcome.outcome), optionId: \(response.outcome.optionId ?? "none")")

        // Return the response as-is
        let responseData = try encoder.encode(response)
        return try decoder.decode(AnyCodable.self, from: responseData)
    }

    private func sendSuccessResponse(requestId: RequestId, result: AnyCodable) async throws {
        let response = JSONRPCResponse(id: requestId, result: result, error: nil)
        print("ACPClient: Sending success response for request \(requestId)")
        try await writeMessage(response)
    }

    private func sendErrorResponse(requestId: RequestId, code: Int, message: String) async throws {
        let error = JSONRPCError(code: code, message: message, data: nil)
        let response = JSONRPCResponse(id: requestId, result: nil, error: error)
        try await writeMessage(response)
    }

    private func handleTermination(exitCode: Int32) async {
        print("Agent process terminated with code: \(exitCode)")

        // Fail all pending requests
        for (_, continuation) in pendingRequests {
            continuation.resume(throwing: ACPClientError.processFailed(exitCode))
        }
        pendingRequests.removeAll()

        readTask?.cancel()
        readTask = nil

        notificationContinuation.finish()
    }

    private func writeMessage<T: Encodable>(_ message: T) async throws {
        guard let stdin = stdinPipe?.fileHandleForWriting else {
            throw ACPClientError.processNotRunning
        }

        let data = try encoder.encode(message)

        if let jsonString = String(data: data, encoding: .utf8) {
            print("ACPClient sending: \(jsonString)")
        }

        var lineData = data
        lineData.append(0x0A) // newline

        try stdin.write(contentsOf: lineData)
    }

    private func registerRequest(
        id: RequestId,
        continuation: CheckedContinuation<JSONRPCResponse, Error>
    ) async {
        pendingRequests[id] = continuation
    }

    private func failRequest(id: RequestId, error: Error) async {
        if let continuation = pendingRequests.removeValue(forKey: id) {
            continuation.resume(throwing: error)
        }
    }

    // MARK: - Shell Environment Loading

    private func loadUserShellEnvironment() -> [String: String] {
        // Try to load environment from user's login shell
        let shell = getLoginShell()
        let homeDir = FileManager.default.homeDirectoryForCurrentUser.path

        print("ACPClient: Loading environment from shell: \(shell)")

        // Run shell in login mode to source profile files
        let process = Process()
        process.executableURL = URL(fileURLWithPath: shell)

        // Different shells use different flags
        let shellName = (shell as NSString).lastPathComponent
        let arguments: [String]
        switch shellName {
        case "fish":
            // Fish uses -l -c for login shell
            arguments = ["-l", "-c", "env"]
        case "zsh", "bash":
            // Bash and Zsh use -l -c
            arguments = ["-l", "-c", "env"]
        case "sh":
            // POSIX sh uses -l -c
            arguments = ["-l", "-c", "env"]
        default:
            // Generic fallback
            arguments = ["-c", "env"]
        }

        process.arguments = arguments
        process.currentDirectoryURL = URL(fileURLWithPath: homeDir)

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe() // Discard stderr

        var shellEnv: [String: String] = [:]

        do {
            try process.run()
            process.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let output = String(data: data, encoding: .utf8) {
                // Parse env output (KEY=VALUE per line)
                for line in output.split(separator: "\n") {
                    if let equalsIndex = line.firstIndex(of: "=") {
                        let key = String(line[..<equalsIndex])
                        let value = String(line[line.index(after: equalsIndex)...])
                        shellEnv[key] = value
                    }
                }
                print("ACPClient: Loaded \(shellEnv.count) environment variables from shell")

                // Log specific env vars we care about
                if let geminiKey = shellEnv["GEMINI_API_KEY"] {
                    print("ACPClient: ✓ Found GEMINI_API_KEY (length: \(geminiKey.count))")
                } else {
                    print("ACPClient: ✗ GEMINI_API_KEY not found in shell environment")
                }

                if let anthropicKey = shellEnv["ANTHROPIC_API_KEY"] {
                    print("ACPClient: ✓ Found ANTHROPIC_API_KEY (length: \(anthropicKey.count))")
                }

                if let openaiKey = shellEnv["OPENAI_API_KEY"] {
                    print("ACPClient: ✓ Found OPENAI_API_KEY (length: \(openaiKey.count))")
                }
            }
        } catch {
            print("ACPClient: Failed to load shell environment: \(error), using process environment")
        }

        // Fallback to process environment if shell loading failed
        if shellEnv.isEmpty {
            print("ACPClient: Shell environment empty, falling back to process environment")
            shellEnv = ProcessInfo.processInfo.environment
        }

        return shellEnv
    }

    private func getLoginShell() -> String {
        // Try to get user's login shell
        if let shell = ProcessInfo.processInfo.environment["SHELL"], !shell.isEmpty {
            return shell
        }

        // Fallback to common shells in order of preference
        let possibleShells = [
            "/bin/zsh",                 // macOS default
            "/bin/bash",                // Common default
            "/opt/homebrew/bin/fish",   // Fish via Homebrew (Apple Silicon)
            "/usr/local/bin/fish",      // Fish via Homebrew (Intel)
            "/bin/fish",                // Fish system install
            "/bin/sh"                   // POSIX fallback
        ]

        for shell in possibleShells {
            if FileManager.default.fileExists(atPath: shell) {
                return shell
            }
        }

        return "/bin/sh"
    }
}

// MARK: - FileHandle Extension

extension FileHandle {
    func readLine() throws -> Data? {
        var buffer = Data()
        let chunkSize = 1024

        while true {
            let chunk = try read(upToCount: chunkSize)

            guard let data = chunk, !data.isEmpty else {
                return buffer.isEmpty ? nil : buffer
            }

            if let newlineIndex = data.firstIndex(of: 0x0A) {
                buffer.append(data[..<newlineIndex])

                // Seek back to after the newline
                let remaining = data.count - newlineIndex - 1
                if remaining > 0 {
                    try seek(toOffset: offset() - UInt64(remaining))
                }

                return buffer
            }

            buffer.append(data)
        }
    }
}
