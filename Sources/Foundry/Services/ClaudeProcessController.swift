import Foundation

/// Manages Claude Code process lifecycle and I/O
/// Uses --print --output-format stream-json --verbose for structured output
/// Each message spawns a new process with --resume for multi-turn
final class ClaudeProcessController: Sendable {
    let sessionID: UUID
    let projectPath: String
    let modelName: String
    private let onEvent: @Sendable (SessionEvent) -> Void
    private let onLog: @Sendable (LogEntry) -> Void
    private let onUsage: @Sendable (TokenUsage) -> Void
    private let onStatusChange: @Sendable (SessionStatus) -> Void

    private let lock = NSLock()
    private nonisolated(unsafe) var _process: Process?
    private nonisolated(unsafe) var _isRunning: Bool = false
    private nonisolated(unsafe) var _claudeSessionID: String?

    var isRunning: Bool {
        lock.lock()
        defer { lock.unlock() }
        return _isRunning
    }

    var claudeSessionID: String? {
        lock.lock()
        defer { lock.unlock() }
        return _claudeSessionID
    }

    var processIdentifier: Int32? {
        lock.lock()
        defer { lock.unlock() }
        return _process?.processIdentifier
    }

    init(
        sessionID: UUID,
        projectPath: String,
        modelName: String = "claude-sonnet-4-6",
        claudeSessionID: String? = nil,
        onEvent: @escaping @Sendable (SessionEvent) -> Void,
        onLog: @escaping @Sendable (LogEntry) -> Void,
        onUsage: @escaping @Sendable (TokenUsage) -> Void,
        onStatusChange: @escaping @Sendable (SessionStatus) -> Void
    ) {
        self.sessionID = sessionID
        self.projectPath = projectPath
        self.modelName = modelName
        self._claudeSessionID = claudeSessionID
        self.onEvent = onEvent
        self.onLog = onLog
        self.onUsage = onUsage
        self.onStatusChange = onStatusChange
    }

    /// Send a message to Claude - spawns a process for each message
    func sendMessage(_ message: String) {
        guard let claudePath = Self.findClaudePath() else {
            onEvent(SessionEvent(type: .error, content: "Claude Code CLI not found"))
            return
        }

        // Signal running
        lock.lock()
        _isRunning = true
        lock.unlock()
        onStatusChange(.running)

        // Add user input event
        onEvent(SessionEvent(type: .userInput, content: message))

        DispatchQueue.global(qos: .userInitiated).async { [self] in
            let process = Process()
            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()

            process.executableURL = URL(fileURLWithPath: claudePath)

            var args = [
                "-p", message,
                "--output-format", "stream-json",
                "--verbose",
                "--model", modelName
            ]

            // Resume existing session if we have a claude session ID
            lock.lock()
            let existingSessionID = _claudeSessionID
            lock.unlock()

            if let sid = existingSessionID {
                args.append(contentsOf: ["--resume", sid])
            }

            process.arguments = args
            process.currentDirectoryURL = URL(fileURLWithPath: projectPath)
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe

            // Inherit PATH
            var env = ProcessInfo.processInfo.environment
            env["TERM"] = "dumb"
            env["NO_COLOR"] = "1"
            process.environment = env

            lock.lock()
            _process = process
            lock.unlock()

            do {
                try process.run()
                onLog(LogEntry(source: .system, content: "Claude process started (PID: \(process.processIdentifier))"))
            } catch {
                onEvent(SessionEvent(type: .error, content: "Failed to start: \(error.localizedDescription)"))
                lock.lock()
                _isRunning = false
                lock.unlock()
                onStatusChange(.error)
                return
            }

            // Read stdout in background
            var stdoutBuffer = ""
            let stdoutHandle = stdoutPipe.fileHandleForReading

            // Read all stdout
            let stdoutData = stdoutHandle.readDataToEndOfFile()
            if let output = String(data: stdoutData, encoding: .utf8) {
                stdoutBuffer = output
                onLog(LogEntry(source: .stdout, content: output))
            }

            // Read stderr
            let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
            if let errOutput = String(data: stderrData, encoding: .utf8),
               !errOutput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                onLog(LogEntry(source: .stderr, content: errOutput))
            }

            process.waitUntilExit()

            // Parse stdout JSON lines
            let lines = stdoutBuffer.components(separatedBy: .newlines)
            for line in lines {
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { continue }
                guard let data = trimmed.data(using: .utf8) else { continue }
                guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    continue
                }

                self.handleStreamEvent(json)
            }

            // Update state
            lock.lock()
            _isRunning = false
            _process = nil
            lock.unlock()

            let exitStatus = process.terminationStatus
            if exitStatus == 0 {
                onStatusChange(.idle)
            } else {
                onEvent(SessionEvent(type: .error, content: "Process exited with status \(exitStatus)"))
                onStatusChange(.error)
            }
        }
    }

    /// Send a slash command
    func sendCommand(_ command: String) {
        sendMessage(command)
    }

    /// Stop the current process
    func stop() {
        lock.lock()
        let process = _process
        _isRunning = false
        lock.unlock()

        process?.terminate()
        onStatusChange(.stopped)
    }

    // MARK: - Stream event handling

    private func handleStreamEvent(_ json: [String: Any]) {
        let type = json["type"] as? String ?? ""

        switch type {
        case "system":
            // Extract session_id for future --resume
            if let sid = json["session_id"] as? String {
                lock.lock()
                _claudeSessionID = sid
                lock.unlock()
            }
            let model = json["model"] as? String ?? ""
            onEvent(SessionEvent(
                type: .sessionStart,
                content: "Model: \(model)"
            ))

        case "assistant":
            guard let message = json["message"] as? [String: Any],
                  let contentBlocks = message["content"] as? [[String: Any]] else {
                return
            }

            for block in contentBlocks {
                let blockType = block["type"] as? String ?? ""
                switch blockType {
                case "text":
                    let text = block["text"] as? String ?? ""
                    if !text.isEmpty {
                        onEvent(SessionEvent(type: .assistantMessage, content: text))
                    }
                case "thinking":
                    let thinking = block["thinking"] as? String ?? ""
                    if !thinking.isEmpty {
                        onEvent(SessionEvent(type: .thinking, content: thinking))
                    }
                case "tool_use":
                    let toolName = block["name"] as? String ?? "unknown"
                    let input = block["input"] as? [String: Any] ?? [:]
                    let content = formatToolInput(toolName: toolName, input: input)
                    var metadata = EventMetadata(toolName: toolName)

                    let eventType: EventType
                    switch toolName {
                    case "Bash":
                        eventType = .bashCommand
                        metadata.command = input["command"] as? String
                    case "Read":
                        eventType = .fileRead
                        metadata.filePath = input["file_path"] as? String
                    case "Write":
                        eventType = .fileWrite
                        metadata.filePath = input["file_path"] as? String
                    case "Edit":
                        eventType = .fileEdit
                        metadata.filePath = input["file_path"] as? String
                    case "Grep", "Glob":
                        eventType = .search
                        metadata.searchPattern = input["pattern"] as? String
                    case "Agent":
                        eventType = .subAgentSpawn
                        metadata.agentName = input["subagent_type"] as? String
                    default:
                        eventType = .toolUse
                    }

                    onEvent(SessionEvent(type: eventType, content: content, metadata: metadata))
                default:
                    break
                }
            }

            // Extract usage from assistant message
            if let usage = message["usage"] as? [String: Any] {
                var tokenUsage = TokenUsage()
                tokenUsage.inputTokens = usage["input_tokens"] as? Int ?? 0
                tokenUsage.outputTokens = usage["output_tokens"] as? Int ?? 0
                tokenUsage.cacheReadTokens = usage["cache_read_input_tokens"] as? Int ?? 0
                tokenUsage.cacheWriteTokens = usage["cache_creation_input_tokens"] as? Int ?? 0
                onUsage(tokenUsage)
            }

        case "result":
            let isError = json["is_error"] as? Bool ?? false
            if isError {
                let errorMsg = json["error"] as? String ?? json["result"] as? String ?? "Unknown error"
                onEvent(SessionEvent(type: .error, content: errorMsg))
            }

            // Extract session ID
            if let sid = json["session_id"] as? String {
                lock.lock()
                _claudeSessionID = sid
                lock.unlock()
            }

            // Extract cost/usage
            if let costUSD = json["total_cost_usd"] as? Double {
                var tokenUsage = TokenUsage()
                tokenUsage.estimatedCostUSD = costUSD
                if let usage = json["usage"] as? [String: Any] {
                    tokenUsage.inputTokens = usage["input_tokens"] as? Int ?? 0
                    tokenUsage.outputTokens = usage["output_tokens"] as? Int ?? 0
                    tokenUsage.cacheReadTokens = usage["cache_read_input_tokens"] as? Int ?? 0
                    tokenUsage.cacheWriteTokens = usage["cache_creation_input_tokens"] as? Int ?? 0
                }
                onUsage(tokenUsage)
            }

        default:
            break
        }
    }

    private func formatToolInput(toolName: String, input: [String: Any]) -> String {
        switch toolName {
        case "Bash":
            return input["command"] as? String ?? ""
        case "Read":
            return input["file_path"] as? String ?? ""
        case "Write":
            let path = input["file_path"] as? String ?? ""
            let contentLen = (input["content"] as? String)?.count ?? 0
            return "\(path) (\(contentLen) chars)"
        case "Edit":
            let path = input["file_path"] as? String ?? ""
            return path
        case "Grep":
            let pattern = input["pattern"] as? String ?? ""
            return "grep: \(pattern)"
        case "Glob":
            return "glob: \(input["pattern"] as? String ?? "")"
        case "Agent":
            return input["description"] as? String ?? ""
        default:
            if let data = try? JSONSerialization.data(withJSONObject: input, options: []),
               let str = String(data: data, encoding: .utf8) {
                return String(str.prefix(300))
            }
            return ""
        }
    }

    // MARK: - Static helpers

    static func findClaudePath() -> String? {
        let paths = [
            "/opt/homebrew/bin/claude",
            "/usr/local/bin/claude",
            "/usr/bin/claude"
        ]

        for path in paths {
            if FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        }

        // Try which
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = ["claude"]
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
               !path.isEmpty {
                return path
            }
        } catch {}

        return nil
    }

    static func checkAvailability() -> (available: Bool, path: String?, version: String?) {
        guard let path = findClaudePath() else {
            return (false, nil, nil)
        }

        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = ["--version"]
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let version = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            return (true, path, version)
        } catch {
            return (true, path, nil)
        }
    }
}

enum FoundryError: Error, LocalizedError {
    case claudeNotFound
    case processStartFailed(String)
    case invalidProjectPath
    case sessionNotFound

    var errorDescription: String? {
        switch self {
        case .claudeNotFound:
            return "Claude Code CLI not found. Please install it first."
        case .processStartFailed(let reason):
            return "Failed to start Claude process: \(reason)"
        case .invalidProjectPath:
            return "Invalid project directory path."
        case .sessionNotFound:
            return "Session not found."
        }
    }
}
