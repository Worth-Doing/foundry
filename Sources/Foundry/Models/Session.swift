import Foundation

enum SessionStatus: String, Codable, Sendable {
    case initializing
    case running
    case idle
    case error
    case stopped
}

struct Session: Identifiable, Codable, Sendable {
    let id: UUID
    var name: String
    var projectPath: String
    var status: SessionStatus
    var events: [SessionEvent]
    var fileChanges: [FileChange]
    var rawLogs: [LogEntry]
    var createdAt: Date
    var updatedAt: Date
    var processID: Int32?
    var modelName: String
    var tokenUsage: TokenUsage
    var claudeSessionID: String?

    init(
        id: UUID = UUID(),
        name: String = "New Session",
        projectPath: String,
        modelName: String = "claude-sonnet-4-6"
    ) {
        self.id = id
        self.name = name
        self.projectPath = projectPath
        self.status = .initializing
        self.events = []
        self.fileChanges = []
        self.rawLogs = []
        self.createdAt = Date()
        self.updatedAt = Date()
        self.processID = nil
        self.modelName = modelName
        self.tokenUsage = TokenUsage()
        self.claudeSessionID = nil
    }
}

struct TokenUsage: Codable, Sendable {
    var inputTokens: Int = 0
    var outputTokens: Int = 0
    var cacheReadTokens: Int = 0
    var cacheWriteTokens: Int = 0
    var estimatedCostUSD: Double = 0.0
}

struct FileChange: Identifiable, Codable, Sendable {
    let id: UUID
    let filePath: String
    let changeType: FileChangeType
    let timestamp: Date
    var diffLines: [DiffLine]

    init(filePath: String, changeType: FileChangeType, diffLines: [DiffLine] = []) {
        self.id = UUID()
        self.filePath = filePath
        self.changeType = changeType
        self.timestamp = Date()
        self.diffLines = diffLines
    }
}

enum FileChangeType: String, Codable, Sendable {
    case created
    case modified
    case deleted
    case renamed
}

struct DiffLine: Identifiable, Codable, Sendable {
    let id: UUID
    let type: DiffLineType
    let content: String
    let oldLineNumber: Int?
    let newLineNumber: Int?

    init(type: DiffLineType, content: String, oldLineNumber: Int? = nil, newLineNumber: Int? = nil) {
        self.id = UUID()
        self.type = type
        self.content = content
        self.oldLineNumber = oldLineNumber
        self.newLineNumber = newLineNumber
    }
}

enum DiffLineType: String, Codable, Sendable {
    case addition
    case deletion
    case context
    case header
}

struct LogEntry: Identifiable, Codable, Sendable {
    let id: UUID
    let timestamp: Date
    let source: LogSource
    let content: String

    init(source: LogSource, content: String) {
        self.id = UUID()
        self.timestamp = Date()
        self.source = source
        self.content = content
    }
}

enum LogSource: String, Codable, Sendable {
    case stdout
    case stderr
    case system
}
