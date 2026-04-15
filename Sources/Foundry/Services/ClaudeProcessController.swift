import Foundation

// MARK: - Session Send Errors

/// Structured error types for Claude Code session failures
enum SessionSendError: Error, LocalizedError, Sendable {
    case claudeNotFound
    case nodeNotFound
    case invalidProjectPath(String)
    case sessionNotFound(String)
    case sessionBusy
    case processStartFailed(String)
    case exitCommandNotFound(stderr: String)
    case exitSessionInvalid(stderr: String)
    case exitRuntimeError(code: Int32, stderr: String)
    case environmentResolutionFailed

    var errorDescription: String? {
        switch self {
        case .claudeNotFound:
            return "Claude Code CLI not found. Install it with: npm install -g @anthropic-ai/claude-code"
        case .nodeNotFound:
            return "Node.js not found in PATH. Claude Code requires Node.js to run."
        case .invalidProjectPath(let path):
            return "Project directory does not exist: \(path)"
        case .sessionNotFound(let sid):
            return "Session \(sid) is no longer available. It may have been deleted or expired."
        case .sessionBusy:
            return "A message is already being processed. Please wait for it to complete."
        case .processStartFailed(let reason):
            return "Failed to launch Claude Code: \(reason)"
        case .exitCommandNotFound(let stderr):
            return "Claude Code command not found (exit 127). This usually means the executable or a dependency (like Node.js) is missing from PATH.\n\(stderr)"
        case .exitSessionInvalid(let stderr):
            return "Session could not be resumed. It may be corrupted or expired.\n\(stderr)"
        case .exitRuntimeError(let code, let stderr):
            return "Claude Code exited with error (code \(code)).\n\(stderr)"
        case .environmentResolutionFailed:
            return "Could not resolve shell environment. Using default PATH."
        }
    }

    /// User-facing short description for the UI
    var userMessage: String {
        switch self {
        case .claudeNotFound:
            return "Claude Code is not installed"
        case .nodeNotFound:
            return "Node.js is not available"
        case .invalidProjectPath:
            return "Project directory is missing"
        case .sessionNotFound:
            return "Session expired or unavailable"
        case .sessionBusy:
            return "Session is busy processing"
        case .processStartFailed:
            return "Failed to start Claude Code"
        case .exitCommandNotFound:
            return "Claude Code could not be found"
        case .exitSessionInvalid:
            return "Session could not be resumed"
        case .exitRuntimeError:
            return "Claude Code encountered an error"
        case .environmentResolutionFailed:
            return "Shell environment issue"
        }
    }

    /// Whether this error suggests the session should be recreated
    var shouldRecreateSession: Bool {
        switch self {
        case .sessionNotFound, .exitSessionInvalid:
            return true
        default:
            return false
        }
    }

    /// Whether a retry might succeed
    var isRetryable: Bool {
        switch self {
        case .sessionBusy, .processStartFailed, .exitRuntimeError:
            return true
        default:
            return false
        }
    }
}

// MARK: - Shell Environment Resolution

/// Resolves the user's full login shell environment (cached)
final class ShellEnvironmentResolver: Sendable {
    static let shared = ShellEnvironmentResolver()

    private let lock = NSLock()
    private nonisolated(unsafe) var _cachedEnv: [String: String]?
    private nonisolated(unsafe) var _resolved = false

    /// Common paths to prepend when environment resolution fails
    private static let fallbackPaths = [
        "/opt/homebrew/bin",
        "/opt/homebrew/sbin",
        "/usr/local/bin",
        "/usr/local/sbin",
        "/usr/bin",
        "/usr/sbin",
        "/bin",
        "/sbin",
        // Common Node.js manager paths
        "/opt/homebrew/opt/node/bin",
        "/usr/local/opt/node/bin"
    ]

    /// NVM, volta, fnm paths that may contain node
    private static func userSpecificPaths() -> [String] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return [
            "\(home)/.nvm/versions/node",  // NVM — we'll find the latest below
            "\(home)/.volta/bin",
            "\(home)/.fnm/aliases/default/bin",
            "\(home)/.local/bin",
            "\(home)/bin",
            "\(home)/.npm-global/bin",
            "\(home)/.cargo/bin"
        ]
    }

    /// Resolve the user's full environment by sourcing their login shell profile.
    /// This captures PATH and other variables that GUI apps don't inherit.
    func resolvedEnvironment() -> [String: String] {
        lock.lock()
        if _resolved, let env = _cachedEnv {
            lock.unlock()
            return env
        }
        lock.unlock()

        let env = resolveFromLoginShell() ?? buildFallbackEnvironment()

        lock.lock()
        _cachedEnv = env
        _resolved = true
        lock.unlock()

        return env
    }

    /// Invalidate the cache (e.g., if the user changes their shell config)
    func invalidateCache() {
        lock.lock()
        _cachedEnv = nil
        _resolved = false
        lock.unlock()
    }

    /// Run the user's login shell to capture the full environment
    private func resolveFromLoginShell() -> [String: String]? {
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"

        let process = Process()
        let pipe = Pipe()

        process.executableURL = URL(fileURLWithPath: shell)
        // Use login + interactive flags, then print env and exit
        // -l for login shell (sources .zprofile, .zshrc, etc.)
        // -c to run command
        process.arguments = ["-l", "-c", "env"]
        process.standardOutput = pipe
        process.standardError = Pipe() // suppress
        process.currentDirectoryURL = FileManager.default.homeDirectoryForCurrentUser

        // Start with a minimal environment so the shell bootstraps properly
        var minEnv: [String: String] = [:]
        minEnv["HOME"] = FileManager.default.homeDirectoryForCurrentUser.path
        minEnv["USER"] = ProcessInfo.processInfo.environment["USER"] ?? NSUserName()
        minEnv["SHELL"] = shell
        minEnv["TERM"] = "dumb"
        minEnv["PATH"] = "/usr/bin:/bin:/usr/sbin:/sbin"
        if let lang = ProcessInfo.processInfo.environment["LANG"] {
            minEnv["LANG"] = lang
        }
        process.environment = minEnv

        do {
            try process.run()
            process.waitUntilExit()

            guard process.terminationStatus == 0 else {
                return nil
            }

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            guard let output = String(data: data, encoding: .utf8) else { return nil }

            var env: [String: String] = [:]
            for line in output.components(separatedBy: .newlines) {
                guard let eqIdx = line.firstIndex(of: "=") else { continue }
                let key = String(line[line.startIndex..<eqIdx])
                let value = String(line[line.index(after: eqIdx)...])
                // Skip potentially dangerous or large vars
                guard !key.isEmpty,
                      !key.hasPrefix("_"),
                      key != "SHLVL",
                      key != "PWD",
                      key != "OLDPWD" else { continue }
                env[key] = value
            }

            // Must have PATH to be useful
            guard env["PATH"] != nil else { return nil }

            return env
        } catch {
            return nil
        }
    }

    /// Build a reasonable fallback environment when shell resolution fails
    private func buildFallbackEnvironment() -> [String: String] {
        var env = ProcessInfo.processInfo.environment

        // Augment PATH with common locations
        let currentPath = env["PATH"] ?? "/usr/bin:/bin"
        var pathComponents = currentPath.components(separatedBy: ":")

        // Add fallback paths that exist
        for path in Self.fallbackPaths where !pathComponents.contains(path) {
            if FileManager.default.isExecutableFile(atPath: path) ||
               FileManager.default.fileExists(atPath: path) {
                pathComponents.insert(path, at: 0)
            }
        }

        // Add user-specific paths that exist
        for path in Self.userSpecificPaths() where !pathComponents.contains(path) {
            if FileManager.default.fileExists(atPath: path) {
                pathComponents.insert(path, at: 0)
            }
        }

        // Try to find NVM's current node version
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let nvmDir = "\(home)/.nvm/versions/node"
        if FileManager.default.fileExists(atPath: nvmDir),
           let versions = try? FileManager.default.contentsOfDirectory(atPath: nvmDir) {
            // Use the latest version directory
            let sorted = versions.sorted { $0.compare($1, options: .numeric) == .orderedDescending }
            if let latest = sorted.first {
                let nodeBin = "\(nvmDir)/\(latest)/bin"
                if !pathComponents.contains(nodeBin) {
                    pathComponents.insert(nodeBin, at: 0)
                }
            }
        }

        env["PATH"] = pathComponents.joined(separator: ":")
        return env
    }
}

// MARK: - Preflight Validation

/// Validates session prerequisites before attempting to send
struct SessionPreflight: Sendable {

    struct ValidationResult: Sendable {
        let isValid: Bool
        let error: SessionSendError?
        let claudePath: String?
        let environment: [String: String]

        static func success(claudePath: String, environment: [String: String]) -> ValidationResult {
            ValidationResult(isValid: true, error: nil, claudePath: claudePath, environment: environment)
        }

        static func failure(_ error: SessionSendError) -> ValidationResult {
            ValidationResult(isValid: false, error: error, claudePath: nil, environment: [:])
        }
    }

    /// Run all preflight checks before sending a message
    static func validate(
        projectPath: String,
        claudeSessionID: String?,
        isRunning: Bool
    ) -> ValidationResult {
        // 1. Check if session is already processing
        if isRunning {
            return .failure(.sessionBusy)
        }

        // 2. Resolve environment (includes PATH augmentation)
        let environment = ShellEnvironmentResolver.shared.resolvedEnvironment()

        // 3. Check project directory exists
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: projectPath, isDirectory: &isDir),
              isDir.boolValue else {
            return .failure(.invalidProjectPath(projectPath))
        }

        // 4. Find Claude executable
        guard let claudePath = ClaudeProcessController.findClaudePath(environment: environment) else {
            return .failure(.claudeNotFound)
        }

        // 5. Validate session ID format if resuming
        if let sid = claudeSessionID {
            // Claude session IDs should be non-empty and reasonable length
            let trimmed = sid.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty || trimmed.count > 200 {
                return .failure(.sessionNotFound(sid))
            }
        }

        return .success(claudePath: claudePath, environment: environment)
    }
}

// MARK: - Claude Process Controller

/// Manages Claude Code process lifecycle and I/O
/// Uses -p --output-format stream-json --verbose for structured output
/// Each message spawns a new process with --resume for multi-turn
final class ClaudeProcessController: Sendable {
    let sessionID: UUID
    let projectPath: String
    let modelName: String
    private let onEvent: @Sendable (SessionEvent) -> Void
    private let onLog: @Sendable (LogEntry) -> Void
    private let onUsage: @Sendable (TokenUsage) -> Void
    private let onStatusChange: @Sendable (SessionStatus) -> Void
    private let onError: @Sendable (SessionSendError) -> Void

    private let lock = NSLock()
    private nonisolated(unsafe) var _process: Process?
    private nonisolated(unsafe) var _isRunning: Bool = false
    private nonisolated(unsafe) var _claudeSessionID: String?
    private nonisolated(unsafe) var _stderrAccumulator: String = ""

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
        onStatusChange: @escaping @Sendable (SessionStatus) -> Void,
        onError: @escaping @Sendable (SessionSendError) -> Void = { _ in }
    ) {
        self.sessionID = sessionID
        self.projectPath = projectPath
        self.modelName = modelName
        self._claudeSessionID = claudeSessionID
        self.onEvent = onEvent
        self.onLog = onLog
        self.onUsage = onUsage
        self.onStatusChange = onStatusChange
        self.onError = onError
    }

    /// Send a message to Claude -- spawns a process for each message.
    /// Output is streamed line-by-line for real-time UI updates.
    /// Returns immediately; runs asynchronously on a background queue.
    func sendMessage(_ message: String) {
        // --- Preflight validation (synchronous, fast) ---
        lock.lock()
        let alreadyRunning = _isRunning
        let existingSessionID = _claudeSessionID
        lock.unlock()

        let preflight = SessionPreflight.validate(
            projectPath: projectPath,
            claudeSessionID: existingSessionID,
            isRunning: alreadyRunning
        )

        guard preflight.isValid, let claudePath = preflight.claudePath else {
            let error = preflight.error ?? .claudeNotFound
            onEvent(SessionEvent(type: .error, content: error.userMessage))
            onError(error)
            return
        }

        // --- Mark as running ---
        lock.lock()
        // Double-check after acquiring lock
        if _isRunning {
            lock.unlock()
            let error = SessionSendError.sessionBusy
            onEvent(SessionEvent(type: .error, content: error.userMessage))
            onError(error)
            return
        }
        _isRunning = true
        _stderrAccumulator = ""
        lock.unlock()

        onStatusChange(.running)
        onEvent(SessionEvent(type: .userInput, content: message))

        // --- Log preflight info ---
        let isResume = existingSessionID != nil
        onLog(LogEntry(
            source: .system,
            content: "Preflight passed. executable=\(claudePath) cwd=\(projectPath) resume=\(isResume) sessionID=\(existingSessionID ?? "none")"
        ))

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
            if let sid = existingSessionID {
                args.append(contentsOf: ["--resume", sid])
            }

            process.arguments = args
            process.currentDirectoryURL = URL(fileURLWithPath: projectPath)
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe

            // Use resolved environment with full PATH
            var env = preflight.environment
            env["TERM"] = "dumb"
            env["NO_COLOR"] = "1"
            process.environment = env

            lock.lock()
            _process = process
            lock.unlock()

            // Log the exact invocation for debugging
            let argsSafe = args.enumerated().map { i, a in
                // Truncate long message content in logs
                if i == 1 && a.count > 200 {
                    return String(a.prefix(200)) + "...(truncated)"
                }
                return a
            }
            onLog(LogEntry(
                source: .system,
                content: "Launching: \(claudePath) \(argsSafe.joined(separator: " "))"
            ))

            do {
                try process.run()
                onLog(LogEntry(source: .system, content: "Process started (PID: \(process.processIdentifier))"))
            } catch {
                let sendError = SessionSendError.processStartFailed(error.localizedDescription)
                onEvent(SessionEvent(type: .error, content: sendError.userMessage))
                onLog(LogEntry(source: .system, content: "Process start failed: \(error)"))
                lock.lock()
                _isRunning = false
                _process = nil
                lock.unlock()
                onStatusChange(.error)
                onError(sendError)
                return
            }

            // -- Streaming stdout line-by-line --
            let bufferLock = NSLock()
            var stdoutBuffer = Data()

            stdoutPipe.fileHandleForReading.readabilityHandler = { [self] handle in
                let chunk = handle.availableData
                guard !chunk.isEmpty else {
                    handle.readabilityHandler = nil
                    return
                }

                bufferLock.lock()
                stdoutBuffer.append(chunk)

                let newline = UInt8(0x0A)
                while let idx = stdoutBuffer.firstIndex(of: newline) {
                    let lineData = stdoutBuffer[stdoutBuffer.startIndex..<idx]
                    stdoutBuffer = stdoutBuffer[(idx + 1)...]
                    bufferLock.unlock()

                    if let line = String(data: lineData, encoding: .utf8) {
                        processStreamLine(line)
                    }

                    bufferLock.lock()
                }
                bufferLock.unlock()
            }

            // -- Streaming stderr (accumulated for error diagnosis) --
            stderrPipe.fileHandleForReading.readabilityHandler = { [self] handle in
                let chunk = handle.availableData
                guard !chunk.isEmpty else {
                    handle.readabilityHandler = nil
                    return
                }
                if let text = String(data: chunk, encoding: .utf8),
                   !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    onLog(LogEntry(source: .stderr, content: text))
                    // Accumulate stderr for error diagnosis
                    lock.lock()
                    _stderrAccumulator += text
                    lock.unlock()
                }
            }

            // Wait for process to finish
            process.waitUntilExit()

            // Clean up handlers
            stdoutPipe.fileHandleForReading.readabilityHandler = nil
            stderrPipe.fileHandleForReading.readabilityHandler = nil

            // Process remaining buffered data
            bufferLock.lock()
            let remaining = stdoutBuffer
            stdoutBuffer = Data()
            bufferLock.unlock()

            if !remaining.isEmpty, let text = String(data: remaining, encoding: .utf8) {
                let lines = text.components(separatedBy: .newlines)
                for line in lines {
                    processStreamLine(line)
                }
            }

            // Capture final state
            lock.lock()
            let stderr = _stderrAccumulator
            _isRunning = false
            _process = nil
            lock.unlock()

            let exitStatus = process.terminationStatus
            let stderrSnippet = String(stderr.suffix(500)).trimmingCharacters(in: .whitespacesAndNewlines)

            onLog(LogEntry(
                source: .system,
                content: "Process exited with code \(exitStatus). resume=\(isResume) sessionID=\(existingSessionID ?? "none")"
            ))

            if exitStatus == 0 {
                onStatusChange(.idle)
            } else {
                // Map exit code to structured error
                let sendError = Self.mapExitCode(
                    exitStatus,
                    stderr: stderrSnippet,
                    isResume: isResume,
                    sessionID: existingSessionID
                )

                onEvent(SessionEvent(
                    type: .error,
                    content: sendError.errorDescription ?? sendError.userMessage,
                    metadata: EventMetadata(exitCode: Int(exitStatus))
                ))
                onLog(LogEntry(
                    source: .system,
                    content: "Error diagnosis: \(sendError.userMessage) | stderr: \(stderrSnippet)"
                ))
                onStatusChange(.error)
                onError(sendError)
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

    /// Clear the stored claude session ID (for session recreation)
    func clearSessionID() {
        lock.lock()
        _claudeSessionID = nil
        lock.unlock()
    }

    // MARK: - Exit Code Mapping

    /// Map a non-zero exit code to a specific SessionSendError
    private static func mapExitCode(
        _ code: Int32,
        stderr: String,
        isResume: Bool,
        sessionID: String?
    ) -> SessionSendError {
        let stderrLower = stderr.lowercased()

        switch code {
        case 127:
            // Command not found -- binary or dependency missing from PATH
            if stderrLower.contains("node") || stderrLower.contains("npm") {
                return .nodeNotFound
            }
            return .exitCommandNotFound(stderr: stderr)

        case 1:
            // Generic error -- try to diagnose from stderr
            if isResume {
                // Check for session-related errors
                if stderrLower.contains("session") && (stderrLower.contains("not found") || stderrLower.contains("invalid") || stderrLower.contains("expired")) {
                    return .exitSessionInvalid(stderr: stderr)
                }
                if stderrLower.contains("no such session") || stderrLower.contains("could not find session") || stderrLower.contains("does not exist") {
                    return .exitSessionInvalid(stderr: stderr)
                }
                if stderrLower.contains("resume") && stderrLower.contains("error") {
                    return .exitSessionInvalid(stderr: stderr)
                }
            }
            // Check for path/permission issues
            if stderrLower.contains("not found") || stderrLower.contains("no such file") {
                return .exitCommandNotFound(stderr: stderr)
            }
            return .exitRuntimeError(code: code, stderr: stderr)

        case 2:
            // Usually invalid arguments
            return .exitRuntimeError(code: code, stderr: stderr)

        case 126:
            // Permission denied
            return .processStartFailed("Permission denied executing Claude Code binary")

        default:
            return .exitRuntimeError(code: code, stderr: stderr)
        }
    }

    // MARK: - Stream line processing

    /// Process a single line of stream-json output in real-time
    private func processStreamLine(_ line: String) {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        onLog(LogEntry(source: .stdout, content: trimmed))

        guard let data = trimmed.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return
        }

        let type = json["type"] as? String ?? ""

        // Extract session_id from system or result events
        if let sid = json["session_id"] as? String {
            lock.lock()
            _claudeSessionID = sid
            lock.unlock()
        }

        switch type {
        case "system":
            let model = json["model"] as? String ?? ""
            onEvent(SessionEvent(type: .sessionStart, content: "Model: \(model)"))

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
                    let content = Utilities.formatToolInput(toolName: toolName, input: input)
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

    // MARK: - Static helpers

    /// Find the Claude binary, using the provided environment's PATH
    static func findClaudePath(environment: [String: String]? = nil) -> String? {
        // 1. Check well-known hardcoded paths first (fastest)
        let wellKnownPaths = [
            "/opt/homebrew/bin/claude",
            "/usr/local/bin/claude",
            "/usr/bin/claude"
        ]

        for path in wellKnownPaths {
            if FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        }

        // 2. Check user-specific paths
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let userPaths = [
            "\(home)/.npm-global/bin/claude",
            "\(home)/.local/bin/claude",
            "\(home)/bin/claude"
        ]

        for path in userPaths {
            if FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        }

        // 3. Search the resolved PATH
        if let envPath = environment?["PATH"] ?? ProcessInfo.processInfo.environment["PATH"] {
            for dir in envPath.components(separatedBy: ":") {
                let candidate = (dir as NSString).appendingPathComponent("claude")
                if FileManager.default.isExecutableFile(atPath: candidate) {
                    return candidate
                }
            }
        }

        // 4. Fallback: `which claude` using resolved environment
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = ["claude"]
        process.standardOutput = pipe
        process.standardError = Pipe()
        if let env = environment {
            process.environment = env
        }

        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
               !path.isEmpty,
               FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        } catch {}

        return nil
    }

    static func checkAvailability() -> (available: Bool, path: String?, version: String?) {
        let env = ShellEnvironmentResolver.shared.resolvedEnvironment()
        guard let path = findClaudePath(environment: env) else {
            return (false, nil, nil)
        }

        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = ["--version"]
        process.standardOutput = pipe
        process.standardError = Pipe()
        process.environment = env

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

// MARK: - Legacy FoundryError (kept for backward compat)

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
