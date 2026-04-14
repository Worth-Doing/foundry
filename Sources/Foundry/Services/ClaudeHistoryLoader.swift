import Foundation

/// Loads real Claude Code session data from ~/.claude/
/// The source of truth is JSONL files in ~/.claude/projects/*/*.jsonl
struct ClaudeHistoryLoader {

    static let claudeDir: URL = {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent(".claude", isDirectory: true)
    }()

    static var projectsDir: URL {
        claudeDir.appendingPathComponent("projects", isDirectory: true)
    }

    // MARK: - Discover all sessions from JSONL files

    struct DiscoveredSession {
        let sessionId: String
        let projectDirName: String
        let jsonlPath: URL
        let cwd: String
        let model: String
        let name: String
        let startedAt: Date
        let lineCount: Int
        let usage: TokenUsage
    }

    /// Scan all JSONL files in ~/.claude/projects/ to discover every session
    static func discoverAllSessions() -> [DiscoveredSession] {
        let fm = FileManager.default
        var results: [DiscoveredSession] = []

        guard let projectDirs = try? fm.contentsOfDirectory(
            at: projectsDir,
            includingPropertiesForKeys: nil,
            options: .skipsHiddenFiles
        ) else { return [] }

        for dir in projectDirs {
            var isDirectory: ObjCBool = false
            guard fm.fileExists(atPath: dir.path, isDirectory: &isDirectory),
                  isDirectory.boolValue else { continue }

            // Skip non-session directories (memory, etc.)
            let dirName = dir.lastPathComponent
            if dirName == "." || dirName == ".." { continue }

            guard let files = try? fm.contentsOfDirectory(
                at: dir,
                includingPropertiesForKeys: [.fileSizeKey],
                options: .skipsHiddenFiles
            ) else { continue }

            for file in files where file.pathExtension == "jsonl" {
                let sessionId = file.deletingPathExtension().lastPathComponent

                // Quick parse: read first lines for metadata, scan all for usage
                if let session = parseSessionFile(
                    jsonlPath: file,
                    sessionId: sessionId,
                    projectDirName: dirName
                ) {
                    results.append(session)
                }
            }
        }

        return results.sorted { $0.startedAt > $1.startedAt }
    }

    /// Parse a session JSONL file to extract metadata and usage
    private static func parseSessionFile(
        jsonlPath: URL,
        sessionId: String,
        projectDirName: String
    ) -> DiscoveredSession? {
        guard let content = try? String(contentsOf: jsonlPath, encoding: .utf8) else {
            return nil
        }

        let lines = content.components(separatedBy: .newlines)
        var cwd = ""
        var model = ""
        var name = ""
        var startedAt = Date.distantPast
        var totalInput = 0
        var totalOutput = 0
        var totalCacheRead = 0
        var totalCacheWrite = 0
        var lineCount = 0

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            lineCount += 1

            guard let data = trimmed.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                continue
            }

            let type = json["type"] as? String ?? ""

            // Extract metadata from first user or system message
            if cwd.isEmpty {
                if let c = json["cwd"] as? String, !c.isEmpty {
                    cwd = c
                }
            }
            if startedAt == Date.distantPast {
                if let ts = json["timestamp"] as? String {
                    startedAt = parseTimestamp(ts)
                }
            }
            if let n = json["name"] as? String, !n.isEmpty, name.isEmpty {
                name = n
            }

            // Extract usage from assistant messages
            if type == "assistant" {
                let messageDict = extractMessageDict(json["message"])
                if let msg = messageDict {
                    if model.isEmpty, let m = msg["model"] as? String {
                        model = m
                    }
                    if let usage = msg["usage"] as? [String: Any] {
                        totalInput += usage["input_tokens"] as? Int ?? 0
                        totalOutput += usage["output_tokens"] as? Int ?? 0
                        totalCacheRead += usage["cache_read_input_tokens"] as? Int ?? 0
                        totalCacheWrite += usage["cache_creation_input_tokens"] as? Int ?? 0
                    }
                }
            }
        }

        guard lineCount > 0 else { return nil }

        // Derive CWD from project dir name if not found in data
        if cwd.isEmpty {
            cwd = projectDirName.replacingOccurrences(of: "-", with: "/")
            if !cwd.hasPrefix("/") {
                cwd = "/" + cwd
            }
        }

        // Calculate cost
        let cost = calculateCost(
            model: model,
            inputTokens: totalInput,
            outputTokens: totalOutput,
            cacheReadTokens: totalCacheRead,
            cacheWriteTokens: totalCacheWrite
        )

        var usage = TokenUsage()
        usage.inputTokens = totalInput
        usage.outputTokens = totalOutput
        usage.cacheReadTokens = totalCacheRead
        usage.cacheWriteTokens = totalCacheWrite
        usage.estimatedCostUSD = cost

        return DiscoveredSession(
            sessionId: sessionId,
            projectDirName: projectDirName,
            jsonlPath: jsonlPath,
            cwd: cwd,
            model: model.isEmpty ? "claude-opus-4-6" : model,
            name: name,
            startedAt: startedAt == Date.distantPast ? Date() : startedAt,
            lineCount: lineCount,
            usage: usage
        )
    }

    // MARK: - Load conversation events from a JSONL file

    static func loadConversationFromFile(_ fileURL: URL) -> [SessionEvent] {
        guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else {
            return []
        }

        var events: [SessionEvent] = []
        let lines = content.components(separatedBy: .newlines)

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            guard let data = trimmed.data(using: .utf8) else { continue }
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                continue
            }

            let type = json["type"] as? String ?? ""
            let timestamp = parseTimestamp(json["timestamp"])

            switch type {
            case "user":
                events.append(contentsOf: parseUserEntry(json, timestamp: timestamp))
            case "assistant":
                events.append(contentsOf: parseAssistantEntry(json, timestamp: timestamp))
            case "system":
                if let content = extractPlainContent(json) {
                    events.append(SessionEvent(
                        type: .systemInfo, content: content, timestamp: timestamp
                    ))
                }
            case "permission-mode":
                let mode = json["permissionMode"] as? String ?? "default"
                events.append(SessionEvent(
                    type: .systemInfo,
                    content: "Permission mode: \(mode)",
                    timestamp: timestamp
                ))
            default:
                break
            }
        }

        return events
    }

    // MARK: - Convert discovered sessions to Foundry Sessions

    static func loadAllAsFoundrySessions() -> [Session] {
        let discovered = discoverAllSessions()
        return discovered.map { d in
            let dirName = URL(fileURLWithPath: d.cwd).lastPathComponent
            var session = Session(
                name: d.name.isEmpty ? dirName : d.name,
                projectPath: d.cwd,
                modelName: d.model
            )
            session.claudeSessionID = d.sessionId
            session.status = .stopped
            session.createdAt = d.startedAt
            session.updatedAt = d.startedAt
            session.tokenUsage = d.usage
            return session
        }
    }

    // MARK: - Parse user entry

    private static func parseUserEntry(_ json: [String: Any], timestamp: Date) -> [SessionEvent] {
        var events: [SessionEvent] = []
        guard let messageDict = extractMessageDict(json["message"]) else {
            // Try as plain string
            if let s = json["message"] as? String, !s.isEmpty {
                events.append(SessionEvent(type: .userInput, content: s, timestamp: timestamp))
            }
            return events
        }

        let content = messageDict["content"]

        if let text = content as? String {
            if !text.isEmpty {
                events.append(SessionEvent(type: .userInput, content: text, timestamp: timestamp))
            }
        } else if let blocks = content as? [[String: Any]] {
            for block in blocks {
                let blockType = block["type"] as? String ?? ""
                if blockType == "tool_result" {
                    let resultContent = extractToolResultContent(block)
                    let isError = block["is_error"] as? Bool ?? false
                    if !resultContent.isEmpty {
                        events.append(SessionEvent(
                            type: isError ? .error : .toolResult,
                            content: String(resultContent.prefix(2000)),
                            timestamp: timestamp
                        ))
                    }
                } else if blockType == "text" {
                    let text = block["text"] as? String ?? ""
                    if !text.isEmpty {
                        events.append(SessionEvent(type: .userInput, content: text, timestamp: timestamp))
                    }
                }
            }
        }

        return events
    }

    // MARK: - Parse assistant entry

    private static func parseAssistantEntry(_ json: [String: Any], timestamp: Date) -> [SessionEvent] {
        var events: [SessionEvent] = []
        guard let messageDict = extractMessageDict(json["message"]) else {
            return events
        }

        guard let contentBlocks = messageDict["content"] as? [[String: Any]] else {
            return events
        }

        for block in contentBlocks {
            let blockType = block["type"] as? String ?? ""

            switch blockType {
            case "text":
                let text = block["text"] as? String ?? ""
                if !text.isEmpty {
                    events.append(SessionEvent(
                        type: .assistantMessage, content: text, timestamp: timestamp
                    ))
                }

            case "thinking":
                let thinking = block["thinking"] as? String ?? ""
                if !thinking.isEmpty {
                    events.append(SessionEvent(
                        type: .thinking,
                        content: String(thinking.prefix(500)),
                        timestamp: timestamp
                    ))
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
                    metadata.agentName = input["subagent_type"] as? String ?? "general"
                default:
                    eventType = .toolUse
                }

                events.append(SessionEvent(
                    type: eventType, content: content,
                    metadata: metadata, timestamp: timestamp
                ))

            default:
                break
            }
        }

        return events
    }

    // MARK: - Helpers

    private static func extractMessageDict(_ raw: Any?) -> [String: Any]? {
        if let d = raw as? [String: Any] {
            return d
        }
        if let s = raw as? String {
            return parsePythonDict(s)
        }
        return nil
    }

    private static func extractPlainContent(_ json: [String: Any]) -> String? {
        if let msg = json["message"] as? String { return msg }
        if let msg = json["message"] as? [String: Any] {
            return msg["content"] as? String
        }
        return nil
    }

    private static func extractToolResultContent(_ block: [String: Any]) -> String {
        if let content = block["content"] as? String {
            return content
        }
        if let contentBlocks = block["content"] as? [[String: Any]] {
            return contentBlocks.compactMap { b -> String? in
                if b["type"] as? String == "text" {
                    return b["text"] as? String
                }
                return nil
            }.joined(separator: "\n")
        }
        return ""
    }

    private static func formatToolInput(toolName: String, input: [String: Any]) -> String {
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
            return input["file_path"] as? String ?? ""
        case "Grep":
            return "grep: \(input["pattern"] as? String ?? "")"
        case "Glob":
            return "glob: \(input["pattern"] as? String ?? "")"
        case "Agent":
            return input["description"] as? String ?? input["prompt"] as? String ?? ""
        case "TaskCreate":
            return input["subject"] as? String ?? ""
        case "TaskUpdate":
            return "Task #\(input["taskId"] as? String ?? "") → \(input["status"] as? String ?? "")"
        default:
            if let data = try? JSONSerialization.data(withJSONObject: input, options: []),
               let str = String(data: data, encoding: .utf8) {
                return String(str.prefix(300))
            }
            return ""
        }
    }

    private static func parseTimestamp(_ value: Any?) -> Date {
        if let str = value as? String {
            // ISO 8601
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = formatter.date(from: str) { return date }
            // Milliseconds as string
            if let ms = Int64(str) {
                return Date(timeIntervalSince1970: Double(ms) / 1000.0)
            }
        }
        if let ms = value as? Int64 {
            return Date(timeIntervalSince1970: Double(ms) / 1000.0)
        }
        if let ms = value as? Int {
            return Date(timeIntervalSince1970: Double(ms) / 1000.0)
        }
        return Date()
    }

    /// Parse Python dict repr as JSON
    private static func parsePythonDict(_ s: String) -> [String: Any]? {
        var json = s
        json = json.replacingOccurrences(of: "None", with: "null")
        json = json.replacingOccurrences(of: "True", with: "true")
        json = json.replacingOccurrences(of: "False", with: "false")
        json = json.replacingOccurrences(of: "'", with: "\"")

        guard let data = json.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return dict
    }

    // MARK: - Cost calculation

    static func calculateCost(
        model: String,
        inputTokens: Int,
        outputTokens: Int,
        cacheReadTokens: Int,
        cacheWriteTokens: Int
    ) -> Double {
        // Pricing per million tokens (USD)
        let inputPrice: Double
        let outputPrice: Double
        let cacheReadPrice: Double
        let cacheWritePrice: Double

        if model.contains("opus") {
            inputPrice = 15.0
            outputPrice = 75.0
            cacheReadPrice = 1.50
            cacheWritePrice = 18.75
        } else if model.contains("haiku") {
            inputPrice = 0.80
            outputPrice = 4.0
            cacheReadPrice = 0.08
            cacheWritePrice = 1.0
        } else {
            // Sonnet default
            inputPrice = 3.0
            outputPrice = 15.0
            cacheReadPrice = 0.30
            cacheWritePrice = 3.75
        }

        let cost = (Double(inputTokens) * inputPrice / 1_000_000) +
                   (Double(outputTokens) * outputPrice / 1_000_000) +
                   (Double(cacheReadTokens) * cacheReadPrice / 1_000_000) +
                   (Double(cacheWriteTokens) * cacheWritePrice / 1_000_000)

        return cost
    }
}

// Extended SessionEvent init with timestamp
extension SessionEvent {
    init(type: EventType, content: String, metadata: EventMetadata? = nil, timestamp: Date, isExpanded: Bool = true) {
        self.id = UUID()
        self.timestamp = timestamp
        self.type = type
        self.content = content
        self.metadata = metadata
        self.isExpanded = isExpanded
    }
}
