import Foundation

/// Manages a single Claude Code process lifecycle and I/O
final class ClaudeProcessController: Sendable {
    private let sessionID: UUID
    private let projectPath: String
    private let modelName: String
    private let onEvent: @Sendable (SessionEvent) -> Void
    private let onLog: @Sendable (LogEntry) -> Void
    private let onUsage: @Sendable (TokenUsage) -> Void
    private let onExit: @Sendable (Int32) -> Void

    private let processLock = NSLock()
    private nonisolated(unsafe) var _process: Process?
    private nonisolated(unsafe) var _stdinPipe: Pipe?
    private nonisolated(unsafe) var _isRunning: Bool = false

    var isRunning: Bool {
        processLock.lock()
        defer { processLock.unlock() }
        return _isRunning
    }

    var processIdentifier: Int32? {
        processLock.lock()
        defer { processLock.unlock() }
        return _process?.processIdentifier
    }

    init(
        sessionID: UUID,
        projectPath: String,
        modelName: String = "claude-sonnet-4-6",
        onEvent: @escaping @Sendable (SessionEvent) -> Void,
        onLog: @escaping @Sendable (LogEntry) -> Void,
        onUsage: @escaping @Sendable (TokenUsage) -> Void,
        onExit: @escaping @Sendable (Int32) -> Void
    ) {
        self.sessionID = sessionID
        self.projectPath = projectPath
        self.modelName = modelName
        self.onEvent = onEvent
        self.onLog = onLog
        self.onUsage = onUsage
        self.onExit = onExit
    }

    /// Launch Claude Code process with streaming JSON I/O
    func start() throws {
        let process = Process()
        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()

        // Find claude binary
        let claudePath = Self.findClaudePath()
        guard let path = claudePath else {
            throw FoundryError.claudeNotFound
        }

        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = [
            "--print",
            "--output-format", "stream-json",
            "--input-format", "stream-json",
            "--model", modelName,
            "--verbose",
            "--add-dir", projectPath
        ]
        process.currentDirectoryURL = URL(fileURLWithPath: projectPath)
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        // Set environment to inherit user's shell PATH
        var env = ProcessInfo.processInfo.environment
        env["TERM"] = "dumb"
        env["NO_COLOR"] = "1"
        process.environment = env

        // Handle stdout - stream JSON events
        stdoutPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else {
                // EOF
                handle.readabilityHandler = nil
                return
            }
            guard let output = String(data: data, encoding: .utf8) else { return }
            self?.handleStdout(output)
        }

        // Handle stderr - log output
        stderrPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else {
                handle.readabilityHandler = nil
                return
            }
            guard let output = String(data: data, encoding: .utf8) else { return }
            self?.handleStderr(output)
        }

        // Handle process termination
        process.terminationHandler = { [weak self] proc in
            self?.processLock.lock()
            self?._isRunning = false
            self?.processLock.unlock()
            self?.onExit(proc.terminationStatus)
        }

        try process.run()

        processLock.lock()
        _process = process
        _stdinPipe = stdinPipe
        _isRunning = true
        processLock.unlock()

        onLog(LogEntry(source: .system, content: "Claude Code process started (PID: \(process.processIdentifier))"))
    }

    /// Send a user message to the Claude process
    func sendMessage(_ message: String) {
        processLock.lock()
        guard let pipe = _stdinPipe, _isRunning else {
            processLock.unlock()
            return
        }
        processLock.unlock()

        // Format as stream-json input
        let jsonMessage: [String: Any] = [
            "type": "user_message",
            "content": message
        ]

        guard let data = try? JSONSerialization.data(withJSONObject: jsonMessage),
              var jsonString = String(data: data, encoding: .utf8) else {
            return
        }
        jsonString += "\n"

        if let writeData = jsonString.data(using: .utf8) {
            pipe.fileHandleForWriting.write(writeData)
        }

        onEvent(SessionEvent(type: .userInput, content: message))
    }

    /// Send a slash command to the Claude process
    func sendCommand(_ command: String) {
        sendMessage(command)
    }

    /// Stop the Claude process
    func stop() {
        processLock.lock()
        guard let process = _process, _isRunning else {
            processLock.unlock()
            return
        }
        processLock.unlock()

        // Close stdin to signal end of input
        _stdinPipe?.fileHandleForWriting.closeFile()

        // Give it a moment, then terminate if still running
        DispatchQueue.global().asyncAfter(deadline: .now() + 2) { [weak self] in
            self?.processLock.lock()
            let stillRunning = self?._isRunning ?? false
            self?.processLock.unlock()

            if stillRunning {
                process.terminate()
            }
        }
    }

    /// Force kill the process
    func kill() {
        processLock.lock()
        let process = _process
        _isRunning = false
        processLock.unlock()

        process?.terminate()
    }

    // MARK: - Private

    private nonisolated(unsafe) var stdoutBuffer = ""

    private func handleStdout(_ output: String) {
        stdoutBuffer += output
        onLog(LogEntry(source: .stdout, content: output))

        // Process complete JSON lines
        while let newlineIndex = stdoutBuffer.firstIndex(of: "\n") {
            let line = String(stdoutBuffer[stdoutBuffer.startIndex..<newlineIndex])
            stdoutBuffer = String(stdoutBuffer[stdoutBuffer.index(after: newlineIndex)...])

            if let event = EventParser.parse(line: line) {
                onEvent(event)
            }
            if let usage = EventParser.parseUsage(from: line) {
                onUsage(usage)
            }
        }
    }

    private func handleStderr(_ output: String) {
        onLog(LogEntry(source: .stderr, content: output))

        // Check for error patterns
        let lines = output.components(separatedBy: .newlines)
        for line in lines where !line.trimmingCharacters(in: .whitespaces).isEmpty {
            if line.lowercased().contains("error") || line.lowercased().contains("fatal") {
                onEvent(SessionEvent(type: .error, content: line))
            }
        }
    }

    // MARK: - Static

    static func findClaudePath() -> String? {
        // Check common locations
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
        let whichProcess = Process()
        let pipe = Pipe()
        whichProcess.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        whichProcess.arguments = ["claude"]
        whichProcess.standardOutput = pipe
        whichProcess.standardError = Pipe()

        do {
            try whichProcess.run()
            whichProcess.waitUntilExit()
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

        // Get version
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
