import Foundation

/// Loads real Claude Code session data from ~/.claude/
struct ClaudeHistoryLoader {

    static let claudeDir: URL = {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent(".claude", isDirectory: true)
    }()

    static var sessionsDir: URL {
        claudeDir.appendingPathComponent("sessions", isDirectory: true)
    }

    static var projectsDir: URL {
        claudeDir.appendingPathComponent("projects", isDirectory: true)
    }

    // MARK: - Load all sessions metadata

    struct ClaudeSessionMeta: Codable {
        let pid: Int?
        let sessionId: String
        let cwd: String?
        let startedAt: Int64?
        let kind: String?
        let entrypoint: String?
        let name: String?
    }

    static func loadAllSessionMetas() -> [ClaudeSessionMeta] {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(
            at: sessionsDir,
            includingPropertiesForKeys: nil,
            options: .skipsHiddenFiles
        ) else { return [] }

        return files
            .filter { $0.pathExtension == "json" }
            .compactMap { url -> ClaudeSessionMeta? in
                guard let data = try? Data(contentsOf: url) else { return nil }
                return try? JSONDecoder().decode(ClaudeSessionMeta.self, from: data)
            }
            .sorted { ($0.startedAt ?? 0) > ($1.startedAt ?? 0) }
    }

    // MARK: - Find conversation JSONL for a session

    static func findConversationFile(sessionId: String) -> URL? {
        let fm = FileManager.default
        guard let projectDirs = try? fm.contentsOfDirectory(
            at: projectsDir,
            includingPropertiesForKeys: nil,
            options: .skipsHiddenFiles
        ) else { return nil }

        for dir in projectDirs {
            let jsonlFile = dir.appendingPathComponent("\(sessionId).jsonl")
            if fm.fileExists(atPath: jsonlFile.path) {
                return jsonlFile
            }
        }
        return nil
    }

    // MARK: - Load conversation events from JSONL

    struct ConversationEntry: Codable {
        let type: String
        let uuid: String?
        let parentUuid: String?
        let timestamp: String?
        let message: MessageValue?
        let sessionId: String?
        let cwd: String?
        let version: String?
        let permissionMode: String?
        let filePath: String?

        // For file-history-snapshot
        let messageId: String?

        enum MessageValue: Codable {
            case string(String)
            case dict([String: AnyCodable])

            init(from decoder: Decoder) throws {
                let container = try decoder.singleValueContainer()
                if let s = try? container.decode(String.self) {
                    self = .string(s)
                } else if let d = try? container.decode([String: AnyCodable].self) {
                    self = .dict(d)
                } else {
                    self = .string("")
                }
            }

            func encode(to encoder: Encoder) throws {
                var container = encoder.singleValueContainer()
                switch self {
                case .string(let s): try container.encode(s)
                case .dict(let d): try container.encode(d)
                }
            }
        }
    }

    static func loadConversation(sessionId: String) -> [SessionEvent] {
        guard let fileURL = findConversationFile(sessionId: sessionId) else {
            return []
        }
        return loadConversationFromFile(fileURL)
    }

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

            // Parse as generic JSON first
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                continue
            }

            let type = json["type"] as? String ?? ""
            let timestamp = parseTimestamp(json["timestamp"])

            switch type {
            case "user":
                let parsed = parseUserEntry(json, timestamp: timestamp)
                events.append(contentsOf: parsed)

            case "assistant":
                let parsed = parseAssistantEntry(json, timestamp: timestamp)
                events.append(contentsOf: parsed)

            case "system":
                if let msg = extractMessageString(json) {
                    events.append(SessionEvent(
                        type: .systemInfo,
                        content: msg,
                        timestamp: timestamp
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

    // MARK: - Parse entries

    private static func parseUserEntry(_ json: [String: Any], timestamp: Date) -> [SessionEvent] {
        var events: [SessionEvent] = []

        guard let messageRaw = json["message"] else { return events }

        let messageDict: [String: Any]
        if let s = messageRaw as? String {
            // Python dict repr string - parse it
            if let parsed = parsePythonDict(s) {
                messageDict = parsed
            } else {
                events.append(SessionEvent(type: .userInput, content: s, timestamp: timestamp))
                return events
            }
        } else if let d = messageRaw as? [String: Any] {
            messageDict = d
        } else {
            return events
        }

        let content = messageDict["content"]

        if let text = content as? String {
            events.append(SessionEvent(type: .userInput, content: text, timestamp: timestamp))
        } else if let blocks = content as? [[String: Any]] {
            // Check if these are tool_results
            for block in blocks {
                let blockType = block["type"] as? String ?? ""
                if blockType == "tool_result" {
                    let toolContent = extractToolResultContent(block)
                    let isError = block["is_error"] as? Bool ?? false
                    events.append(SessionEvent(
                        type: isError ? .error : .toolResult,
                        content: toolContent,
                        metadata: EventMetadata(toolName: block["tool_use_id"] as? String),
                        timestamp: timestamp
                    ))
                } else if blockType == "text" {
                    let text = block["text"] as? String ?? ""
                    events.append(SessionEvent(type: .userInput, content: text, timestamp: timestamp))
                }
            }
        }

        return events
    }

    private static func parseAssistantEntry(_ json: [String: Any], timestamp: Date) -> [SessionEvent] {
        var events: [SessionEvent] = []

        guard let messageRaw = json["message"] else { return events }

        let messageDict: [String: Any]
        if let s = messageRaw as? String {
            if let parsed = parsePythonDict(s) {
                messageDict = parsed
            } else {
                events.append(SessionEvent(type: .assistantMessage, content: s, timestamp: timestamp))
                return events
            }
        } else if let d = messageRaw as? [String: Any] {
            messageDict = d
        } else {
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
                        type: .assistantMessage,
                        content: text,
                        timestamp: timestamp
                    ))
                }

            case "thinking":
                let thinking = block["thinking"] as? String ?? ""
                if !thinking.isEmpty {
                    events.append(SessionEvent(
                        type: .thinking,
                        content: thinking,
                        timestamp: timestamp
                    ))
                }

            case "tool_use":
                let toolName = block["name"] as? String ?? "unknown"
                let input = block["input"] as? [String: Any] ?? [:]
                let inputStr = formatToolInput(toolName: toolName, input: input)

                let eventType: EventType
                var metadata = EventMetadata(toolName: toolName)

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
                case "Grep":
                    eventType = .search
                    metadata.searchPattern = input["pattern"] as? String
                case "Glob":
                    eventType = .search
                    metadata.searchPattern = input["pattern"] as? String
                case "Agent":
                    eventType = .subAgentSpawn
                    metadata.agentName = input["subagent_type"] as? String ?? "general"
                default:
                    eventType = .toolUse
                }

                events.append(SessionEvent(
                    type: eventType,
                    content: inputStr,
                    metadata: metadata,
                    timestamp: timestamp
                ))

            default:
                break
            }
        }

        return events
    }

    // MARK: - Helpers

    private static func parseTimestamp(_ value: Any?) -> Date {
        if let str = value as? String {
            // ISO 8601
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = formatter.date(from: str) {
                return date
            }
            // Try milliseconds
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

    private static func extractMessageString(_ json: [String: Any]) -> String? {
        if let msg = json["message"] as? String {
            return msg
        }
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
            let path = input["file_path"] as? String ?? ""
            let old = input["old_string"] as? String ?? ""
            return "\(path) (replacing \(old.count) chars)"
        case "Grep":
            let pattern = input["pattern"] as? String ?? ""
            let path = input["path"] as? String ?? "."
            return "\(pattern) in \(path)"
        case "Glob":
            return input["pattern"] as? String ?? ""
        case "Agent":
            return input["description"] as? String ?? input["prompt"] as? String ?? ""
        case "TaskCreate":
            return input["subject"] as? String ?? ""
        case "TaskUpdate":
            let id = input["taskId"] as? String ?? ""
            let status = input["status"] as? String ?? ""
            return "Task #\(id) → \(status)"
        default:
            if let data = try? JSONSerialization.data(withJSONObject: input, options: []),
               let str = String(data: data, encoding: .utf8) {
                return String(str.prefix(200))
            }
            return ""
        }
    }

    /// Parse Python dict repr as JSON (handles common cases)
    private static func parsePythonDict(_ s: String) -> [String: Any]? {
        // Replace Python-specific syntax with JSON
        var json = s
        json = json.replacingOccurrences(of: "None", with: "null")
        json = json.replacingOccurrences(of: "True", with: "true")
        json = json.replacingOccurrences(of: "False", with: "false")
        // Replace single quotes with double quotes (simplified)
        json = json.replacingOccurrences(of: "'", with: "\"")

        guard let data = json.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return dict
    }

    // MARK: - Load all sessions as Foundry Sessions

    static func loadAllClaudeSessions() -> [Session] {
        let metas = loadAllSessionMetas()
        return metas.map { meta in
            let startDate: Date
            if let ms = meta.startedAt {
                startDate = Date(timeIntervalSince1970: Double(ms) / 1000.0)
            } else {
                startDate = Date()
            }

            let projectPath = meta.cwd ?? "~"
            let dirName = URL(fileURLWithPath: projectPath).lastPathComponent

            var session = Session(
                name: meta.name ?? dirName,
                projectPath: projectPath,
                modelName: "claude-sonnet-4-6"
            )
            session.claudeSessionID = meta.sessionId
            session.status = .stopped
            session.createdAt = startDate
            session.updatedAt = startDate

            return session
        }
    }

    static func loadSessionEvents(claudeSessionId: String) -> [SessionEvent] {
        return loadConversation(sessionId: claudeSessionId)
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
